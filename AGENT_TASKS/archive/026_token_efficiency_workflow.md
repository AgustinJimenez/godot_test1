# 026: Agent token-efficiency workflow

## Status

Complete and archived. `scripts/trace_query.py` is implemented and verified (stdlib-only, no install),
and `AGENTS.md`'s "Logs and live debugging" section points at it. The remaining ideas below
are optional future tooling, not unfinished acceptance criteria for this task.

## Problem

Token cost equals bytes placed in the model's context. Foot IK work produces 10-20 MB
JSONL traces, 1000-line source files, and 60-row per-frame tables. Raw artifacts must
never reach the context; deterministic tools should answer questions and emit a few
lines. In one session, avoidable waste was roughly 40-50% of tokens: an accidental
full-frame JSON dump, several multi-row frame tables pasted into chat, whole-file reads,
and re-reads of already-seen regions.

## Implemented

`scripts/trace_query.py` - compact query CLI over the Foot IK JSONL schema. Pure
`python3` stdlib (works in CI/pre-commit, no pip). It parses JSONL line by line, bounds
memory when `--last-n` is used, and reports malformed input or empty query windows in a
compact diagnostic. Traces are small enough that DuckDB/polars only matter above ~1 GB.

```sh
python3 scripts/trace_query.py --trace /tmp/trace.jsonl summary
python3 scripts/trace_query.py --trace /tmp/trace.jsonl worst --metric toe --n 5
python3 scripts/trace_query.py --trace /tmp/trace.jsonl clips --n 5
python3 scripts/trace_query.py --trace /tmp/trace.jsonl toe-riser --n 5
python3 scripts/trace_query.py --trace /tmp/trace.jsonl swing --from 70 --to 74 --side right
python3 scripts/trace_query.py --trace /tmp/trace.jsonl field --path feet.right.target_owner --from 71 --to 74
python3 scripts/trace_query.py --trace /tmp/trace.jsonl keys
```

Notes:
- `key` names use the trace's documented `feet.*` fields; missing keys are tolerated so
  older trace schemas still answer.
- `toe-riser` hardcodes the preview scene's staircase origins/rises
  (`foot_ik_preview.gd _build_stairs`); update `_PREVIEW_STAIRS` if that geometry moves.
- `user://` paths are not resolved - pass a real path (Godot user dir depends on OS).
- Every record requires the schema's numeric `frame` identity. Optional nested fields
  remain tolerant so older trace schemas still answer with `no-data` where appropriate.

## Candidate implementations (menu)

### 1. Get data out of context
- ~~`trace_query.py`~~ (done).
- Extend `scripts/trace.sh` / `analyze_trace.gd` with the same named queries so the
  Godot-side tool and the Python tool stay in sync.
- `jq` (present at `/usr/bin/jq`) for ad-hoc JSONL slicing: `jq -c 'select(...)'`.
- `duckdb` (not installed; `brew install duckdb`) for SQL over JSONL/CSV and parquet
  caching if traces ever grow past ~1 GB. `read_json_auto()` handles the schema.
- `mlr` (Miller) for CSV/TSV streaming summaries.
- Make every headless harness print one `CHECK PASS metric=...` line (already the house
  style) and store baselines numerically, so regressions are a `SELECT`/diff, not a
  reading exercise.

### 2. Search/index instead of reading files
- `ast-grep` / `sg` (not installed) for structural GDScript queries:
  `sg -p 'func $F($$$)' -l gdscript`, or "every call to `_apply_support_contact`".
- `universal-ctags` (only BSD `ctags` present) for a jump-to-symbol index;
  GNU Global/`gtags` as an alternative.
- A Godot/GDScript language server in the client for go-to-definition and references.
- Regex `rg` with `-A/-B/-C`, `--max-count`, and `--glob` windowed to a few lines;
  always prefer the built-in `grep` tool (clean output) over the wrapped `rg`, whose
  output has been observed to mangle match text.
- Reading rule: grep for the symbol, read +/-20 lines - not the whole file/function.

### 3. Summarize hierarchically
- Have harnesses compute the acceptance numbers; the model sees only the verdict.
- Cache per-scenario metrics into JSON/SQLite so a regression run is one query.
- Optional local-LLM pre-filter (`mods`, `llm`, `ollama`) to condense large logs before
  they enter the main context.

### 4. Agent/context engineering
- Delegate broad search to the `explore` subagent (separate context; returns a summary).
- Batch independent searches in one message (parallel tool calls).
- Scope one fresh context per sub-task; hand off via the `AGENT_TASKS/NNN` file.
- Load skills only when their task matches.
- Ask for an exact one-line output contract ("worst toe depth frame only") so
  investigation does not sprawl into chat.

### 5. Tooling / integrations
- MCP server exposing trace-query + scene-run + graph metrics as structured tools
  (opencode supports MCP natively; this repo already has an MCP bridge). Lets the model
  call functions instead of shell + parse + paste.
- Custom opencode commands for the recurring loop: "run fast suite, summarize",
  "query worst clip", "A/B a file against HEAD".

### 6. Caching / baselines
- A checked-in `baseline.json` of known-red numbers (see `check_foot_ik_all.sh`'s
  `KNOWN_BASELINE_FAILURES`) so numeric comparison replaces re-derivation.
- Parquet/SQLite sidecar for repeated trace queries.

### 7. Process discipline (cheapest, no install)
- At the source: `godot ... > "$log" 2>&1 || true`, then `rg`/`head` - never print raw.
- Never run `python3 file.jsonl <<EOF` (heredoc consumed as stdin, JSONL as the script);
  use `python3 - file.jsonl`.
- Prefer one tool call that prints a verdict over five that print evidence.
- Redirect per-frame analysis to `/tmp/*.txt`; print only top-N + a +/-3-frame window.

## Pick order (highest value first)

1. Use `trace_query.py` for every trace question (zero setup).
2. Add `ast-grep` + GNU `ctags` and adopt the grep-then-read rule.
3. Delegate exploration to subagents by default.
4. Add baseline files for numeric regression comparison.
5. Only then consider DuckDB/MCP/local-LLM infrastructure.

## Verification

- `python3 scripts/trace_query.py --trace <trace> summary|clips|toe-riser|swing` on a
  real capture prints the expected compact lines (checked against
  `/tmp/walk_contact_trace.jsonl` and the preserved live session trace).
- All seven commands were rechecked against the current live trace; empty windows,
  truncated vector fields, malformed JSON, invalid arguments, and missing optional foot
  data produce bounded explanations rather than silence or tracebacks.
- Keep `trace_query.py` stdlib-only; `scripts/check.sh` and therefore pre-commit now
  syntax-check every repository Python tool without generating cache files.
