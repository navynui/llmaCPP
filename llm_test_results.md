# LLM Model Performance Log (P100 16GB)

## Complete Test Results (Ordered by Speed)

| Rank | Model Name | Quantization | Avg Speed (t/s) | Intelligence / Notes | Status |
|---|---|---|---|---|---|
| 1 | gemma-4-E4B-it-Q4_K_M.gguf | Q4_K_M (~8GB) | **35.3** t/s | Excellent speed, solid general capability | ✅ BEST SPEED |
| 2 | gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf | Q4_K_M (~8GB) | **34.4** t/s | Fast uncensored variant — strong on technical/creative, hallucinates factual QA | ✅ FAST |
| 3 | Qwen3.6-35B-A3B-UD-IQ3_S.gguf | IQ3_S (~17GB) | **32.8** t/s | Strong MoE reasoning, fast for size | ✅ HIGH PERFORMER |
| 4 | gemma-4-26B-A4B-it-APEX-GGUF | APEX Q4 (~13GB) | **18.0** t/s | Decent quality, acceptable speed | ⚠️ OK |
| 5 | gemma-4-26B-A4B-it-UD-IQ4_XS.gguf | IQ4_XS (~13.6GB) | **17.0** t/s | Similar to APEX, slightly slower | ⚠️ OK |
| 6 | Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf | Q4_K_M (~15GB) | **30.7** t/s | Solid dense MoE, balanced performance | ✅ RECOMMENDED |
| 7 | Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf | Q4_K_M (~5.5GB) | **29.4** t/s | Small model, fast but less capable | ⚠️ SMALL MODEL |
| 8 | Qwen2.5-Coder-32B (Q4_K_M) | Q4_K_M (~17-18GB) | **3.0** t/s ❌ | Too large for 16GB VRAM; CPU offload kills speed | 🔴 REJECT |

## Test Environment
- **GPU:** Tesla P100 PCIE 16GB (Compute 6.1)
- **Context Window:** Varies per test (tested up to ~4096 tokens)
- **Benchmark Suite:** 5-round evaluation (Knowledge QA, Technical Reasoning, Code Generation, Abstract Reasoning, Creative Writing)
- **Date:** June 2026

### Notes on Data Extraction
Raw test data is stored as individual JSON files in `/home/nui/workspace/model_test_output/`. Each file follows a standard 5-round evaluation format (`Knowledge QA`, `Technical Reasoning`, `Code Generation`, `Abstract Reasoning`, `Creative Writing`). The "Avg Speed (t/s)" column aggregates the `tokens_per_second` metrics from all successful rounds. Qualitative notes ("Intelligence / Notes") are derived from round-by-round prompt/response analysis, scoring factors like accuracy, code correctness, and hallucination rates.

## Key Findings & Recommendations

### What Works Well on P100 16GB:
- **E4B variants (~8GB)** are the sweet spot for maximum speed (~35 t/s) while maintaining good intelligence.
- **Qwen3.6 series (MoE, ~28-35B)** performs surprisingly well even with aggressive quantization (IQ3_S). The 35B-A3B variant hit 32.8 t/s — very close to E4B speed with much more capability.
- **Qwen3.6-28B-REAP20-A3B** at Q4_K_M is a strong all-rounder: fast enough (~31 t/s) and smart enough for most tasks.

### What to Avoid:
- Models >15GB (like Qwen2.5-Coder-32B Q4_K_M) **must not be loaded on P100** without CPU offloading, which tanks performance to unusable levels (<5 t/s).
- Aggressive custom quantizations (IQ4, APEX) on the 26B-A4B MoE are fine but offer no real advantage over standard Q4_K_M in this size range.

### Recommended Models for Future Use:
1. **Qwen3.6-28B-REAP20-A3B-Q4_K_M** — Best balance of speed + intelligence
2. **Gemma 4 E4B Q4_K_M** — Fastest, lightest, still smart
3. **Qwen3.5-9B Uncensored** — Use only for lightweight tasks; fast but limited
