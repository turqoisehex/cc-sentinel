---
name: sync-sentinel
description: Sync cc-sentinel public repo with upstream changes from the host project. Universalizes project-specific content, updates tests, verifies CI passes. Run when governance infrastructure has been modified in the host project and needs to be pushed to the public cc-sentinel repo.
---

# /sync-sentinel — Sync Public Repository

**Trigger:** `/sync-sentinel` after modifying cc-sentinel governance infrastructure in a host project.

Syncs changes from a host project's `.claude/` install into the public `cc-sentinel` repository. Handles universalization (removing project-specific content), test updates, and CI verification.

## Prerequisites

- cc-sentinel repo cloned locally
- Host project has modified `.claude/` infrastructure that originated from cc-sentinel modules
- Know which files changed (from CT, git log, or memory)

## Procedure

### Step 1: Hash comparison inventory

Dispatch a Sonnet agent to compare hashes of all matching files between the host install (`~/.claude/`) and cc-sentinel source (`modules/`). Output to `verification_findings/sentinel_sync_audit.md`.

Classify each file: `STALE` (cc-sentinel copy is behind), `MISSING` (exists in host but not in cc-sentinel), `IN_SYNC`, or `N/A` (personal/project-specific, should not sync).

For MISSING files, sub-classify: `UNIVERSAL` (belongs in public repo) vs `PERSONAL` (contains project name, domain class names, project-specific paths). Personal files do NOT sync.

### Step 2: Universalization pre-flight (per file, BEFORE copy)

For each STALE or UNIVERSAL-MISSING file, grep for forbidden patterns BEFORE copying to cc-sentinel:

```bash
# Forbidden patterns — ALL must be checked:
grep -n "Wakeful\|wakeful\|WAKEFUL" "$file"
grep -n "ExerciseDefinition\|ModuleTemplate\|ParameterDef" "$file"
grep -n "docs/superpowers/" "$file"
grep -n "lib/presentation/\|lib/domain/\|lib/data/" "$file"
grep -n "WAKEFUL_LISTENER\|WAKEFUL_CHANNEL" "$file"
grep -n "SPRINT_CHECKLIST\|COMPREHENSIVE_IMPLEMENTATION_PLAN" "$file"
grep -n "decisions_ch[0-9]" "$file"
grep -n "breathing.engine\|meditation\|journeying\|bodywork\|triage" "$file"
grep -n "Sprint\s*1[0-9]" "$file"
grep -n "2026-0[0-9]-[0-9][0-9]" "$file"  # specific dates
grep -n "Ankhara\|rich.kobelt\|D:\\\\Documents" "$file"
```

**Zero tolerance:** if ANY match found, universalize IN the host file FIRST (or make a universalized copy), THEN copy. Never stage a file with project-specific content. A single grep pass declaring "clean" is NOT sufficient — verification squad finds 2-3x more (historically 23+ items across 3 rounds).

#### Replacement strategy:

| Project-specific | Universal replacement |
|---|---|
| `lib/presentation/`, `lib/domain/`, `lib/data/` | "your presentation/domain/data layer (e.g., `src/ui/`, `lib/domain/`, `app/models/`)" |
| `ExerciseDefinition`, `ModuleTemplate`, `ParameterDef` | "any entity class, schema definition, config type, or domain model" |
| `docs/superpowers/specs/2026-...` | "your project's spec file" or generic path placeholder |
| Flutter/Dart-specific patterns | Generic multi-stack examples (Python/TS/Go/Rust) |
| Specific exercise/meditation/breathing references | Generic domain examples |
| `design-spec section N.N` | "interleaved squad design § N.N" or remove citation |
| Hardcoded channel numbers (ch1, ch3, ch7) | `chN` placeholder notation |
| `SPRINT_CHECKLIST.md`, `COMPREHENSIVE_IMPLEMENTATION_PLAN.md` | Make conditional: "If your project uses these files..." |
| `WAKEFUL_LISTENER`, `WAKEFUL_CHANNEL` | Remove entirely — project-name env vars are never universal |

#### Intentionally generic (do NOT replace):

- `CURRENT_TASK.md` / `CURRENT_TASK_chN.md` — cc-sentinel's convention
- `verification_findings/` paths — cc-sentinel's own directory structure
- `~/.claude/` paths — standard install location
- Hook filenames (anti-deferral.sh, etc.) — cc-sentinel's own files
- `SENTINEL_CHANNEL=N` — cc-sentinel's own env var

### Step 3: Copy files to cc-sentinel

Copy each universalized file to its cc-sentinel module location. Do NOT stage yet.

```
Host path                              → cc-sentinel path
~/.claude/hooks/<name>.sh              → modules/<module>/hooks/<name>.sh
~/.claude/skills/<name>/SKILL.md       → modules/<module>/skills/<name>/SKILL.md
~/.claude/reference/<name>.md          → modules/<module>/reference/<name>.md
~/.claude/scripts/<name>.sh            → modules/<module>/scripts/<name>.sh
```

### Step 4: Install-path verification (new files only)

For each NEW file, trace through `install.ps1` and `install.sh`:
1. Where does the installer put this file?
2. Does any consumer script reference it at a different path?
3. If mismatch: add fallback path resolution to the consumer OR fix the installer category.

Historical bug: `codex-postfix-prompt.md` installed to `reference/` but script looked in `scripts/`. This class of bug is silent at install time and fails at runtime.

### Step 5: Pre-commit diff grep

```bash
cd <cc-sentinel-repo>
git diff HEAD -- . | grep -i "wakeful\|ExerciseDefinition\|superpowers\|WAKEFUL_CHANNEL\|SPRINT_CHECKLIST\|breathing.engine\|Ankhara"
```

If any hits: fix before staging. This is your last gate before the content enters git history.

### Step 6: Update modules.json

For NEW files:
- Add to the appropriate module's `files` section (scripts, reference, hooks, skills, tests)
- Verify category matches install behavior (scripts = executable .sh/.ps1, reference = .md docs)

For REMOVED files:
- Remove from modules.json
- Add to uninstall scripts

**Consistency check:** Every file in `modules/*/scripts/`, `modules/*/reference/`, `modules/*/agents/` must be listed. Every uninstaller entry must exist in modules.json. No orphans in either direction.

### Step 7: Update uninstallers

Check `uninstall.ps1` and `uninstall.sh`. Every file in modules.json must appear in the appropriate array:
- Scripts → `$Scripts` / `SCRIPTS`
- Reference → `$Reference` / `REFERENCE`
- Hooks → `$Hooks` / `HOOKS`
- Agents → `$Agents` / `AGENTS`

Remove entries for files that no longer exist. Add entries for new files.

### Step 8: Update tests for hook behavior changes

**Most commonly missed step.** When a hook's behavior changes, its test MUST be updated.

For EACH modified hook:
1. Read `modules/<module>/tests/test_<hook_name>.sh`
2. For each assertion, verify it matches the hook's CURRENT behavior
3. Common mismatches:
   - Hook now skips a check → test still asserts output from that check
   - Hook output format changed → test grep pattern doesn't match
   - Hook added stdin consumption → test doesn't pipe input (hangs in CI)
   - Hook added/removed env var sensitivity → test doesn't set/unset the var
   - Hook uses anchored grep (`^...$`) → test creates content with pattern embedded in longer text

**stdin drain pattern:** Any hook receiving piped input from Claude must drain stdin. Bash: `INPUT="$(cat)"`. PowerShell: `if (-not [Console]::IsInputRedirected) {} else { [void][Console]::In.ReadToEnd() }`. Tests must pipe something.

### Step 9: Run tests locally

```bash
cd <cc-sentinel-repo>
# ALL bash tests
for f in modules/*/tests/test_*.sh; do echo "=== $f ==="; bash "$f"; done

# Python tests
python -m pytest modules/ -v
```

**Fix failures before pushing.** Common CI issues:
- **Grep anchoring:** `grep -q "^PATTERN$"` in hook but test creates pattern mid-line
- **File aging:** Tests needing stale files use `python -c "import os,time; os.utime(...)"` on Windows
- **Path separators:** Windows CI uses Git Bash — forward slashes preferred
- **Assertion inversion:** Hook behavior flipped (now skips instead of reports) but test still expects output

### Step 10: Stray file check

```bash
git status --short | grep "^??"
```

Delete development artifacts (test.txt, scratch files, etc.) before committing.

### Step 11: Commit and push

Batch strategy for large syncs (>10 files):
- **Batch 1:** Core reference + hooks + scripts. Commit + push.
- **Batch 2:** Skills + agents + templates. Commit + push.
- **Batch 3:** Bug fixes + test updates. Commit + push.
- **Batch 4:** New files + modules.json + uninstallers. Commit + push.

Smaller syncs: one commit is fine.

### Step 12: Verification squad (mandatory for >5 files)

Run `/verify` scoped to the full cc-sentinel repo. Squad prompt emphasis:

> "You are a new user who has never heard of any specific project. Find: content assuming knowledge of a specific project, instructions unexecutable without hidden context, paths wrong for a fresh installation, dependencies on uninstalled files."

Fix all above-INFO findings. Re-run if any FAIL found.

### Step 13: CI check

```bash
gh run list --limit 3
```

Wait for CI to pass. If it fails:
1. `gh run view <id> --log-failed`
2. Fix in-place
3. Commit with `fix(ci): <description>`
4. Push, re-check

### Step 14: Update sync inventory

Update `verification_findings/governance_sync_report.md` (or equivalent) with:
- Every file synced + source commit
- Every file excluded + reason
- Deliberate divergences between host and public

## Anti-patterns (historically painful)

1. **Syncing hooks but not their tests** — test suite compatibility is part of the sync
2. **Pushing before running tests locally** — CI emails are embarrassing; always local first
3. **Declaring "clean" after one grep pass** — verification squad finds 2-3x more every time
4. **Missing new files in modules.json** — installs but won't be discovered by installer
5. **Missing new files in uninstallers** — installs but won't uninstall cleanly
6. **Assuming project-name env vars are "fine"** — `WAKEFUL_CHANNEL` is obviously project-specific
7. **Leaving worked examples with project paths** — specific spec filenames are not universal examples
8. **Forgetting stdin drain on notification hooks** — Claude pipes JSON; hooks that don't consume it hang
9. **Copying before universalizing** — once in git history, the project-specific content is permanent
10. **Committing batch 1 then finding universalization issues** — pre-flight BEFORE copy, not after
