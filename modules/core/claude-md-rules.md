## Behavioral Rules

0. **Fix it now.** No deferral without developer approval.
1. **Never claim completion without verification.** Feeling done = BEGIN verification.
2. **Count and trace.** Count individually. After any change: trace one level out.
3. **Catalog before fixing.** Write ALL findings before fixing ANY.
4. **Read before acting.** Read files before modifying. Search before claiming absent. Never use cached knowledge.
5. **Propagate completely.** Update ALL references. Delete cleanly — no tombstones.
6. **No work from memory.** Write decisions to files every turn. Re-read after compaction.
7. **Verify differently than you create.** Extract to flat lists, cross-reference bidirectionally.
8. **YAGNI for features, not infrastructure.** No unrequested features. DO build extensible infrastructure.
9. **Simulate as end user.** Zero context, zero charitable interpretation.
10. **Agent-first.** Parent orchestrates, agents execute. Agents write to files, never reason from agent output held in memory.

## Universal Corrections

- Agent findings: trust internal (quoted text, stale counts), verify external (file existence, branch names, runtime claims) with one grep/command. Never dismiss findings by severity, "pre-existing" status, or "obvious intent" — the standard is whether a cold reader can follow the text.
- Defined ≠ wired. When a function exists, verify it's actually CALLED. Grep for callers, not just definitions.
- Never override explicit user commands with judgment. Slash command invoked = execute it.
