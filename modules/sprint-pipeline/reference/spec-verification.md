## Spec-to-Code Verification Rule

**Trigger:** Before claiming any screen, module, feature, or sprint is complete.

Runs during `/5` Step 4. Verifies code implements everything the spec describes (not just that existing code passes tests).

---

### Phase 1: Identify the Authoritative Spec

Find spec section(s) defining "done": relevant spec files, `docs/plans/*.md`, or project planning documents. No spec → flag before proceeding.

#### Phase 2: Extract the Flat Checklist

Read the spec section **in full, start to finish**. Extract every discrete feature, UI element, behavior, data flow, and integration point into a numbered flat list.

**Anti-lost-in-the-middle rules:**

1. **Read in segments of 50 lines max.** After each segment, write down every feature found in that segment before moving to the next. Do NOT read the entire spec and then try to recall — extraction happens DURING reading, not after.

2. **Use the spec's own terms.** Do not paraphrase, summarize, or combine items. "Feature toggle (option A/option B)" is one item. "Settings panel" is a separate item. "Admin-only override" is a separate item. If the spec lists them separately, the checklist lists them separately.

3. **Count structural elements.** After extraction, count: How many UI widgets/controls? How many data flows (save/load/wire)? How many conditional behaviors (role-specific, mode-specific)? These counts become verification targets.

4. **Cross-check against headings.** Re-read ONLY the section headings, subheadings, and bold text in the spec. Does every heading have at least one checklist item? If a heading has zero items, you missed something — re-read that section.

5. **Reverse-scan the last third.** Items in the final third of any document are most likely to be missed. After completing the full extraction, re-read the last 30% of the spec and verify every item appears in your checklist.

6. **Cross-section verb scan.** After extraction, grep for UI verbs (`shows`, `displays`, `renders`, `presents`) in non-UI sections (engine, data, API, model). Each hit is a cross-cutting requirement: the data layer must compute it AND the UI layer must display it. Verify both sides independently. "Engine tracks X" ≠ "UI shows X."

Output: numbered flat list with source file:lines and item count.

### Phase 3: Verify Each Item Against Code

For EACH item, independently verify (grep or Read — not from memory of prior items).

Mark: `[P]` PRESENT (cite file:line), `[M]` MISSING, `[I]` INCOMPLETE (state what's missing).

### Phase 4: Reverse Verify (Code → Spec)

Scan implementation for features NOT in spec. Flag: removed spec items, speculative features, spec gaps.

### Phase 5: Report

Total items, [P]/[M]/[I] counts, code-only count. VERDICT: PASS (all present) or FAIL (N missing). FAIL = not complete — implement or explicitly defer before close-out.

