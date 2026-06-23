# Model Parameters in llama.cpp Router Mode

## Overview
When using router mode with a `models.ini` preset, each model section can define its own runtime parameters. These are passed to the server on every request via the `--parameter <value>` flag or via per-model defaults.

## Common Sampling Parameters

| Parameter | Type | Default (build‑dependent) | Description |
|-----------|------|---------------------------|-------------|
| **temperature** | float (0‑∞) | 1.0 (or build default) | Controls randomness of token selection. < 1 makes output deterministic, > 1 more creative. `0` yields greedy decoding. |
| **top_p** (nucleus) | float (0‑1] | 1.0 | Limits the next‑token sampling pool to the smallest set of tokens whose cumulative probability ≥ p. Useful for controlling diversity while keeping tail probabilities negligible. |
| **min_p** | float (0‑1] | 0.0 | Minimum probability threshold; only tokens with probability **≥** this value are considered for top‑p / nucleus sampling. Often used together with `top_k`. |
| **top_k** | integer (1‑∞) | 0 (disabled) | Restricts sampling to the top‑k most likely tokens, regardless of probability mass. Frequently paired with `top_p`. |
| **repeat_penalty** | float (> 0) | 1.0 | Multiplies token probabilities by a penalty factor each time they appear, reducing repetition. Values > 1 discourage repeats; < 1 encourages them (use cautiously). |
| **presence_penalty** | float | 0.0 | Increases probability of tokens that have not yet appeared, decreasing the likelihood of repeating the same phrase. |
| **frequency_penalty** | float | 0.0 | Scales with token frequency; higher values reduce repetition of frequent tokens. |
| **n‑gram_repetition_bias** (if supported) | float | 1.0 | Biases against repeated n‑grams; useful for creative text generation. |

### Model‑Specific Sections in `models.ini`

```ini
[ModelA]
model = /models/model_a.gguf
temperature = 0.7          ; balanced creativity
top_p = 0.9                ; allow diverse but not too wild output
min_p = 0.01               ; keep very low‑probability tokens out
repeat_penalty = 1.1       ; mild repetition avoidance

[ModelB]
model = /models/model_b.gguf
temperature = 0.2          ; more deterministic for factual answers
top_p = 0.95               ; allow slightly broader pool
min_p = 0.001              ; keep rare tokens only when needed
repeat_penalty = 1.3       ; stronger avoidance of repeated phrasing

[ModelC]
model = /models/model_c.gguf
temperature = 1.2          ; high creativity for storytelling or brainstorming
top_p = 0.95               ; allow many tokens
min_p = 0.0                ; include all tokens (no cutoff)
repeat_penalty = 0.9       ; lower penalty to encourage variety
```

### How Parameters Are Applied

1. **Per‑model section** – The flags defined inside a model’s `[section]` are applied only when that model is selected.
2. **Global defaults** – Any parameter omitted in the section falls back to the global defaults set via command‑line arguments (`--temperature`, `--top-p`, etc.) or built‑in server defaults.
3. **Runtime override** – If you send a request with a different `temperature` (or other sampler flag) value, it overrides the preset for that single call.

### Example: Switching Models on the Fly

```bash
curl -X POST http://localhost:8080/completions \
  -H "Content-Type: application/json" \
  -d '{
        "model": "ModelB",
        "messages": [{"role":"user","content":"Explain quantum entanglement in simple terms"}],
        "temperature": 0.5   # overrides ModelB's preset temperature of 0.2 for this request
      }'
```

The server loads `ModelB` (if not already loaded) and uses its preset values unless you explicitly provide a different sampler setting in the JSON payload.

### Practical Tips

- **VRAM Management** – Large models (> 13 B parameters) should have `n-gpu-layers = -1` to offload all layers, but keep `stop-timeout` low (e.g., 30‑60 s) to free VRAM when idle.
- **Preset Consistency** – Keep `ctx-size`, `cache-type-k/v`, and `ubatch-size` consistent across models of similar size; otherwise the server may reject a preset that requests more layers than available VRAM.
- **Testing Load/Unload** – Use `/models/load` and `/models/unload` endpoints to verify which model is active before sending production traffic.
- **Documentation Source** – All flags are documented in `llama.cpp/README.md#parameters` and the `--samplers` section of the CLI help.

---

*This file was generated for quick reference when editing `~/llmaCPP/models/models.ini`. Adjust values per model to match your VRAM budget and desired output behavior.*
