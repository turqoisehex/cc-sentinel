# Opus Listener Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable Opus sessions to receive prompt files via `_pending_opus/chN/`, parallel to the existing Sonnet listener, by renaming `_pending/` → `_pending_sonnet/`, adding a `--model` flag to `wait_for_work.sh`, implementing `.active` signal files, and expanding the liveness check to 7 states.

**Architecture:** All changes are in the cc-sentinel repo (`D:\Documents\LLM\cc-sentinel`). The core change is making `wait_for_work.sh` model-aware (opus vs sonnet) with a `--model` flag that selects the pending directory. A new `.active` signal file proves the listener is processing (not just alive), enabling a 7-state liveness model in `channel_commit.sh`. The `_pending/` → `_pending_sonnet/` rename is a coordinated atomic change across 33 files (101 occurrences). Wakeful propagation follows separately.

**Tech Stack:** Bash (shell scripts), Python (spawn.py), PowerShell (install.ps1)

**Spec:** `docs/specs/2026-03-23-opus-listener-design.md` (v1.5)

---

## File Structure

**Modified (functional scripts — 8 files):**
- `modules/commit-enforcement/scripts/wait_for_work.sh` — add `--model` flag, oldest-first, `.active` write
- `modules/commit-enforcement/scripts/channel_commit.sh` — path rename, threshold changes, 7-state liveness
- `modules/commit-enforcement/hooks/safe-commit.sh` — path rename at line 75
- `modules/core/hooks/session-orient.sh` — clean both dirs, `.active` cleanup
- `modules/verification/hooks/stop-task-check.sh` — regex update for opus variant
- `modules/sprint-pipeline/tools/spawn.py` — template string rename, mkdir both dirs
- `install.sh` — mkdir both dirs
- `install.ps1` — mkdir both dirs

**Modified (command/skill docs — 21 files):**
- `modules/sprint-pipeline/commands/opus.md` + `skills/opus/SKILL.md` — rewrite for listener startup
- `modules/sprint-pipeline/commands/sonnet.md` + `skills/sonnet/SKILL.md` — dir rename, `--model sonnet`
- 17 remaining doc files — mechanical `_pending/` → `_pending_sonnet/` string replacement

**Modified (test files — 4 files):**
- `modules/commit-enforcement/tests/test_safe_commit.sh` — fixture path updates
- `modules/commit-enforcement/tests/test_channel_commit.sh` — fixture + liveness tests
- `modules/core/tests/test_session_orient.sh` — dual-dir + `.active` cleanup tests
- `modules/verification/tests/test_stop_task_check.sh` — fixture update + opus variant test

**Created (test file — 1 file):**
- `modules/commit-enforcement/tests/test_wait_for_work.sh` — `--model` flag, oldest-first, `.active` write/overwrite

---

### Task 1: Global `_pending/` → `_pending_sonnet/` rename

The foundation rename. All 33 files, 101 occurrences. Mechanical find-and-replace. Existing tests updated so they pass with new paths.

**Files:**
- Modify: all 33 files listed in spec Migration section (lines 231–268)
- Test: all 4 existing test files

- [ ] **Step 1: Run rename across all source files**

```bash
cd "D:\Documents\LLM\cc-sentinel"

# Functional scripts (8 files)
for f in \
  modules/commit-enforcement/scripts/wait_for_work.sh \
  modules/commit-enforcement/scripts/channel_commit.sh \
  modules/commit-enforcement/hooks/safe-commit.sh \
  modules/core/hooks/session-orient.sh \
  modules/verification/hooks/stop-task-check.sh \
  modules/sprint-pipeline/tools/spawn.py \
  install.sh install.ps1; do
  sed -i 's|_pending/|_pending_sonnet/|g' "$f"
  sed -i 's|_pending"|_pending_sonnet"|g' "$f"
done

# Doc files (21 files)
for f in \
  modules/sprint-pipeline/commands/sonnet.md \
  modules/sprint-pipeline/skills/sonnet/SKILL.md \
  modules/sprint-pipeline/commands/opus.md \
  modules/sprint-pipeline/skills/opus/SKILL.md \
  modules/sprint-pipeline/commands/build.md \
  modules/sprint-pipeline/skills/build/SKILL.md \
  modules/sprint-pipeline/commands/design.md \
  modules/sprint-pipeline/skills/design/SKILL.md \
  modules/sprint-pipeline/commands/finalize.md \
  modules/sprint-pipeline/skills/finalize/SKILL.md \
  modules/sprint-pipeline/commands/perfect.md \
  modules/sprint-pipeline/skills/perfect/SKILL.md \
  modules/sprint-pipeline/commands/audit.md \
  modules/sprint-pipeline/skills/audit/SKILL.md \
  modules/sprint-pipeline/templates/plugin-auto-invoke.md \
  modules/core/commands/cold.md \
  modules/core/skills/cold/SKILL.md \
  modules/core/commands/cleanup.md \
  modules/core/skills/cleanup/SKILL.md \
  modules/core/reference/operator-cheat-sheet.md \
  modules/commit-enforcement/reference/channel-routing.md; do
  sed -i 's|_pending/|_pending_sonnet/|g' "$f"
done

# Test files (4 files)
for f in \
  modules/commit-enforcement/tests/test_safe_commit.sh \
  modules/commit-enforcement/tests/test_channel_commit.sh \
  modules/core/tests/test_session_orient.sh \
  modules/verification/tests/test_stop_task_check.sh; do
  sed -i 's|_pending/|_pending_sonnet/|g' "$f"
  sed -i 's|_pending"|_pending_sonnet"|g' "$f"
done
```

- [ ] **Step 2: Verify occurrence count**

```bash
cd "D:\Documents\LLM\cc-sentinel"
# Should return 0 — no remaining _pending/ (without _sonnet or _opus suffix)
grep -rn '"_pending/' --include="*.sh" --include="*.py" --include="*.ps1" --include="*.md" \
  modules/ install.sh install.ps1 | grep -v '_pending_sonnet' | grep -v '_pending_opus' | grep -v 'docs/specs/' | wc -l
```

Expected: `0`

- [ ] **Step 3: Run all existing tests**

```bash
cd "D:\Documents\LLM\cc-sentinel"
bash modules/commit-enforcement/tests/test_safe_commit.sh
bash modules/commit-enforcement/tests/test_channel_commit.sh
bash modules/core/tests/test_session_orient.sh
bash modules/verification/tests/test_stop_task_check.sh
```

Expected: All tests pass. The rename is mechanical — tests use the same string pattern in fixtures and assertions.

**Important:** `test_stop_task_check.sh` Test 8 fixture says `"Watching _pending/"`. After this rename it becomes `"Watching _pending_sonnet/"`. The hook's grep pattern (line 100) also becomes `"Watching _pending_sonnet/"`. Test 8 should still pass because fixture matches pattern. The opus variant test is added in Task 5.

- [ ] **Step 4: Commit**

```bash
cd "D:\Documents\LLM\cc-sentinel"
git add -A
git commit -m "refactor: rename _pending/ → _pending_sonnet/ (101 occurrences, 33 files)"
```

---

### Task 2: `wait_for_work.sh` — `--model` flag, oldest-first, `.active` signal

Core behavioral change. The script becomes model-aware and writes `.active` before returning.

**Files:**
- Modify: `modules/commit-enforcement/scripts/wait_for_work.sh`
- Create: `modules/commit-enforcement/tests/test_wait_for_work.sh`

- [ ] **Step 1: Write the test file**

```bash
cat > modules/commit-enforcement/tests/test_wait_for_work.sh << 'TESTEOF'
#!/usr/bin/env bash
# Test harness for wait_for_work.sh
# Run: bash modules/commit-enforcement/tests/test_wait_for_work.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WAIT_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/scripts/wait_for_work.sh"

[[ ! -f "$WAIT_SCRIPT" ]] && echo "ERROR: wait_for_work.sh not found at $WAIT_SCRIPT" >&2 && exit 1

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
[[ ! -t 1 ]] && RED="" && GREEN="" && NC=""

setup() {
  TMPDIR_ROOT=$(mktemp -d)
  PROJECT="$TMPDIR_ROOT/project"
  mkdir -p "$PROJECT"
  cd "$PROJECT"
}

teardown() {
  cd /
  # Kill any leftover heartbeat processes from tests
  [[ -f "$PROJECT/verification_findings/_pending_sonnet/.heartbeat_pid" ]] && \
    kill "$(cat "$PROJECT/verification_findings/_pending_sonnet/.heartbeat_pid")" 2>/dev/null
  [[ -f "$PROJECT/verification_findings/_pending_opus/.heartbeat_pid" ]] && \
    kill "$(cat "$PROJECT/verification_findings/_pending_opus/.heartbeat_pid")" 2>/dev/null
  for d in "$PROJECT"/verification_findings/_pending_*/ch*; do
    [[ -f "$d/.heartbeat_pid" ]] && kill "$(cat "$d/.heartbeat_pid")" 2>/dev/null
  done
  rm -rf "$TMPDIR_ROOT" 2>/dev/null
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" == "$expected" ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local file="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -f "$file" ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — file not found: $file"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_contains() {
  local file="$1" pattern="$2" label="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — '$pattern' not found in $file"
    [[ -f "$file" ]] && echo "    contents: $(cat "$file")"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== wait_for_work.sh Test Harness ==="
echo ""

# --- Test 1: --model sonnet uses _pending_sonnet/ ---
echo "Test 1: --model sonnet selects _pending_sonnet/"
setup
mkdir -p verification_findings/_pending_sonnet
echo "test prompt" > verification_findings/_pending_sonnet/task.md
RESULT=$(timeout 10 bash "$WAIT_SCRIPT" --model sonnet 2>/dev/null)
assert_eq "verification_findings/_pending_sonnet/task.md" "$RESULT" "returns sonnet pending path"
teardown

# --- Test 2: --model opus uses _pending_opus/ ---
echo ""
echo "Test 2: --model opus selects _pending_opus/"
setup
mkdir -p verification_findings/_pending_opus
echo "opus prompt" > verification_findings/_pending_opus/opus_task.md
RESULT=$(timeout 10 bash "$WAIT_SCRIPT" --model opus 2>/dev/null)
assert_eq "verification_findings/_pending_opus/opus_task.md" "$RESULT" "returns opus pending path"
teardown

# --- Test 3: --model with --channel ---
echo ""
echo "Test 3: --model opus --channel 2 uses _pending_opus/ch2/"
setup
mkdir -p verification_findings/_pending_opus/ch2
echo "ch2 work" > verification_findings/_pending_opus/ch2/work.md
RESULT=$(timeout 10 bash "$WAIT_SCRIPT" --model opus --channel 2 2>/dev/null)
assert_eq "verification_findings/_pending_opus/ch2/work.md" "$RESULT" "returns channeled opus path"
teardown

# --- Test 4: Unknown --model value exits with error ---
echo ""
echo "Test 4: Unknown --model value -> error exit"
setup
RESULT=$(timeout 10 bash "$WAIT_SCRIPT" --model badvalue 2>&1)
LAST_EXIT=$?
TOTAL=$((TOTAL + 1))
if [[ $LAST_EXIT -ne 0 ]]; then
  echo -e "  ${GREEN}PASS${NC}: exits non-zero for unknown model"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: should exit non-zero for unknown model (got $LAST_EXIT)"
  FAIL=$((FAIL + 1))
fi
teardown

# --- Test 5: Default model is sonnet ---
echo ""
echo "Test 5: No --model flag defaults to sonnet"
setup
mkdir -p verification_findings/_pending_sonnet
echo "default" > verification_findings/_pending_sonnet/default.md
RESULT=$(timeout 10 bash "$WAIT_SCRIPT" 2>/dev/null)
assert_eq "verification_findings/_pending_sonnet/default.md" "$RESULT" "defaults to _pending_sonnet"
teardown

# --- Test 6: Oldest-first ordering ---
echo ""
echo "Test 6: Returns oldest file first (by mtime)"
setup
mkdir -p verification_findings/_pending_sonnet
echo "newer" > verification_findings/_pending_sonnet/newer.md
sleep 1
echo "oldest" > verification_findings/_pending_sonnet/oldest.md
# Touch oldest to be older
OLDEST_WIN=$(cygpath -w "verification_findings/_pending_sonnet/oldest.md" 2>/dev/null || echo "verification_findings/_pending_sonnet/oldest.md")
python -c "import os, time; os.utime(r'$OLDEST_WIN', (time.time()-60, time.time()-60))" 2>/dev/null || \
  python3 -c "import os, time; os.utime(r'$OLDEST_WIN', (time.time()-60, time.time()-60))" 2>/dev/null || \
  touch -d "1 minute ago" "verification_findings/_pending_sonnet/oldest.md" 2>/dev/null
RESULT=$(timeout 10 bash "$WAIT_SCRIPT" --model sonnet 2>/dev/null)
assert_eq "verification_findings/_pending_sonnet/oldest.md" "$RESULT" "oldest file returned first"
teardown

# --- Test 7: .active file written before return ---
echo ""
echo "Test 7: .active signal file written with timestamp + filename"
setup
mkdir -p verification_findings/_pending_sonnet
echo "work" > verification_findings/_pending_sonnet/squad_prompt.md
RESULT=$(timeout 10 bash "$WAIT_SCRIPT" --model sonnet 2>/dev/null)
ACTIVE_FILE="verification_findings/_pending_sonnet/.active"
assert_file_exists "$ACTIVE_FILE" ".active file created"
assert_file_contains "$ACTIVE_FILE" "processing squad_prompt.md" ".active contains filename"
assert_file_contains "$ACTIVE_FILE" "^[0-9]{4}-[0-9]{2}-[0-9]{2}T" ".active contains ISO timestamp"
teardown

# --- Test 8: .active overwrite when pre-existing ---
echo ""
echo "Test 8: .active silently overwritten when pre-existing"
setup
mkdir -p verification_findings/_pending_sonnet
echo "2026-01-01T00:00:00Z processing old_stale.md" > verification_findings/_pending_sonnet/.active
echo "new work" > verification_findings/_pending_sonnet/new_prompt.md
RESULT=$(timeout 10 bash "$WAIT_SCRIPT" --model sonnet 2>/dev/null)
ACTIVE_FILE="verification_findings/_pending_sonnet/.active"
assert_file_contains "$ACTIVE_FILE" "processing new_prompt.md" ".active overwritten with new filename"
TOTAL=$((TOTAL + 1))
if ! grep -q "old_stale" "$ACTIVE_FILE" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC}: old .active content replaced"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: old .active content still present"
  FAIL=$((FAIL + 1))
fi
teardown

# ==================== SUMMARY ====================
echo ""
echo "========================================="
echo "  RESULTS: $PASS passed, $FAIL failed ($TOTAL total)"
echo "========================================="
[[ $FAIL -gt 0 ]] && exit 1
echo "All tests passed."
exit 0
TESTEOF
chmod +x modules/commit-enforcement/tests/test_wait_for_work.sh
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd "D:\Documents\LLM\cc-sentinel"
bash modules/commit-enforcement/tests/test_wait_for_work.sh
```

Expected: Tests 2, 3, 4, 6, 7, 8 fail (no --model opus support, no oldest-first, no .active write). Tests 1, 5 may pass since default is sonnet and Task 1 already renamed the path.

- [ ] **Step 3: Implement wait_for_work.sh changes**

Replace the full file content of `modules/commit-enforcement/scripts/wait_for_work.sh`:

```bash
#!/usr/bin/env bash
set -u
# Blocks INDEFINITELY until a .md file appears in the model-specific pending dir.
# Returns the filename on stdout (oldest-first by mtime). Writes .active signal
# before returning so observers know what's being processed.
#
# Heartbeat continues in background after work is found so channel_commit.sh
# never sees a stale heartbeat during processing.
#
# The background heartbeat self-terminates when the parent shell exits via
# PPID polling.
#
# Usage: bash scripts/wait_for_work.sh --model opus|sonnet [--channel N]
CHANNEL=""
MODEL="sonnet"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="$2"; shift 2 ;;
    --model)   MODEL="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Validate model
case "$MODEL" in
  opus|sonnet) ;;
  *) echo "ERROR: --model must be 'opus' or 'sonnet', got '$MODEL'" >&2; exit 1 ;;
esac

if [[ -n "$CHANNEL" ]]; then
  PENDING_DIR="verification_findings/_pending_${MODEL}/ch${CHANNEL}"
else
  PENDING_DIR="verification_findings/_pending_${MODEL}"
fi

mkdir -p "$PENDING_DIR"
HEARTBEAT_FILE="$PENDING_DIR/.heartbeat"
HEARTBEAT_PID_FILE="$PENDING_DIR/.heartbeat_pid"
LISTENER_PID=$PPID

# Kill any prior stale heartbeat process
if [[ -f "$HEARTBEAT_PID_FILE" ]]; then
  OLD_PID=$(cat "$HEARTBEAT_PID_FILE" 2>/dev/null)
  kill "$OLD_PID" 2>/dev/null || true
  rm -f "$HEARTBEAT_PID_FILE"
fi

# Start background heartbeat — survives after this script exits.
# Self-terminates when parent shell is gone.
_heartbeat_loop() {
  while true; do
    if ! kill -0 "$LISTENER_PID" 2>/dev/null; then
      rm -f "$HEARTBEAT_FILE" "$HEARTBEAT_PID_FILE"
      exit 0
    fi
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$HEARTBEAT_FILE" 2>/dev/null
    sleep 3
  done
}
_heartbeat_loop &
echo $! > "$HEARTBEAT_PID_FILE"

# Poll for work — oldest-first by mtime
while true; do
  OLDEST=$(ls -tr "$PENDING_DIR"/*.md 2>/dev/null | head -1)
  if [[ -n "$OLDEST" ]] && [[ -f "$OLDEST" ]]; then
    # Write .active signal before returning
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") processing $(basename "$OLDEST")" > "$PENDING_DIR/.active"
    echo "$OLDEST"
    exit 0
  fi
  sleep 3
done
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd "D:\Documents\LLM\cc-sentinel"
bash modules/commit-enforcement/tests/test_wait_for_work.sh
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
cd "D:\Documents\LLM\cc-sentinel"
git add modules/commit-enforcement/scripts/wait_for_work.sh modules/commit-enforcement/tests/test_wait_for_work.sh
git commit -m "feat: wait_for_work.sh — --model flag, oldest-first, .active signal"
```

---

### Task 3: `channel_commit.sh` — 7-state liveness check

Expand `check_heartbeat()` from 2 states (fresh/stale) to 7 states matching the Liveness States table. Update thresholds: warn 30→300s, switch-to-local 300→900s.

**Files:**
- Modify: `modules/commit-enforcement/scripts/channel_commit.sh`
- Modify: `modules/commit-enforcement/tests/test_channel_commit.sh`

- [ ] **Step 1: Add liveness test cases to test_channel_commit.sh**

Append before the SUMMARY section of `test_channel_commit.sh`. These tests exercise `check_heartbeat()` indirectly through the main flow — a stale/missing heartbeat causes LOCAL_VERIFY fallback, which we detect via stderr messages.

```bash
# --- Liveness Test: Fresh heartbeat + no .active -> dispatch normally ---
echo ""
echo "Liveness 1: Fresh heartbeat + no .active -> dispatch"
setup_repo
create_test_file "scripts/code.sh"
create_heartbeat "verification_findings/_pending_sonnet"
run_commit --files "scripts/code.sh" -m "liveness fresh idle"
assert_exit 0 "commits successfully (dispatch path)"
teardown_repo

# --- Liveness Test: Fresh + .active present -> dispatch normally ---
echo ""
echo "Liveness 2: Fresh heartbeat + .active -> dispatch (queued)"
setup_repo
create_test_file "scripts/code.sh"
create_heartbeat "verification_findings/_pending_sonnet"
echo "2026-03-23T20:00:00Z processing current_task.md" > verification_findings/_pending_sonnet/.active
run_commit --files "scripts/code.sh" -m "liveness fresh active"
assert_exit 0 "commits via dispatch (prompt queued for next cycle)"
assert_stderr_contains "(alive|processing|current_task)" "logs .active contents"
teardown_repo

# --- Liveness Test: Warn-stale + no .active -> dispatch normally with warning ---
echo ""
echo "Liveness 3: Warn-stale heartbeat + no .active -> warn + dispatch"
setup_repo
create_test_file "scripts/code.sh"
mkdir -p verification_findings/_pending_sonnet
touch verification_findings/_pending_sonnet/.heartbeat
HB_FILE="verification_findings/_pending_sonnet/.heartbeat"
HB_WIN=$(cygpath -w "$HB_FILE" 2>/dev/null || echo "$HB_FILE")
python -c "import os, time; os.utime(r'$HB_WIN', (time.time()-600, time.time()-600))" 2>/dev/null || \
  python3 -c "import os, time; os.utime(r'$HB_WIN', (time.time()-600, time.time()-600))" 2>/dev/null || \
  touch -d "10 minutes ago" "$HB_FILE" 2>/dev/null
run_commit --files "scripts/code.sh" -m "liveness warn-stale idle"
assert_exit 0 "commits via dispatch (not local fallback)"
assert_stderr_contains "(slow|stalled)" "warns about slow listener"
teardown_repo

# --- Liveness Test: Warn-stale + .active -> dispatch normally ---
echo ""
echo "Liveness 4: Warn-stale heartbeat + .active -> dispatch normally"
setup_repo
create_test_file "scripts/code.sh"
mkdir -p verification_findings/_pending_sonnet
touch verification_findings/_pending_sonnet/.heartbeat
echo "2026-03-23T20:00:00Z processing big_task.md" > verification_findings/_pending_sonnet/.active
HB_FILE="verification_findings/_pending_sonnet/.heartbeat"
HB_WIN=$(cygpath -w "$HB_FILE" 2>/dev/null || echo "$HB_FILE")
python -c "import os, time; os.utime(r'$HB_WIN', (time.time()-600, time.time()-600))" 2>/dev/null || \
  python3 -c "import os, time; os.utime(r'$HB_WIN', (time.time()-600, time.time()-600))" 2>/dev/null || \
  touch -d "10 minutes ago" "$HB_FILE" 2>/dev/null
run_commit --files "scripts/code.sh" -m "liveness warn-stale busy"
assert_exit 0 "commits via dispatch (not local fallback)"
assert_stderr_contains "(busy|long task|big_task)" "mentions .active contents"
teardown_repo

# --- Liveness Test: Stale + .active present -> local fallback + mentions stuck ---
echo ""
echo "Liveness 5: Stale heartbeat + .active -> dispatch + local fallback"
setup_repo
create_test_file "scripts/code.sh"
mkdir -p verification_findings/_pending_sonnet
touch verification_findings/_pending_sonnet/.heartbeat
echo "2026-03-23T20:00:00Z processing slow_task.md" > verification_findings/_pending_sonnet/.active
HB_FILE="verification_findings/_pending_sonnet/.heartbeat"
HB_WIN=$(cygpath -w "$HB_FILE" 2>/dev/null || echo "$HB_FILE")
python -c "import os, time; os.utime(r'$HB_WIN', (time.time()-1200, time.time()-1200))" 2>/dev/null || \
  python3 -c "import os, time; os.utime(r'$HB_WIN', (time.time()-1200, time.time()-1200))" 2>/dev/null || \
  touch -d "20 minutes ago" "$HB_FILE" 2>/dev/null
# No --local-verify: let check_heartbeat trigger the fallback itself
run_commit --files "scripts/code.sh" -m "liveness stuck"
assert_stderr_contains "(may be stuck|slow_task)" "mentions stuck + active file"
assert_stderr_contains "(local|fallback|optimistic)" "falls back to local"
teardown_repo

# --- Liveness Test: Stale + no .active -> local fallback ---
echo ""
echo "Liveness 6: Stale heartbeat + no .active -> local"
setup_repo
create_test_file "scripts/code.sh"
mkdir -p verification_findings/_pending_sonnet
touch verification_findings/_pending_sonnet/.heartbeat
HB_FILE="verification_findings/_pending_sonnet/.heartbeat"
HB_WIN=$(cygpath -w "$HB_FILE" 2>/dev/null || echo "$HB_FILE")
python -c "import os, time; os.utime(r'$HB_WIN', (time.time()-1200, time.time()-1200))" 2>/dev/null || \
  python3 -c "import os, time; os.utime(r'$HB_WIN', (time.time()-1200, time.time()-1200))" 2>/dev/null || \
  touch -d "20 minutes ago" "$HB_FILE" 2>/dev/null
# No --local-verify: let check_heartbeat trigger the fallback itself
run_commit --files "scripts/code.sh" -m "liveness stale down"
assert_stderr_contains "(likely down|switching to local)" "warns stale/down"
teardown_repo

# --- Liveness Test: Missing heartbeat -> local fallback ---
echo ""
echo "Liveness 7: Missing heartbeat -> local"
setup_repo
create_test_file "scripts/code.sh"
# No heartbeat file created — should fall back to local
# No --local-verify: let check_heartbeat trigger the fallback itself
run_commit --files "scripts/code.sh" -m "liveness missing"
assert_stderr_contains "No listener heartbeat" "warns about missing heartbeat"
teardown_repo
```

- [ ] **Step 2: Run new liveness tests to verify they fail**

```bash
cd "D:\Documents\LLM\cc-sentinel"
bash modules/commit-enforcement/tests/test_channel_commit.sh
```

Expected: New liveness tests fail (current check_heartbeat doesn't handle .active or 7 states).

- [ ] **Step 3: Implement check_heartbeat rewrite**

In `channel_commit.sh`, replace the `check_heartbeat()` function (lines 192–212) with:

```bash
# --- Heartbeat + Liveness Check ---
# Returns 0 = dispatch normally, 1 = switch to local, 2 = dispatch + local fallback.
# Matches the 7-state Liveness States table in the opus-listener spec.
OPTIMISTIC_DISPATCH="false"

check_heartbeat() {
  local hb_file="${PENDING_DIR}/.heartbeat"
  local active_file="${PENDING_DIR}/.active"

  # State: Missing heartbeat (any .active state) → not started or crashed
  if [[ ! -f "$hb_file" ]]; then
    echo "WARNING: No listener heartbeat detected — switching to local verification." >&2
    echo "  Start /sonnet in a second terminal for full per-commit verification." >&2
    return 1
  fi

  local now hb_time age active_info=""
  now=$(date +%s)
  hb_time=$(stat -c %Y "$hb_file" 2>/dev/null || stat -f %m "$hb_file" 2>/dev/null || echo 0)
  age=$((now - hb_time))
  [[ -f "$active_file" ]] && active_info=$(cat "$active_file" 2>/dev/null)

  if (( age > 900 )); then
    # Stale heartbeat (>15 min)
    if [[ -n "$active_info" ]]; then
      echo "WARNING: Listener may be stuck (heartbeat ${age}s, active: $active_info) — dispatching + local fallback." >&2
      OPTIMISTIC_DISPATCH="true"
      return 1
    else
      echo "WARNING: Listener likely down (heartbeat ${age}s) — switching to local verification." >&2
      return 1
    fi
  elif (( age > 300 )); then
    # Warn-stale heartbeat (5–15 min)
    if [[ -n "$active_info" ]]; then
      echo "Listener busy on long task (heartbeat ${age}s, active: $active_info)." >&2
    else
      echo "WARNING: Listener slow or briefly stalled (heartbeat ${age}s)." >&2
    fi
    return 0
  else
    # Fresh heartbeat (<5 min)
    if [[ -n "$active_info" ]]; then
      echo "Listener alive, processing: $active_info" >&2
    fi
    return 0
  fi
}
```

Then update the main flow where `check_heartbeat` is called (around line 225) to handle optimistic dispatch:

```bash
  if [[ "$LOCAL_VERIFY" != "true" ]]; then
    if ! check_heartbeat; then
      if [[ "$OPTIMISTIC_DISPATCH" == "true" ]]; then
        # Listener may recover — write dispatch file optimistically
        mkdir -p "$PENDING_DIR"
        rm -f "${PENDING_DIR}"/verify_*.md 2>/dev/null || true
        cat > "${PENDING_DIR}/verify_${HASH}.md" << OPT_EOF
---
type: commit-verification
diff_path: ${DIFF_FILE}
agents:
  - name: commit-adversarial
    output_path: ${CHECK_FILE}
  - name: commit-cold-reader
    output_path: ${COLD_READ_FILE}
---
## Commit Verification (optimistic — listener may be stuck)
Hash: ${HASH}
Message: ${MESSAGE}
Files: ${FILE_ARRAY[*]}
OPT_EOF
        echo "Optimistic dispatch written — proceeding with local verification" >&2
      fi
      LOCAL_VERIFY="true"
    fi
  fi
```

- [ ] **Step 4: Run all channel_commit tests**

```bash
cd "D:\Documents\LLM\cc-sentinel"
bash modules/commit-enforcement/tests/test_channel_commit.sh
```

Expected: All tests pass (existing + new liveness tests).

- [ ] **Step 5: Commit**

```bash
cd "D:\Documents\LLM\cc-sentinel"
git add modules/commit-enforcement/scripts/channel_commit.sh modules/commit-enforcement/tests/test_channel_commit.sh
git commit -m "feat: channel_commit.sh — 7-state liveness check with .active support"
```

---

### Task 4: `session-orient.sh` — dual-dir cleanup + `.active` cleanup

Clean both `_pending_sonnet/` and `_pending_opus/` (and their `ch*/` subdirs). Add `.active` stale cleanup (>30 min).

**Files:**
- Modify: `modules/core/hooks/session-orient.sh`
- Modify: `modules/core/tests/test_session_orient.sh`

- [ ] **Step 1: Add new test cases**

Append before the SUMMARY section of `test_session_orient.sh`:

```bash
# --- Test 12: Stale pending cleanup in _pending_opus/ ---
echo ""
echo "Test 12: Stale pending files cleaned from _pending_opus/"
setup_temp
create_ct "$PROJECT" "IN PROGRESS"
mkdir -p "$PROJECT/verification_findings/_pending_opus"
STALE_FILE="$PROJECT/verification_findings/_pending_opus/stale_opus.md"
echo "old opus work" > "$STALE_FILE"
STALE_WIN=$(cygpath -w "$STALE_FILE" 2>/dev/null || echo "$STALE_FILE")
python -c "import os, time; os.utime(r'$STALE_WIN', (time.time()-7200, time.time()-7200))" 2>/dev/null || \
  python3 -c "import os, time; os.utime(r'$STALE_WIN', (time.time()-7200, time.time()-7200))" 2>/dev/null || \
  touch -d "2 hours ago" "$STALE_FILE" 2>/dev/null
INPUT=$(build_input "$PROJECT")
run_hook "$INPUT"
assert_exit 0 "exit 0"
TOTAL=$((TOTAL + 1))
if [[ ! -f "$STALE_FILE" ]]; then
  echo -e "  ${GREEN}PASS${NC}: stale opus pending file was cleaned up"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: stale opus pending file still exists"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test 13: Stale .active cleanup in _pending_sonnet/ ---
echo ""
echo "Test 13: Stale .active file cleaned from _pending_sonnet/"
setup_temp
create_ct "$PROJECT" "IN PROGRESS"
mkdir -p "$PROJECT/verification_findings/_pending_sonnet/ch1"
ACTIVE_FILE="$PROJECT/verification_findings/_pending_sonnet/ch1/.active"
echo "2026-01-01T00:00:00Z processing old.md" > "$ACTIVE_FILE"
ACTIVE_WIN=$(cygpath -w "$ACTIVE_FILE" 2>/dev/null || echo "$ACTIVE_FILE")
python -c "import os, time; os.utime(r'$ACTIVE_WIN', (time.time()-3600, time.time()-3600))" 2>/dev/null || \
  python3 -c "import os, time; os.utime(r'$ACTIVE_WIN', (time.time()-3600, time.time()-3600))" 2>/dev/null || \
  touch -d "1 hour ago" "$ACTIVE_FILE" 2>/dev/null
INPUT=$(build_input "$PROJECT")
run_hook "$INPUT"
assert_exit 0 "exit 0"
TOTAL=$((TOTAL + 1))
if [[ ! -f "$ACTIVE_FILE" ]]; then
  echo -e "  ${GREEN}PASS${NC}: stale .active file was cleaned up"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: stale .active file still exists"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test 14: Stale .active cleanup in _pending_opus/ ---
echo ""
echo "Test 14: Stale .active file cleaned from _pending_opus/ch2"
setup_temp
create_ct "$PROJECT" "IN PROGRESS"
mkdir -p "$PROJECT/verification_findings/_pending_opus/ch2"
ACTIVE_FILE="$PROJECT/verification_findings/_pending_opus/ch2/.active"
echo "2026-01-01T00:00:00Z processing crashed.md" > "$ACTIVE_FILE"
ACTIVE_WIN=$(cygpath -w "$ACTIVE_FILE" 2>/dev/null || echo "$ACTIVE_FILE")
python -c "import os, time; os.utime(r'$ACTIVE_WIN', (time.time()-3600, time.time()-3600))" 2>/dev/null || \
  python3 -c "import os, time; os.utime(r'$ACTIVE_WIN', (time.time()-3600, time.time()-3600))" 2>/dev/null || \
  touch -d "1 hour ago" "$ACTIVE_FILE" 2>/dev/null
INPUT=$(build_input "$PROJECT")
run_hook "$INPUT"
assert_exit 0 "exit 0"
TOTAL=$((TOTAL + 1))
if [[ ! -f "$ACTIVE_FILE" ]]; then
  echo -e "  ${GREEN}PASS${NC}: stale opus .active file was cleaned up"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: stale opus .active file still exists"
  FAIL=$((FAIL + 1))
fi
teardown_temp
```

- [ ] **Step 2: Run tests to verify new ones fail**

```bash
cd "D:\Documents\LLM\cc-sentinel"
bash modules/core/tests/test_session_orient.sh
```

Expected: Tests 12–14 fail (session-orient.sh doesn't know about `_pending_opus/` or `.active` cleanup yet).

- [ ] **Step 3: Implement session-orient.sh changes**

Replace the stale-cleanup section (lines 23–30) with:

```bash
# Clean stale prompt files from _pending_sonnet/ and _pending_opus/ (older than 1 hour)
for pending_base in "_pending_sonnet" "_pending_opus"; do
  PENDING_PATH="$PROJECT_DIR/verification_findings/$pending_base"
  if [[ -d "$PENDING_PATH" ]]; then
    find "$PENDING_PATH/" -name "*.md" -mmin +60 -delete 2>/dev/null
    # Clean stale .active files (older than 30 minutes — crashed session)
    find "$PENDING_PATH/" -name ".active" -mmin +30 -delete 2>/dev/null
  fi
  # Also clean channeled subdirectories
  for chdir in "$PENDING_PATH"/ch*/; do
    if [[ -d "$chdir" ]]; then
      find "$chdir" -name "*.md" -mmin +60 -delete 2>/dev/null
      find "$chdir" -name ".active" -mmin +30 -delete 2>/dev/null
    fi
  done
done
```

- [ ] **Step 4: Run tests to verify all pass**

```bash
cd "D:\Documents\LLM\cc-sentinel"
bash modules/core/tests/test_session_orient.sh
```

Expected: All 14 tests pass.

- [ ] **Step 5: Commit**

```bash
cd "D:\Documents\LLM\cc-sentinel"
git add modules/core/hooks/session-orient.sh modules/core/tests/test_session_orient.sh
git commit -m "feat: session-orient.sh — dual-dir cleanup + .active stale removal"
```

---

### Task 5: `stop-task-check.sh` — regex update + opus listener test

Update the listener bypass pattern to match both `_pending_sonnet/` and `_pending_opus/`.

**Files:**
- Modify: `modules/verification/hooks/stop-task-check.sh` (line 100)
- Modify: `modules/verification/tests/test_stop_task_check.sh` (Test 8 fixture + new test)

- [ ] **Step 1: Add opus listener test**

Append before the SUMMARY section of `test_stop_task_check.sh`:

```bash
# --- Test 15: Opus listener bypass ---
echo ""
echo "Test 15: Opus listener session -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale
INPUT=$(build_input "$PROJECT" "Watching _pending_opus/ch1/ for new work...")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (Opus listener bypass)"
teardown_temp

# --- Test 15b: Sonnet listener with new path -> ALLOW ---
echo ""
echo "Test 15b: Sonnet listener (renamed path) -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale
INPUT=$(build_input "$PROJECT" "Watching _pending_sonnet/ch2/ for new work...")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (Sonnet listener bypass with new path)"
teardown_temp
```

- [ ] **Step 2: Run tests to verify Test 15 fails**

```bash
cd "D:\Documents\LLM\cc-sentinel"
bash modules/verification/tests/test_stop_task_check.sh
```

Expected: Test 15 (opus listener) fails — current pattern doesn't match `_pending_opus/`.

- [ ] **Step 3: Update the regex pattern**

In `stop-task-check.sh`, line 100, replace:

```bash
if echo "$LAST_MSG" | grep -qiE "Watching _pending_sonnet/" 2>/dev/null; then
```

with:

```bash
if echo "$LAST_MSG" | grep -qiE "Watching _pending_(sonnet|opus)/" 2>/dev/null; then
```

Also update the log message on line 101:

```bash
  echo "  -> ALLOW (listener session)" >> "$LOGFILE" 2>/dev/null
```

- [ ] **Step 4: Run tests**

```bash
cd "D:\Documents\LLM\cc-sentinel"
bash modules/verification/tests/test_stop_task_check.sh
```

Expected: All tests pass including Test 15 and 15b.

- [ ] **Step 5: Commit**

```bash
cd "D:\Documents\LLM\cc-sentinel"
git add modules/verification/hooks/stop-task-check.sh modules/verification/tests/test_stop_task_check.sh
git commit -m "feat: stop-task-check.sh — listener bypass for both sonnet and opus"
```

---

### Task 6: `spawn.py` + installers — dual mkdir

Update `spawn.py` to create both `_pending_sonnet/chN/` and `_pending_opus/chN/`. Update installers to create both dirs.

**Files:**
- Modify: `modules/sprint-pipeline/tools/spawn.py` (lines 1032, 1040)
- Modify: `install.sh` (line 662)
- Modify: `install.ps1` (line 506)

- [ ] **Step 1: Update spawn.py**

In `spawn.py`, line 1032, the routing file write already references `_pending_sonnet/` (from Task 1 rename). Keep that.

At line 1040, replace the single mkdir:

```python
            (p / "verification_findings" / "_pending_sonnet" / ("ch%d" % i)).mkdir(
                parents=True, exist_ok=True,
            )
```

Add the opus directory:

```python
            (p / "verification_findings" / "_pending_sonnet" / ("ch%d" % i)).mkdir(
                parents=True, exist_ok=True,
            )
            (p / "verification_findings" / "_pending_opus" / ("ch%d" % i)).mkdir(
                parents=True, exist_ok=True,
            )
```

- [ ] **Step 2: Update install.sh**

At line 662, replace:

```bash
    mkdir -p verification_findings/_pending_sonnet
```

with:

```bash
    mkdir -p verification_findings/_pending_sonnet verification_findings/_pending_opus
```

- [ ] **Step 3: Update install.ps1**

At line 506, replace:

```powershell
    New-Item -ItemType Directory -Path "verification_findings/_pending_sonnet" -Force | Out-Null
```

with:

```powershell
    New-Item -ItemType Directory -Path "verification_findings/_pending_sonnet" -Force | Out-Null
    New-Item -ItemType Directory -Path "verification_findings/_pending_opus" -Force | Out-Null
```

- [ ] **Step 4: Verify spawn.py dual-dir creation**

```bash
cd "D:\Documents\LLM\cc-sentinel"
python -c "
import tempfile, pathlib, sys
sys.path.insert(0, 'modules/sprint-pipeline/tools')
# Create a temp dir, call scaffold_channels, verify both dirs exist
tmpdir = pathlib.Path(tempfile.mkdtemp())
(tmpdir / 'CURRENT_TASK.md').write_text('test')
# We can't import spawn.py directly (it's a CLI tool), so grep the source
src = pathlib.Path('modules/sprint-pipeline/tools/spawn.py').read_text()
assert '_pending_sonnet' in src, 'FAIL: _pending_sonnet not in spawn.py'
assert '_pending_opus' in src, 'FAIL: _pending_opus not in spawn.py'
print('PASS: spawn.py references both _pending_sonnet and _pending_opus')
"
```

Expected: `PASS: spawn.py references both _pending_sonnet and _pending_opus`

- [ ] **Step 5: Commit**

```bash
cd "D:\Documents\LLM\cc-sentinel"
git add modules/sprint-pipeline/tools/spawn.py install.sh install.ps1
git commit -m "feat: spawn.py + installers — create both _pending_sonnet/ and _pending_opus/"
```

---

### Task 7: `/opus N` command + skill — listener startup rewrite

Rewrite the opus command and skill docs to include the new listener startup procedure. These are the behavioral doc changes specified in Component 2 of the spec.

**Files:**
- Modify: `modules/sprint-pipeline/commands/opus.md`
- Modify: `modules/sprint-pipeline/skills/opus/SKILL.md`

- [ ] **Step 1: Read current opus command and skill files**

Read both files to understand the full current content before rewriting.

- [ ] **Step 2: Update startup procedure in both files**

The key changes (apply to both opus.md and SKILL.md):

1. `mkdir -p verification_findings/_pending_opus/ch$ARGUMENTS` (replace `_pending_sonnet/`)
2. Start background listener: `bash scripts/wait_for_work.sh --model opus --channel $ARGUMENTS` with `run_in_background: true`
3. On prompt arrival: read prompt file. If file missing → log warning, re-spawn listener. Otherwise: delete prompt, execute, cleanup (delete `.active`, re-spawn listener).
4. Sonnet heartbeat check path remains `_pending_sonnet/chN/.heartbeat` (no change needed — Opus checks Sonnet's heartbeat, not its own).
5. Dispatch path: Sonnet dispatches go to `_pending_sonnet/chN/`
6. Sonnet heartbeat check: `_pending_sonnet/chN/.heartbeat`

- [ ] **Step 3: Commit**

```bash
cd "D:\Documents\LLM\cc-sentinel"
git add modules/sprint-pipeline/commands/opus.md modules/sprint-pipeline/skills/opus/SKILL.md
git commit -m "feat: /opus N — listener startup, .active lifecycle, prompt intake"
```

---

### Task 8: `/sonnet` command + skill — `--model sonnet` flag

Update the sonnet command/skill to pass `--model sonnet` to wait_for_work.sh and add `.active` cleanup.

**Files:**
- Modify: `modules/sprint-pipeline/commands/sonnet.md`
- Modify: `modules/sprint-pipeline/skills/sonnet/SKILL.md`

- [ ] **Step 1: Read current files**

Read both files fully.

- [ ] **Step 2: Update both files**

Key changes:
1. `wait_for_work.sh` call adds `--model sonnet`
2. Announce line: "Watching _pending_sonnet/chN/" (already renamed in Task 1)
3. Cleanup step: delete `.active` after processing, then re-spawn wait
4. SKILL.md description: update from `_pending/` to `_pending_sonnet/`

- [ ] **Step 3: Commit**

```bash
cd "D:\Documents\LLM\cc-sentinel"
git add modules/sprint-pipeline/commands/sonnet.md modules/sprint-pipeline/skills/sonnet/SKILL.md
git commit -m "feat: /sonnet — --model sonnet flag, .active cleanup on completion"
```

---

### Task 9: Full test suite validation

Run all test suites to verify everything works together.

**Files:** None (validation only)

- [ ] **Step 1: Run all 5 test suites**

```bash
cd "D:\Documents\LLM\cc-sentinel"
echo "=== wait_for_work.sh ===" && bash modules/commit-enforcement/tests/test_wait_for_work.sh && \
echo "=== safe_commit.sh ===" && bash modules/commit-enforcement/tests/test_safe_commit.sh && \
echo "=== channel_commit.sh ===" && bash modules/commit-enforcement/tests/test_channel_commit.sh && \
echo "=== session-orient.sh ===" && bash modules/core/tests/test_session_orient.sh && \
echo "=== stop-task-check.sh ===" && bash modules/verification/tests/test_stop_task_check.sh && \
echo "ALL SUITES PASSED"
```

Expected: All 5 suites pass with 0 failures.

- [ ] **Step 2: Verify no remaining `_pending/` references (without _sonnet or _opus suffix)**

```bash
cd "D:\Documents\LLM\cc-sentinel"
grep -rn '"_pending/' --include="*.sh" --include="*.py" --include="*.ps1" --include="*.md" \
  modules/ install.sh install.ps1 | grep -v '_pending_sonnet' | grep -v '_pending_opus' | grep -v 'docs/specs/'
```

Expected: No output (zero remaining bare `_pending/` references outside spec docs).

---

### Task 10: Wakeful propagation

After sentinel work is complete, propagate changes to the Wakeful repo.

**Files (in `D:\Documents\LLM\App\Wakeful`):**
- Modify: `scripts/wait_for_work.sh` — same changes as Task 2
- Modify: `scripts/channel_commit.sh` — path rename + threshold update + 7-state liveness
- Modify: `scripts/claude-hooks/safe-commit.sh` — path rename
- Modify: `scripts/claude-hooks/stop-task-check.sh` — regex update for opus variant
- Modify: `.claude/commands/sonnet.md`, `opus.md`, `squad.md`, `1.md`–`5.md`, `cold.md`, `cleanup.md` — path renames
- Modify: `.claude/reference/channel-routing.md` — path rename
- Modify: `.gitignore` — update `_pending/` entries
- Modify: `CLAUDE.md` — two references (requires GOVERNANCE-EDIT-AUTHORIZED marker)
- Modify: `spawn.py` — template + mkdir both dirs

- [ ] **Step 1: Rename `_pending/` → `_pending_sonnet/` across all Wakeful files**

Same mechanical rename as Task 1 but targeting Wakeful paths.

- [ ] **Step 2: Apply behavioral changes**

- `scripts/wait_for_work.sh` — copy from sentinel (or apply same --model, oldest-first, .active changes)
- `scripts/channel_commit.sh` — apply same check_heartbeat rewrite
- `scripts/claude-hooks/stop-task-check.sh` — apply same regex change
- `spawn.py` — apply same dual mkdir
- `.gitignore` — replace `verification_findings/_pending/` with both `verification_findings/_pending_sonnet/` and `verification_findings/_pending_opus/`

- [ ] **Step 3: CLAUDE.md governance edit**

Write `GOVERNANCE-EDIT-AUTHORIZED` to CT, update the two `_pending/` references in CLAUDE.md, remove marker.

- [ ] **Step 4: Commit**

```bash
cd "D:\Documents\LLM\App\Wakeful"
bash scripts/channel_commit.sh --channel 1 --files "scripts/wait_for_work.sh scripts/channel_commit.sh scripts/claude-hooks/safe-commit.sh scripts/claude-hooks/stop-task-check.sh .claude/commands/sonnet.md .claude/commands/opus.md .claude/commands/squad.md .claude/reference/channel-routing.md .gitignore CLAUDE.md spawn.py" -m "feat: opus listener — _pending_sonnet rename + behavioral changes"
```
