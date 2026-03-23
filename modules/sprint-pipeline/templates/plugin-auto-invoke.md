## Auto-Invocation Rules

Check triggers BEFORE starting work. Detect and invoke automatically — never ask.

### Trigger Map

| Context | Action |
|---|---|
| New feature / UI change / behavior mod | `superpowers:brainstorming` before implementation |
| Multi-step task with spec | `superpowers:writing-plans` before code |
| Bug / test failure / unexpected behavior | `superpowers:systematic-debugging` before fixes |
| Mid-sprint completion claim | Verification Squad (`/squad`) — 5 agents, hook-enforced |
| Implementing feature/bugfix | `superpowers:test-driven-development` before code |
| Plan with independent tasks | `superpowers:subagent-driven-development` |
| 2+ independent tasks, no shared state | `superpowers:dispatching-parallel-agents` |
| Sprint/feature complete, tests pass | `/finalize` (alias `/5`) |
| Major feature pre-merge | `superpowers:requesting-code-review` |
| Receiving code review feedback | `superpowers:receiving-code-review` |
| Post-implementation quality pass | `/perfect` (alias `/4`) |
| Completed unit of work, before claiming done | `/grill` |
| Subsystem needs ground-up rewrite | `/rewrite` |
| Caught mistake (user, verification, hook) | `/mistake` |
| Session ending or context critically high | `/cold` |
| Launch multiple CC sessions | `/spawn` |
| Quick orientation check | `/status` |

**Priority:** Process skills first (brainstorming, debugging, writing-plans), then implementation (TDD, subagent-driven-development).

### Sonnet Delegation

Opus orchestrates, Sonnet executes. Delegate mechanical work (lint, search, test patterns, enum/schema validation, templates) via `verification_findings/_pending/`. 2+ independent -> parallel agents (`run_in_background: true`).

### Do NOT auto-invoke

`superpowers:writing-skills` (explicit only), `superpowers:using-superpowers` (this file replaces it), `/cleanup` (manual end-of-session only).
