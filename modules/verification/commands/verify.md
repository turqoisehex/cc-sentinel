# /verify — Launch Verification Squad

**Trigger:** `/verify [scope]`

Run the Verification Squad (up to 5 parallel agents) against a specified scope of work.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix.

**Scope check:** Verify squad scope belongs to your channel. Cross-channel scope → use unchanneled paths.

## Scopes

| Usage | Scope |
|-------|-------|
| `/verify` | Staged + unstaged. If clean, last commit. |
| `/verify full` | All changes since session start (find boundary in CT or `git log --oneline -20`). |
| `/verify last` | `HEAD~1..HEAD` |
| `/verify last N` | `HEAD~N..HEAD` |
| `/verify since <ref>` | `<ref>..HEAD` + uncommitted |
| `/verify on <files>` | Specific file(s) only. Comma-separated or glob. |
| `/verify commit <hash>` | `<hash>~1..<hash>` |

## Procedure

### Step 1: Determine scope and gather changes

Run the appropriate git diff command for the scope (see table above). Use `--stat` for overview. Produce a **change summary**: files changed, lines added/removed, one-sentence description.

### Step 2: Identify source spec

Check in order: (1) CT spec reference, (2) user's invocation, (3) changed files → governing spec, (4) user's original request as requirement source. Never silently skip — if no spec, state explicitly: "No authoritative spec found. Using user request as requirement source."

### Step 3: Build squad parameters

```
WORK_PRODUCT: [changed files with paths]
SOURCE_SPEC: [spec file path, or "User request: <quoted text>"]
SCOPE_SUMMARY: [one sentence]
SQUAD_DIR: squad_[chN_]sonnet/
```

### Step 4: Launch verification

**Default mode (native dispatch):**
Spawn `sonnet-verifier` subagent via `Agent(model: "sonnet")`. Pass: WORK_PRODUCT, SOURCE_SPEC, SCOPE_SUMMARY, SQUAD_DIR, list of agents to launch (from Step 4a filtering).

The subagent:
1. Writes manifest.json to squad directory
2. Spawns verification agents in parallel
3. Collects all results to standard paths
4. Returns: overall verdict + finding counts + path to summary file

**Duo mode** (`CC_DUO_MODE=1` or Sonnet listener active):
Write squad prompt to `_pending_sonnet/[chN/]squad_<timestamp>.md` with YAML frontmatter. Wait via `bash scripts/wait_for_results.sh` (run_in_background: true).

"Simple enough to do myself" / "already have context" / "faster" / "no heartbeat detected" are NOT valid bypass reasons.

**Sonnet sessions** (detected by `SENTINEL_LISTENER=true` env var): Spawn the verification agents directly with `run_in_background: true` and write to the squad directory. Do NOT follow the delegation block. Detection: persistent Sonnet listeners set `SENTINEL_LISTENER=true` (injected by spawn.py during session launch). Native Sonnet subagents do NOT have this var — they follow the default mode path and return results to their parent.

**`/verify local <scope>`:** Preserved as an explicit override. Forces local agent execution regardless of mode — equivalent to default-mode behavior even in a duo session. Useful for quick single-agent re-runs where file-based dispatch is unnecessary overhead.

#### Step 4a: Smart agent filtering

Before launching agents, classify the changed files to determine which agents are relevant:

| File Category | Agents Launched |
|---|---|
| Docs only (.md, .txt, .rst) | cold_reader.md |
| Tests only (*_test.*, *_spec.*, test_*) | mechanical.md, completeness.md |
| Config only (.json, .yaml, .toml, .env*) | adversarial.md, dependency.md |
| Source code (everything else) | all 5 |
| Mixed | union of matching categories |

Write `manifest.json` to the squad directory. Agent names MUST include the `.md` extension (the commit gate checks filenames directly):
```json
{"launched": ["cold_reader.md"], "reason": "docs-only scope", "timestamp": "ISO"}
```

If all files are source code (or mixed), launch all 5 and **delete any existing manifest.json** in the squad directory (to prevent stale partial-run manifests from affecting the commit gate).

**Duo mode dispatch sequence** (when using file-based dispatch):
1. Update CT — cold-start ready.
2. Write squad prompt to `verification_findings/_pending_sonnet/[chN/]squad_<timestamp>.md`.
3. Run wait loop for result files.
4. Read results when they appear.

YAML frontmatter required — resolve bracket notation before writing:

```yaml
---
type: squad
agents:
  - name: mechanical
    output_path: verification_findings/squad_[chN_]sonnet/mechanical.md
  - name: adversarial
    output_path: verification_findings/squad_[chN_]sonnet/adversarial.md
  - name: completeness
    output_path: verification_findings/squad_[chN_]sonnet/completeness.md
  - name: dependency
    output_path: verification_findings/squad_[chN_]sonnet/dependency.md
  - name: cold_reader
    output_path: verification_findings/squad_[chN_]sonnet/cold_reader.md
---
```

After frontmatter, include: WORK_PRODUCT, SOURCE_SPEC, SCOPE_SUMMARY from Step 3, and the full 5-agent prompts from the verification squad reference.

For `on <files>`: agents focus only on specified files.
For `full`: agents may batch-process if diff is large.

### Step 4b: While agents run

Do not idle. Proceed with queued work or run `/grill`. The wait task notifies on completion — no polling needed (`run_in_background: true`).

### Step 5: Report

When all expected result files present:

1. Read all launched agent output files (may be fewer than 5 if smart filtering was applied).
2. Present consolidated summary: each agent PASS/FAIL with issue count.
3. ALL PASS or WARN → write `VERIFICATION_PASSED` + summary to CT (documentation only — hooks require actual squad files).
4. ANY FAIL → list issues, ask user whether to fix and re-run failed agent(s).

### Step 6: Fix loop (if needed)

**Fix ALL findings before launching the next round.** This includes findings from agents that returned FAIL or WARN, and any pre-existing issues surfaced by agents. The standard is: a fresh squad should return all PASS. Selectively fixing only FAILs while leaving WARN findings creates a moving baseline that never converges.

Fix issues -> re-run ONLY failed agent(s). Max 3 rounds total. After round 3: write `VERIFICATION_BLOCKED` + remaining issues to CT, present to user.

**NEVER self-certify verification results.** After fixing FAILs, always launch a fresh squad on the same scope. The new squad's independent result count determines completion, not your tally of fixes applied. Fixing issues and declaring "0 remaining" is performative progress, not verification.

Squad files are ephemeral and gitignored. Exemptions from the verification squad reference still apply — if clearly exempt, say so and skip. When in doubt, run it.
