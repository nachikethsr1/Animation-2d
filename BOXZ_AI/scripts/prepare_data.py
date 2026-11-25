"""Prepare user-supplied records without modifying raw inputs."""
import argparse
import csv
import json
import random
from pathlib import Path

def records(path, field):
    suffix = path.suffix.lower()
    if suffix == '.txt':
        # One document per file, preserving line breaks.
        yield path.read_text(encoding='utf-8-sig')
    elif suffix in ('.json', '.jsonl', '.csv'):
        with path.open(encoding='utf-8-sig', newline='') as f:
            if suffix == '.json':
                data = json.load(f); items = data if isinstance(data, list) else [data]
            elif suffix == '.jsonl': items = (json.loads(line) for line in f if line.strip())
            else: items = csv.DictReader(f)
            for item in items:
                if isinstance(item, str): yield item
                elif isinstance(item, dict) and isinstance(item.get(field), str): yield item[field]
                else: raise ValueError(f'{path}: record must be a string or have string field {field!r}')
    else: raise ValueError(f'Unsupported format: {path}')

def prepare(inputs, output, field='text', val_fraction=0.1, seed=42):
    if not 0 < val_fraction < 1: raise ValueError('val_fraction must be between 0 and 1')
    unique, seen, empty, duplicates = [], set(), 0, 0
    for path in inputs:
        for text in records(path, field):
            text = text.replace('\r\n', '\n').replace('\r', '\n').strip()
            if not text: empty += 1; continue
            if text in seen: duplicates += 1; continue
            seen.add(text); unique.append(text)
    if len(unique) < 2: raise ValueError('Need at least two distinct nonempty records for train/validation split')
    random.Random(seed).shuffle(unique)
    nval = min(len(unique)-1, max(1, round(len(unique)*val_fraction)))
    output = Path(output); output.mkdir(parents=True, exist_ok=True)
    for name, subset in [('train', unique[nval:]), ('val', unique[:nval])]:
        with (output / f'{name}.jsonl').open('w', encoding='utf-8') as f:
            for text in subset: f.write(json.dumps({'text': text}, ensure_ascii=False) + '\n')
    print(f'train={len(unique)-nval} validation={nval} empty={empty} duplicates={duplicates}')

def main():
    p = argparse.ArgumentParser(); p.add_argument('inputs', nargs='+', type=Path); p.add_argument('--output', default='data/processed'); p.add_argument('--field', default='text'); p.add_argument('--val-fraction', type=float, default=.1); p.add_argument('--seed', type=int, default=42)
    a = p.parse_args(); prepare(a.inputs, a.output, a.field, a.val_fraction, a.seed)
if __name__ == '__main__': main()
