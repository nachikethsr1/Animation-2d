import json
import torch
from torch.utils.data import Dataset

class TokenDataset(Dataset):
    """Independent non-overlapping document chunks; padding is ignored by loss."""
    def __init__(self, path, tokenizer, context_length):
        self.samples = []; self.context_length = context_length; self.pad_id = tokenizer.pad_id
        with open(path, encoding='utf-8') as f:
            for line in f:
                if not line.strip(): continue
                text = json.loads(line)['text']
                ids = tokenizer.encode(text, add_bos=True, add_eos=True)
                # Overlap one token so every adjacent pair is represented exactly once.
                for start in range(0, len(ids)-1, context_length):
                    chunk = ids[start:start+context_length+1]
                    if len(chunk) >= 2: self.samples.append(chunk)
        if not self.samples: raise ValueError(f'No training sequences in {path}')
    def __len__(self): return len(self.samples)
    def __getitem__(self, index):
        ids = self.samples[index]; n = self.context_length
        x = ids[:-1] + [self.pad_id] * (n - len(ids) + 1)
        y = ids[1:] + [-100] * (n - len(ids) + 1)
        return torch.tensor(x), torch.tensor(y)
