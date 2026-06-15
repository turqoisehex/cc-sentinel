## Verification Behavior Rules

Read before running /verify, /perfect, /grill, or any verification pass.

### Procedural Compliance Is Non-Negotiable

Execute every verification procedure EXACTLY as defined. If the procedure says 5 Sonnet agents, launch 5 Sonnet agents. When Codex CLI is on PATH, the interleaved squad fires: 5 Sonnet R1 + 5 Codex R2 + 1–5 Sonnet R3 per flagged roles + gate + Opus closure. Launch all phases per the rules below. The interleaved procedure applies to ALL /verify invocations regardless of what is being verified — specs, plans, code, configs, prompts, 10-line files, 10,000-line files. The scope type and scope size grant ZERO discretion over which phases run or how many agents launch. "It's just a spec" / "it's only transformation rules" / "it's not a codebase artifact" / "this is too simple for 15 agents" = rationalization, not judgment. If a procedure states a phase cap, respect it (interleaved cap: 7 phases before VERIFICATION_BLOCKED). There is ZERO discretion to reduce, collapse, compact, abbreviate, or "streamline" any verification procedure. A single comprehensive agent is NOT a substitute for a multi-agent squad. "Context pressure," "equivalent coverage," "already verified," "diminishing returns," "sufficient confidence," and "scope doesn't warrant it" are NEVER valid reasons to skip or reduce steps. These are mechanical commands — execute them without reasoning about whether they can be shortened.

### No Skimming

Context percentage is never a valid reason to skip reading files. If a procedure says "read," read. If context is genuinely tight, delegate the reading to a subagent. Never present a skimmed evaluation as thorough. If you can't do a step properly, say so — don't silently degrade it.

### Externalize Decisions Before Verification

Before any verification or completion claim: replay conversation, list every user decision/approval/rejection, grep work product for each. Anything missing -> write to file immediately. Only then launch verification. Parent session's job — agents lack conversation context.

After edits: re-read edited sections to confirm changes are physically present. Never claim "N fixes applied" based on having called Edit. Gap between "I noted that" and "it's in the file" is where decisions die.

### Fixes Are In-Place Edits — Never Appendices

When a verification round finds wrong text in a spec, code, or any file, the fix is to **edit the original wrong text at its source location**. Find the wrong prose, change it, done.

**Banned fix patterns** (all forms of fix theater that leave the original wrong text in place):
- Appending a "Consolidated fixes" or "Bindings" section at the end of the file
- Writing "§ 3.X R{N} corrections" appendix blocks that describe what earlier sections should say
- Adding "SUPERSEDED" or "OBSOLETE" markers to the original text instead of replacing it
- Writing a "fix_summary" that lists changes as if they were applied, when the original text is untouched
- Any structure where the wrong text and its correction coexist in the same file

**Why this matters for convergence:** Cold readers read linearly. If § 2.3 says X, they implement X — they will never find the correction in § 3.8. Each round's appendix becomes new surface area for the next round's agents to flag. Findings compound instead of subtracting. In one observed case, rounds 11→15 went from 30 to 40 findings because four rounds of appendix "fixes" never edited the original wrong prose.

**Convergence diagnostic:** If round N+1 has more findings than round N, stop. The fix method is broken. Re-read every "fix" from round N. If any fix was an annotation rather than an in-place edit, convert it before launching the next round.

### Round Execution Rules

- Squad that found problems ≠ fix verifiers. Fix commits need a fresh squad — never re-run the same agents that found the issues.
- Never dismiss a finding as "stale," "agent error," or "pre-existing." Check the source file first, then fix. Squad findings are owned by the session that ran the squad.
- Commit only when the entire round = all agents PASS. Partial PASS (some agents PASS, others WARN/FAIL) does not meet the gate.
- `VERDICT: PASS` plain text, never bold. Hooks grep for the literal string; `**VERDICT: PASS**` breaks the match.
- Squad manifest format: `"launched"` key + `sonnet_`-prefixed filenames (or unprefixed when Codex absent). Include `codex` field when Codex agents are part of the squad.

### Post-fix integrity scan (mandatory before next round)

**Cardinality and skip rule:** The scan fires exactly ONCE per round, AFTER all fix application is complete and BEFORE re-dispatching the next squad — regardless of how many fix-application units (Sonnet agents, direct edits) ran during the round. **Skip the scan entirely when the round produced zero above-INFO findings** (no fix was applied, so there is no fix-drift to detect); in that case proceed directly to the next-round re-dispatch step per SKILL.md Step 5 item 7. The byte-equality contract between the install wrapper (`~/.claude/scripts/codex-postfix-scan.sh`) and its in-tree mirror (project-specific draft location) is maintained via `cp + cmp` and is operator-discipline, not enforced by hook — verify with `cmp` before scan invocation if the wrapper has been edited recently.

After applying fixes from a verification round (whether direct edits or Sonnet fix-application agent), substitute the actual channel name (or use the unchanneled form) and run:

    # Unchanneled run:
    ~/.claude/scripts/codex-postfix-scan.sh \
      <spec_path> \
      verification_findings/squad_sonnet/integrity_scan.md

    # Channeled run (e.g., channel 3):
    ~/.claude/scripts/codex-postfix-scan.sh \
      <spec_path> \
      verification_findings/squad_ch3_sonnet/integrity_scan.md

The `[chN_]` notation (and siblings `[chN/]`, `[_chN]`) are prose-readability placeholders for channel-routing — substitute the actual channel number before any shell invocation. `[chN/]` = dispatch subdir (e.g., `_pending_sonnet/ch3/`), `[chN_]` = squad-directory prefix (e.g., `squad_ch3_sonnet/`), `[_chN]` = file-name suffix (e.g., `integrity_scan_ch3.md`). All three are unchanneled-empty (substitute the empty string for an unchanneled run). Never paste them literally into a shell: bracket forms are bash glob character classes and the wrapper rejects them with exit 3. `<spec_path>` is the absolute or project-root-relative path to the spec under verification — substitute the actual path before invoking.

The scan output file is OVERWRITTEN on each invocation. Squad dirs are gitignored (`verification_findings/squad*/`) and `safe-commit.sh` (an internal mechanism, never invoked directly — operators use `channel_commit.sh`) deletes their contents on each successful commit, so prior scan output is NOT preserved by committing. If preservation is needed for a specific round, copy `integrity_scan.md` out of the squad dir to a tracked location before the next squad cycle. The `.raw.md` sibling (preserved on `TRANSIENT_NO_OUTPUT` no-VERDICT-line sub-path) sits at the same top-level position as `integrity_scan.md` and is cleaned up by the same flat-glob squad-dir cleanup — no separate cleanup wiring is required, but operators preserving an `integrity_scan.md` for forensic reasons should copy `${OUTPUT_PATH}.raw.md` alongside it; both files together are the diagnostic artifact, not just one.

The output path MUST sit at the top level of the squad directory — never inside a `spec_rN/` subdir; the wrapper rejects nested paths with exit 3 because `safe-commit.sh`'s squad cleanup is flat (rm + rmdir).

**What the scan flags (controlled vocabulary — 7 patterns).** These are the only artifact classes the scan is contracted to detect; full prompt definitions live in `.claude/reference/codex-postfix-prompt.md` (global installs: `~/.claude/reference/codex-postfix-prompt.md`):

1. **DUPLICATE PARAGRAPHS** — same sentence/paragraph copied into two places (often R{N} appendix vs original section).
2. **APPEND-INSTEAD-OF-EDIT** — a "Consolidated fixes," "Bindings," "R{N} corrections," or "Appendix — RN fixes" section that describes what earlier sections should say instead of editing them.
3. **STALE CROSS-REFERENCES** — `§ N.N`, `Task N`, or `line N` pointers that no longer resolve to the cited content. Includes sub-pattern 3b (heading-text-edit drift): a referrer naming a heading by text (e.g., "see Decision 7") where the heading was renamed (e.g., to "Decision 7a") so the textual reference no longer matches.
4. **ORPHAN PSEUDOCODE MARKERS** — `PSEUDOCODE WARNING` or `PSEUDOCODE NOTE` annotations with no following fenced code block within 30 lines (reading downward from the marker).
5. **ROUND-MARKER POLLUTION** — `R{N}`, `Cold_F<N>`, `Adv_<X>`, or other agent-finding tombstones inlined in the spec body.
6. **CODE-BLOCK FENCE IMBALANCE** — odd number of triple-backtick fences (one fence opened but never closed, or vice versa).
7. **ORPHAN TODO/FIXME MARKERS** — naked `TODO`, `FIXME`, `XXX`, or `HACK` annotations outside code blocks.

**Pattern 5 is unconditional.** Round markers and tombstones are banned in spec body prose; there is no exemption mechanism. Audit-trail material that needs to survive (round IDs, finding labels, fix rationale) lives in `verification_findings/` squad output files and git history, not in the spec.

**When to use `--no-streak`.** Two operating modes:

| Mode | Use `--no-streak`? | Reason |
|------|--------------------|--------|
| /3 calibration | YES | Iterating on the wrapper itself; intentional repeated transients are normal. The streak counter would surface false STOPs and burn operator attention. |
| Steady-state /verify rounds | NO | The two-consecutive-transient STOP is the safety mechanism that prevents an inert scan from silently degrading the verification floor. |

Setting the env var `CODEX_POSTFIX_NO_STREAK=1` is equivalent to passing `--no-streak`. Do NOT export it into a shell profile (`.bashrc`, `.zshrc`, `.env`) — that silently disables streak tracking for every subsequent session.

- Exit 0 (CLEAN): proceed to next round (re-run any agent that returned anything above INFO, per SKILL.md Step 5 item 7).

- Exit 1 (ARTIFACTS_FOUND): abort. Read integrity_scan.md, fix artifacts in place, re-run scan until CLEAN, THEN dispatch next squad. Exit 1 is a procedural gate, not a hard commit block — the hook chain does not enforce it; operator compliance is the mechanism.

- Exit 2 (transient). **Do NOT re-run the scan on this round.** (`TRANSIENT_TIMEOUT` / `TRANSIENT_RATE_LIMIT` / `TRANSIENT_AUTH` / `TRANSIENT_NO_OUTPUT`; the wrapper REMAPS an ARTIFACTS_FOUND reply that has no body or no Enumeration trace to `TRANSIENT_NO_OUTPUT` rather than emitting a distinct sub-label, so all transient causes are covered by the four labels above; see "VERDICT labels emitted" bold paragraph below for the per-cause sub-label): proceed without the scan THIS round. The 5 Sonnet agent squad is the floor; the scan is additive. Log a one-line note in CT (`integrity scan exit 2 — <VERDICT>`). The two-consecutive-transient STOP is enforced automatically by the wrapper (Exit 4 below) — operators do not manually track consecutive transients. When the cause is the no-VERDICT sub-path of `TRANSIENT_NO_OUTPUT` (which covers two sub-paths sharing the same VERDICT label: empty stdout AND stdout-with-content-but-no-VERDICT-line), the original Codex reply is preserved at `${OUTPUT_PATH}.raw.md` only on the second sub-path — see "Sibling `${OUTPUT_PATH}.raw.md` on the no-VERDICT path" bold paragraph below for the full forensic-inspection contract.

- Exit 3 (fatal — wrong args, missing files, codex CLI absent, sha256sum/shasum both absent, `wc`/`timeout`/`mktemp` absent, `$HOME` unset or unwritable): wiring bug. STOP, fix, re-invoke. Note: a codex CLI that is present on PATH but non-functional (corrupt install, missing runtime, auth-crash-on-start) surfaces as exit 2 instead — check codex install health if exit 2 persists after network recovery.

- Exit 4 (consecutive-exit-2 STOP): the wrapper detected two exit-2 results in a row on this spec and self-aborted. Investigate the streak cause before next squad dispatch; reset rules below.

#### VERDICT labels emitted into `integrity_scan.md`

`CLEAN` (exit 0), `ARTIFACTS_FOUND` (exit 1), `TRANSIENT_TIMEOUT` / `TRANSIENT_RATE_LIMIT` / `TRANSIENT_AUTH` / `TRANSIENT_NO_OUTPUT` (exit 2 variants — useful when reading the raw file to identify which transient cause fired). Exit 3 paths write no findings file (errors go to stderr only). Exit 4 paths DO write a findings file: it contains the `TRANSIENT_*` VERDICT line from the second consecutive transient that triggered the STOP — the file is the diagnostic record of the cause. Codex stdout with a non-empty preamble before the VERDICT line is tolerated — the wrapper emits a stderr WARN ("VERDICT line is not the first non-empty line") and proceeds with the verdict.

**Sibling `${OUTPUT_PATH}.raw.md` on the no-VERDICT path:** When `TRANSIENT_NO_OUTPUT` fires specifically because Codex stdout had content but no `VERDICT:` line anywhere in it, the wrapper preserves the original Codex reply at `${OUTPUT_PATH}.raw.md` (sibling of `integrity_scan.md`) for forensic inspection — the diagnostic block in `integrity_scan.md` itself replaces the original. Other exit-2 sub-causes (timeout, rate-limit, auth, empty stdout) do NOT produce a `.raw.md` sibling — only the no-VERDICT path does, since that is where the original reply is most diagnostically valuable. Note: on this path, `cp` of the staging file to `${OUTPUT_PATH}.raw.md` is best-effort; if it fails (disk full, permissions), the wrapper logs a WARN to stderr and continues without `.raw.md` — the diagnostic block in `integrity_scan.md` is then the sole forensic record.

**Prompt-injection threat model (limitation).** The runtime cryptographic nonce on the spec-region sentinels defeats sentinel-collision attacks from co-located observers (any process that can see `ps`, the clock, or PIDs). It does NOT defeat prompt-injection from inside the spec body itself: a meta-spec whose narrative content instructs Codex (the LLM) to treat its prose as outside the spec region — or that quotes the controlled-vocabulary verdict strings (`VERDICT: CLEAN` / `VERDICT: ARTIFACTS_FOUND`) literally in the body — can suborn the verdict despite the nonce. The wrapper's defense-in-depth check WARNs only on the literal `{{SPEC_CONTENTS}}` token in HEAD/TAIL regions, not on `<!-- BEGIN_SPEC` / `<!-- END_SPEC` literal HTML-comment prefixes nor on quoted verdict strings in the spec body. **Treat any spec that quotes the wrapper's prompt scaffolding or verdict vocabulary as a self-injection risk** — escape the placeholders (e.g., `VERDICT\:` or `VERD&#x200B;ICT:`) or run the scan against a sanitized copy. Operators editing meta-specs about this scan should double-check that the spec body does not begin a line with `VERDICT:` outside a fenced code block. The wrapper pre-flight WARN on this case is non-fatal — the scan proceeds, and a CLEAN result on a meta-spec that echoes the vocabulary may be spurious; the WARN is your only signal.

**Consecutive-exit-2 counter — reset rules (must match the definition in `~/.claude/skills/verify/SKILL.md` Step 5 item 6).** The wrapper maintains the counter on disk at `~/.claude/state/codex_postfix_streak_<spec_hash>.txt` (per-spec keying via SHA-256 of the spec path); operators do NOT track manually. The wrapper auto-increments on every exit-2 path and resets on every exit-0 / exit-1 path; when the streak hits two, it surfaces a STOP message to stderr quoting the streak file path. "Consecutive" means: two exit-2 results in a row, with NO intervening exit-0 (CLEAN) or exit-1 (ARTIFACTS_FOUND) result between them. The counter resets when EITHER (a) the wrapper emits exit 0 or exit 1 on a subsequent run, OR (b) the operator manually deletes the streak file after resolving the underlying transient cause and confirming the resolution in CT. To delete the per-spec streak file, compute the hash and run `SPEC_HASH=$(printf '%s' "<absolute_spec_path>" | sha256sum | cut -c1-12); rm -f ~/.claude/state/codex_postfix_streak_${SPEC_HASH}.txt; ls ~/.claude/state/codex_postfix_streak_*.txt 2>/dev/null  # confirm the matching file is gone` (on macOS, replace `sha256sum` with `shasum -a 256` — the wrapper uses whichever is available).

If the streak-file write itself fails (read-only HOME, NFS perm drift, lock contention beyond retry budget), the wrapper emits a stderr WARN and continues; STOP enforcement may miss that round — symptoms are stderr-only. To reset all specs at once (e.g., after an extended Codex outage that affected every spec under verification), use the wildcard form `rm -f ~/.claude/state/codex_postfix_streak_*.txt` — this is a deliberate scope-everything affordance, not a fallback for hash-computation difficulty. Do NOT hand-edit streak files — non-numeric content (a stray newline, the wrong character) causes the wrapper to silently reset the counter to 0, erasing a prior transient and delaying the STOP that should fire on the second consecutive transient by one round. The counter does NOT reset across sessions, across `/verify` invocations, or across separate verification rounds — exit 2 in R3 followed by exit 2 in R4 is two consecutive even if the rounds ran in different sessions. The counter is per-spec; a fresh exit-2 streak on a different spec does not inherit prior streaks. Exit 3 (fatal) does not touch the counter at all. Exit 4 (STOP) is the side-effect of the second consecutive exit-2 increment — that increment runs first, hits 2, and the wrapper then emits exit 4. Exit 4 does NOT itself perform a further increment. After exit 4, subsequent runs either reset the counter (on exit 0/1) or re-increment normally (on the next exit 2).

**Calibration mode (`--no-streak`).** Adding `--no-streak` as the first wrapper argument disables BOTH directions of streak interaction (no increment on exit-2, no reset on exit-0 / exit-1). Setting the env var `CODEX_POSTFIX_NO_STREAK=1` is equivalent to passing `--no-streak` and is intended for test harnesses and CI scripts that prefer environment-based configuration. Used during /3 calibration only; steady-state /verify rounds run without `--no-streak` and without the env var. Do NOT export `CODEX_POSTFIX_NO_STREAK=1` into your shell profile (`.bashrc`, `.zshrc`, project `.env` sourced at startup) — that silently disables streak tracking for every subsequent session, making the safety counter inert without warning. Use the flag or env var per-invocation only. If only the env var (not the flag) sets `--no-streak`, the wrapper emits a one-shot stderr WARN per invocation as a tripwire against silent shell-profile exports.

**Env-var bypass via captured stderr.** The tripwire WARN is suppressed when stderr is captured or discarded by a wrapping script (Sonnet listener, CI pipeline, direnv, `.envrc`, Nix shell); the env var still wins silently. **If you want streak tracking ACTIVE for a run, explicitly unset the env var on the invocation:** `env -u CODEX_POSTFIX_NO_STREAK ~/.claude/scripts/codex-postfix-scan.sh ...`. Conversely, if you want it DISABLED, pass `--no-streak` explicitly so the audit trail (shell history, CI log) records the choice — the env var leaves no trace there.

Note: the scan is NOT enforced by `stop-task-check.sh` or `safe-commit.sh` — `integrity_scan.md` is intentionally absent from the squad manifest's `"launched"` list. The scan is a safety net layered on top of the 5 Sonnet agent squad, not a hard commit gate; an operator who hits Exit 2 can still ship.

This catches the fix-application failure mode that caused the Ch3 spec verification to balloon to 20 rounds.

## Codex verification agents (interleaved squad)

**Phase glossary:** R1 = first Sonnet round (5 agents, baseline). R2 = Codex round (5 agents, cross-architecture). R3 = Sonnet re-validation (1–5 agents, only roles flagged in R1/R2). R4 = conditional Codex round (gpt-5.5+xhigh, only still-failing roles after R3). Gate = decision point after R3: all Sonnet PASS → Opus closure fires; any FAIL/WARN above INFO → R4. Opus closure = terminal 5-agent round in `squad_[chN_]opus/`, findings applied without re-verification.

Codex agents are additive — 5 Sonnet agents remain the absolute floor. Codex transient failures don't block the fix step or invalidate the round.

**TRANSIENT sub-labels:**
- `TRANSIENT — rate limit` (stderr matches rate-limit patterns)
- `TRANSIENT — auth not configured` (missing ~/.codex/auth.json or auth_mode)
- `TRANSIENT — malformed output (exit 0, no VERDICT line)` (no structured output produced)
- `TRANSIENT — <exit code> <first line of stderr>` (all other non-zero exits)

**No hard timeout** on Codex execution. The Codex CLI manages its own budget.

**VERDICT validation:** `^VERDICT: (PASS|WARN|FAIL)` — case-sensitive, no markdown formatting, must be first word on the line. Same format as Sonnet agent output.

**Output extraction:** Raw `codex exec` stdout contains session log noise. The wrapper extracts from the last valid VERDICT line to EOF. Full raw output preserved at `OUTPUT_PATH.raw.md` for debugging.

**Codex CLI absent:** If `codex` not on PATH, falls back to 5-agent Sonnet-only dispatch. Manifest omits `codex` field entirely.

**Sonnet-only PASS rule:** When a Codex agent returns TRANSIENT and the corresponding Sonnet role returned PASS with no findings above INFO from either model, the role is considered passed for gate purposes. The missing Codex perspective is recovered opportunistically if R4 triggers for other roles. This prevents persistent rate limits from burning through phases on roles already validated by Sonnet. When Sonnet itself had findings on a role AND Codex was TRANSIENT for that role, normal phase progression applies — the role is flagged for R3 re-run based on the Sonnet findings, not the TRANSIENT.

**All-TRANSIENT degradation:** If all 5 Codex agents return TRANSIENT in R2, R3 becomes a full 5-role Sonnet re-run (since no cross-architecture data exists to determine which roles need re-validation). If all Sonnet PASS in R3, the gate passes and Opus closure fires. The session degrades gracefully to Sonnet-only coverage without blocking or wasting budget on retries. If R4 triggers (Sonnet found something in R3), Codex is attempted again for the failing roles; if still rate-limited, those roles proceed Sonnet-only.

**R4 conditional phase:** When the R3 gate fails (any re-run Sonnet agent returns FAIL or WARN above INFO), R4 dispatches Codex (gpt-5.5+xhigh) on the still-failing roles only. After R4 fixes, Sonnet re-validates those roles again (another R3 evaluation). Max 2 additional R3/R4 cycles before VERIFICATION_BLOCKED. R4 uses deeper reasoning (xhigh) to surface harder issues that standard Codex missed.

**Hook fallback arrays (known latent risk, no change required):** Both `stop-task-check.sh` (`SQUAD_EXPECTED` inline assignment) and `safe-commit.sh` (`DEFAULT_AGENTS` variable) have hardcoded unprefixed fallback arrays. These fire only when `manifest.json` is absent (crash before manifest write). In interleaved sessions, `sonnet_`-prefixed files exist but the fallback expects unprefixed — silent misreport. No code change is required because the manifest is always written first (Step 4a). This is accepted latent risk; if manifests become unreliable, update the fallback arrays as a separate follow-up.

## Opus closure

After the R3 gate passes (all re-run Sonnet agents PASS), fire 5 Opus agents in `squad_[chN_]opus/` with unprefixed filenames (`mechanical.md`, `adversarial.md`, etc.). Write the `squad_[chN_]opus/manifest.json` BEFORE any progress message to the user, so `stop-task-check.sh` sees the directory as active while Opus agents run. Opus closure is a single terminal pass — findings are applied without re-verification. The closure fires ONLY after the gate passes; if VERIFICATION_BLOCKED is reached, no closure fires.

**Provisional evaluation:** After each sprint that uses the interleaved squad, record in CT: "Opus closure: N unique findings this sprint" (where N = findings surfaced only by Opus agents, not previously found by Sonnet or Codex). After 3–5 sprints, review whether N justifies the Opus closure round's token cost. If N ≈ 0 consistently, the Opus round may be made conditional.

### /verify full = Full Squad

When `/verify full` is invoked on implementation plans (.md files describing code changes), treat as "mixed" scope — the plan touches source code even though the plan file is markdown. Run all applicable agents. Only use docs-only filtering for pure documentation (READMEs, changelogs, comments).

### Per-Instance Field Value Completeness

The field-consumption audit checks "is this field consumed?" — but not "does every instance that needs this field actually declare it?" When a field has per-instance semantics (e.g., per-phase configs, per-exercise parameters, per-round overrides), consumption by at least one instance does NOT prove correctness. A field present on one instance but missing from others silently falls back to a default — the consumer works, the audit sees a read site, and the bug ships.

**Rule:** For every consumed field on a multi-instance data type, verify the field has the correct value on EVERY instance, not just the first match. Enumerate all instances of the containing type → for each, confirm the field value matches the spec. Missing = silent default = FAIL.

**Applies to:** Any data type where multiple instances carry independently-set fields: phase configs, exercise definitions, per-round overrides, Map/List entries with per-item fields.

**In /perfect Phase 2.5:** After the [C]/[T]/[D] pass, add a second pass: for each [C] field on a multi-instance type, list every instance and its value. Flag any instance where the value is absent (relying on `?? default`) or differs from the spec without justification.

**In /verify completeness agent:** Check not just "does the spec requirement have implementing code?" but "does every runtime instance that the spec governs carry the correct value?" A spec requirement that applies to N instances must map to N correct declarations, not one.

### Platform Compatibility Verification (dependency agent mandate)

**The problem:** Verification agents reason from training data. Training data conflates versions. `Join-Path a b c` reads as correct because PS 7+ accepts it — but PS 5.1 (default on Win 10/11) does not. No amount of cold-reading catches this without checking documentation. The same class of bug applies to every cross-platform surface: Flutter APIs unavailable on certain platforms, Dart SDK version-gated features, npm packages with platform-conditional behavior, shell builtins that differ between bash 3 (macOS) and bash 5 (Linux).

**The rule:** When the dependency agent encounters API calls, method invocations, CLI flags, or language features that are platform-specific or version-specific, it MUST verify compatibility against the project's declared targets using documentation tools (context7 `resolve-library-id` → `query-docs`, web search, or official docs). **Never trust training data for version-specific behavior.** Training data does not carry version annotations — it blends all versions into one undifferentiated pool.

**Declared targets (cc-sentinel infrastructure):**
- PowerShell 5.1+ (Windows installer — NOT pwsh 7)
- Bash: 3.2+ (macOS ships ancient bash) and 5.x (Linux)
- Node.js: LTS (for Codex CLI tooling)

**Project targets:** Determined at runtime by reading the project's config files (`pubspec.yaml`, `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, etc.). The dependency agent should identify the project's shipping platforms from these files and verify API compatibility against them.

**What to check (dependency agent checklist for cross-platform code):**

1. **API version availability.** For any method, flag, parameter, or constructor: is it available on ALL target versions? Check docs, not memory. Examples: `Join-Path` variadic (PS 7 only), `Get-Date -AsUTC` (PS 7 only), `Start-Process` with `.ps1` files (doesn't work — PS doesn't register .ps1 as executable), `readlink -f` (GNU only, not macOS).

2. **Encoding and non-ASCII.** Script files (.ps1, .sh, .bat) that contain non-ASCII characters (em dashes, smart quotes, Unicode) will fail on systems with restrictive codepages or BOM expectations. Flag any non-ASCII byte in executable scripts. Use `—` escapes or ASCII equivalents.

3. **Path construction.** Platform-specific path separators, case sensitivity differences, maximum path length (Windows 260 char limit), spaces in paths, tilde expansion (shell-only, not available in most APIs).

4. **Process launching.** How processes are started differs fundamentally: `Start-Process` can't launch `.ps1` files directly; `cmd.exe /c` has quote-stripping behavior; Git Bash on Windows mangles arguments passed to PowerShell (known Claude Code bug #56452); `exec` vs `spawn` semantics differ by platform.

5. **Shell compatibility.** `[[` (bash-only, not POSIX sh), `echo -e` (not portable), array syntax (bash 4+ features), associative arrays (bash 4+), `local -n` (bash 4.3+), `readarray`/`mapfile` (bash 4+).

6. **Feature gating.** Framework features that exist on some platforms but not others: desktop-only APIs called from mobile code, platform-specific plugins, browser APIs unavailable in native builds.

**How to verify (procedure for the dependency agent):**

When you encounter a potentially version-gated API:
1. Identify the minimum target version (from declared targets above or project config)
2. Use context7 (`resolve-library-id` → `query-docs`) to look up when the API was introduced
3. If context7 lacks version info, use web search for "[API name] minimum version" or "[API name] added in version"
4. If the API is NOT available on all targets: flag as HIGH with the specific version constraint and a suggested compatible alternative
5. If you cannot determine availability with certainty: flag as MEDIUM with "version compatibility unverified — manual check needed"

**This is NOT optional for the dependency agent.** Every verification round on cross-platform code (scripts, installers, code targeting multiple platforms) requires at least one documentation lookup per file to verify the most complex API call used. "It looks right" is the exact failure mode this rule prevents.

**Examples of bugs this catches (cc-sentinel infrastructure):**
- `Join-Path` variadic form (PS 7 only — PS 5.1 accepts only 2 args)
- `Get-Date -AsUTC` (PS 7 only — use `[DateTime]::UtcNow` for PS 5.1)
- `readlink -f` (GNU only — macOS requires `realpath` or manual resolution)
- `echo -e` (not portable — use `printf` instead)
- `local -n` nameref (bash 4.3+ — not available on macOS default bash 3.2)
- `timeout` command (GNU coreutils — not on macOS; use `gtimeout` or manual kill)
- Array append `+=` in bash (3.1+ but behavior differs with `set -u` in 3.2 vs 4.x)
- `sed -i ''` (macOS) vs `sed -i` (GNU) — in-place edit syntax diverges

### Fidelity-Audit WARN→INFO Triage

Downgrading a fidelity-audit WARN→INFO requires citing the specific spec or plan rule that authorizes the observed behavior. "Belt-and-suspenders" or "no conflict" is not a valid downgrade rationale on its own — grep the plan/spec for explicit prohibitions on the shape being approved before declaring it safe to downgrade.

An observed incident: a WARN was downgraded as "belt-and-suspenders" but the plan explicitly prohibited the early-return shape it approved; the commit-adversarial pass caught the error several rounds later — the downgrade should have grepped the plan for the prohibition first.

### Sonnet Listener CT Isolation

Sonnet listener sessions must NEVER write to CURRENT_TASK files, even when the stop hook fires. The /sonnet skill states: "Never write to CURRENT_TASK files" and "Ignore stop hooks." Stop hooks are designed for Opus orchestrator sessions, not stateless Sonnet listeners.
