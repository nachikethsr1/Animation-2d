# BOXZ AI — neural language-model foundation

A research prototype for a **decoder-only Transformer trained from scratch**. No external LLM, pretrained model, pretrained weights, dataset downloads or rule-based response engine are included. No final tokenizer or model has been trained. Outputs from an untrained or inadequately trained model will not be useful conversation. This project does not guarantee chat ability; that requires suitable, permissioned conversational data, substantial compute and evaluation.

## Setup

From this directory, with Python 3.11+:

```sh
python3 -m venv .venv
source .venv/bin/activate       # Windows: .venv\Scripts\activate
python -m pip install -r requirements.txt
python -m pytest -q
```

PyTorch is the neural-network framework; NumPy is provided for numerical interoperability; PyYAML parses configuration, tqdm displays progress, and pytest runs tests. On CPU-only machines, a CPU-only PyTorch wheel from PyTorch's official installation instructions can reduce installation size. CUDA is selected only when PyTorch detects a usable CUDA device; otherwise CPU is used. The default 6-layer configuration can be slow on limited hardware; lower dimensions, layers, context length and batch size in `config.yaml` for experiments. Hidden dimension must divide evenly by the head count.

## Your data and workflow (do not run training until approved)

1. Put **your own** UTF-8 files in `data/raw/`. Files are never modified. Inputs can be TXT (one document per file), JSON (array of strings or objects), JSONL (one string or object per line), or CSV. JSON/CSV objects need a `text` string field by default; use `--field COLUMN` to select another. Split long TXT files into multiple documents yourself; at least two distinct nonempty records are required. For conversation, supply suitably formatted examples, e.g. consistent `User:` and `Assistant:` turns; no examples are provided by this project.
2. From `BOXZ_AI/`, choose your actual file paths explicitly:

```sh
python -m scripts.prepare_data data/raw/your_file.jsonl --val-fraction 0.1
```

It normalizes line endings, trims outer whitespace, drops empty strings and exact duplicates, randomly splits **whole records** (seed 42), and writes `data/processed/train.jsonl` and `val.jsonl`. It preserves punctuation and Unicode. It reports counts; malformed or unsupported records are errors. The output paths are overwritten on rerun; raw files are untouched. Exact duplicates only are detected; similar or related records may still leak across splits. These files may contain private data, so protect them accordingly.
3. Only when ready, train the tokenizer **on the training split only**:

```sh
python -m tokenizer.train_tokenizer --input data/processed/train.jsonl --output tokenizer/vocabulary.json --vocab-size 512
```

The requested size is a maximum: training stops early if no pair reaches the minimum frequency. An optional inspectable token-ID export is available with `python -m scripts.tokenize_data`; training itself tokenizes processed text directly in memory. For validation export, pass `--input data/processed/val.jsonl --output data/tokenized/val.jsonl`.
4. **After explicitly approving model training**, launch:

```sh
python -m scripts.train --config config.yaml
```

Configuration controls batch size, context, model dimensions, learning rate, epochs and gradient accumulation. The tokenizer determines vocabulary size. Checkpoints are saved atomically at each **completed epoch** in `checkpoints/latest.pt`; loss metrics append to `logs/loss.jsonl`. Interrupted partial epochs restart at the last checkpoint. Resume the same run with `python -m scripts.train --resume checkpoints/latest.pt` using the exact same config, tokenizer and unchanged datasets. Resume restores model, optimizer, scheduler and random states; dataset contents are not fingerprinted, so keep them unchanged. To continue training on additional data or with new settings, use `python -m scripts.train --init-from checkpoints/latest.pt` (fresh optimizer/schedule; tokenizer and model architecture must match). Save a copy of your previous checkpoint first. Changing tokenizer changes token IDs and requires a new model; don't retrain it for an existing checkpoint.
5. After training:

```sh
python -m inference.chat --checkpoint checkpoints/latest.pt --tokenizer tokenizer/vocabulary.json
```

Use `/clear` to reset context and `/quit` to exit. Generation supports `--temperature`, `--top-k`, `--top-p`, `--max-new-tokens` and `--history-turns`; old context is truncated to the model window. This plain-text turn format is not an instruction-tuning guarantee; generated text may be nonsensical or continue the prompt. Checkpoints are Python pickle files: **only load trusted files**.

## Architecture and implementation

- `tokenizer/tokenizer.py`: custom byte-level BPE; fixed IDs PAD=0, UNK=1, BOS=2, EOS=3 followed by all 256 bytes. Pair merges learned deterministically from user text are stored in JSON. UTF-8 bytes ensure unseen Unicode can be encoded without an unknown symbol. Invalid decoded byte sequences use replacement characters. Naive BPE counts/replaces in memory, so large corpora need a more scalable implementation.
- `model/model.py`: learned token and positional embeddings, 6 configurable pre-layer-normalized Transformer blocks, multi-head causal attention with a triangular mask, residual connections, GELU feed-forward network and vocabulary projection. Defaults: hidden 256, 8 heads, FF 1024, context 256. Outputs predict the next token.
- `model/generation.py`, `inference/sampler.py`: autoregressive sampling, sliding context window, temperature, top-k, nucleus top-p and EOS stopping. `inference/chat.py` provides the terminal interface and bounded history.
- `engine/data_loader.py`: encodes each document with BOS/EOS and prepares overlapping chunk boundaries; padded targets use `-100` for ignored loss. `engine/trainer.py` uses token-weighted cross-entropy, AdamW, cosine schedule, gradient accumulation/clipping, validation and loss logging. `engine/checkpoint.py` stores model/optimizer/scheduler/config/tokenizer hash and random state; `engine/device.py` selects device.
- `scripts/prepare_data.py` validates and splits raw data; `scripts/tokenize_data.py` exports IDs; `scripts/train.py` is the explicit training entry point. `tests/test_engine.py` tests tokenizer, causality, optimization, checkpoints, generation and data handling with tiny synthetic inputs only.

## Limitations

Data preparation, tokenizer learning and dataset loading currently hold the corpus or encoded chunks in RAM; use small datasets on constrained machines. There is no streaming, distributed training, mixed precision, moderation, benchmark suite, fine-grained checkpointing or model quality guarantee. Validation is token-level loss rather than a measure of conversational ability. Data and generated artifacts, including vocabulary, checkpoints and logs, are ignored by Git; back them up securely yourself. The model is randomly initialized until you train it.
