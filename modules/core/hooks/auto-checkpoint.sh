#!/usr/bin/env bash
# Auto-checkpoint: creates git stash snapshots on Stop/PreCompact
# Silent hook — exits 0 with no stdout
set -u

# Not in git repo? Graceful exit.
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# No changes? Nothing to checkpoint.
git status --porcelain 2>/dev/null | grep -q . || exit 0

# Create checkpoint without modifying working directory
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S)
# Save which files were staged before we touch the index
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null)
git add -A 2>/dev/null
SHA=$(git stash create "sentinel-checkpoint: $TIMESTAMP" 2>/dev/null)
git reset --quiet 2>/dev/null
# Restore any files that were staged before the hook ran (including staged deletions)
if [[ -n "$STAGED_FILES" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && git add "$f" 2>/dev/null
  done <<< "$STAGED_FILES"
fi

# stash create returns empty if nothing to stash (shouldn't happen given porcelain check, but guard)
[[ -z "$SHA" ]] && exit 0

git stash store -m "sentinel-checkpoint: $TIMESTAMP" "$SHA" 2>/dev/null

# Prune oldest sentinel checkpoints beyond MAX_CHECKPOINTS
MAX_CHECKPOINTS=10
SENTINEL_REFS=()
while IFS= read -r line; do
  if [[ "$line" == *"sentinel-checkpoint:"* ]]; then
    REF=$(echo "$line" | cut -d: -f1)
    SENTINEL_REFS+=("$REF")
  fi
done < <(git stash list 2>/dev/null)

if [[ ${#SENTINEL_REFS[@]} -gt $MAX_CHECKPOINTS ]]; then
  # Drop from the end (oldest first — git stash list is newest-first)
  for (( i=${#SENTINEL_REFS[@]}-1; i>=MAX_CHECKPOINTS; i-- )); do
    git stash drop "${SENTINEL_REFS[$i]}" --quiet 2>/dev/null
  done
fi

exit 0
