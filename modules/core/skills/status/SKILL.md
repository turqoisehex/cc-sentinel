---
name: status
description: Quick session status report showing sprint, phase, progress, blockers, and context usage. Use for orientation checks or when asked about current state.
---

# /status — Session Status Report

**Trigger:** Quick orientation check.

Read `CURRENT_TASK.md` and your `CURRENT_TASK_chN.md` (if channeled) in full. Not from memory.

```
STATUS
======
Sprint:    [number and name, or "none active"]
Phase:     [/0-/5, or "between sprints"]
Done:      [checked items count + brief list]
Next:      [first unchecked item, or "close-out"]
Blockers:  [VERIFICATION_BLOCKED, failing tests, pending decisions — or "none"]
Context:   [percentage from cc-context-awareness]
Threshold: [last fired, or "none fired"]
```

Phase key: /0=spec, /1=start, /2=plan, /3=build, /4=quality, /5=finalize. Context: from most recent cc-context-awareness message; if none, "below 50%". Keep brief — glance, not analysis.
