# LLM Model Performance Log (P100 16GB)

## Complete Test Results (Ordered by Speed)

| Rank | Model Name | Quantization | Avg Speed (t/s) | Score /100 | Intelligence / Notes | Status |
|---|---|---|---|---|---|---|
| 1 | Hermes-3-Llama-3.2-3B.Q5_K_M | Q5_K_M (~2GB) | **60.8** t/s **BLAZING** | 34/100 | NEW ABSOLUTE SPEED KING (~60 t/s), but weak reasoning | ✅ BLAZING |
| 2 | Qwen3.6-14B-A3B-VibeForged-v2-Q4_K_M | Q4_K_M (~2GB) | **39.8** t/s **FAST** | 24/100 | Fast MoE, but weak QA reasoning | ✅ FAST |
| 3 | gemma-4-E4B-it-Q4_K_M | Q4_K_M (~5.5-6GB) | **35.4** t/s **FAST** | 25/100 | FASTEST LARGE MODEL, solid general capability | ✅ FAST |
| 4 | Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M | Q4_K_M (~5.5-6GB) | **34.9** t/s **FAST** | 19/100 | Fast uncensored variant — strong on technical/creative | ✅ FAST |
| 5 | Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M | Q4_K_M (~5.5-6GB) | **34.8** t/s **FAST** | 23/100 | Fast uncensored variant — strong on technical/creative | ✅ FAST |
| 6 | oh-dcft-v3.1-gpt-4o-mini.Q4_K_M | Q4_K_M (~6-8GB) | **34.5** t/s **FAST** | 25/100 | Very fast but hallucinates QA & buggy code snippets | ✅ FAST |
| 7 | Hermes-3-Llama-3.1-8B.Q4_K_M | Q4_K_M (~5.5-6GB) | **34.4** t/s **FAST** | 25/100 | Strong reasoning, clean structure; TOP PICK for interactive use | ✅ FAST |
| 8 | Qwopus3.6-35B-A3B-v1-IQ4_XS | IQ4_XS (16-20GB) | **33.2** t/s **FAST** | 22/100 | Fast 35B MoE — excellent code gen & QA despite aggressive quantization | ✅ FAST |
| 9 | Qwen3.6-35B-A3B-UD-IQ3_S | IQ3_S (16-20GB) | **32.8** t/s **FAST** | 22/100 | Strong MoE reasoning, fast for size; VRAM on GPU ceiling | ✅ FAST |
| 10 | granite-4.1-8b-Q4_K_M | Q4_K_M (~5.5-6GB) | **30.8** t/s **FAST** | 21/100 | Highly reliable production workhorse; excellent structured outputs | ✅ FAST |
| 11 | Qwen3.6-28B-REAP20-A3B-Q4_K_M | Q4_K_M (~13-15GB) | **30.8** t/s **FAST** | 21/100 | Solid MoE performance | ✅ FAST |
| 12 | Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M | Q4_K_M (~5.5-6GB) | **29.4** t/s OK | 21/100 | Small but fast; less capable reasoning | ✅ FAST |
| 13 | gemma-3-12b-it-vl-HighIQ-Polaris-Heretic-Uncensored-Thinking.i1-Q4_K_M | Q4_K_M (~7.5GB) | **19.9** t/s OK | 19/100 | Best tool-calling & QA in small-model tier — beats official QAT variant | ⚠️ OK |
| 14 | gemma-3-12b-it-qat-Q4_K_M | Q4_K_M (~7.5GB) | **19.5** t/s OK | 17/100 | Good structure/code, but heavily hallucinates factual QA vs HighIQ variant | ⚠️ OK |
| 15 | DeepSeek-R1-Distill-Qwen-32B-IQ3_M | IQ3_M (~15-17GB) | **3.0** t/s **SLOW** | 12/100 | Massive CoT overhead; completely unusable for interactive speed (~3 t/s) | 🔴 SLOW |

## Test Environment
- **GPU:** Tesla P100 PCIE 16GB (Compute 6.1)
- **Context Window:** Varies per test (tested up to ~4096 tokens)
- **Benchmark Suite:** 5-round evaluation (Knowledge QA, Technical Reasoning, Code Generation, Abstract Reasoning, Creative Writing)
- **Date:** June 2026

### Notes on Data Extraction
Raw test data is stored as individual JSON files in `/home/nui/workspace/llmTest/model_test_output/` and `/home/nui/workspace/*.json`. Each file follows a standard 5-round evaluation format (`Knowledge QA`, `Technical Reasoning`, `Code Generation`, `Abstract Reasoning`, `Creative Writing`). The "Avg Speed (t/s)" column aggregates the `tokens_per_second` metrics from all successful rounds. Qualitative notes ("Intelligence / Notes") are derived from round-by-round prompt/response analysis, scoring factors like accuracy, code correctness, and hallucination rates.

## Key Findings & Recommendations

### What Works Well on P100 16GB:
- **Hermes-3-Llama-3.2-3B (Q5_K_M)** — blazing speed of ~60 t/s with only ~2GB VRAM, but limited reasoning capability; best for lightweight routing/filtering
- **Hermes-3-Llama-3.1-8B & GPT-4o-mini (~5.5-6GB)** — speed champions at ~34 t/s with clean structure and stable code generation — TOP PICK for interactive use
- **Gemma 4 E4B (Q4_K_M)** — fastest large model tier at ~35 t/s, solid general capability with strong abstract reasoning
- **Granite 4.1 8B Q4_K_M** — highly reliable production workhorse (~29.5 t/s) — excellent structured outputs for pipeline automation
- **Qwopus3.6-35B-A3B-v1 (IQ4_XS)** — fastest 35B MoE at ~33 t/s despite aggressive quantization; excellent code gen and QA, VRAM on GPU ceiling (~17GB)
- **Gemma 3 12B-it HighIQ Uncensored** — #1 for specialized tool-calling, complex QA chains, and agentic workflows requiring high instruction adherence

### What to Avoid:
- Models >15GB (like Qwen2.5-Coder-32B Q4_K_M) **must not be loaded on P100** without CPU offloading, which tanks performance to unusable levels (<5 t/s)
- Heavy reasoning/CoT models like **DeepSeek-R1-Distill-Qwen-32B-IQ3_M** (~15-17GB) generate excellent chain-of-thought but are completely unusable for interactive workloads due to massive overhead (~3 t/s average). Reserve only for offline batch processing.
- The standard **Gemma 3 12B-it Q4_K_M (QAT)** variant hallucinates factual QA significantly worse than the HighIQ/Uncensored variant

### Recommended Models for Future Use:
1. **Hermes-3-Llama-3.2-3B.Q5_K_M** — New absolute speed king (~60 t/s, ~2GB). Ideal for lightweight routing, prompt filtering, or simple chat.
2. **Hermes-3-Llama-3.1-8B.Q4_K_M** — Best balance of speed + reliability (~34 t/s, ~5.5GB). Clean structure, stable code generation.
3. **Granite 4.1 8B Q4_K_M** — Highly reliable production workhorse (~29.5 t/s, ~5.5GB). Perfect for pipeline automation & enterprise use cases.
4. **Gemma 3 12B-it HighIQ Uncensored** — #1 for specialized tool-calling, complex QA chains, and agentic workflows (~8GB).
5. **Qwopus3.6-35B-A3B-v1-IQ4_XS** — Retain as heavy-duty specialist when VRAM budget allows (>10GB headroom); excellent capability despite aggressive quantization.

---

## 📝 Update Log
**Date:** June 5, 2026 | **Source:** `/home/nui/workspace/` and `/home/nui/workspace/llmTest/model_test_output/`  

### Newly Processed Models:
- **Qwen3.6-14B-A3B-VibeForged-v2-Q4_K_M**: Avg Speed 39.8 t/s | Score 24/100 | VRAM ~2GB
- **Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M**: Avg Speed 34.8 t/s | Score 23/100 | VRAM ~5.5-6GB
- **Qwopus3.6-35B-A3B-v1-IQ4_XS**: Avg Speed 33.2 t/s | Score 22/100 | VRAM 16-20GB

### Total Models Tracked: 15