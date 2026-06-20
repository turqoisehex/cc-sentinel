## Workflows Config — `/5` prove-gate opt-in

Read before the §5 gate parses opt-in. This file is the INTENT signal (the second
signal is a live `ToolSearch select:Workflow` availability probe — an intent flag
can never answer "does this harness expose the tool").

### Keys (schema)

| Key | Type | Default | Rule |
|-----|------|---------|------|
| `workflows_enabled` | bool | `false` | ONLY always-required key. Absent → FILE-ABSENT (gate = OFF). `false` = OFF short-circuit (tunables NOT required). Malformed (not exactly `true`/`false`) = PARSE-FAIL. |
| `dryRounds` (K) | int | `2` | Required only when `workflows_enabled: true`. Floor 2; a phase may raise it. |
| `maxRounds` | int | `5` | Required only when `workflows_enabled: true`. MUST be ≥ `dryRounds` (else CLEAN is unreachable → PARSE-FAIL). |
| `budget` | `{rounds, spend}` | on | Recognized when enabled. Ceiling on BOTH axes, shared across the whole gate incl. all parent re-invocations. |
| `enabled-phases` | list | `["/5"]` | Required only when `workflows_enabled: true`. A phase not listed short-circuits to fallback. |
| `budgetGuard` | bool | on | Recognized when enabled. The parent circuit-breaker + budget ceiling. |
| `fanoutTypeCap` | int | `8` | Optional. Maximum number of touched data-model TYPES Phase 2.5 will fan out to in a single `/4` run. Absent → defaults to 8 without PARSE-FAIL (optional key). Exceeding the cap halts Phase 2.5 with `FIDELITY_BLOCKED` before the engine is invoked; the operator must narrow the type set, raise this value, or annotate the CT with a scoped subset. |
| `build-gates` | object | (skill defaults) | Optional. Per-project mechanisms the `/3` per-task deterministic VERIFY needs: `{ src, test, ext, diffScan?, gates: [{name, cmd}] }`. `src`/`test`/`ext` = the lens-4/5 grep roots + source extension; `diffScan` (optional) = the project's changed-field detector for lens 5; `gates[]` = the cheap-gate `{name, cmd}` pairs (each `name` maps to the verdict-file `source: gate-<name>` id). NESTED object → schema-aware parsing. Absent → lenses 4/5 run with the skill-default `src`/`test`/`ext`, cheap-gate tier degrades to lenses 4/5 only (graceful default, NO warning, NEVER PARSE-FAIL). Malformed (wrong shape — e.g. `gates` not an array of `{name,cmd}`) → graceful-default-WITH-warning (NOT a hard PARSE-FAIL, NOT a silent OFF). |

### Parse semantics (four distinct cases)
- file absent → FILE-ABSENT → gate = fallback, banner `config OFF`.
- `workflows_enabled: false` → OFF short-circuit; tunables are NOT checked (shipped default has no tunables).
- `workflows_enabled` present but malformed (not exactly `true`/`false`) → PARSE-FAIL (never silent OFF).
- `workflows_enabled: true` AND a required-when-enabled key missing/malformed = schema FAIL + auto-retry; if it
  still fails → fallback, banner `config PARSE-FAIL` (NOT silent OFF — a half-written
  config must not look like "off").

### Default-OFF stub (edit `workflows_enabled` to `true` to opt in; tunables are only needed when enabling)
workflows_enabled: false
<!-- tunables below are only parsed when workflows_enabled: true -->
<!-- dryRounds: 2     # consecutive fully-covered no-new-gap rounds = discovery converged (floor 2) -->
<!-- maxRounds: 5     # hard cap on discovery rounds; must be >= dryRounds -->
<!-- budget: { rounds: 12, spend: <your-ceiling> }  # stop if EITHER is exhausted -->
<!-- enabled-phases: ["/4","/5"]  # which phases run the engine -->
<!-- budgetGuard: true -->
<!-- fanoutTypeCap: 8   # optional; max touched model TYPES for /4 Phase 2.5 fan-out (default 8); absent = 8, not PARSE-FAIL -->
<!-- build-gates: { src: "lib", test: "test", ext: "dart", diffScan: "git diff <baselineRef> -- lib | grep -E '^[+-].*(final|String|int|bool|double|DateTime) '", gates: [ { name: "analyze", cmd: "flutter analyze" }, { name: "test", cmd: "flutter test --exclude-tags property,pairwise,slow" } ] }  # optional /3 per-task verify mechanisms; values shown are example project mechanisms (a Flutter/Dart project) — each project supplies its own; absent = skill defaults, malformed = graceful-default-with-warning, never PARSE-FAIL -->

### Two-signal gate (why a file, not an env var)
Opt-in = intent flag (this file) AND a live tool probe. One cross-platform `Read`
carries the whole knob-set; `$VAR`/`$env:VAR` reads split across PowerShell/POSIX.

### Pro-plan note (mandatory, MD-21 / §10.2 item 12)
On Pro plans, `workflows_enabled: true` ALONE will NOT expose the Workflow tool.
You must ALSO enable the harness-level Dynamic-workflows row via `/config`. Until
then the availability probe reports `tool absent` and the gate runs the single-pass
fallback. (Env var `SENTINEL_WORKFLOWS` is at most an optional convenience override
of `workflows_enabled` — never the primary mechanism.)
