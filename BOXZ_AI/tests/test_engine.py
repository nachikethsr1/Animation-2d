import json
import torch
from torch.utils.data import DataLoader
from tokenizer.tokenizer import BPETokenizer
from model.model import BoxzModel, ModelConfig
from model.generation import generate
from inference.sampler import sample
from engine.trainer import loss_for, fit
from engine.checkpoint import load_checkpoint
from engine.data_loader import TokenDataset
from engine.device import get_device
from scripts.prepare_data import prepare

def tiny(): return BoxzModel(ModelConfig(vocab_size=260, context_length=8, n_layers=1, hidden_dim=16, n_heads=4, ff_dim=32, dropout=0))

def test_tokenizer_unicode_and_specials(tmp_path):
    texts = ['héllo 世界 🐱', 'héllo 世界 🐱']
    t = BPETokenizer.train(texts, 280)
    ids = t.encode(texts[0], add_bos=True, add_eos=True)
    assert ids[0] == t.bos_id and ids[-1] == t.eos_id and t.decode(ids) == texts[0]
    assert t.decode([t.unk_id], skip_special=False) == '<UNK>'
    assert t.decode([999], skip_special=False) == '<UNK>'
    t.save(tmp_path/'v.json'); t2 = BPETokenizer.load(tmp_path/'v.json')
    assert t2.encode(texts[0]) == t.encode(texts[0]) and t2.decode(t2.encode('नमस्ते')) == 'नमस्ते'

def test_model_causal_and_optimization():
    torch.manual_seed(1); model = tiny().cpu().eval()
    x = torch.tensor([[1, 5, 7, 9]]); y = torch.tensor([[5, 7, 9, 3]])
    before = model(x); other = model(torch.tensor([[1, 5, 55, 42]]))
    assert before.shape == (1, 4, 260)
    torch.testing.assert_close(before[:, :2], other[:, :2])
    opt = torch.optim.AdamW(model.parameters(), lr=.001); loss = loss_for(model,x,y)
    old = model.head.weight.detach().clone(); loss.backward(); opt.step()
    assert torch.isfinite(loss) and not torch.equal(old, model.head.weight)
    assert get_device().type in ('cpu','cuda')

def test_checkpoint_and_training(tmp_path):
    tok = BPETokenizer(); path = tmp_path/'v.json'; tok.save(path)
    data = tmp_path/'data.jsonl'; data.write_text(json.dumps({'text':'test'})+'\n', encoding='utf-8')
    loader = DataLoader(TokenDataset(data,tok,8), batch_size=1)
    model = tiny(); cfg = dict(epochs=1, gradient_accumulation=2, gradient_clip=1., learning_rate=.001, weight_decay=.01)
    fit(model, loader, loader, torch.device('cpu'), cfg, path, tmp_path/'model.pt')
    ck = load_checkpoint(tmp_path/'model.pt'); other = tiny(); other.load_state_dict(ck['model'])
    for a,b in zip(model.parameters(), other.parameters()): torch.testing.assert_close(a,b)
    assert ck['epoch'] == 1
    fit(other, loader, loader, torch.device('cpu'), cfg, path, tmp_path/'model.pt', ck)

def test_generation_and_sampling():
    model = tiny(); x = torch.tensor([[1, 7]])
    out = generate(model,x,3,top_k=5,top_p=.8)
    assert out.shape == (1,5) and torch.equal(out[:,:2],x)
    assert sample(torch.tensor([[0.,100.,0.]]), top_k=1).item() == 1
    # Force EOS to verify early stopping.
    with torch.no_grad(): model.head.weight.zero_()
    torch.manual_seed(2)
    assert generate(model,x,0,eos_id=3).shape == x.shape

def test_data_preparation(tmp_path):
    raw = tmp_path/'raw.jsonl'; raw.write_text('\n'.join(json.dumps({'text': x}) for x in ['one!', 'two 世界', 'one!', '  ']), encoding='utf-8')
    original = raw.read_bytes(); prepare([raw], tmp_path/'out')
    assert raw.read_bytes() == original
    a = [json.loads(l)['text'] for l in (tmp_path/'out/train.jsonl').read_text().splitlines()]
    b = [json.loads(l)['text'] for l in (tmp_path/'out/val.jsonl').read_text().splitlines()]
    assert set(a).isdisjoint(b) and set(a+b) == {'one!', 'two 世界'}

def test_eos_stopping():
    from unittest.mock import patch
    model = tiny(); prompt = torch.tensor([[1, 7]])
    with patch('model.generation.sample', return_value=torch.tensor([[3]])):
        out = generate(model, prompt, max_new_tokens=9, eos_id=3)
    assert out.tolist() == [[1, 7, 3]]
