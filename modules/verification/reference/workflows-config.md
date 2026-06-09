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
<!-- enabled-phases: ["/5"]  # which phases run the engine -->
<!-- budgetGuard: true -->

### Two-signal gate (why a file, not an env var)
Opt-in = intent flag (this file) AND a live tool probe. One cross-platform `Read`
carries the whole knob-set; `$VAR`/`$env:VAR` reads split across PowerShell/POSIX.

### Pro-plan note (mandatory, MD-21 / §10.2 item 12)
On Pro plans, `workflows_enabled: true` ALONE will NOT expose the Workflow tool.
You must ALSO enable the harness-level Dynamic-workflows row via `/config`. Until
then the availability probe reports `tool absent` and the gate runs the single-pass
fallback. (Env var `SENTINEL_WORKFLOWS` is at most an optional convenience override
of `workflows_enabled` — never the primary mechanism.)
