# Commit Protocol

**Read before any commit at any stage (1-5).** Not auto-loaded into CLAUDE.md — read on demand. The skills for `/audit`, `/design`, `/build`, `/perfect`, `/finalize`, and `/cleanup` all point here. Follow this protocol regardless of which skill issued the commit.

## Core rule

**The git index is off-limits during commit prep.** Multi-channel sessions share the same index. Any session that stages files pollutes every other session's view of `git diff --cached`. `channel_commit.sh` owns all staging and hashing inside a lock; your job is to provide content and verification, not to touch the index.

"Index-independent" in this document means: a command that inspects the working tree against `HEAD` without consulting the git index (the staging area). `git diff HEAD -- <file>` is index-independent. `git diff --cached` is not.

"Foreign staging" = files staged into the index by a different session (a different channel's `channel_commit.sh` invocation, or a manual `git add` from another terminal). Your session cannot see which files it owns once they are in the shared index.

## Forbidden (when `channel_commit.sh` is available — the default in this repo)

- `git add` (in any form, including `-A` or specific files)
- `git diff --cached` (reads the shared index, not your file)
- `git hash-object` (hash is computed by the script inside the lock)
- `git reset` (in any form — bare `reset` unstages everything, `reset HEAD -- <file>` unstages files another session may own)
- `git commit` (bypasses the lock)

Exception: if `scripts/channel_commit.sh` does not exist in the repo (Core-only install of `cc-sentinel`, with no Commit Enforcement module), multi-channel operation is not a concern and raw git is acceptable. This exception applies to the `cleanup` skill only and MUST be gated on the script's absence.

## Required workflow

```text
1. Finish edits. Working tree has your changes.
2. Compute the verifier input (index-independent):
     git diff HEAD -- <files> > verification_findings/staged_diff_chN.diff
   (Use `staged_diff.diff` without suffix for unchanneled sessions.)
3. Spawn commit-adversarial + commit-cold-reader subagents in parallel.
   Pass BOTH of these to each agent in its prompt:
     - diff_path:   verification_findings/staged_diff_chN.diff
     - output_path: verification_findings/commit_check_chN.md       (adversarial)
                    verification_findings/commit_cold_read_chN.md   (cold-reader)
   For unchanneled sessions, use the same directory prefix with unsuffixed
   filenames: verification_findings/commit_check.md and
   verification_findings/commit_cold_read.md. Never omit the
   `verification_findings/` prefix — a bare filename writes to the repo root
   and the script's grep will not find it.

   The channel_commit.sh script greps output_path files whose names
   match the channel suffix — passing the wrong output_path means the
   script cannot find the verdict and exits 1.

   Agents read the diff file and write a verdict line in one of three
   equal-weight forms:
     VERDICT: PASS                     (no issues)
     VERDICT: WARN (N minor findings)  (minor/stylistic issues only)
     VERDICT: FAIL (N findings)        (logic, spec, regression, contradiction)
   WARN and FAIL are first-class outcomes, not exceptions to a PASS baseline.
   No HASH line needed. No Diff hash line needed — the script owns stamping
   in BOTH local-verify and listener modes.

4. Call the script:
     bash scripts/channel_commit.sh \
       --channel N \
       --files "<files>" \
       -m "<message>" \
       --local-verify
   (Either path works: `scripts/channel_commit.sh` is the project-local
    copy; `~/.claude/scripts/channel_commit.sh` is the global copy,
    kept in sync. Skill files hardcode the global path because a global
    skill cannot know the current project's layout — this is correct
    and intentional. Inside the repo, `scripts/channel_commit.sh` is
    equally valid. Either invocation ends up running the same code.)

   The script:
     - Acquires the commit lock
     - Runs `git reset` (total — unstages EVERYTHING in the index,
       including any foreign files staged by other channels)
     - Immediately re-stages ONLY the files named in --files
       (the "reset then selective re-stage" pair is what excludes
       foreign staging — the reset is how it clears pollution, and
       the selective `git add` is how it ensures only your files
       land in the Phase 1 diff)
     - Computes the real hash from its own freshly-staged diff
     - "Stamps" that hash into commit_check_chN.md /
       commit_cold_read_chN.md via sed — "stamps" here means either
       overwriting an existing `HASH:` line or inserting a new `HASH:`
       line immediately after the `VERDICT:` line
     - Validates VERDICT: PASS|WARN
     - Re-stages in Phase 2, re-hashes, drift-checks, commits
```

## Why `git diff HEAD -- <file>` is safe

`git diff HEAD -- <file>` compares the working tree against the HEAD tree for the specified file. It does NOT consult the index, so other sessions' staging is invisible. Two consecutive calls produce identical output regardless of what any session has staged in between.

Contrast with `git diff --cached`, which reads the entire index. If session B has staged files X, Y, Z, your `git diff --cached` output will contain X, Y, Z even though you only touched W — and your verifier agents will report FAIL because the diff doesn't match your commit message.

## Why manual hashing is wasted work

`channel_commit.sh` stamps the real hash into verification files via `sed` in BOTH modes:
- **local-verify mode**: stamps after confirming the files exist (before validate_results runs).
- **listener mode**: stamps after `wait_for_results.sh` returns success, and stale files are deleted before dispatch so the listener's fresh writes are the only files stamped.

If the file already has a `HASH:` line, it's overwritten. If not, a new `HASH:` line is inserted after the `VERDICT:` line. If the file has no `VERDICT:` line at all, sed makes no change — and that's fine, because `validate_results` will fail on the missing VERDICT first. The VERDICT is the only thing that gates the commit.

Any hash you compute by hand will be overwritten or ignored. If the index was polluted when you computed it, the hash is meaningless. Don't compute it.

## Failure mode example (2026-04-14 incident)

Session ch0 was committing one test file during `/perfect` Phase 3. Session ch2 had independently staged four unrelated files (`CURRENT_TASK_ch2.md`, `MANUAL_TEST_QUEUE.md`, `SPRINT_CHECKLIST.md`, `decisions_ch2_cse_phantom.md`) for its own upcoming commit.

ch0 ran the pre-fix `/build` commit ceremony (since removed — the old `commands/build.md` that contained it has been deleted; `/build` now resolves directly to `~/.claude/skills/build/SKILL.md`): `git add <file> && git diff --cached > diff_ch0.tmp && git hash-object --stdin < diff_ch0.tmp`. The diff captured all five files (ch0's + ch2's). ch0 wrote verification files with the polluted hash and dispatched agents. Agents correctly reported FAIL: "3 files staged — commit message claims 1." ch0 then attempted `git reset HEAD` (bare) and `git reset HEAD -- <ch2's files>` — both forbidden. Took ~15 tool calls to recover before finally using `channel_commit.sh --files` which handled everything cleanly on the first attempt.

Net: the script would have worked correctly on the first call if ch0 had written stub verification files (`VERDICT: PASS`, no hash) and called the script directly. The manual pre-staging and pre-hashing was the cause of the failure, not a precaution against it.

## Stage-specific notes

- **/build (stage 3):** commits at task-group / phase boundaries per the skill's batching rules. Follow this protocol exactly.
- **/perfect (stage 4):** commits grill-round fixes in a single batch before Phase 3. Follow this protocol.
- **/finalize (stage 5):** commits sprint-close artifacts (including `--skip-squad` wip commits for pre-verification stashing). Follow this protocol for file discovery (`git diff HEAD -- <files>`); the `--skip-squad` flag bypasses verifier spawning but does NOT permit `git add`.
- **/cleanup:** commits end-of-session housekeeping. Follow this protocol when `scripts/channel_commit.sh` exists; fall back to raw `git add` only when the enforcement module is NOT installed (Core-only cc-sentinel). The fallback is gated on the script's absence — never on inconvenience.
- **/audit (stage 1), /design (stage 2):** rarely commit. If they do, follow this protocol.

## Sync targets

When editing any of the files below, sync all copies listed. `install.sh` preserves locally-modified copies on reinstall (diff-check gated by a `.cc-sentinel-installed` marker), so intentional local divergences survive — but unintentional drift means the next session running from a different copy sees a different script. Keep them aligned.

| File | Canonical | Sync targets |
|------|-----------|--------------|
| `channel_commit.sh` | `cc-sentinel/modules/commit-enforcement/scripts/` | Project `scripts/`, `~/.claude/scripts/` |
| `safe-commit.sh` | `cc-sentinel/modules/commit-enforcement/hooks/` | `~/.claude/hooks/` (may carry documented local divergences — e.g., project-specific `flutter test --exclude-tags` overrides. Mark the divergence inline with `# INTENTIONAL DIVERGENCE: <reason>` so reinstall diff-check preserves it.) |
| `commit-adversarial.md` | `cc-sentinel/modules/commit-enforcement/agents/` | `~/.claude/agents/`, project `.claude/agents/` |
| `commit-cold-reader.md` | `cc-sentinel/modules/commit-enforcement/agents/` | `~/.claude/agents/`, project `.claude/agents/` |
| `commit-protocol.md` (this file) | `cc-sentinel/modules/commit-enforcement/reference/` | `~/.claude/reference/`, project `.claude/reference/` |
| Sprint-pipeline skills — `audit`, `design`, `build`, `perfect`, `finalize`, `sonnet`, `opus`, `rewrite`, `spawn` (9 skills) | `cc-sentinel/modules/sprint-pipeline/skills/<name>/SKILL.md` | `~/.claude/skills/<name>/SKILL.md` |
| `cleanup` skill (Core module — distinct from sprint-pipeline) | `cc-sentinel/modules/core/skills/cleanup/SKILL.md` | `~/.claude/skills/cleanup/SKILL.md` |

**Core-only installs do not have `channel_commit.sh` or this reference file.** The `cleanup` skill's Step 3 is written so the `commit-protocol.md` reference appears only inside the `if scripts/channel_commit.sh exists` branch — Core-only readers never hit a dead link.

**Delete candidates (legacy, no canonical role):**
- `~/.claude/hooks/enforcement/safe-commit.sh` — predates the hook migration to `~/.claude/hooks/`. Not registered in any hook object, only in permissions allowlists. Remove file + allowlist entry when encountered.
- Project-local `scripts/claude-hooks/safe-commit.sh` (Wakeful pattern) — pre-migration copy, unreferenced.

## Governance sessions

Governance work (e.g., `/verify` runs against governance-protection or commit-enforcement files, multi-round R1–RN squads producing architectural fixes) often runs concurrently with other channel work that reuses the same shared `verification_findings/squad_sonnet/` directory. A concurrent session's squad dispatch will overwrite your R1–RN evidence with no warning.

**Rule:** Before each round's squad dispatch during governance work, archive the prior round's outputs to a timestamped directory:

```bash
cp -r verification_findings/squad_sonnet/ \
      verification_findings/squad_sonnet_archive_$(date +%Y%m%d_%H%M%S)/
```

(Use `squad_chN_sonnet/` for channeled sessions.) The archive is gitignored but local, so it survives cross-session overwrites. Findings that drive architectural decisions must ALSO be distilled into the governance commit's code + reference changes — archives are evidence, not the deliverable.

## If the script rejects your commit

- `CONFLICT: HEAD advanced and diff changed` — another session committed between your Phase 1 and Phase 2. Re-run the workflow. The script retries up to 3 times automatically.
- `LOCK_TIMEOUT` — another session is holding the commit lock past 180s. Check for a stuck `channel_commit.sh` process.
- `Hash mismatch` — LEGACY error string; the script no longer emits it. If you still see it, you are running a stale copy of `channel_commit.sh`. Sync all copies to the current canonical — see the Sync targets matrix above.
- `ADVERSARIAL CHECK FAILED` or `COLD-READER CHECK FAILED` — agents reported FAIL. Read the finding, fix the code, re-run the workflow.
- Script cannot find `commit_check_chN.md` — you passed the wrong `output_path` to the agents (unsuffixed when the script expected chN-suffixed, or vice versa). Re-spawn agents with the correct `output_path`.
