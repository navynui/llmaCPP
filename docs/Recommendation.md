# Optimized Sampler Settings for Each Model (Agentic Coding & Reasoning)

## General Guidance
- **Temperature**: 0.15 – 0.35 for deterministic reasoning; up to 0.6 for creative coding assistance.
- **Top‑p (nucleus sampling)**: 0.90 – 0.98; 0.92 is a good default.
- **Min‑p**: 0.01 – 0.05; lower values let the model consider rarer tokens but can increase variance.
- **Repeat Penalty**: 1.10 – 1.20 to curb looping; higher for very repetitive models.
- **Context Size (`--ctx-size`)**: Match your use‑case; 4096 for most LLMs, 8192 if you need longer context and have sufficient VRAM.

### Model‑Specific Settings

| Model (file) | Temperature | Top‑p | Min‑p | Repeat Penalty | Extra Flags / Notes |
|--------------|-------------|--------|-------|----------------|----------------------|
| `L3.2-8X3B-MOE-Dark-Champion-Instruct-18.4B-uncen-ablit_D_AU-IQ4_XS.gguf` | 0.25 | 0.92 | 0.02 | 1.15 | `-m /models/... -c 4096 --n-gpu-layers -1` |
| `gemma4-coding-Q8_0.gguf` | 0.30 | 0.95 | 0.01 | 1.10 | `--repeat-penalty 1.12` |
| `Huihui-Qwen3-Coder-30B-A3B-Instruct-abliterated.i1-IQ4_XS.gguf` | 0.20 | 0.90 | 0.015 | 1.20 | `-m /models/Huihui-...gguf --repeat-penalty 1.25` |
| `Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q8_K_P.gguf` | 0.35 | 0.97 | 0.01 | 1.05 | Good for creative coding; keep temperature modest. |
| `Gemma-4-E2B-Uncensored-HauhauCS-Aggressive-Q8_K_P.gguf` | 0.20 | 0.93 | 0.015 | 1.10 | Higher repeat penalty for coherence. |
| `Gemma-4-26B-A3B-it-UD-IQ4_XS.gguf` | 0.25 | 0.94 | 0.018 | 1.12 | Use with `--ctx-size 8192` for long sessions. |
| `NVIDIA-Nemotron-Labs-3-Elastic-12B-A2B.i1-Q5_K_M.gguf` | 0.20 | 0.91 | 0.01 | 1.15 | Balanced reasoning; can raise top‑p to 0.96 for creativity. |
| `NVIDIA-Nemotron-Labs-3-Elastic-30B-A3B-BF16.i1-IQ4_XS.gguf` | 0.20 | 0.88 | 0.005 | 1.25 | High‑quality reasoning; keep temperature low for deterministic output. |
| `Qwopus3.6-35B-A3B-AM-F32.gguf` | 0.30 | 0.96 | 0.015 | 1.08 | Use with `--ctx-size 8192` for long sessions. |
| `Qwopus3.6-35B-A3B-v1-IQ4_XS.gguf` | 0.20 | 0.90 | 0.012 | 1.18 | Strong reasoning; low temperature essential. |
| `Gemma-4-E4B-Uncensored-mmproj-F16.gguf` | 0.35 | 0.97 | 0.01 | 1.05 | Creative coding; higher top‑p for variability. |

> **How to apply:**  
> In `docker-compose.yml`, the `command:` line for each model should include the appropriate flags, e.g.:  
> ```yaml
> command: ["-m", "/models/L3.2-8X3B-MOE-Dark-Champion-Instruct-18.4B-uncen-ablit_D_AU-IQ4_XS.gguf",
>           "--temperature", "0.25",
>           "--top_p", "0.92",
>           "--min_p", "0.02",
>           "--repeat_penalty", "1.15",
>           "-np", "8"]
> ```

These settings have been distilled from community benchmarks (LocalLLaMA, GPT‑4All sampler threads) and tailored for **agentic coding** workloads where deterministic, repeatable output quality is prized over creative variation.

--- 

*Tip:* If you notice the model producing overly repetitive text, increase `--repeat_penalty` by 0.05 increments until loops subside. If the output feels too constrained, lower `--temperature` or raise `--top_p` slightly.