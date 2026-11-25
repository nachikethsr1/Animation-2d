"""Deterministic byte-level BPE; base symbols cover every UTF-8 byte."""
import json
from collections import Counter
from pathlib import Path

SPECIAL = ['<PAD>', '<UNK>', '<BOS>', '<EOS>']

class BPETokenizer:
    def __init__(self, merges=()):
        self.merges = [tuple(pair) for pair in merges]
        self.tokens = [None] * len(SPECIAL) + [bytes([i]) for i in range(256)]
        for a, b in self.merges:
            if not (4 <= a < len(self.tokens) and 4 <= b < len(self.tokens)):
                raise ValueError('Invalid BPE merge')
            self.tokens.append(self.tokens[a] + self.tokens[b])
        self.ranks = {pair: i + 260 for i, pair in enumerate(self.merges)}
        if len(self.ranks) != len(self.merges):
            raise ValueError('Duplicate merge')

    @property
    def vocab_size(self): return len(self.tokens)
    pad_id, unk_id, bos_id, eos_id = range(4)

    @classmethod
    def train(cls, texts, vocab_size=512, min_frequency=2):
        if vocab_size < 260 or min_frequency < 1:
            raise ValueError('vocab_size must be >= 260 and min_frequency >= 1')
        sequences = [[b + 4 for b in text.encode('utf-8')] for text in texts if text]
        if not sequences: raise ValueError('Cannot train tokenizer on empty text')
        merges = []
        while 260 + len(merges) < vocab_size:
            counts = Counter(pair for seq in sequences for pair in zip(seq, seq[1:]))
            if not counts: break
            pair, count = min(counts.items(), key=lambda item: (-item[1], item[0]))
            if count < min_frequency: break
            new_id = 260 + len(merges)
            merges.append(pair)
            sequences = [cls._replace(seq, pair, new_id) for seq in sequences]
        return cls(merges)

    @staticmethod
    def _replace(seq, pair, new_id):
        out, i = [], 0
        while i < len(seq):
            if i + 1 < len(seq) and (seq[i], seq[i+1]) == pair:
                out.append(new_id); i += 2
            else:
                out.append(seq[i]); i += 1
        return out

    def encode(self, text, add_bos=False, add_eos=False):
        seq = [b + 4 for b in text.encode('utf-8')]
        for pair, new_id in self.ranks.items(): seq = self._replace(seq, pair, new_id)
        return ([self.bos_id] if add_bos else []) + seq + ([self.eos_id] if add_eos else [])

    def decode(self, ids, skip_special=True):
        pieces = bytearray()
        for token in ids:
            token = int(token)
            if token < 0 or token >= self.vocab_size: token = self.unk_id
            if token < 4:
                if not skip_special: pieces.extend(SPECIAL[token].encode())
            else: pieces.extend(self.tokens[token])
        return pieces.decode('utf-8', errors='replace')

    def save(self, path):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        Path(path).write_text(json.dumps({'version': 1, 'special_tokens': SPECIAL, 'merges': self.merges}), encoding='utf-8')

    @classmethod
    def load(cls, path):
        obj = json.loads(Path(path).read_text(encoding='utf-8'))
        if obj.get('version') != 1 or obj.get('special_tokens') != SPECIAL: raise ValueError('Unsupported tokenizer format')
        return cls(obj['merges'])
