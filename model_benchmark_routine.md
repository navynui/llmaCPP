# LLM Model Benchmark Routine (P100 16GB)

## Step-by-Step Process

### 1. Locate & Read the Raw Test Data
- **Source:** `/home/nui/workspace/llmTest/model_test_output/`
- Open the new `.json` file for the model just tested.
- Verify it contains all 5 rounds: `Knowledge QA`, `Technical Reasoning`, `Code Generation`, `Abstract Reasoning`, `Creative Writing`.

### 2. Extract Key Metrics
From the JSON, pull out these numbers:
| Metric | Where to Find It | Notes |
|---|---|---|
| **Avg Speed (t/s)** | Average of `tokens_per_second` across all rounds | Primary ranking metric |
| **VRAM Fit** | Model size + quantization scheme | Q4_K_M = ~8GB, IQ3_S = ~17GB, etc. |
| **Quality Notes** | Round-by-round analysis | Note hallucinations, accuracy, code cleanliness |

### 3. Update the Master Document
- **File:** `/home/nui/llmaCPP/llm_test_results.md`
- Add a new row to the ranking table with Rank, Model Name, Quantization, Avg Speed (t/s), Intelligence / Notes, and Status icon:
  - `✅` for fast/accurate models
  - `⚠️` for OK or niche use
  - `🔴` for rejects (too large/slow)
- **Sorting:** Sort the table by final score in descending order.
- **Renumber** all existing ranks sequentially from 1.

### 4. Update Recommendations Section
- Review the "Recommended Models" section at the bottom.
- If a new model outperforms current recommendations, insert it in logical order.
- Note any significant qualitative findings (e.g., "beats official QAT variant", "hallucinates QA").

### 5. Final Checks Before Saving
- [ ] Are all ranks sequential and correct?
- [ ] Is the ranking table sorted by final score descending?
- [ ] Does the score in `llm_test_results.md` match the score in `llm_scoring.md`?
- [ ] Are VRAM estimates accurate for the P100's 16GB limit?
- [ ] Has the "Notes on Data Extraction" section been updated if new extraction methods were used?

### 6. Log Completion
Reply with:
- New model name and rank
- Comparison to best current pick (e.g., "faster than Qwen28B", "smarter but slower")
- Recommendation status for the active Docker container swap

---

## Quick Reference
- **P100 VRAM Ceiling:** 16GB hard limit. Anything >15GB needs careful context tuning or aggressive quantization (IQ4_XS, IQ3_S).
- **Speed Sweet Spot:** >25 t/s is interactive; <10 t/s feels sluggish.
- **Best Overall Pick (Current):** Hermes-3-Llama-3.1-8B.Q4_K_M (~34 t/s) or Granite 4.1 8B Q4_K_M (~29.5 t/s). For speed-only: Hermes-3-Llama-3.2-3B (~60 t/s, ~2GB).

---

## 🧮 Scoring Methodology & Weighting System (v1.0)

This benchmark applies a **100-point weighted scoring system** across 6 metrics to evaluate LLM performance on local inference hardware (P100 16GB). Scores directly inform model selection for routing, agentic tasks, or batch processing.

### 🔢 Metric Weights & Max Points
| Category | Max Points | Weight % | Primary Focus | Evaluation Criteria |
|---|---|---|---|---|
| **⚡ Speed** | 25 pts | 25% | Throughput & Latency | Normalized against a `60 t/s` baseline. Calculated as `(observed_tps / 60) * 25`. Capped at max if >60. |
| **💻 Code Generation** | 18 pts | 18% | Syntax, Logic, Completeness | Runs from 0–18 based on syntax correctness, architectural patterns (async/error handling), and bug-free execution readiness. |
| **🔬 Technical Reasoning** | 18 pts | 18% | Conceptual Depth & Accuracy | Evaluates step-by-step breakdowns of CS/architecture concepts. Scores penalize hallucination and reward structured, accurate explanations. |
| **📚 Knowledge QA** | 15 pts | 15% | Factual Retrieval & Translation | Tests factual accuracy (formal names, translations, dates). Heavy penalties for confident hallucination or outdated knowledge. |
| **🔢 Abstract Logic** | 14 pts | 14% | Multi-step Reasoning & Math | Assesses chain-of-thought coherence on mathematical derivations and logical transformations. Rewards structured intermediate steps. |
| **✍️ Creative Writing** | 10 pts | 10% | Style, Narrative, Tone | Measures adherence to prompt style, narrative pacing, vocabulary richness, and formatting consistency without drifting into boilerplate. |

### 🧮 Calculation Workflow
1. **Raw Qualitative Scoring:** Each model is evaluated across the 5 qualitative categories (Code through Creative) on a point scale matching the max points above. Scores are assigned by comparing outputs against expected benchmarks for that parameter/quantization tier, penalizing hallucination and rewarding precision.
2. **Speed Normalization Formula:** 
   - Baseline `60 t/s` = 25 pts.
   - Formula: `(Model_Avg_tps / 60) * 25`.
3. **Total Score Assembly:** Sum of all 6 category scores yields the final out-of-100 score.
4. **Ranking & Tiers:** Models are sorted descending by total score and bucketed into deployment tiers:
   - `70+`: 🥇 High-Fidelity / Production Ready (Best overall balance)
   - `60–69`: 🔹 Strong Performers / Pipeline Optimized
   - `40–59`: ⚠️ Niche Utility / Routing & Filtering only
   - `< 40`: ❌ Underperformer for this hardware config

### 📝 Application Notes for Future Runs
- **VRAM Headroom Impact:** Quantization (Q4/KM/IQ3) heavily impacts usable context length. Scores assume stable generation without OOM drops mid-prompt.
- **Timeout Penalties:** If a model times out on complex logic/knowledge rounds, those categories default to partial credit or `0` depending on failure type (crash vs silent fail), as observed in the DeepSeek-R1 run.
- **Consistency Check:** Re-run top-tier models 2–3 times and average scores if variance >5% across runs before finalizing rankings.
