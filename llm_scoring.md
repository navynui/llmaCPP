# 📊 LLM Model Scoring Report (P100 16GB)
**Date:** June 3, 2026  
**Base Speed Normalization:** `60 t/s` = 25 pts | **Total Max Score:** 100 pts

### 🔢 Scoring Methodology
Models are evaluated across **6 weighted metrics** totaling 100 points. 
- **Speed (25 pts):** Calculated via `(Model_tps / 60) * 25`. Baseline is set to ~60 t/s based on the current fastest model (`Hermes-3-Llama-3.2-3B`).
- **Qualitative Metrics:** Each category is scored out of its max points (18, 15, 14, or 10) based on prompt adherence, factual accuracy, structural logic, and code completeness per the raw JSON test outputs.

---

## 🏆 Ranked Results (Sorted by Total Score)

| Rank | Model Name | Speed (t/s) | ⚡ Speed | 💻 Code | 🔬 Tech Reason | 📚 Knowledge QA | 🔢 Abstract Logic | ✍️ Creative Writing | **Total** |
|:---|:---|:---|:---|:---|:---|:---|:---|:---|:---|
| 1 | `gem-3-12b-it-HighIQ-Uncensored-Thinking.i1` | 19.6 | **8** /25 | **16/18** | **17/18** | **14/15** | **13/14** | **6/10** | **🥇 74/100** |
| 2 | `Hermes-3-Llama-3.1-8B.Q4_K_M` | 34.2 | **14/25** | **18/18** | **16/18** | **7/15** | **12/14** | **7/10** | **🥈 73/100** |
| 3 | `Qwen3.6-28B-REAP20-A3B-Q4_K_M` | 30.7 | **13/25** | **14/18** | **15/18** | **12/15** | **11/14** | **7/10** | **🥉 72/100** |
| 4 | `Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M` | 34.4 | **14/25** | **15/18** | **16/18** | **7/15** | **10/14** | **9/10** | **🏅 71/100** |
| 5 | `Qwen3.6-35B-A3B-UD-IQ3_S` | 32.8 | **14/25** | **15/18** | **16/18** | **5/15** | **11/14** | **8/10** | **🏅 69/100** |
| 6 | `gemma-4-E4B-it-Q4_K_M` | 35.3 | **15/25** | **14/18** | **13/18** | **10/15** | **9/14** | **6/10** | **🏅 67/100** |
| 7 | `granite-4.1-8b-Q4_K_M` | ~29.5 | **12/25** | **17/18** | **17/18** | **6/15** | **9/14** | **6/10** | **🏅 67/100** |
| 8 | `Hermes-3-Llama-3.2-3B.Q5_K_M` | 60.6 | **25/25** | **3/18** | **9/18** | **4/15** | **13/14** | **7/10** | **🔹 63/100** |
| 9 | `gemma-3-12b-it-qat-Q4_K_M` | ~19.5 | **8/25** | **12/18** | **13/18** | **7/15** | **9/14** | **6/10** | **🔹 55/100** |
| 10 | `oh-dcft-v3.1-gpt-4o-mini.Q4_K_M` | 34.4 | **14/25** | **8/18** | **10/18** | **5/15** | **7/14** | **6/10** | **🔹 50/100** |
| 11 | `gemma-4-26B-A4B-it-APEX-GGUF` | 18.0 | **8/25** | **11/18** | **9/18** | **8/15** | **6/14** | **5/10** | **🔹 47/100** |
| 12 | `Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M` | 29.4 | **12/25** | **8/18** | **7/18** | **6/15** | **5/14** | **4/10** | **🔹 42/100** |
| 13 | `gemma-4-26B-A4B-it-UD-IQ4_XS` | 17.0 | **7/25** | **10/18** | **8/18** | **7/15** | **5/14** | **4/10** | **🔹 41/100** |
| 14* | `DeepSeek-R1-Distill-Qwen-32B-IQ3_M` | ~3.0 | **1/25** | **18/18** | **18/18** | **15/15** | **N/A (Timeout)** | **9/10** | **🔹 46/100†** |

---

### 📝 Detailed Category Breakdowns
| Rank | Model | ⚡ Speed Score | 💻 Code Gen | 🔬 Tech Reasoning | 📚 Knowledge QA | 🔢 Abstract Logic | ✍️ Creative Writing |
|:---|:---|:---|:---|:---|:---|:---|:---|
| 1 | `gem-3-12b-HighIQ` | **8** (19.6 t/s) | Excellent clean code gen, beats official QAT variants | Highly accurate step-by-step technical breakdowns | Factual QA is highly reliable with correct translations | Strong multi-step logical manipulation & chain-of-thought | Solid style adherence & narrative pacing |
| 2 | `Hermes-3-Llama-3.1-8B` | **14** (34.2 t/s) | Complete, highly optimized Python script with rate limiting & async error handling | Detailed step-by-step explanation of KV cache allocation vs static buffers | Hallucinates factual names (e.g., Bangkok's formal Thai name) | Robust structural logic despite verbose output | Clean narrative structure, slightly verbose on factual constraints |
| 3 | `Qwen3.6-28B-REAP20` | **13** (30.7 t/s) | Reliable code generation with clean syntax & documentation | Very capable dense MoE reasoning with accurate domain knowledge | Strong retrieval capabilities for its model class | High logical capacity due to Mixture-of-Experts architecture | Consistent style adherence across varied creative prompts |
| 4 | `Gemma-4-E4B-Uncensored` | **14** (34.4 t/s) | Excellent technical code generation with modern async patterns | Strong performance on complex domain knowledge queries | Heavy hallucination in factual QA tasks despite speed | Decent abstract logic but struggles with multi-variable transformations | Uncensored/aggressive prompting yields highly diverse & vivid narratives |
| 5 | `Qwen3.6-35B-A3B-UD-IQ3_S` | **14** (32.8 t/s) | Solid dynamic code generation; script runs in executor but hits generation cutoff | Comprehensive technical reasoning on KV contiguous pooling & memory pools | Moderate knowledge retrieval; hallucinates Thai names with Latin chars | Solid mathematical derivations with step-by-step proofs | Excellent hard-boiled cyberpunk first-person story |
| 6 | `gemma-4-E4B-it-Q4_K_M` | **15** (35.3 t/s) | Solid, functional code generation across multiple languages | Good general technical capability without deep specialization | Moderate QA accuracy; relies on prompt structure for factual grounding | Acceptable logical transformations but lacks deep chain-of-thought | Adequate creative writing for standard prompts |
| 7 | `granite-4.1-8b-Q4_K_M` | **12** (29.5 t/s) | Highly optimized Python scripts with custom rate limiters & backoff | Exceptionally structured, clear explanations of paged attention vs static buffers | Hallucinates formal names & factual QA; requires strict constraints for accuracy | Moderate abstract reasoning capability | Straightforward, highly predictable text generation |
| 8 | `Hermes-3-Llama-3.2-3B` | **25** (60.6 t/s) | Skeleton code with placeholder comments requiring human intervention | Plausible but slightly hallucinated memory management explanations | Incorrect factual translations & formal city names | Excellent mathematical formula derivation `(N-j, i)` | Surprisingly competent narrative generation for a sub-4GB model |
| 9 | `gemma-3-12b-qat` | **8** (19.5 t/s) | Good structure but prone to logical gaps in async code | Solid technical explanation, lacks depth of HighIQ variant | Heavily hallucinates factual QA compared to the HighIQ version | Standard small-model abstract reasoning performance | Acceptable style adherence with minor formatting inconsistencies |
| 10 | `oh-dcft-v3.1-gpt-4o-mini` | **14** (34.4 t/s) | Buggy code snippets requiring significant rewriting | Shallow technical explanations that miss architectural nuances | Severe factual hallucination under open-ended QA prompts | Superficial abstract logic handling | Decent creative writing but struggles with long-form coherence |
| 11 | `gemma-4-26B-A4B-it-APEX` | **8** (18.0 t/s) | Functional code generation with standard patterns | Acceptable technical reasoning, lacks architectural depth | Moderate QA accuracy degraded by quantization artifacts | Struggles with multi-step logical transformations under tight VRAM | Basic narrative generation with limited stylistic range |
| 12 | `Qwen3.5-9B-Uncensored` | **12** (29.4 t/s) | Fast but simplified code output lacking error handling | Superficial technical explanations missing key implementation details | Limited factual knowledge base due to smaller parameter count | Weak multi-step logic; prone to early termination errors | Basic narrative generation with limited plot depth |
| 13 | `gemma-4-26B-A4B-it-UD-IQ4_XS` | **7** (17.0 t/s) | Similar functionality to APEX variant with slightly more output overhead | Comparable technical reasoning with minor quantization degradation | Moderate QA accuracy hampered by aggressive IQ4_XS compression | Poor handling of complex logical transformations | Minimal stylistic variation; repetitive sentence structures |
| 14* | `DeepSeek-R1-Distill-Qwen-32B` | **1** (~3.0 t/s) | Complete, production-grade async Python scripts with rate limiters & backoff | Excellent step-by-step breakdowns of paged attention vs static buffers | Correctly identifies formal names (`Krung Thep Maha Nakhon`) & translations | ⚠️ **TIMEOUT** on Round 4 (600s read timeout) | High-quality cyberpunk narrative with strong thematic adherence |

---

### 📊 Key Takeaways for P100 Deployment
- **🥇 Best Overall Balance:** `Gemma 3 12B HighIQ` & `Hermes-3-Llama-3.1-8B` dominate the top tier (~73-74 pts). The Llama variant is faster and better for code generation, while Gemma excels at factual QA & reasoning accuracy.
- **⚡ Pure Speed vs Capability Trade-off:** `Hermes-3-Llama-3.2-3B` maxes out speed (60 t/s) but scores only 63/100 due to weak code/QA generation. Ideal strictly for lightweight routing or prompt filtering, not agentic tasks.
- **🔧 Production Reliability:** `Granite-4.1-8B` scores a tied 67/100 and is arguably the best model for automated pipelines due to its highly structured, low-hallucination technical outputs—despite lower QA accuracy.
- **⚠️ DeepSeek-R1 Anomaly:** Though it crashes under interactive constraints (~3 t/s avg) and timed out on abstract reasoning (`DeepSeek-R1-Distill-Qwen-32B`), its *raw output quality* when it responds is exceptional (Code: 18/18, Tech: 18/18). Reserve strictly for offline batch processing, not live inference.
