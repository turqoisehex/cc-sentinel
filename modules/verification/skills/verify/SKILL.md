---
name: verify
description: "Launch verification squad (5 Sonnet minimum + Codex interleaved when available)"
---

# /verify — Launch Verification Squad

**Trigger:** `/verify [scope]`

Run the Verification Squad (5 parallel agents) against a specified scope of work.

**THE INTERLEAVED PROCEDURE IS MANDATORY WHEN CODEX IS ON PATH. "Interleaved" = R1 (5 Sonnet) → R2 (5 Codex) → R3 (flagged-role Sonnet re-validation) → Gate → conditional R4 → Opus closure. All phases fire per the rules in "Default mode" below. No phase may be skipped, reduced, or omitted. The scope type (spec, plan, code, config, 10 lines or 10,000 lines) NEVER grants discretion to run fewer phases or fewer agents. "It's just a spec" / "it's only N lines" / "it's not a codebase artifact" = rationalization. Execute the full procedure or do not invoke /verify at all. A partial run — regardless of justification — is INVALID and its output MUST NOT be acted on.**

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix.

**Scope check:** Verify squad scope belongs to your channel. Cross-channel scope -> use unchanneled paths.

## Scopes

| Usage | Scope |
|-------|-------|
| `/verify` | Staged + unstaged. If clean, last commit. |
| `/verify full` | All changes since session start. |
| `/verify last` | `HEAD~1..HEAD` |
| `/verify last N` | `HEAD~N..HEAD` |
| `/verify since <ref>` | `<ref>..HEAD` + uncommitted |
| `/verify on <files>` | Specific file(s) only. |
| `/verify commit <hash>` | `<hash>~1..<hash>` |

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

### Step 4: Launch verification

**Which mode am I in?** Check env: `SENTINEL_LISTENER=true` → Sonnet listener (spawn agents directly with `run_in_background: true`, write to squad dir, no file-based dispatch). `CC_DUO_MODE=1` and not a Sonnet listener → Duo mode (file-based dispatch via `_pending_sonnet/[chN/]squad_<timestamp>.md` with YAML frontmatter; wait via `bash ~/.claude/scripts/wait_for_results.sh` run in background). Neither → Default mode (native dispatch — interleaved phases when Codex available, see below).

**`/verify local <scope>`:** explicit override — forces native agent execution regardless of env. Useful when you want the squad to run in this terminal rather than dispatching via duo file-signal.

**Default mode (native dispatch — interleaved phases):**

Parent enters the interleaved phase loop after writing manifest:

1. **Codex availability check:** `which codex || which codex.cmd` (Git Bash on Windows). If absent → fall back to 5-agent Sonnet-only with unprefixed filenames (existing behavior, skip R2/R3/R4).

2. **R1: 5 Sonnet agents (baseline sweep)**
   ONE message, all 5 parallel: `Agent(model: "sonnet", run_in_background: true)` × 5
   Filenames: `sonnet_mechanical.md`, `sonnet_adversarial.md`, `sonnet_completeness.md`, `sonnet_dependency.md`, `sonnet_cold_reader.md`
   Wait for all 5 to complete. Read outputs.

3. **Fix R1:** Fix all above-INFO findings in place. Run integrity scan (codex-postfix-scan.sh). Proceed only after CLEAN.

4. **R2: 5 Codex agents (cross-architecture sweep on post-fix content)**
   ONE message, all 5 parallel: `Bash(~/.claude/scripts/codex-verify-agent.sh -m MODEL -r ROLE -w WORK_PRODUCT -s SOURCE_SPEC -S "SCOPE" -o SQUAD_DIR/codex_ROLE.md, run_in_background: true)` × 5
   MODEL = manifest `codex_model` value (default: `gpt-5.4`)
   Wait for all 5 to complete. Read outputs.
   R2 is UNCONDITIONAL — runs regardless of R1 results (DD-11).

5. **Fix R2:** Fix all above-INFO Codex findings in place. Integrity scan → CLEAN.

6. **R3: Sonnet re-validation (flagged roles only)**
   Re-run Sonnet on any role where R1 OR R2 produced above-INFO findings.
   Roles that were all-PASS in both R1 and R2 are NOT re-run.
   Overwrites R1 output files for re-run roles.
   **UX trace enforcement (cold_reader only):** After reading cold_reader output, if work product includes presentation-layer, domain-layer, or engine code (e.g., `src/ui/`, `src/views/`, `lib/presentation/`, `src/domain/`, or equivalent project paths) AND the output lacks `## UX Journey Trace` section → treat as incomplete (re-run cold_reader with fresh prompt).

   **All-Codex-TRANSIENT in R2:** If all 5 Codex agents return TRANSIENT, R3 becomes a full 5-role Sonnet re-run (no cross-architecture data exists).

7. **Gate decision:**
   - All R3 Sonnet PASS → Opus closure
   - Any R3 Sonnet FAIL/WARN → R4

8. **R4 (conditional): Codex on failing roles only**
   MODEL = manifest `codex_model_r4` value (default: `gpt-5.5` with `--reasoning xhigh`)
   Run only on roles that still have FAIL/WARN in R3.
   Fix → re-run Sonnet on those roles → re-evaluate gate.
   Max 2 additional R4+R3' cycles. Total phase cap: 7 phases before VERIFICATION_BLOCKED.

9. **Opus closure:** After gate passes, write new manifest to `squad_[chN_]opus/` BEFORE any progress message (ensures `stop-task-check.sh` sees the Opus dir immediately). Then dispatch 5 Opus agents. Both squad dirs must pass commit gate independently.

**NEVER spawn a "dispatcher" subagent to launch agents on your behalf. Subagents cannot spawn subagents.** Launching fewer than 5 Sonnet agents in R1 is a procedural failure.

#### Step 4a: Write manifest — ALL 5 agents, always

**There is no filtering. All 5 agents run on every invocation, regardless of file type, scope size, or any other factor. Reasoning about which agents are "relevant" is the failure mode — stop and launch all 5.**

**Before writing `manifest.json`: delete any existing `manifest.json` in the squad dir.** Stale partial-run manifests poison the commit gate (which checks filenames against the `launched` list verbatim). Agent names MUST include the `.md` extension.

```json
{"launched": ["sonnet_mechanical.md", "sonnet_adversarial.md", "sonnet_completeness.md", "sonnet_dependency.md", "sonnet_cold_reader.md"], "codex": ["codex_mechanical.md", "codex_adversarial.md", "codex_completeness.md", "codex_dependency.md", "codex_cold_reader.md"], "codex_model": "gpt-5.4", "codex_model_r4": "gpt-5.5", "reason": "interleaved squad — R1 Sonnet, R2 Codex, R3 re-validate, R4 conditional", "timestamp": "ISO"}
```

When Codex CLI is absent: `launched` uses unprefixed filenames, `codex`/`codex_model`/`codex_model_r4` are omitted entirely. Fallback manifest:

```json
{"launched": ["mechanical.md", "adversarial.md", "completeness.md", "dependency.md", "cold_reader.md"], "reason": "full squad — Codex absent, Sonnet-only fallback", "timestamp": "ISO"}
```

**Duo mode dispatch sequence** (when using file-based dispatch):
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
    output_path: verification_findings/squad_[chN_]sonnet/sonnet_mechanical.md
  - name: adversarial
    output_path: verification_findings/squad_[chN_]sonnet/sonnet_adversarial.md
  - name: completeness
    output_path: verification_findings/squad_[chN_]sonnet/sonnet_completeness.md
  - name: dependency
    output_path: verification_findings/squad_[chN_]sonnet/sonnet_dependency.md
  - name: cold_reader
    output_path: verification_findings/squad_[chN_]sonnet/sonnet_cold_reader.md
---
```

Codex-absent fallback (unprefixed):

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

When Codex is absent: use the unprefixed YAML template above. The manifest `launched` field must match the YAML `output_path` basenames exactly — mismatch triggers commit gate failure.

After frontmatter, include: WORK_PRODUCT, SOURCE_SPEC, SCOPE_SUMMARY, and the full 5-agent prompts from `.claude/reference/verification-behavior.md` (or your project's equivalent verification-behavior reference).

### Step 4b: While agents run

Do not idle. Proceed with queued work or run `/grill`. Do NOT launch a second /verify whose scope overlaps the in-flight squad — overlapping invocations on the same files inflate round counts and produce nondeterministic squad output; queue the second invocation until the first reaches all-PASS or VERIFICATION_BLOCKED.

### Step 5: Report + fix (automatic, no asking)

When all expected result files present:

1. Read all 5 agent output files (mechanical, adversarial, completeness, dependency, cold_reader). If any are missing, the run is INCOMPLETE — do not report results, re-run the missing agents.
2. Present consolidated summary: each agent PASS/FAIL/WARN with issue count.
3. **Fix everything above INFO automatically.** Do NOT ask the user. FAIL, WARN, HIGH, MEDIUM, LOW — all get fixed inline without permission. Only INFO items may be deferred.
4. **Fixes MUST be in-place edits to the original wrong text.** (A "round" = one full launch of the 5-agent squad; see Step 6 "Fix loop" for the loop structure.) Find the wrong prose, code, or reference and change it at its source location. NEVER: append a "consolidated fixes" section, add "binding" appendix bullets, write correction blocks at the end of the file, or annotate the wrong text with "SUPERSEDED" markers while leaving it in place. These are all forms of fix theater — the original wrong text remains in the file, cold readers implement it, and the next round re-flags it. If the original text says X and it should say Y, the fix is: change X to Y. Not: leave X in § 2 and write "X is actually Y" in § 3.8. After applying in-place fixes, delete any prior-round appendix/binding/correction sections that are now redundant — git history preserves the trail.

   **No annotations, no tombstones, no round markers — anywhere in the work product.** Round numbers, finding IDs, agent names, and fix rationale belong ONLY in the ephemeral squad output files (`verification_findings/squad_*/`) — never inline in body prose, code comments, or parenthetical edits. Banned shapes (in prose or code comments) include: `(M14 R18)`, `(Adv H4 R18)`, `(R<N>`, `<!-- fixed in R7 -->`, `// updated per finding M3`. These survive every round and accumulate as round-marker pollution. /verify does NOT commit (commit boundaries belong to /3 and /5) — the rationale trail lives in squad files for the loop and is then discarded.
5. **Pause ONLY for genuine design decisions** — not fix permission. A design decision is: a choice with real tradeoffs that requires user intent (e.g., "which of two architectures," "include feature X or not"). Mechanical fixes, typos, stale references, broken citations, missing content, budget violations with an obvious resolution — these are NOT design decisions. Apply and move on.
6. **Post-fix integrity scan.**

   **Skip rule:** If this round produced zero above-INFO findings, skip the scan entirely and proceed to item 7 ('Re-run any agent that returned anything above INFO') below. Otherwise:

   **Shell prerequisite:** Run from Git Bash on Windows or bash/zsh on Linux/macOS. PowerShell and `cmd.exe` are NOT supported (no `~` expansion, no POSIX path resolution).

   **Pre-flight checklist (confirm BEFORE invoking):**
   1. Every above-INFO finding from this round has been edited in place.
   2. No fix-application Sonnet agents are still running (check via BashOutput on backgrounded agents).
   3. No design-decision pause is currently open.
   4. CWD is the project root (the `verification_findings/...` output path is project-relative).
   5. If your project maintains an in-tree draft of `codex-postfix-scan.sh`, confirm wrapper/draft byte-equality before first invocation: `cmp ~/.claude/scripts/codex-postfix-scan.sh <draft-path>` (exit 0 = identical). Skip this check if your project does not track a local draft.
   6. Confirm `<spec_path>` is not a symlink to a file outside the project tree — a symlinked spec gets `cat`'d into the prompt and shipped to Codex (exfiltration risk).

   If any item is uncertain, do NOT run the scan yet. If the design-decision pause is currently in effect, defer this scan until the user resolves the decision and the remaining fixes are applied.

   **Cardinality:** the scan fires exactly ONCE per round, AFTER all fix application is complete, BEFORE re-dispatching the next squad, regardless of how many fix-application units (Sonnet agents, direct edits) ran. If a round dispatched three separate fix-application agents, only one scan runs — at the end, when ALL above-INFO findings from this round have been resolved. Do NOT scan after each individual fix-application unit; that multiplies Codex invocations and rate-limit pressure without changing the fix-drift detection signal.

   When all checklist items above are confirmed true, substitute the actual channel name into the path AND run the scan command below. `<spec_path>` is the spec file currently under verification (absolute or project-root-relative); when `/verify` scope is multiple files, run the scan once per spec.

   For an unchanneled run:

   `~/.claude/scripts/codex-postfix-scan.sh <spec_path> verification_findings/squad_sonnet/integrity_scan.md`

   *Worked example — substitute your own spec path; the path below is illustrative and project-specific. Assumes CWD = project root:*

   `~/.claude/scripts/codex-postfix-scan.sh docs/specs/my-feature-design.md verification_findings/squad_sonnet/integrity_scan.md`

   Expect a 10–60 second wait (no progress indicator beyond a stderr banner). Maximum scan budget is 300 seconds; the wrapper times out beyond that and exits 2.

   The output path **must** sit at the top level of the squad directory. Never under a `spec_rN/` subdir; the wrapper exits 3 on nested paths. (Squad cleanup is non-recursive.)

   For a channeled run (e.g., channel 3, channel 7):

   `~/.claude/scripts/codex-postfix-scan.sh <spec_path> verification_findings/squad_ch3_sonnet/integrity_scan.md`

   `~/.claude/scripts/codex-postfix-scan.sh <spec_path> verification_findings/squad_ch7_sonnet/integrity_scan.md`

   **Substitute the actual channel before pasting.** The `[chN_]` notation is documentation prose, never a shell literal — bash treats `[…]` as a glob character class and the wrapper rejects bracket characters with exit 3. Unchanneled: `verification_findings/squad_sonnet/integrity_scan.md`. Channel N: substitute `N` (e.g., `squad_ch3_sonnet/`, `squad_ch7_sonnet/`). Placeholder definitions live in the Channel block at the top of this Procedure.

   The scan output file is OVERWRITTEN on each invocation. Squad dirs are gitignored (`verification_findings/squad*/`) and `safe-commit.sh` (an internal mechanism, never invoked directly — operators use `channel_commit.sh`) deletes their contents on each successful commit, so prior scan output is NOT preserved by committing. If preservation is needed for a specific round, copy `integrity_scan.md` out of the squad dir to a tracked location (e.g., the plan dir) before the next squad cycle.

   **Wrapper / draft byte-equality contract:** The install wrapper at `~/.claude/scripts/codex-postfix-scan.sh` and its in-tree mirror (project-specific location) MUST be byte-identical (`cmp` returns 0). Maintained via `cp + cmp` after every wrapper edit; operator-discipline, not hook-enforced. Verify with `cmp ~/.claude/scripts/codex-postfix-scan.sh <project-root>/codex-postfix-scan.sh.draft` before scan invocation if the wrapper has been edited recently.

   **Pattern 5 is unconditional.** Round markers, tombstones, and "R<N> —" annotations are banned in spec body prose. There is no exemption — every round-marker artifact in the spec body trips Pattern 5. Audit-trail material that needs to survive lives in `verification_findings/` (squad output files) or git history, not in the spec.

   Each scan run writes a `VERDICT: <label>` line as the first non-blank line of the findings file. The full vocabulary is: `CLEAN` (exit 0), `ARTIFACTS_FOUND` (exit 1), and four exit-2 sub-labels — `TRANSIENT_TIMEOUT`, `TRANSIENT_RATE_LIMIT`, `TRANSIENT_AUTH`, `TRANSIENT_NO_OUTPUT`. The exit code summarized below corresponds directly to this label. Full VERDICT semantics live in `.claude/reference/verification-behavior.md` § "Post-fix integrity scan".

   > **Meta-spec hazard — VERDICT echo.** The wrapper parses the first `^[[:space:]]*VERDICT: ` line in Codex's reply as Codex's verdict. If your spec body documents the wrapper's verdict vocabulary verbatim (as this section does, as `verification-behavior.md` does, as the implementation plan does), Codex may quote a `VERDICT: CLEAN` or `VERDICT: ARTIFACTS_FOUND` line from your spec when summarizing — the wrapper will then parse that quote as Codex's own verdict, yielding a spurious result. The wrapper pre-flight WARNs on this case but does not abort. Mitigation: before scanning a meta-spec, escape the VERDICT prefix in the spec body (e.g., write `VERDICT\:` or `VERD&#x200B;ICT:`), or scan a sanitized copy. Both mitigations render as the literal `VERDICT:` glyph sequence visually in most markdown viewers (`\:` strips the backslash on render; `&#x200B;` is a zero-width space invisible to readers); only the wrapper's regex parser sees the difference. The same caution applies to any spec body that includes literal Codex reply samples.

   - Exit 0 (CLEAN) -> proceed to item 7 ('Re-run any agent that returned anything above INFO') in this Step 5 list.

   - Exit 1 (ARTIFACTS_FOUND) -> **Pause this scan round (in-loop fix-and-resume — distinct from exit-4 STOP, which halts the loop and escalates to the operator).** Read integrity_scan.md, fix the reported artifacts in place, re-run the scan until CLEAN, then proceed to item 7. The scan reports any of seven controlled-vocabulary artifact patterns: DUPLICATE PARAGRAPHS, APPEND-INSTEAD-OF-EDIT, STALE CROSS-REFERENCES, ORPHAN PSEUDOCODE MARKERS, ROUND-MARKER POLLUTION, CODE-BLOCK FENCE IMBALANCE, ORPHAN TODO/FIXME MARKERS (full enumeration in `.claude/reference/verification-behavior.md` § "Post-fix integrity scan (mandatory before next round)"). *No hook enforces this. The next squad round will re-find the artifacts; bypassing exit 1 guarantees non-convergence in subsequent rounds. Compliance is the mechanism that keeps /verify rounds finite — the cost of skipping lands in the next round, not at commit time.* (The integrity scan is intentionally absent from the squad manifest's `"launched"` list and `safe-commit.sh` does not enforce it; see `.claude/reference/verification-behavior.md`.)

   - Exit 2 (transient) -> **Action:** skip the scan this round. Log a one-line note in CT (`integrity scan exit 2 — <VERDICT>`) and proceed to item 7 ('Re-run any agent that returned anything above INFO') in this Step 5 list. Do NOT re-run the scan on this round; the 5 Sonnet agent squad is the floor, the scan is additive. The wrapper auto-promotes a second consecutive exit-2 to exit 4 (see below) — operators do not track this manually.

     **Sub-labels** (read the `VERDICT:` line in the findings file): `TRANSIENT_TIMEOUT`, `TRANSIENT_RATE_LIMIT`, `TRANSIENT_AUTH`, `TRANSIENT_NO_OUTPUT`. The wrapper remaps a malformed ARTIFACTS_FOUND reply (no `### A1:`/`### Artifact N:` body or missing `## Enumeration trace`) to `TRANSIENT_NO_OUTPUT`. A codex CLI broken-but-on-PATH (corrupt install, auth-crash-on-start) also surfaces here.

   - **Forensic file (TRANSIENT_NO_OUTPUT stdout-with-content sub-path):** the wrapper preserves the raw Codex reply at a sibling file at the same output path with `.raw.md` appended (e.g., if the output path was `verification_findings/squad_sonnet/integrity_scan.md`, the raw reply lands at `verification_findings/squad_sonnet/integrity_scan.md.raw.md`). Best-effort: on `cp` failure the diagnostic block in `integrity_scan.md` is the sole record, in which case the `.raw.md` sibling will be absent even on the stdout-with-content sub-path. Absent `.raw.md` therefore means either the empty-stdout sub-path OR a `cp` failure on the stdout-with-content sub-path — check the diagnostic block in `integrity_scan.md` to disambiguate. See `.claude/reference/verification-behavior.md` for the complete VERDICT vocabulary.

     **Codex-broken-but-on-PATH symptom checklist.** Persistent `TRANSIENT_NO_OUTPUT` results with empty `.raw.md` (or absent `.raw.md` AND a diagnostic block showing zero stdout bytes), no rate-limit/auth tokens in stderr, and no network failures = the codex CLI is installed but non-functional (corrupt install, missing runtime, auth-crash-on-start, or a `codex.cmd` shim that exits 0 with no output on Windows + Git Bash). Disambiguate from a genuine transient by running these two commands directly: `codex --version` (confirms the binary loads; on Windows Git Bash, use `codex.cmd --version` if `codex` is not found) and `codex exec --skip-git-repo-check "Reply with exactly: PING" 2>&1` (confirms the exec path produces stdout; likewise `codex.cmd exec ...` on Windows Git Bash). If either fails, the wiring is broken — exit 2 will recur on every invocation until codex is repaired, consuming one STOP cycle per `/verify` even though the underlying cause is not transient.

   - Exit 3 (fatal misconfiguration — wrong args, missing files, codex CLI absent, sha256sum/shasum both absent, `wc`/`timeout`/`mktemp` absent, `$HOME` unset or unwritable) -> STOP. Surface to user; this is a wiring bug, not a transient failure. A codex CLI that is present on PATH but non-functional (corrupt install, missing runtime, auth-crash-on-start) does NOT surface as exit 3 — it surfaces as exit 2 with no usable Codex output. Check codex install health if exit 2 persists after network and rate-limit recovery.

   - Exit 4 (STOP — halt and escalate; do NOT auto-retry) -> two consecutive exit-2 results on the same spec. Surface to user; investigate the underlying transient cause (rate-limit window, network, Codex CLI degradation, spec size exceeding 300s scan budget) before the next squad dispatch. After resolving the cause, reset the streak counter per the **"Consecutive-exit-2 counter — reset rules"** bold subsection below. The STOP signal itself is emitted to wrapper stderr (with the streak file path); the findings file written on the exit-4 path carries the `TRANSIENT_*` VERDICT line from the second consecutive transient that triggered the STOP — not a distinct `STOP` label, and the VERDICT line in the file identifies the transient cause that triggered the STOP, not the STOP itself. A `.raw.md` sibling (same output path with `.raw.md` appended) may also be present from the triggering transient if that transient was a `TRANSIENT_NO_OUTPUT` on the stdout-with-content sub-path (see **Forensic file (TRANSIENT_NO_OUTPUT stdout-with-content sub-path)** above); read both files when debugging an exit 4. Specs containing the literal `{{SPEC_CONTENTS}}` token in their HEAD or TAIL regions (the prompt-template scaffold areas, not the spec body) cannot be self-scanned; the wrapper's scoped defense-in-depth check does not false-positive on `{{SPEC_CONTENTS}}` appearing in the spec body itself, but the prompt template uses that token as the splice anchor — if a meta-spec quotes the prompt template's head/tail regions verbatim, escape the placeholders before scanning.

   **Consecutive-exit-2 counter — reset rules.** The wrapper itself maintains the counter on disk at `~/.claude/state/codex_postfix_streak_<spec_hash>.txt` (per-spec keying via SHA-256 of the spec path). Operators do NOT track this manually; the wrapper auto-increments on every exit-2 path and resets on every exit-0 (CLEAN) or exit-1 (ARTIFACTS_FOUND) path. When the streak hits two, the wrapper exits **4** (distinct from plain transient exit 2) and surfaces a STOP message to stderr quoting the streak file path. "Consecutive" means: two exit-2 results in a row, with NO intervening exit-0 or exit-1 between them. The counter resets when either (a) the wrapper emits exit 0 or exit 1 on a subsequent run, OR (b) the operator manually deletes the streak file after resolving the underlying transient cause and noting the resolution in CT.

   > **Stderr-only degradation surfacing.** If the streak-file write fails, the wrapper emits a WARN to **stderr only** — the findings file at `OUTPUT_PATH` will NOT mention the degradation, and a subsequent CLEAN result will look identical to a healthy CLEAN. STOP enforcement may silently miss the affected round. Causes group into two classes: *transient* (lockdir contention exhausts the retry budget under heavy concurrency) and *persistent* (filesystem error, `$HOME` unwritable mid-run, BOM or NUL corruption in an existing streak file). If STOP semantics matter (e.g., a recurring transient cause you are trying to detect), inspect session stderr in addition to the findings file. The lockdir stale-recovery path (30s + steal) is the normal degradation route under concurrent invocations; persistent retry exhaustion indicates a deeper filesystem or environment problem.

   **Per-spec rm form (recommended):**

   Linux / Git Bash on Windows:
   ```
   SPEC_HASH=$(printf '%s' "<absolute_spec_path>" | sha256sum | cut -c1-12)
   rm -f ~/.claude/state/codex_postfix_streak_${SPEC_HASH}.txt
   ls ~/.claude/state/codex_postfix_streak_*.txt 2>/dev/null
   ```

   macOS (shasum replaces sha256sum):
   ```
   SPEC_HASH=$(printf '%s' "<absolute_spec_path>" | shasum -a 256 | cut -c1-12)
   rm -f ~/.claude/state/codex_postfix_streak_${SPEC_HASH}.txt
   ls ~/.claude/state/codex_postfix_streak_*.txt 2>/dev/null
   ```
   `<absolute_spec_path>` MUST be the absolute path to the spec, exactly as you would pass it to the wrapper — the wrapper canonicalizes via `realpath`/`readlink -f` internally and hashes the canonical form, so a relative-path substitution here yields a DIFFERENT hash and `rm -f` silently does nothing (rm -f does not error on missing files). The 12-char truncation, `printf '%s'` (no trailing newline; `echo` would inject `\n` and produce a different hash), and `sha256sum`/`shasum -a 256` invocation are all binding — the wrapper uses the same form (with auto-detection fallback), so any deviation breaks the lookup. Use whichever hash command is available on your platform. After running, `ls ~/.claude/state/codex_postfix_streak_*.txt` confirms whether the reset succeeded (the file matching the spec's hash should be gone).

   **Wildcard form (use only if you have confirmed the transient cause for EVERY active spec):**
   ```
   rm -f ~/.claude/state/codex_postfix_streak_*.txt
   ```
   This resets streaks for ALL specs at once, possibly papering over genuine consecutive-transient failures elsewhere. Default to the per-spec form unless you've verified each active streak.

   Streak files left at zero bytes are inert (their content `0` or empty zero-byte means streak=0 by design); operators may safely `rm` zero-byte files at any time as a cosmetic cleanup. The wrapper does NOT auto-unlink reset files because doing so would race with concurrent invocations on the same spec. The counter does NOT reset across sessions, across `/verify` invocations, or across separate verification rounds — if R3 hits exit 2 and R4 also hits exit 2, that is two consecutive even if R3 and R4 ran in different sessions on different days. The counter is per-spec; a fresh exit-2 streak on a different spec does not inherit prior streaks. Exit 3 (fatal) does not touch the counter at all and must be fixed before any subsequent scan is meaningful. Exit 4 (STOP) is the side-effect of the second consecutive exit-2 increment — that increment runs first, hits 2, and the wrapper then emits exit 4. Exit 4 does NOT itself perform a further increment. After exit 4, subsequent runs either reset the counter (on exit 0/1) or re-increment normally (on the next exit 2).

   **Calibration mode (`--no-streak`).** Maintainers building or testing THIS wrapper use this flag to disable streak interaction in both directions (no increment on exit 2, no reset on exit 0/1). **Steady-state /verify operators NEVER use this flag.** If you don't know why you'd need it, you don't need it. The env var `CODEX_POSTFIX_NO_STREAK=1` is equivalent to passing `--no-streak`.

   > **WARNING:** Do NOT export `CODEX_POSTFIX_NO_STREAK=1` into a shell profile (`.bashrc`, `.zshrc`, project `.env` sourced at startup) — that silently disables streak tracking for every subsequent session, making the safety counter inert without warning.

   > **Env-var bypass via captured stderr.** The wrapper treats `CODEX_POSTFIX_NO_STREAK=1` as equivalent to `--no-streak`. When the env var is set WITHOUT the flag, the wrapper emits a one-shot stderr tripwire WARN — but the WARN is suppressed when stderr is captured or discarded by a wrapping script (Sonnet listener, CI pipeline, direnv, `.envrc`, Nix shell). The env var still wins silently. If you have exported the env var anywhere in your environment, two operator-discipline rules apply: **(1) If you want streak tracking ACTIVE for a run, explicitly unset the env var on the invocation:** `env -u CODEX_POSTFIX_NO_STREAK ~/.claude/scripts/codex-postfix-scan.sh ...`. **(2) If you want streak tracking DISABLED, pass `--no-streak` explicitly** even if you've also exported the env var — the explicit flag in the invocation line is the only signal a code reviewer can audit later; the env var leaves no trace in shell history.
7. **Phase progression (interleaved squad active):** R1 Sonnet → R2 Codex → R3 Sonnet re-validation → gate → conditional R4. Re-run only roles flagged in prior phases. In 5-agent fallback (Codex absent): re-run only agents that returned above-INFO. Fresh prompts in all modes — no prior-phase references.
8. **Opus closure (interleaved squad active):** Fires ONLY after the R3 gate passes (all re-run Sonnet agents PASS). Manifest written to `squad_[chN_]opus/` BEFORE any progress message (ensures `stop-task-check.sh` sees the Opus dir immediately). Uses unprefixed filenames (`mechanical.md`, etc.). Both `squad_[chN_]sonnet/` and `squad_[chN_]opus/` dirs checked independently by commit gate. In 5-agent fallback (Codex absent): fires after all 5 Sonnet agents PASS in a round (existing behavior, unchanged).

### Step 6: Fix loop

**Fix ALL findings above INFO before launching the next round.** FAIL/WARN/MEDIUM/LOW + pre-existing issues surfaced by agents all qualify; only INFO defers. A fresh squad should return nothing but INFOs — selectively fixing only FAILs/HIGHs leaves a moving baseline that never converges. Apply every fix in-place per Step 5 #4. If round N+1 has MORE findings than round N, the fix method is broken — stop the loop, re-read every round-N fix, and convert any annotation to an in-place edit before continuing.

When the interleaved squad is active, the fix loop is implicit in the R3/R4 cycle with gate check (max 7 phases). In 5-agent fallback mode (Codex absent), existing agent-scoped re-run applies unchanged (max 5 rounds). After the phase cap is reached: write `VERIFICATION_BLOCKED` + remaining issues to CT, present to user.

**/verify itself never commits.** Commit boundaries belong to /3 (build end) and /5 (sprint end); the squad's role is to clear the path to those commits.

**Opus closure round terminates the loop.** Per Step 5 #8: when the R3 gate passes (all re-run Sonnet agents PASS), Opus closure fires. Apply any above-INFO fixes from closure in-place. Do NOT spawn another round — closure is the terminator. The closure round does NOT count against the phase cap.

**NEVER self-certify verification results before the Opus closure round.** Within the interleaved loop, after fixing findings, always progress to the next phase. The closure round itself is the only round whose fixes are not re-verified.

**Do not ask permission to fix.** Asking "should I fix and re-run?" is a procedural failure — the answer is always yes. Only genuine design decisions warrant a pause.

Squad files are ephemeral and gitignored. When in doubt, run it.
