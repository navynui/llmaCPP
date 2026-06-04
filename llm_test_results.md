# LLM Model Performance Log (P100 16GB)

## Complete Test Results (Ordered by Speed)

| Rank | Model Name | Quantization | Avg Speed (t/s) | Intelligence / Notes | Status |
|---|---|---|---|---|---|
| 1 | Hermes-3-Llama-3.2-3B.Q5_K_M.gguf | Q5_K_M (~2GB) | **60.6** t/s | Blazing fast, but weak reasoning & code gen; excellent as a lightweight router or prompt filter | ✅ NEW SPEED KING |
| 2 | gemma-4-E4B-it-Q4_K_M.gguf | Q4_K_M (~8GB) | **35.3** t/s | Excellent speed, solid general capability | ✅ FASTEST LARGE MODEL |
| 3 | oh-dcft-v3.1-gpt-4o-mini.Q4_K_M.gguf | Q4_K_M (~6GB) | **34.4** t/s | Very fast, but hallucinates QA & generates buggy code snippets | ⚠️ FAST/UNSTABLE |
| 4 | gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf | Q4_K_M (~8GB) | **34.4** t/s | Fast uncensored variant — strong on technical/creative, hallucinates factual QA | ✅ FAST |
| 5 | Hermes-3-Llama-3.1-8B.Q4_K_M.gguf | Q4_K_M (~5.5GB) | **34.2** t/s | Strong reasoning, clean structure, slightly verbose on factual QA | ✅ TOP PICK |
| 6 | Qwen3.6-35B-A3B-UD-IQ3_S.gguf | IQ3_S (~17GB) | **32.8** t/s | Strong MoE reasoning, fast for size | ✅ HIGH PERFORMER |
| 7 | Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf | Q4_K_M (~15GB) | **30.7** t/s | Solid dense MoE, balanced performance | ✅ RECOMMENDED |
| 8 | granite-4.1-8b-Q4_K_M.gguf | Q4_K_M (~5.5GB) | **~29.5** t/s | Highly reliable, straightforward structured outputs; excellent for production pipelines | ✅ RECOMMENDED |
| 9 | Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf | Q4_K_M (~5.5GB) | **29.4** t/s | Small model, fast but less capable | ⚠️ SMALL MODEL |
| 10 | gemma-3-12b-it-HighIQ-Uncensored-Thinking.i1-Q4_K_M.gguf | Q4_K_M (~8GB) | **19.6** t/s | Best tool-calling & QA in small-model tier — accurate, clean code gen, beats official QAT variant | ✅ TOP TIER |
| 11 | gemma-3-12b-it-qat-Q4_K_M.gguf | Q4_K_M (~8GB) | **~19.5** t/s | Good structure/code, but heavily hallucinates factual QA compared to HighIQ variant | ⚠️ OK |
| 12 | gemma-4-26B-A4B-it-APEX-GGUF | APEX Q4 (~13GB) | **18.0** t/s | Decent quality, acceptable speed | ⚠️ OK |
| 13 | gemma-4-26B-A4B-it-UD-IQ4_XS.gguf | IQ4_XS (~13.6GB) | **17.0** t/s | Similar to APEX, slightly slower | ⚠️ OK |
| 14 | DeepSeek-R1-Distill-Qwen-32B-IQ3_M.gguf | IQ3_M (~14GB) | **~3.0** t/s ❌ | Massive CoT overhead; unusable for interactive speed despite strong reasoning depth | 🔴 REJECT |

## Test Environment
- **GPU:** Tesla P100 PCIE 16GB (Compute 6.1)
- **Context Window:** Varies per test (tested up to ~4096 tokens)
- **Benchmark Suite:** 5-round evaluation (Knowledge QA, Technical Reasoning, Code Generation, Abstract Reasoning, Creative Writing)
- **Date:** June 2026

### Notes on Data Extraction
Raw test data is stored as individual JSON files in `/home/nui/workspace/llmTest/model_test_output/`. Each file follows a standard 5-round evaluation format (`Knowledge QA`, `Technical Reasoning`, `Code Generation`, `Abstract Reasoning`, `Creative Writing`). The "Avg Speed (t/s)" column aggregates the `tokens_per_second` metrics from all successful rounds. Qualitative notes ("Intelligence / Notes") are derived from round-by-round prompt/response analysis, scoring factors like accuracy, code correctness, and hallucination rates.

## Key Findings & Recommendations

### What Works Well on P100 16GB:
- **Hermes-3-Llama-3.2-3B (Q5_K_M)** is the new absolute speed king at ~60.6 t/s, using only ~2GB VRAM. However, it's a very small model (~3B) with weak reasoning and code generation skills. Best used as a lightning-fast router/prompt filter or simple chatbot.
- **Hermes-3-Llama-3.1-8B & GPT-4o-mini (~5.5-6GB)** remain the speed champions for capable models at ~34 t/s, delivering snappy interactive response times while leaving massive VRAM headroom for context windows or concurrent requests.
- **Granite 4.1 8B Q4_K_M** emerges as a highly reliable production workhorse (~29.5 t/s). It consistently generates structured, accurate outputs with minimal hallucination, making it ideal for automated pipelines and enterprise tooling.
- **Gemma 3 12B-it (Q4_K_M)** remains the benchmark for tool-calling and factual QA in the small-model tier (~8GB). The HighIQ/Uncensored variant significantly outperforms Google's official QAT build on code generation, reasoning accuracy, and knowledge retrieval.
- **E4B variants (~8GB)** continue to offer maximum raw speed (~35 t/s) while maintaining solid general capability for lightweight tasks.
- **Qwen3.6 series (MoE, ~28-35B)** performs surprisingly well even with aggressive quantization (IQ3_S). The 35B-A3B variant hit 32.8 t/s — very close to E4B speed with much more capability.

### What to Avoid:
- Models >15GB (like Qwen2.5-Coder-32B Q4_K_M) **must not be loaded on P100** without CPU offloading, which tanks performance to unusable levels (<5 t/s).
- Heavy reasoning/CoT models like **DeepSeek-R1-Distill-Qwen-32B-IQ3_M** (~14GB VRAM) generate excellent chain-of-thought but are completely unusable for interactive workloads due to massive overhead (~3 t/s average). Reserve only for offline batch processing.
- Aggressive custom quantizations (IQ4, APEX) on the 26B-A4B MoE are fine but offer no real advantage over standard Q4_K_M in this size range.

### Recommended Models for Future Use:
1. **Hermes-3-Llama-3.2-3B.Q5_K_M** — New absolute speed king (~60 t/s, ~2GB). Ideal for lightweight routing, prompt filtering, or simple chat where reasoning depth isn't critical.
2. **Hermes-3-Llama-3.1-8B.Q4_K_M (or oh-dcft-v3.1-gpt-4o-mini)** — Best balance of speed + reliability (~34 t/s, ~6GB). Llama 3.1 variant is preferred over the GPT-4o-mini fork for stable code generation and accurate reasoning without heavy hallucination.
3. **Granite 4.1 8B Q4_K_M** — Highly reliable production workhorse (~29.5 t/s, ~5.5GB). Excellent structured outputs; perfect for pipeline automation & enterprise use cases where consistency matters more than raw throughput.
4. **Gemma 3 12B-it (HighIQ Uncensored)** — Still #1 for specialized tool-calling, complex QA chains, and agentic workflows requiring high instruction adherence (~8GB).
5. **Qwen3.6-28B/35B-A3B series** — Retain as heavy-duty specialists for deep research & long-context synthesis when VRAM budget allows (>10GB headroom).

---

## 📝 Update Log (Step 6)
**Date:** June 3, 2026 | **Source:** `/home/nui/workspace/llmTest/model_test_output/`  
**New Models Added:** 5 files processed via automated JSON extraction.  

| Model | Rank | Avg Speed | VRAM Est. | Verdict vs Current Best | Recommendation Status |
|---|---|---|---|---|---|
| `Hermes-3-Llama-3.2-3B.Q5_K_M` | 1 | **60.6** t/s | ~2GB | New speed champion, but limited reasoning due to small size | ✅ **NEW ABSOLUTE #1 SPEED** |
| `oh-dcft-v3.1-gpt-4o-mini.Q4_K_M` | 3 | **34.4** t/s | ~6GB | Faster than Gemma 12B, but hallucinates QA & buggy code snippets | ⚠️ Keep for speed demos only |
| `Hermes-3-Llama-3.1-8B.Q4_K_M` | 5 | **34.2** t/s | ~5.5GB | Matches GPT-4o-mini speed with significantly better reasoning stability & cleaner structure | ✅ **TOP PICK** for interactive use |
| `Qwen3.6-35B-A3B-UD-IQ3_S` | 5 (Quality) | **32.8** t/s | ~17GB | High MoE reasoning depth, but VRAM consumption is right on the GPU ceiling and hallucinates on factual QA | ⚠️ Niche Specialist |
| `granite-4.1-8b-Q4_K_M` | 6 | **~29.5** t/s | ~5.5GB | Highly reliable, straightforward structured outputs; beats Gemma 3 QAT on factual consistency | ✅ **RECOMMENDED** for production pipelines |
| `gemma-3-12b-it-qat-Q4_K_M` | 8 | **~19.5** t/s | ~8GB | Good structure/code generation, but heavily hallucinates factual QA vs HighIQ variant | ⚠️ OK / fallback only |
| `DeepSeek-R1-Distill-Qwen-32B-IQ3_M` | 14 | **~3.0** t/s ❌ | ~14GB | Massive CoT overhead; completely unusable for interactive speed despite strong reasoning depth | 🔴 REJECT (offline batch only) |

**Container Swap Ready:** `Hermes-3-Llama-3.2-3B.Q5_K_M` or `Hermes-3-Llama-3.1-8B.Q4_K_M`  
**VRAM Headroom:** The 3B variant leaves ~14GB free on P100, enabling massive context windows or highly concurrent batched requests.
