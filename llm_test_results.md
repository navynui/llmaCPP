# LLM Model Performance Log (P100 16GB)

## Complete Test Results (Ordered by Score)

| Rank | Model Name | Quantization | Avg Speed (t/s) | Score /100 | Intelligence / Notes | Status |
|---|---|---|---|---|---|---|
| 1 | Hermes-3-Llama-3.1-8B.Q4_K_M | Q4_K_M (~5.5-6GB) | **34.4** t/s **FAST** | 73/100 | Strong reasoning, clean structure; TOP PICK for interactive use | ✅ FAST |
| 2 | Qwen3.6-28B-REAP20-A3B-Q4_K_M | Q4_K_M (~13-15GB) | **30.8** t/s **FAST** | 72/100 | Solid MoE performance | ✅ FAST |
| 3 | Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M | Q4_K_M (~5.5-6GB) | **34.9** t/s **FAST** | 71/100 | Fast uncensored variant — strong on technical/creative | ✅ FAST |
| 4 | Qwen3.6-35B-A3B-UD-IQ3_S | IQ3_S (16-20GB) | **32.8** t/s **FAST** | 69/100 | Strong MoE reasoning, fast for size; VRAM on GPU ceiling | ✅ FAST |
| 4 | Qwopus3.6-35B-A3B-v1-IQ4_XS | IQ4_XS (16-20GB) | **33.2** t/s **FAST** | 69/100 | Fast 35B MoE — excellent code gen, tech reasoning & creative writing; context-limit kills abstract reasoning | ✅ FAST |
| 5 | gemma-4-E4B-it-Q4_K_M | Q4_K_M (~5.5-6GB) | **35.4** t/s **FAST** | 67/100 | FASTEST LARGE MODEL, solid general capability | ✅ FAST |
| 5 | Qwen3.5-9B-Claude-HighIQ-THINKING-HERETIC-UNCENSORED-4.6-Q4_K | Q4_K (~5.5-6GB) | **29.6** t/s OK | 67/100 | Strong creative writing & abstract logic; code has concurrency bug | ✅ FAST |
| 5 | granite-4.1-8b-Q4_K_M | Q4_K_M (~5.5-6GB) | **30.8** t/s **FAST** | 67/100 | Highly reliable production workhorse; excellent structured outputs | ⚠️ HALLUCINATION WARNING |
| 7 | Hermes-3-Llama-3.2-3B.Q5_K_M | Q5_K_M (~2GB) | **60.8** t/s **BLAZING** | 63/100 | NEW ABSOLUTE SPEED KING (~60 t/s), but weak reasoning | ⚠️ HALLUCINATION WARNING |
| 9 | Qwen3.6-14B-A3B-VibeForged-v2-Q4_K_M | Q4_K_M (~9GB) | **39.8** t/s **FAST** | 61/100 | Fast MoE, good abstract logic & tech reasoning, but catastrophic QA hallucination & creative writing loop | ⚠️ HALLUCINATION WARNING |
| 10 | oh-dcft-v3.1-gpt-4o-mini.Q4_K_M | Q4_K_M (~6-8GB) | **34.5** t/s **FAST** | 50/100 | Very fast but hallucinates QA & buggy code snippets | ✅ FAST |
| 11 | Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M | Q4_K_M (~5.5-6GB) | **29.4** t/s OK | 42/100 | Small but fast; less capable reasoning | ⚠️ HALLUCINATION WARNING |

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
- **Qwen3.6-14B-A3B-VibeForged-v2-Q4_K_M**: Avg Speed 39.8 t/s | Score TBD | VRAM ~2GB
- **gemma-4-12b-it-Q4_K_M**: Avg Speed 19.3 t/s | Score 10/100 | UNSTABLE |
- **Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M**: Avg Speed 34.8 t/s | Score 71/100 | VRAM ~5.5-6GB
- **Qwopus3.6-35B-A3B-v1-IQ4_XS**: Avg Speed 33.2 t/s | Score TBD | VRAM 16-20GB
- **Qwen3.5-9B-Claude-HighIQ-THINKING-HERETIC-UNCENSORED-4.6-Q4_K**: Avg Speed 29.6 t/s | Score TBD | VRAM ~5.5-6GB

### Total Models Tracked: 12

---

## 🔴 Hallucination Audit — Knowledge QA Round (Bangkok Formal Name)

**Benchmark prompt:** *"What is the full formal name of Bangkok, Thailand? Please include the Thai script and official English translation."*  
**Correct answer:** Full name = กรุงเทพมหานคร อมรรัตนโกสินทร์ มหินทรายุธยา มหาดิลกภพ นพรัตน์ราชธานีบุรีรมย์ อุดมราชนิเวศน์มหาสถาน อมรพิมานอวตารสถิต สักกะทัตติยะวิษณุกรรมประสิทธิ์ | Short form = กรุงเทพมหานคร (Krung Thep Maha Nakhon)

| Model | Hallucination? | Evidence |
|---|---|---|
| `Hermes-3-Llama-3.1-8B` | ✅ No (short form only) | Gave กรุงเทพมหานคร correctly; truncated full name but no fabrication |
| `Qwen3.6-28B-REAP20` | ✅ No (incomplete) | `<think>` loop; knew correct segments but hit token limit before clean answer |
| `Qwen3.6-35B-A3B-UD-IQ3_S` | ✅ No (incomplete) | `<think>` loop working toward correct answer; hit context cap |
| `Gemma-4-E4B-Uncensored` | ✅ No (short form) | Gave กรุงเทพมหานคร correctly; noted it as abbreviated |
| `gemma-4-E4B-it` | ✅ No (short form) | Gave กรุงเทพมหานคร correctly; acknowledged it's the official shortened form |
| `oh-dcft-v3.1-gpt-4o-mini` | ✅ No (short form) | Gave กรุงเทพมหานคร correctly; then hallucinated Thai phrases unrelated to the question |
| `DeepSeek-R1-Distill-Qwen-32B` | ✅ No (short form) | Gave กรุงเทพมหานคร correctly; acknowledged it's the abbreviated form |
| `Qwopus3.6-35B` | ✅ No (incomplete) | Deep `<think>` reasoning; correctly identified all 8 name segments; hit token limit before clean answer |
| `Qwen3.5-9B-Claude-HighIQ` | ✅ No (short form) | Gave กรุงเทพมหานคร correctly; missed full ceremonial form; wrong attribution |
| `Hermes-3-Llama-3.2-3B` | 🔴 **YES** | Invented **"กรุงบงกช (Kun Bang Klang)"** and **"กรุงธนบุรี"** — complete fabrication |
| `granite-4.1-8b` | 🔴 **YES** | Invented **"กรุงเทพลูกเสือ (Krung Thep Luk Suea)"** = "tiger's cub"; fabricated Dvaravati etymology |
| `Qwen3.5-9B-Uncensored` | 🔴 **YES** | Started with fabricated **"Phra Chao Maha Nakhon"**; invented Rama I 1782 backstory; later corrected to short form |
| `gemma-3-12b-qat` | 🔴 **YES** | Thai script looks plausible but English transliteration is **completely fabricated gibberish** (repeated for 4096 tokens) |
| `gemma-3-12b-HighIQ` | 🔴 **YES** | Invented suffix **"อมรสินธุ์ บริพัตร สยามโอรส ยศวรไทยทิศ"** — not part of the real name |
| `gemma-4-12b-it` | 🔴 **YES (BROKEN)** | Total output failure — repeated **"50% cut off"** for entire 4096-token response |
| `gemma4-opus48` | 🔴 **YES** | Answered about **Khao Pad (fried rice)** — complete topic confusion; ignored the question entirely |
| `Qwen3.6-14B-VibeForged-v2` | 🔴 **YES** | Invented **"Bangkok City"** with fabricated etymology ("bany" = abundance) — no Thai script provided |

**Summary:** 8 out of 17 models tested produced hallucinated or broken responses to this factual question.  
**Models with ⚠️ HALLUCINATION WARNING:** `granite-4.1-8b`, `Hermes-3-Llama-3.2-3B`, `Qwen3.5-9B-Uncensored`, `gemma-3-12b-qat`, `gemma-3-12b-HighIQ`, `gemma-4-12b-it`, `gemma4-opus48`, `Qwen3.6-14B-VibeForged-v2`
