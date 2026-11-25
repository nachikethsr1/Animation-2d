import argparse
import torch
import yaml
from torch.utils.data import DataLoader
from tokenizer.tokenizer import BPETokenizer
from model.model import ModelConfig, BoxzModel
from engine.data_loader import TokenDataset
from engine.device import get_device
from engine.trainer import fit
from engine.checkpoint import load_checkpoint, tokenizer_hash

def main():
    p = argparse.ArgumentParser(description='Train BOXZ only when explicitly launched')
    p.add_argument('--config', default='config.yaml'); p.add_argument('--tokenizer', default='tokenizer/vocabulary.json')
    p.add_argument('--train', default='data/processed/train.jsonl'); p.add_argument('--val', default='data/processed/val.jsonl')
    p.add_argument('--checkpoint', default='checkpoints/latest.pt'); group = p.add_mutually_exclusive_group(); group.add_argument('--resume', default=None); group.add_argument('--init-from', default=None)
    a = p.parse_args()
    with open(a.config, encoding='utf-8') as f: config = yaml.safe_load(f)
    cfg = config['training']; torch.manual_seed(cfg['seed']); device = get_device(); print('Device:', device)
    tok = BPETokenizer.load(a.tokenizer); mc = ModelConfig(vocab_size=tok.vocab_size, **config['model'])
    train = TokenDataset(a.train, tok, mc.context_length); val = TokenDataset(a.val, tok, mc.context_length)
    train_loader = DataLoader(train, batch_size=cfg['batch_size'], shuffle=True); val_loader = DataLoader(val, batch_size=cfg['batch_size'])
    resume = load_checkpoint(a.resume, device) if a.resume else None
    if resume and (resume['tokenizer_hash'] != tokenizer_hash(a.tokenizer) or resume['model_config'] != vars(mc)): raise ValueError('Checkpoint tokenizer or model configuration mismatch')
    model = BoxzModel(mc).to(device)
    if a.init_from:
        initial = load_checkpoint(a.init_from, device)
        if initial['tokenizer_hash'] != tokenizer_hash(a.tokenizer) or initial['model_config'] != vars(mc): raise ValueError('Checkpoint tokenizer or model configuration mismatch')
        model.load_state_dict(initial['model'])
    fit(model, train_loader, val_loader, device, cfg, a.tokenizer, a.checkpoint, resume)
if __name__ == '__main__': main()
