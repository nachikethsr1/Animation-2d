import argparse
import torch
from tokenizer.tokenizer import BPETokenizer
from model.model import ModelConfig, BoxzModel
from model.generation import generate
from engine.checkpoint import load_checkpoint, tokenizer_hash
from engine.device import get_device

def main():
    p = argparse.ArgumentParser(); p.add_argument('--checkpoint', default='checkpoints/latest.pt'); p.add_argument('--tokenizer', default='tokenizer/vocabulary.json'); p.add_argument('--max-new-tokens', type=int, default=100); p.add_argument('--temperature', type=float, default=.8); p.add_argument('--top-k', type=int, default=40); p.add_argument('--top-p', type=float, default=.95); p.add_argument('--history-turns', type=int, default=4)
    a = p.parse_args()
    if a.history_turns < 0: p.error('--history-turns must be nonnegative')
    device = get_device(); tok = BPETokenizer.load(a.tokenizer); checkpoint = load_checkpoint(a.checkpoint, device)
    if checkpoint['tokenizer_hash'] != tokenizer_hash(a.tokenizer): raise ValueError('Tokenizer does not match checkpoint')
    if checkpoint.get('epoch', 0) < 1: raise ValueError('Checkpoint has no completed training epoch')
    model = BoxzModel(ModelConfig(**checkpoint['model_config'])).to(device); model.load_state_dict(checkpoint['model']); model.eval()
    history = []; print('BOXZ AI (experimental). Type /quit to exit, /clear to reset.')
    while True:
        try: text = input('You: ').strip()
        except (EOFError, KeyboardInterrupt): print(); break
        if text == '/quit': break
        if text == '/clear': history.clear(); continue
        if not text: continue
        prompt = ''.join(f'User: {u}\nAssistant: {v}\n' for u,v in history) + f'User: {text}\nAssistant:'
        ids = [tok.bos_id] + tok.encode(prompt); ids = ids[-model.config.context_length:]
        inp = torch.tensor([ids], device=device); out = generate(model, inp, a.max_new_tokens, a.temperature, a.top_k, a.top_p, tok.eos_id)
        response = tok.decode(out[0, len(ids):].tolist()).strip(); print('BOXZ:', response)
        if a.history_turns: history = (history + [(text, response)])[-a.history_turns:]
if __name__ == '__main__': main()
