import argparse
import json
from tokenizer.tokenizer import BPETokenizer

def main():
    p = argparse.ArgumentParser(description='Train a new BPE tokenizer on prepared training records only')
    p.add_argument('--input', default='data/processed/train.jsonl'); p.add_argument('--output', default='tokenizer/vocabulary.json')
    p.add_argument('--vocab-size', type=int, default=512); p.add_argument('--min-frequency', type=int, default=2)
    args = p.parse_args()
    with open(args.input, encoding='utf-8') as f: texts = [json.loads(line)['text'] for line in f if line.strip()]
    tok = BPETokenizer.train(texts, args.vocab_size, args.min_frequency); tok.save(args.output)
    print(f'Saved {tok.vocab_size} tokens to {args.output}')
if __name__ == '__main__': main()
