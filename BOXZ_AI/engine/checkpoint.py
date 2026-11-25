import hashlib
from pathlib import Path
import torch

def tokenizer_hash(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def save_checkpoint(path, model, optimizer, scheduler, epoch, tokenizer_path, train_config):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + '.tmp')
    torch.save({'model_config': vars(model.config), 'model': model.state_dict(), 'optimizer': optimizer.state_dict(), 'scheduler': scheduler.state_dict(), 'epoch': epoch, 'tokenizer_hash': tokenizer_hash(tokenizer_path), 'training_config': train_config, 'rng': torch.get_rng_state(), 'cuda_rng': torch.cuda.get_rng_state_all() if torch.cuda.is_available() else None}, tmp)
    tmp.replace(path)

def load_checkpoint(path, device='cpu'):
    # Checkpoints are Python pickle files: only load files you trust.
    return torch.load(path, map_location=device, weights_only=False)
