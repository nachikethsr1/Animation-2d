import torch
from inference.sampler import sample

@torch.no_grad()
def generate(model, ids, max_new_tokens=100, temperature=1.0, top_k=0, top_p=1.0, eos_id=None):
    if max_new_tokens < 0 or ids.ndim != 2 or ids.shape[0] != 1 or ids.shape[1] == 0: raise ValueError('Expected a nonempty single prompt and nonnegative length')
    was_training = model.training; model.eval()
    try:
        for _ in range(max_new_tokens):
            logits = model(ids[:, -model.config.context_length:])[:, -1, :]
            next_id = sample(logits, temperature, top_k, top_p)
            ids = torch.cat((ids, next_id), dim=1)
            if eos_id is not None and next_id.item() == eos_id: break
        return ids
    finally:
        model.train(was_training)
