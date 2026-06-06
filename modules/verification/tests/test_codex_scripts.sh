#!/usr/bin/env bash
# Regression tests for the two Codex-tooling bugs fixed 2026-06-05:
#   BUG-1 codex-verify-agent.sh — placeholder splice must handle sed-hostile chars
#         (| & newline; / was always fine) in -w/-s/-S without dying or corrupting.
#   BUG-2 codex-postfix-scan.sh — codex exec must pass -m (default gpt-5.5); the CLI's
#         own default gpt-5.3-codex HTTP-400s on a ChatGPT account.
# Strategy: a `codex` STUB on PATH captures its args + stdin and echoes a canned reply,
# so the wrappers run end-to-end without touching the network.
set -uo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
VERIFY="$SCRIPTS_DIR/codex-verify-agent.sh"
POSTFIX="$SCRIPTS_DIR/codex-postfix-scan.sh"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# --- hermetic HOME: codex-verify-agent.sh runs an auth pre-flight (gates on
# $HOME/.codex/auth.json containing "auth_mode") BEFORE it ever invokes codex; with no
# auth file it short-circuits to VERDICT: TRANSIENT and the codex stub never runs, so
# $CX_PROMPT stays empty and every splice assertion fails. CI runners have no ~/.codex,
# so point HOME at a temp dir with a stub auth file. (postfix-scan has no auth gate.) ---
export HOME="$TMP/home"
mkdir -p "$HOME/.codex"
printf '{"auth_mode":"chatgpt"}\n' > "$HOME/.codex/auth.json"
# --- codex stub: records args -> $CX_ARGS, stdin -> $CX_PROMPT, echoes a reply ---
mkdir -p "$TMP/bin"
cat > "$TMP/bin/codex" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${CX_ARGS:-/dev/null}"
cat > "${CX_PROMPT:-/dev/null}"
printf 'VERDICT: PASS\nstub reply line\n'
exit 0
STUB
chmod +x "$TMP/bin/codex"
export PATH="$TMP/bin:$PATH"
export CX_ARGS="$TMP/cx_args.txt" CX_PROMPT="$TMP/cx_prompt.txt"
# --- stub prompts file (verify-agent reads $CODEX_PROMPTS_FILE; the real one lives at
# $HOME/.claude/reference/ which is absent in CI). A MECHANICAL role section (--- delimited)
# carrying the three placeholders the splice replaces, so we can assert each is spliced. ---
PROMPTS="$TMP/prompts.md"
printf '## MECHANICAL\nWORK_PRODUCT={{WORK_PRODUCT}}\nSOURCE_SPEC={{SOURCE_SPEC}}\nSCOPE_SUMMARY={{SCOPE_SUMMARY}}\n---\n## ADVERSARIAL\nstub\n---\n' > "$PROMPTS"
export CODEX_PROMPTS_FILE="$PROMPTS"

# ===================== BUG-1: codex-verify-agent.sh splice =====================
echo "Test BUG-1: verify-agent splice handles sed-hostile chars in -w/-s/-S"
# A scope summary packed with every sed-hostile char + a slash path work-product.
SCOPE="$(printf 'scope a/b | c & d\nsecond line')"
WP="specs/feat|x&y.md"
SS="docs/spec a/b.md"
OUT="$TMP/verify_out.md"
: > "$CX_ARGS"; : > "$CX_PROMPT"
bash "$VERIFY" -m gpt-5.5 -r mechanical -w "$WP" -s "$SS" -S "$SCOPE" -o "$OUT" >"$TMP/v.log" 2>&1
vrc=$?
# (a) must not hard-fail on a sed error and must write an output file
if [[ -s "$OUT" ]]; then ok "verify-agent wrote output (no splice crash), rc=$vrc"; else no "verify-agent produced no output (rc=$vrc): $(tail -2 "$TMP/v.log")"; fi
# (b) the spliced prompt the stub received must contain the literal values
if grep -qF "$WP" "$CX_PROMPT" 2>/dev/null; then ok "WORK_PRODUCT spliced literally (| & / preserved)"; else no "WORK_PRODUCT not literal in prompt"; fi
if grep -qF 'scope a/b | c & d' "$CX_PROMPT" 2>/dev/null; then ok "SCOPE_SUMMARY spliced literally (| & preserved)"; else no "SCOPE_SUMMARY not literal in prompt"; fi
if grep -qF 'second line' "$CX_PROMPT" 2>/dev/null; then ok "SCOPE_SUMMARY newline preserved"; else no "SCOPE_SUMMARY newline lost"; fi
# (c) no leftover unspliced placeholder
if grep -qF '{{SCOPE_SUMMARY}}' "$CX_PROMPT" 2>/dev/null; then no "placeholder {{SCOPE_SUMMARY}} left unspliced"; else ok "no leftover placeholders"; fi

# ===================== BUG-2: codex-postfix-scan.sh model =====================
echo "Test BUG-2: postfix-scan passes -m gpt-5.5 to codex exec (default)"
SPEC="$TMP/spec.md"; printf '# spec\nrole: integrity\n' > "$SPEC"
PFOUT="$TMP/postfix_out.md"
: > "$CX_ARGS"; : > "$CX_PROMPT"
CODEX_POSTFIX_NO_STREAK=1 bash "$POSTFIX" "$SPEC" "$PFOUT" >"$TMP/p.log" 2>&1 || true
if grep -qx 'exec' "$CX_ARGS" 2>/dev/null && grep -qx 'gpt-5.5' "$CX_ARGS" 2>/dev/null && grep -qx '\-m' "$CX_ARGS" 2>/dev/null; then
  ok "postfix-scan invoked: codex exec -m gpt-5.5"
else
  no "postfix-scan did not pass -m gpt-5.5 (captured args: $(tr '\n' ' ' < "$CX_ARGS" 2>/dev/null))"
fi
echo "Test BUG-2b: CODEX_MODEL env override is honored"
: > "$CX_ARGS"
CODEX_MODEL=gpt-5.5-test CODEX_POSTFIX_NO_STREAK=1 bash "$POSTFIX" "$SPEC" "$PFOUT" >"$TMP/p2.log" 2>&1 || true
if grep -qx 'gpt-5.5-test' "$CX_ARGS" 2>/dev/null; then ok "CODEX_MODEL env override honored"; else no "CODEX_MODEL env override ignored (args: $(tr '\n' ' ' < "$CX_ARGS" 2>/dev/null))"; fi

echo ""
echo "RESULTS: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && echo "All codex-script tests passed." || exit 1
