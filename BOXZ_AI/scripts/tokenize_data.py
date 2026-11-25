"""Export tokenized records as JSONL for inspection or external tooling."""
import argparse
import json
from pathlib import Path
from tokenizer.tokenizer import BPETokenizer

def main():
    p = argparse.ArgumentParser(); p.add_argument('--tokenizer', default='tokenizer/vocabulary.json'); p.add_argument('--input', default='data/processed/train.jsonl'); p.add_argument('--output', default='data/tokenized/train.jsonl'); a = p.parse_args()
    tok = BPETokenizer.load(a.tokenizer); output = Path(a.output); output.parent.mkdir(parents=True, exist_ok=True)
    with open(a.input, encoding='utf-8') as src, output.open('w', encoding='utf-8') as dst:
        for line in src:
            if line.strip(): dst.write(json.dumps({'ids': tok.encode(json.loads(line)['text'], add_bos=True, add_eos=True)}) + '\n')
    print(f'Saved token IDs to {output}')
if __name__ == '__main__': main()
