# LLM Manager — Benchmark Module Integration Specification

## Overview

This specification describes the integration of a **Benchmark Module** into the existing `llm-manager` dashboard. Instead of a standalone app, this module provides a centralized interface for managing, viewing, and analyzing LLM performance results (speed and quality) directly within the orchestrator.

**Integration Goal**: Transform `llm-manager` from a server controller into a unified **LLM Intelligence Suite**.

---

## 1. Architecture & Integration Strategy

### Module Design
The Benchmark Module will be implemented as a discrete logical unit within the existing `llm-manager` project:
- **Backend**: A new FastAPI `APIRouter` module to be included in `main.py`.
- **Database**: A dedicated SQLite database file (`llm_bench.db`) to keep benchmark data separate from system telemetry/logs.
- **Frontend**: A new view/component within the existing Single Page App (SPA) architecture. To prevent the main `script.js` from becoming a "God file," the frontend will be modularized into separate logic files (e.g., `router.js`, `bench_ui.js`, `api_client.js`) that are dynamically loaded or organized as modules, maintaining a single-page experience without page reloads.

---

## 2. Database Schema (`llm_bench.db`)

### `models` — Model metadata
| Column | Type | Notes |
|---|---|---|
| model_id | TEXT PRIMARY KEY | Normalized from filename; strip `.gguf`, lowercase. e.g., `qwen3.6-35b-a3b-uncensored-hauhaucs-aggressive-iq3_m` |
| name | TEXT NOT NULL | Human-readable name (e.g., `Qwen3.6-35B-A3B-Uncensored`) |
| quantization | TEXT | e.g., `IQ3_M`, `Q4_K_M` |
| vram_fit | TEXT | Estimated VRAM requirement (e.g., `~17GB`). May be validated against P100's 16GB ceiling. |
| status | TEXT DEFAULT 'pending' | `active` / `rejected` / `pending` — **not** derived from tier score; reflects operational readiness on the target hardware |
| notes | TEXT | Qualitative findings (hallucinations, logic strength, etc.) |

### `rounds` — Per-round scoring data
| Column | Type | Notes |
|---|---|---|
| id | INTEGER PRIMARY KEY AUTOINCREMENT | |
| model_id | TEXT NOT NULL FK → models.model_id | |
| round_name | TEXT NOT NULL | Normalized: `knowledge_qa`, `technical_reasoning`, `code_generation`, `abstract_logic`, `creative_writing` (matches scoring rubric, not the JSON's "Round N:" format) |
| score | INTEGER | Raw score from scoring methodology (e.g., 13 out of 25 for Speed). Human-entered via `/upsert`. |
| max_score | INTEGER DEFAULT 0 | From scoring rubric (25 for Speed, 18 for Code/Tech Reasoning, 15 for Knowledge QA, 14 for Abstract Logic, 10 for Creative Writing) |
| speed_tps | REAL | Average tokens/sec — auto-computed from imported test data on ingestion |

### `scoring_rules` — Scoring rubric (seeded once)
| Column | Type | Notes |
|---|---|---|
| id | INTEGER PRIMARY KEY AUTOINCREMENT | |
| category_name | TEXT UNIQUE NOT NULL | e.g., `speed`, `code_generation`, `technical_reasoning`, `knowledge_qa`, `abstract_logic`, `creative_writing` (renamed from `round_name`; these are evaluation categories, not test rounds) |
| max_points | INTEGER DEFAULT 0 | From rubric: Speed=25, Code Gen=18, Tech Reasoning=18, Knowledge QA=15, Abstract Logic=14, Creative Writing=10 |

### `test_runs` — Per-test-run metadata (NEW)
| Column | Type | Notes |
|---|---|---|
| run_id | TEXT PRIMARY KEY | Auto-generated UUID or hash; links a single test execution to its model and rounds |
| model_id | TEXT NOT NULL FK → models.model_id | |
| timestamp | TEXT NOT NULL | From the JSON file's own `timestamp` field (e.g., `2026-06-03 21:40:20`) |
| raw_output_path | TEXT | Path to the original `.json` file on disk, for auditability |

### `round_scores` — Per-round scores linked to a specific test run (NEW)
| Column | Type | Notes |
|---|---|---|
| id | INTEGER PRIMARY KEY AUTOINCREMENT | |
| run_id | TEXT NOT NULL FK → test_runs.run_id | |
| round_name | TEXT NOT NULL | Same normalized names as `rounds.round_name` |
| score | INTEGER | Human-entered via `/upsert`. May be null if not yet scored. |

### `model_hallucinations` — Hallucination audit entries (NEW)
| Column | Type | Notes |
|---|---|---|
| id | INTEGER PRIMARY KEY AUTOINCREMENT | |
| model_id | TEXT NOT NULL FK → models.model_id | |
| round_name | TEXT NOT NULL | Which round/category the hallucination was observed in |
| description | TEXT NOT NULL | What happened (e.g., "Invented Thai city name suffix") |
| severity | TEXT DEFAULT 'warning' | `info` / `warning` / `critical` |

### SQLite Initialization Note
**CRITICAL**: SQLite does **not** enforce foreign key constraints by default. Your DB initialization code must run `PRAGMA foreign_keys = ON;` on every connection before any DDL/DML, or orphan rows will accumulate silently.

---

## 3. API Endpoints (`/api/benchmarks/...`)

All endpoints will be prefixed with `/api/benchmarks/` to avoid collisions with existing `llm-manager` APIs.

### Import, Upsert & Automation
| Method | Path | Request Body | Description |
|---|---|---|---|
| POST | `/api/benchmarks/import` | Multipart form-data: one `.json` file per request | **Ingests raw test data only — no scoring.** Extracts `model_name`, `timestamp`, and round metrics. Computes average TPS per round from JSON's `metrics.tokens_per_second`. Skips duplicates using the JSON's own `timestamp` + model ID as dedup key. **IMPORTANT**: May receive corrupted/broken output (e.g., `50% cut off` repeated, infinite loops). Must handle gracefully — do not crash or corrupt DB on malformed responses. |
| POST | `/api/benchmarks/upsert` | JSON body: `{ "model_id": "...", "name": "...", "quantization": "...", "vram_fit": "~17GB", "score_knowledge_qa": 7, "score_code_generation": 16, ... }` | **Human-entered or AI-suggested scores.** Populates the qualitative score columns. |
| POST | `/api/benchmarks/run` | JSON body: `{ "model_id": "..." }` or `{ "all_pending": true }` | **The Automated Runner**. Orchestrates a test cycle: 1. Commands `llama-server` to switch to the target model via Router API. 2. Waits for load confirmation. 3. Executes the 5-round benchmark suite. 4. Saves the resulting JSON to disk and triggers `/import`. |
| POST | `/api/benchmarks/judge` | JSON body: `{ "run_id": "..." }` | **The AI Judge**. Uses the currently loaded high-fidelity model (or a designated judge model) to evaluate raw outputs against the scoring rubric. It proposes scores and qualitative notes to be stored as "pending approval" in the DB. |
| DELETE | `/api/benchmarks/models/<id>` | — | Remove model and all associated data (rounds, test runs, hallucination entries) |

### Rankings & Detail Views
| Method | Path | Query Params | Response Schema |
|---|---|---|---|
| GET | `/api/benchmarks/rankings` | `tier=high-fidelity`, `search=h3`, `sort_by=total_score|speed|name`, `limit=20`, `offset=0` | Array of: `{ rank, model_id, name, quantization, total_score, tier, speed_tps, status }` |
| GET | `/api/benchmarks/rankings/tiers` | — | Object with tier names as keys, each containing count and list of model_ids |
| GET | `/api/benchmarks/models/<id>` | `run_id=<optional-filter>` | `{ model: { ... }, rounds: [ { round_name, score, max_score, speed_tps } ], test_runs: [ { run_id, timestamp, raw_output_path } ], hallucinations: [ { description, severity } ] }` |

---

## 4. Frontend Integration (`index.html` & `script.js`)

### UI Components
1.  **"Benchmarks" Navigation**: A new entry in the main dashboard sidebar.
2.  **Rankings Table**:
    *   Sortable columns (Speed, Score, Name).
    *   Color-coded rank badges — tiers match scoring methodology labels: 🥇 **High-Fidelity / Production Ready**, 🔹 **Strong Performers / Pipeline Optimized**, ⚠️ **Niche Utility / Routing & Filtering only**, ❌ **Underperformer for this hardware config**.
    *   **Status Column**: Visual indicators — `✅` stable, `⚠️` hallucination warnings (from `model_hallucinations` table), `🔴` rejected.
3.  **Tiered Sidebar**: Filter results by deployment readiness tiers matching the scoring methodology labels above.
4.  **Detail View**: An expandable area showing:
    *   Round-by-round breakdown (6 categories with individual scores)
    *   Total score and tier badge
    *   Qualitative notes from `models.notes`
    *   Hallucination audit entries from `model_hallucinations` (if any)
    *   **AI Judge Panel**: A "Review Suggestions" area where the user can see proposed scores from the AI Judge and click "Approve" to commit them to the DB.
5.  **Management Modals**: "Import JSON" (drag-and-drop); "Upsert Model" (manual entry); "Start Auto-Run" (trigger the Automated Runner for one or many models).

### Styling
*   Must use existing `style.css` and Tailwind classes for visual consistency.
*   Maintain the existing Dark/Light mode themes.

---

## 5. Automated Workflow & "AI Brain" Integration

### Initialization Flow
1.  **On Startup**: The module's initialization code checks for `llm_bench.db`. If missing, it creates it and runs `schema.sql` and `seed.sql`. **CRITICAL**: Must execute `PRAGMA foreign_keys = ON;` on every DB connection before any DDL/DML.
2.  **Nightly Runner (Auto-Test Cycle)**:
    *   A scheduled or user-triggered task scans for models in `models/` that lack recent test runs.
    *   It uses the `llama-server` Router API to switch models.
    *   It executes the benchmark suite, saving raw JSON outputs to `/home/nui/workspace/llmTest/model_test_output/`.
    *   It automatically triggers the `/import` endpoint.
3.  **AI-Assisted Scoring (The Judge)**:
    *   Once raw data is imported, the user (or a scheduled task) triggers the `/judge` endpoint.
    *   The system loads a "Judge" model (a high-fidelity MoE) and feeds it the rubric and the raw model responses.
    *   The Judge proposes scores and identifies hallucinations.
    *   The user reviews these suggestions in the UI, refining them before final submission via `/upsert`.
4.  **Background Migration**: A background task scans the workspace directory (`/home/nui/workspace/llmTest/model_test_output/`) for new `.json` files and imports them automatically using an idempotent process.

### Import Endpoint Behavior (Raw Data Only)
The `/import` endpoint ingests raw test output JSONs from llama.cpp — it does **NOT** compute or store any scores. Specifically:
- Extracts `model_name` / `model_id`, `timestamp`, and round-level metrics (`tokens_per_second`, `duration_seconds`, `tokens_generated`) from each round in the JSON
- Computes average TPS per round from the raw data (no scoring involved)
- **Skips corrupted/broken output gracefully**: If a round's response is entirely garbled (e.g., `50% cut off` repeated 4096 times), log a warning and continue with other rounds. Do not crash.
- Creates entries in `test_runs` to track which JSON file was ingested

### Upsert Endpoint Behavior (Human Scores)
The `/upsert` endpoint is where human-entered qualitative scores go:
- Accepts all 6 category scores: Speed, Code Generation, Technical Reasoning, Knowledge QA, Abstract Logic, Creative Writing
- May also update model metadata (name, quantization, vram_fit, notes)
- If the model_id doesn't exist in `models`, creates it with default status `'pending'`

### Scoring Methodology Reference
The backend does **NOT** auto-calculate scores. All 100-point scoring is human-entered via `/upsert`. The scoring methodology (from `benchmark_routine.md`) defines:

| Category | Max Points | Formula / Notes |
|---|---|---|
| ⚡ Speed | 25 | `(observed_avg_tps / 60) * 25`, capped at 25. Baseline: ~60 t/s (Hermes-3-Llama-3.2-3B) |
| 💻 Code Generation | 18 | Syntax correctness, architectural patterns, bug-free readiness |
| 🔬 Technical Reasoning | 18 | Step-by-step accuracy on CS/architecture concepts; penalizes hallucination |
| 📚 Knowledge QA | 15 | Factual accuracy; heavy penalties for confident hallucination |
| 🔢 Abstract Logic | 14 | Chain-of-thought coherence on math/logic transformations |
| ✍️ Creative Writing | 10 | Style adherence, narrative pacing, vocabulary richness |

### Tier Assignment (Score-Derived)
Tiers are computed at query time from the total score — no separate `tier` column is needed:
- `70+` → 🥇 High-Fidelity / Production Ready
- `60–69` → 🔹 Strong Performers / Pipeline Optimized
- `40–59` → ⚠️ Niche Utility / Routing & Filtering only
- `< 40` → ❌ Underperformer for this hardware config

### VRAM Ceiling Handling
Models exceeding the P100's 16GB hard limit should be flagged via status = `'rejected'` or a dedicated `vramp_exceeds_limit` boolean (TBD). Models that are technically loadable but require CPU offloading (which tanks performance to unusable levels, e.g., <5 t/s) should also receive appropriate flagging — they belong in the Underperformer tier.

### Data Retention Strategy (TBD)
The current design stores one entry per model. If models are re-tested with different quantizations or context lengths, a new `test_runs` record is created. Consider:
- **Retention**: Keep all historical test runs for auditability; do not prune automatically in v1
- **Averaging**: When multiple runs exist for the same model+quantization, average scores for display purposes (manual override still supported via `/upsert`)

---

## 6. Implementation Roadmap (Incremental & Testable)

The implementation will follow a "Build $\rightarrow$ Test $\rightarrow$ Commit" cycle. Each phase must be verified before moving to the next.

### Phase 1: Database Foundation
- **Task**: Create `schema.sql` and `seed.sql`. Implement the database connection logic in the backend ensuring `PRAGMA foreign_keys = ON;` is executed on every connection.
- **Test**: Initialize the app and verify `llm_bench.db` is created with all tables and seeded rules.
- **Commit**: `feat: benchmark db foundation`

### Phase 2: Basic Model Management API
- **Task**: Implement `GET /api/benchmarks/rankings` and `DELETE /api/benchmarks/models/<id>`. Implement a simple `POST /api/benchmarks/upsert` for manual entry.
- **Test**: Use `curl` to add a model, list it in rankings, and then delete it.
- **Commit**: `feat: benchmark basic model api`

### Phase 3: Raw Data Import Pipeline
- **Task**: Implement `POST /api/benchmarks/import`. Handle JSON parsing, TPS computation, and duplicate detection using the timestamp+modelID key. Implement graceful failure for corrupted output.
- **Test**: Upload a valid JSON and a corrupted JSON. Verify the valid one is recorded in `test_runs` and `rounds` while the corrupted one logs a warning.
- **Commit**: `feat: benchmark data import pipeline`

### Phase 4: Frontend - Navigation & Rankings
- **Task**: Modularize `script.js` into `router.js`, `api_client.js`, and `bench_ui.js`. Add the "Benchmarks" link to the sidebar and implement the Rankings Table with tier badges.
- **Test**: Navigate to Benchmarks and verify the table populates correctly from the API.
- **Commit**: `feat: benchmark rankings ui`

### Phase 5: Frontend - Detail View & Manual Upsert
- **Task**: Implement the expandable Detail View and the "Upsert Model" modal for human scoring.
- **Test**: Open a model's details, update its score via the modal, and verify the total score and tier badge update in real-time.
- **Commit**: `feat: benchmark detail view and scoring ui`

### Phase 6: The Automated Runner (Router Integration)
- **Task**: Implement `POST /api/benchmarks/run`. Integrate with the `llama-server` Router API to switch models, wait for loading, execute benchmark prompts, and save JSON files.
- **Test**: Trigger a run for a specific model. Verify the server switches models and a new `.json` file appears in the output directory.
- **Commit**: `feat: benchmark automated runner`

### Phase 7: The AI Judge (Inference Integration)
- **Task**: Implement `POST /api/benchmarks/judge`. Logic to feed raw outputs and the rubric to a high-fidelity model and store the result as "pending approval."
- **Test**: Run the judge on a recently imported test run. Verify proposed scores appear in the database.
- **Commit**: `feat: benchmark ai judge backend`

### Phase 8: Frontend - AI Judge Approval Workflow
- **Task**: Implement the "Review Suggestions" panel in the Detail View. Add "Approve" and "Edit" buttons to commit judge scores to the final record.
- **Test**: Review an AI-proposed score and click "Approve." Verify the final score is updated and the "pending" status is cleared.
- **Commit**: `feat: benchmark ai judge ui`

### Phase 9: Background Automation & Polish
- **Task**: Implement the background directory scanner for auto-import and the nightly run scheduler.
- **Test**: Drop a JSON file into the workspace folder and verify it is imported automatically without manual intervention.
- **Commit**: `feat: benchmark background automation`

---

## 7. Non-Goals (Out of Scope for v1)

- Multi-user authentication (use existing `llm-manager` security).
- Visual charting/graphing (stick to tables and text for v1).
- Automatic tier recalculation when scores change — tiers are computed at query time from total score.

## 8. Caveats & Assumptions

- **Scoring is entirely human-entered**: No auto-calculation of qualitative scores from raw test data. The import endpoint only ingests raw metrics (TPS, tokens generated). Scores come exclusively via `/upsert`.
- **Tiers are score-derived, not stored separately**: Tier badges are computed at query time from total score. This means UI must be responsive to score changes without requiring a separate "recalculate tiers" action.
- **Single source of truth for scores is the DB**: The manual cross-check between `llm_test_results.md` and `llm_scoring.md` (documented in the benchmark routine) should become unnecessary once all scoring data lives in the database. Score verification via UI is a v2 goal.
- **Corrupted test outputs are expected**: Models like `gemma-4-12b-it-Q4_K_M` produce completely garbled output on context-limit failures (50% cut off repeated). The import endpoint must handle these gracefully — log a warning, skip the corrupted round if possible, never crash.
- **P100 16GB is the reference platform**: VRAM estimates and tier assignments assume this hardware. Scores for models running on different hardware with CPU offloading should be flagged as incomparable.
