# Test Script: Skills Migration + Squad Fixes

## Automated Tests
- [ ] `cd modules/sprint-pipeline/tests && python -m pytest test_spawn.py -v` → 50 passed, 4 skipped

## Manual Verification

### Skills
- [ ] Count skill directories: `ls -d modules/*/skills/*/` → 23 directories (22 from commands + configure-context-awareness)
- [ ] All skills have YAML frontmatter: `for f in modules/*/skills/*/SKILL.md; do head -1 "$f"; done` → all show `---`
- [ ] Numeric aliases redirect: `cat modules/sprint-pipeline/skills/1/SKILL.md` → contains "Alias for"
- [ ] Content skills have substance: `wc -l modules/sprint-pipeline/skills/opus/SKILL.md` → 30+ lines

### Install Script
- [ ] Dry run: `bash install.sh --modules "core" --target project --dry-run` → no errors, shows WOULD GENERATE for skills
- [ ] Auto-invoke template listed: grep `plugin-auto-invoke.md` in install.sh rules_templates → found
- [ ] Dependency checker runs: `bash install.sh --modules "core" --target project` → shows "All commands have matching skills"

### Squad Fixes
- [ ] opus.md $ARGUMENTS: grep for `'"$ARGUMENTS"'` quote-break pattern → found
- [ ] spawn.py SSH guard: grep `SSH_CONNECTION` → found in _can_use_tkinter
- [ ] spawn.py non-ASCII: grep `UnicodeEncodeError` → found in type_text
- [ ] channel_commit.sh FILE_ARRAY: grep `FILE_ARRAY=()` → found at line 16
- [ ] sonnet.md global path: grep `~/.claude/scripts` → found in both command and skill

### README
- [ ] "Tested on" section present with 3 platforms
- [ ] Context awareness paragraph mentions "Claude Code itself"
- [ ] Self-test section mentions auto-invoke rules
