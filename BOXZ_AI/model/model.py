"""Decoder-only Transformer with pre-normalized causal attention."""
from dataclasses import dataclass, asdict
import torch
from torch import nn
from torch.nn import functional as F

@dataclass
class ModelConfig:
    vocab_size: int
    context_length: int = 256
    n_layers: int = 6
    hidden_dim: int = 256
    n_heads: int = 8
    ff_dim: int = 1024
    dropout: float = 0.1
    def __post_init__(self):
        if min(self.vocab_size, self.context_length, self.n_layers, self.hidden_dim, self.n_heads, self.ff_dim) <= 0 or self.hidden_dim % self.n_heads:
            raise ValueError('Invalid dimensions: all must be positive and hidden_dim divisible by n_heads')
        if not 0 <= self.dropout < 1: raise ValueError('dropout must be in [0, 1)')

class CausalAttention(nn.Module):
    def __init__(self, config):
        super().__init__(); self.heads = config.n_heads; self.dim = config.hidden_dim // config.n_heads
        self.qkv = nn.Linear(config.hidden_dim, config.hidden_dim * 3); self.proj = nn.Linear(config.hidden_dim, config.hidden_dim)
        self.dropout = nn.Dropout(config.dropout)
        self.register_buffer('mask', torch.tril(torch.ones(config.context_length, config.context_length, dtype=torch.bool)), persistent=False)
    def forward(self, x):
        b, t, c = x.shape
        q, k, v = self.qkv(x).chunk(3, dim=-1)
        q, k, v = (z.view(b, t, self.heads, self.dim).transpose(1, 2) for z in (q, k, v))
        weights = (q @ k.transpose(-2, -1)) * (self.dim ** -0.5)
        weights = self.dropout(F.softmax(weights.masked_fill(~self.mask[:t, :t], float('-inf')), dim=-1))
        return self.proj((weights @ v).transpose(1, 2).contiguous().view(b, t, c))

class TransformerBlock(nn.Module):
    def __init__(self, config):
        super().__init__(); self.ln1 = nn.LayerNorm(config.hidden_dim); self.ln2 = nn.LayerNorm(config.hidden_dim)
        self.attn = CausalAttention(config)
        self.ff = nn.Sequential(nn.Linear(config.hidden_dim, config.ff_dim), nn.GELU(), nn.Linear(config.ff_dim, config.hidden_dim), nn.Dropout(config.dropout))
        self.drop = nn.Dropout(config.dropout)
    def forward(self, x):
        x = x + self.drop(self.attn(self.ln1(x)))
        return x + self.ff(self.ln2(x))

class BoxzModel(nn.Module):
    def __init__(self, config):
        super().__init__(); self.config = config
        self.token_embedding = nn.Embedding(config.vocab_size, config.hidden_dim)
        self.position_embedding = nn.Embedding(config.context_length, config.hidden_dim)
        self.drop = nn.Dropout(config.dropout)
        self.blocks = nn.Sequential(*(TransformerBlock(config) for _ in range(config.n_layers)))
        self.norm = nn.LayerNorm(config.hidden_dim); self.head = nn.Linear(config.hidden_dim, config.vocab_size, bias=False)
    def forward(self, ids):
        if ids.ndim != 2 or not 0 < ids.size(1) <= self.config.context_length: raise ValueError('Expected [batch, sequence] within context length')
        positions = torch.arange(ids.size(1), device=ids.device)
        x = self.drop(self.token_embedding(ids) + self.position_embedding(positions))
        return self.head(self.norm(self.blocks(x)))
