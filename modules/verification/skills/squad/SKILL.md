---
name: squad
description: "Launch 5-agent verification squad against a scope of work. Agents check mechanics, adversarial cases, completeness, dependencies, and cold-readability. Use after completing work or before claiming done."
---

# /squad — Launch Verification Squad

**Trigger:** `/squad [scope]`

Run the Verification Squad (5 parallel agents) against a specified scope of work.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix.

**Scope check:** Verify squad scope belongs to your channel. Cross-channel scope -> use unchanneled paths.

## Scopes

| Usage | Scope |
|-------|-------|
| `/squad` | Staged + unstaged. If clean, last commit. |
| `/squad full` | All changes since session start. |
| `/squad last` | `HEAD~1..HEAD` |
| `/squad last N` | `HEAD~N..HEAD` |
| `/squad since <ref>` | `<ref>..HEAD` + uncommitted |
| `/squad on <files>` | Specific file(s) only. |
| `/squad commit <hash>` | `<hash>~1..<hash>` |

## Procedure

### Step 1: Determine scope and gather changes

Run the appropriate git diff command. Use `--stat` for overview. Produce a **change summary**.

### Step 2: Identify source spec

Check in order: (1) CT spec reference, (2) user's invocation, (3) changed files -> governing spec, (4) user's original request. Never silently skip.

### Step 3: Build squad parameters

```
WORK_PRODUCT: [changed files with paths]
SOURCE_SPEC: [spec file path, or "User request: <quoted text>"]
SCOPE_SUMMARY: [one sentence]
SQUAD_DIR: squad_[chN_]sonnet/
```

### Step 4: Delegate to Sonnet

DISPATCH TO SONNET AND ASSUME THE LISTENER IS RUNNING. You do NOT have permission to run squad agents locally unless invoked with `/squad local <scope>`. No heartbeat, no listener directory, no prior evidence of Sonnet — none of these are valid reasons to run locally.

Follow this exact sequence:
1. Update CT — cold-start ready.
2. Write squad prompt to `verification_findings/_pending_sonnet/[chN/]squad_<timestamp>.md`.
3. Run wait loop for result files.
4. Read results when they appear.

YAML frontmatter required:

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

After frontmatter, include: WORK_PRODUCT, SOURCE_SPEC, SCOPE_SUMMARY, and the full 5-agent prompts from the verification squad reference.

### Step 4b: While agents run

Do not idle. Proceed with queued work or run `/grill`.

### Step 5: Report

When all 5 result files present:

1. Read all 5 output files.
2. Present consolidated summary: each agent PASS/FAIL with issue count.
3. ALL PASS -> write `VERIFICATION_PASSED` + summary to CT.
4. ANY FAIL -> list issues, ask user whether to fix and re-run.

### Step 6: Fix loop (if needed)

Fix issues -> re-run ONLY failed agent(s). Max 3 rounds total. After round 3: write `VERIFICATION_BLOCKED` + remaining issues to CT, present to user.

**NEVER self-certify verification results.** After fixing FAILs, always launch a fresh squad on the same scope.

Squad files are ephemeral and gitignored. When in doubt, run it.
