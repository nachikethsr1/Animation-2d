import math
import json
from pathlib import Path
import torch
from torch.nn import functional as F
from tqdm import tqdm
from engine.checkpoint import save_checkpoint

def loss_for(model, x, y):
    logits = model(x)
    return F.cross_entropy(logits.reshape(-1, logits.size(-1)), y.reshape(-1), ignore_index=-100)

def run_epoch(model, loader, device, optimizer=None, scheduler=None, accumulation=1, clip=1.0):
    training = optimizer is not None; model.train(training)
    total_loss, total_tokens = 0.0, 0
    if training: optimizer.zero_grad(set_to_none=True)
    # Scale summed token losses by the number of valid tokens in each accumulation group.
    group_tokens = 0
    with torch.set_grad_enabled(training):
        for i, (x, y) in enumerate(tqdm(loader, desc='train' if training else 'validation')):
            x, y = x.to(device), y.to(device)
            count = int((y != -100).sum()); loss = loss_for(model, x, y)
            total_loss += loss.item() * count; total_tokens += count
            if training:
                (loss * count).backward(); group_tokens += count
                if (i + 1) % accumulation == 0 or i + 1 == len(loader):
                    for param in model.parameters():
                        if param.grad is not None: param.grad.div_(group_tokens)
                    torch.nn.utils.clip_grad_norm_(model.parameters(), clip)
                    optimizer.step(); scheduler.step(); optimizer.zero_grad(set_to_none=True); group_tokens = 0
    return total_loss / total_tokens

def fit(model, train_loader, val_loader, device, cfg, tokenizer_path, checkpoint_path, resume=None):
    if cfg['epochs'] < 1 or cfg['gradient_accumulation'] < 1 or cfg['gradient_clip'] <= 0: raise ValueError('Invalid training settings')
    optimizer = torch.optim.AdamW(model.parameters(), lr=cfg['learning_rate'], weight_decay=cfg['weight_decay'])
    steps = math.ceil(len(train_loader) / cfg['gradient_accumulation']) * cfg['epochs']
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=max(1, steps))
    start = 0
    if resume:
        if resume['training_config'] != cfg: raise ValueError('Resume requires the same training configuration')
        model.load_state_dict(resume['model']); optimizer.load_state_dict(resume['optimizer']); scheduler.load_state_dict(resume['scheduler'])
        torch.set_rng_state(resume['rng'].cpu())
        if device.type == 'cuda' and resume.get('cuda_rng') is not None: torch.cuda.set_rng_state_all(resume['cuda_rng'])
        start = resume['epoch']
    for epoch in range(start, cfg['epochs']):
        train_loss = run_epoch(model, train_loader, device, optimizer, scheduler, cfg['gradient_accumulation'], cfg['gradient_clip'])
        val_loss = run_epoch(model, val_loader, device)
        print(f'epoch {epoch+1}: train loss={train_loss:.4f} validation loss={val_loss:.4f}')
        log = Path('logs/loss.jsonl'); log.parent.mkdir(parents=True, exist_ok=True)
        with log.open('a', encoding='utf-8') as f: f.write(json.dumps({'epoch': epoch+1, 'train_loss': train_loss, 'validation_loss': val_loss}) + '\n')
        save_checkpoint(checkpoint_path, model, optimizer, scheduler, epoch+1, tokenizer_path, cfg)
