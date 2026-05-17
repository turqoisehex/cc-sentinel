---
name: design
description: "Design and planning phase: brainstorming, task classification (Opus/Sonnet split), decision externalization, and Sonnet prompt generation. Phase /2 of the sprint pipeline. Also invoked as /2."
---

# /design — Design + Plan (alias: /2)

**Trigger:** New features, spec gaps, design decisions needed.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

**Step 0:** Before any other work, TaskCreate every step. Mark in_progress→completed.

## Logical ordering (read first)

The /design pipeline produces two artifacts that derive from each other: the **spec** (output of brainstorming) and the **plan** (output of writing-plans, consumed by /3). Each artifact must be verified BEFORE downstream work consumes it. Spec-verify therefore runs BEFORE writing-plans, not after — otherwise the plan derives from an unverified spec and any spec-level issue forces a plan rewrite, wasting plan-writing work.

Order: brainstorm → spec → **experiential walkthrough** → **/verify spec** → writing-plans → classify + consolidate → decision externalization → scrap-and-rewrite CT → **/verify plan** → (situational) **/verify external-tool prompt** → generate Sonnet specs → user approval.

## Procedure

### Step 1: Brainstorm

Invoke `superpowers:brainstorming` skill. Flow: brainstorm → spec doc. The spec is the input to Step 1b.

### Step 1b: Experiential walkthrough (MANDATORY before /verify)

Code is in service to user experience, not the other way around. Before /verify (which checks rigor, not coherence), narrate the user's journey end-to-end and stress-test the *experience*. Verify catches what's wrong; the walkthrough catches what's missing because nobody designed it.

**Method:** Walk every interaction step-by-step, in user time, asking three questions at each step:

1. **What is the user actually doing/feeling/perceiving here?** (visually, audibly, somatically, psychologically)
2. **What would make this awesome?** (the affordance that turns a generic moment into a great one)
3. **What would make this confusing or frustrating?** (the silent failure mode — no countdown, ambiguous button, missing feedback, false coercion, dead-end UX)

**Walk both happy paths and the in-between moments.** The friction lives in the seams: pause-resume, app-backgrounding, what plays during a decision gate, what shows when nothing else is happening, how the screen looks at t=0 and t=nominal and t=nominal+5s, what an accessibility user hears, what someone returning after a 30-min interruption sees.

**Surface every micro-decision the brainstorm didn't reach.** These typically show up as:
- Counter visibility (count-up vs count-down vs none — different psychological frames)
- Button affordance over time (always tappable / fade-in / hard-gate — coercion vs. invitation)
- Audio behavior at gates (continue / loop / silence — urgency vs. honesty)
- Round/step indicators ("Round 2 of 3" vs implicit)
- End-of-thing transitions (auto-advance vs. user-paced settle)
- Accessibility parity (screen-reader semantics matching visual coaching)
- Mode interactions (does setting X affect feature Y? often the answer is "no, category error")
- Equal-weight decision affordances (visual style biases the choice)

**Output:** add an `## Experiential walkthrough` section to the spec containing every micro-decision surfaced, each as a one-line decision with rationale. The /verify squad in Step 2 then has these to check against. Do NOT proceed to Step 2 until the walkthrough is complete and the user has confirmed (or overridden) every micro-decision surfaced.

**Anti-pattern to avoid:** the walkthrough is *not* a feature checklist. It is an *experience* check. Asking "is X handled?" is different from asking "what does the user feel at moment X?" The first is verification; the second is design.

### Step 2: Spec verification (MANDATORY before plan-writing)

Run `/verify full` scoped to the spec/design doc produced in Step 1. Up to **10 rounds** (overrides default 5-round cap). Follow the `/verify` skill procedure exactly, using the squad prefix `[chN_]` for channel routing.

- WORK_PRODUCT = spec file path(s).
- SOURCE_SPEC = the primary source material or brainstorming decisions.
- Run the full 5-agent squad (mechanical, adversarial, completeness, dependency, cold_reader).
- Fix all findings above INFO before launching the next round.
- All agents PASS (or WARN with zero new fixes needed) → proceed to Step 3.
- If round 10 ends with unresolved issues above INFO → write `VERIFICATION_BLOCKED` + remaining issues to CT and surface to user.

Why first: plan-writing is expensive (Sonnet dispatch, multi-phase decomposition, many file reads). Catching spec-level issues after the plan is written forces rewriting the plan. Spec-verify-first protects plan-writing work.

### Step 3: writing-plans produces detailed implementation plan

Invoke `superpowers:writing-plans`. Input is the verified spec from Step 2. Let the skill complete fully before proceeding.

### Step 3b: Classify tasks for Opus/Sonnet split

**Priority order for all agent decisions: (1) output quality — maximize it, (2) token budget — minimize waste, (3) wall clock time — irrelevant, never sacrifice quality or add risk to save time.**

Review every task. Classify each as `[OPUS]`, `[SONNET]`, or `[PARENT]`:

| Tag | When to use |
|-----|------------|
| `[SONNET]` | Self-contained with clear file paths + acceptance criteria, OR mechanical/pattern-following work. Spawned as Sonnet subagent via `Agent(model: "sonnet")`. |
| `[OPUS]` | Requires parent context, judgment, or design decisions. Executed directly by Opus. |
| `[PARENT]` | Requires conversation context, orchestration, or user-facing decisions. |

Classification rules:
1. If a task has clear inputs (file paths), clear outputs (acceptance criteria), and requires no design judgment → `[SONNET]`.
2. When in doubt between OPUS and SONNET → `[OPUS]`. Budget waste from over-classifying as OPUS is recoverable; broken output from under-classifying is not.
3. Parallelism is a capability, not a target. Spawn the **fewest** agents that preserve quality, not the most. Writing-plans produces fine-grained tasks for human readability; do NOT reflexively map one plan-task to one agent. Wall-clock speed-up is NEVER a reason to spawn more agents — quality is equal or better with merged dispatches because the agent sees adjacent context instead of cold-starting on a subset.

Annotate each task heading with its tag. Add summary table at top. MANDATORY — every plan with >5 tasks has Sonnet-eligible work. If none qualifies, state why.

### Step 3c: Consolidation pass (MANDATORY when ≥3 [SONNET] tasks)

After tagging, re-group [SONNET] tasks into the minimum number of dispatches. Every Sonnet spawn costs ~25–40k tokens of bootstrap context (CLAUDE.md + shared CT + channel CT + spec + plan + initial file reads) before any productive work. Two dispatches that share >70% of their context reads are burning that bootstrap twice for no quality gain.

**Merge when ALL true:**
- Tasks touch adjacent files in the same layer (e.g., all data-layer, all filter-chain, all test files).
- Tasks follow the same pattern (e.g., "add field X to N exercises" — one agent, one instruction, N edits).
- Combined task scope is still reviewable in one diff (<~200 LOC changed, <~6 files).
- No hard ordering dependency between the tasks being merged.

**Keep separate when ANY true:**
- File-write collision: two tasks edit the same file → must serialize, MUST be separate agents (parallel Edit calls on one file corrupt the diff).
- Different domains or reviewers: merging a data-layer edit with a UI-layer edit forces one reviewer to context-switch.
- One task depends on another's output.
- Combined diff would exceed ~200 LOC or ~6 files (agent attention degrades; reviewer attention degrades).

**When in doubt → merge.** The failure mode of over-merging (one agent doing slightly more work) is strictly smaller than the failure mode of over-splitting (N agents each paying full bootstrap cost).

**Produce a dispatch plan** with an estimated-tokens column:

| Dispatch | Merged plan-tasks | Files | Est. bootstrap | Est. working | Rationale |
|----------|-------------------|-------|----------------|--------------|-----------|
| D1 | Task 2 + Task 4 | 2 | ~30k | ~8k | Same data-layer surface, same edit pattern. |
| D2 | Task 3 | 1 | ~30k | ~5k | UI filter — separate reviewer. |
| D3 | Tasks 5 + 6 + 6b + 7 | 4 | ~35k | ~20k | All test files; shared harness imports. |

If a plan with ≥3 [SONNET] tasks has no merges, justify in one line why none qualify. "Reviewability" is a valid reason; "parallelism" is not.

### Step 4: Decision externalization

**Cannot be delegated — only parent has conversation context.**

BEFORE writing CT:
1. Replay the entire brainstorming conversation.
2. List every user decision, approval, rejection, refinement, constraint.
3. For each: grep the design doc for evidence it's in a file.
4. Missing → write to design doc NOW.

Risk: brainstorming generates the most decisions per turn. They feel captured because they're in conversation. They are NOT captured until in a file.

### Step 5: Scrap and rewrite CT

"Knowing everything you know now, scrap the initial CT and write the thorough, complete, cold-start-ready version with full plan."

Required sections: numbered steps with checkboxes + acceptance criteria, key file paths + infrastructure status, design decisions with rationale, out-of-scope list, each task classified `[OPUS]`/`[SONNET]`/`[PARENT]` (default `[OPUS]`).

Anti-lost-in-the-middle: write in segments of ~7 items, count structural elements, cross-check against plan headings, reverse-scan last third.

**Cross-channel dispatch:** If the user specifies that this work should be picked up by another channel (e.g., "put it in channel 7", "Opus 7 should run this"), write TWO files:

1. **CT:** `CURRENT_TASK_chN.md` (target channel). Fully self-contained — another Opus session reads it via `/opus N` and executes `/3` with zero additional context. Requirements:
   - Plan file path (the plan must also be written and committed)
   - All design decisions, key file paths, source paths, execution order
   - No references to "this conversation" or context only available here
2. **Prompt:** `verification_findings/_pending_opus/chN/<descriptive-name>.md`. This is the trigger file the Opus listener picks up. Keep it short — just the command to execute (e.g., "Read `CURRENT_TASK_ch7.md` and execute `/3`."). The CT carries the detail.

Both files required. CT without prompt = work prepared but never triggered. Announce readiness: "Channel N CT + prompt ready for pickup" and register in shared `CURRENT_TASK.md`'s Active Channels table.

### Step 6: Plan verification (MANDATORY before user approval)

Run `/verify full` scoped to the implementation plan produced in Step 3 (and refined through Steps 3b–5). Up to **10 rounds**. Same protocol as Step 2.

- WORK_PRODUCT = plan file path(s).
- SOURCE_SPEC = the spec verified in Step 2.
- Run the full 5-agent squad.
- Fix all findings above INFO before launching the next round.
- All agents PASS (or WARN with zero new fixes needed) → proceed to Step 7.
- If round 10 ends with unresolved issues above INFO → write `VERIFICATION_BLOCKED` + remaining issues to CT and surface to user.

### Step 7: External-tool prompt verification (situational — run only if applicable)

If the spec or plan includes a prompt the user must paste into an EXTERNAL tool (e.g., Claude Design for Flutter widgets, an image generator, a transcription model), the prompt is part of the deliverable surface and gets the same /verify rigor BEFORE the user pastes it.

Run `/verify full` scoped to the prompt(s). Up to **10 rounds**. Same protocol as Step 2.

- WORK_PRODUCT = prompt location (file + line range or dedicated prompt file).
- SOURCE_SPEC = the verified spec (Step 2) + the verified plan (Step 6).
- Verify scope grades: clarity, completeness, technical accuracy, missing constraints, project-style fidelity (color, typography, motion, voice), platform-feasibility (e.g., 60fps target, memory budget), invariant compliance.
- Do NOT run prompt verification in parallel with plan verification — surface as a serial gated step so the user sees verification results before pasting.

Skip Step 7 entirely if the sprint produces no external-tool prompts. Document the skip in CT (one line: "Step 7 N/A — no external-tool prompts in this sprint").

### Step 8: Generate Sonnet task specifications (MANDATORY)

Always classify. Always generate. If Step 3b found zero [SONNET] tasks, state why and skip.

**Default mode:** Task specs are embedded directly in the /3 plan. No dispatch file or YAML frontmatter needed.

**Duo mode:** Write dispatch-ready prompt to `verification_findings/_pending_sonnet/[chN/]sonnet_<feature>_<timestamp>.md` with YAML frontmatter.

Use `type: implementation` for code tasks, `type: squad` for analysis (see `channel-routing.md` Dispatch Type Selection).

YAML frontmatter required:
```yaml
---
type: implementation
tasks:
  - name: task-name
    signal_file: verification_findings/sonnet_task_done[_chN].md
---
```

Prompt body MUST include: task list with acceptance criteria, file paths, code patterns, field mappings, what NOT to do (Opus-reserved), cross-model dependencies, channel routing (`SENTINEL_CHANNEL=N`).

**Sonnet session rules (include in prompt):** Read CT + shared CT + CLAUDE.md + project-specific rules files first. Do NOT modify files outside task list. Do NOT make design decisions — flag for Opus. Mark completed tasks `[SONNET-DONE]` in CT.

### Step 9: Present for user approval

Show plan (with classification table AND Step 3c dispatch plan including estimated-tokens column), Sonnet prompt, and — if Step 7 ran — the verified external-tool prompt + verification result. The dispatch plan makes the token cost of the proposed /3 run visible BEFORE spawning — the user can say "merge D1 and D2" or "this is fine" with a full picture. Announce `/2` complete.

**If same-session execution:** Do NOT proceed to `/3` until user approves.

**If cross-channel dispatch:** Confirm target CT (`CURRENT_TASK_chN.md`) is written and registered in shared CT. The target session picks up with `/opus N` → reads CT → executes `/3`.
