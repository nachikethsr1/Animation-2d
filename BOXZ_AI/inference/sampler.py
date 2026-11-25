import torch

def sample(logits, temperature=1.0, top_k=0, top_p=1.0):
    if temperature <= 0 or top_k < 0 or not 0 < top_p <= 1: raise ValueError('Invalid sampling settings')
    logits = logits / temperature
    if top_k:
        k = min(top_k, logits.size(-1)); cutoff = torch.topk(logits, k).values[..., -1, None]
        logits = logits.masked_fill(logits < cutoff, float('-inf'))
    if top_p < 1:
        sorted_logits, indices = torch.sort(logits, descending=True, dim=-1)
        cumulative = torch.softmax(sorted_logits, dim=-1).cumsum(dim=-1)
        remove = cumulative > top_p
        remove[..., 1:] = remove[..., :-1].clone(); remove[..., 0] = False
        sorted_logits = sorted_logits.masked_fill(remove, float('-inf'))
        logits = torch.full_like(logits, float('-inf')).scatter(-1, indices, sorted_logits)
    return torch.multinomial(torch.softmax(logits, dim=-1), 1)
