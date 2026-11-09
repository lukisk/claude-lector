#!/bin/bash
# Tests for hooks/capture-prompt.sh. Every case: stdout empty, exit 0.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/capture-prompt.sh"
fail=0
pass() { echo "ok   - $1"; }
bad()  { echo "FAIL - $1"; fail=1; }

run_hook() { # $1 = stdin; env via caller
  local out rc
  set +e; out=$(printf '%s' "$1" | "$HOOK"); rc=$?; set -e
  [[ -z "$out" ]] || { bad "stdout not empty: $out"; }
  [[ $rc -eq 0 ]] || { bad "exit code $rc"; }
}

T=$(mktemp -d); trap 'chmod -R u+w "$T"; rm -rf "$T"' EXIT
export CLAUDE_LECTOR_INBOX="$T/sub/inbox.jsonl"

# 1. normal input
CLAUDE_CODE_ENTRYPOINT=cli CLAUDE_CODE_SESSION_ATTENDED=1 run_hook '{"session_id":"s","cwd":"/a/b","prompt_id":"p","prompt":"hi there friend","hook_event_name":"UserPromptSubmit"}'
if [[ -f "$CLAUDE_LECTOR_INBOX" ]] && [[ $(wc -l < "$CLAUDE_LECTOR_INBOX") -eq 1 ]] && \
   jq -e '.prompt=="hi there friend" and .prompt_id=="p" and .session_id=="s" and .cwd=="/a/b" and .entrypoint=="cli" and .attended=="1" and (.timestamp|test("^[0-9-]+T[0-9:]+Z$"))' "$CLAUDE_LECTOR_INBOX" >/dev/null
then pass "normal input writes one line"; else bad "normal input writes one line"; fi

# 2. hostile content round-trips
nasty=$'He said "hi" \\ back\nnew line $(rm -rf /) `x` 🚀 é'
input=$(jq -cn --arg p "$nasty" '{session_id:"s",cwd:"/a",prompt_id:"p2",prompt:$p}')
run_hook "$input"
got=$(tail -n1 "$CLAUDE_LECTOR_INBOX" | jq -r '.prompt')
[[ "$got" == "$nasty" ]] && pass "hostile prompt round-trips" || bad "hostile prompt round-trips"

# 3. 200 KB prompt
big=$(head -c 200000 /dev/zero | tr '\0' 'a')
run_hook "$(jq -cn --arg p "$big" '{session_id:"s",cwd:"/a",prompt_id:"p3",prompt:$p}')"
[[ $(tail -n1 "$CLAUDE_LECTOR_INBOX" | jq -r '.prompt | length') -eq 200000 ]] && pass "200 KB prompt" || bad "200 KB prompt"

# 4. lines accumulate
[[ $(wc -l < "$CLAUDE_LECTOR_INBOX") -eq 3 ]] && pass "lines accumulate" || bad "lines accumulate"

# 5. missing env → null
env -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_SESSION_ATTENDED "$HOOK" <<<'{"session_id":"s","cwd":"/a","prompt_id":"p4","prompt":"x"}' >/dev/null
tail -n1 "$CLAUDE_LECTOR_INBOX" | jq -e '.entrypoint==null and .attended==null' >/dev/null && pass "missing env is null" || bad "missing env is null"

# 6. invalid JSON → nothing written
before=$(wc -l < "$CLAUDE_LECTOR_INBOX")
run_hook 'not json'
[[ $(wc -l < "$CLAUDE_LECTOR_INBOX") -eq $before ]] && pass "invalid json writes nothing" || bad "invalid json writes nothing"

# 7. unwritable dir
CLAUDE_LECTOR_INBOX="$T/ro/inbox.jsonl"; mkdir -p "$T/ro"; chmod 500 "$T/ro"
CLAUDE_LECTOR_INBOX="$T/ro/inbox.jsonl" run_hook '{"session_id":"s","cwd":"/a","prompt_id":"p5","prompt":"x"}'
pass "unwritable dir: silent exit 0"

# 8. no jq on PATH
out=$(PATH=/nonexistent /bin/bash "$HOOK" <<<'{"prompt":"x"}'; echo "rc=$?")
[[ "$out" == "rc=0" ]] && pass "no jq: silent exit 0" || bad "no jq: got '$out'"

# 9. fast
start=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')
printf '%s' '{"session_id":"s","cwd":"/a","prompt_id":"p6","prompt":"speed test here"}' | "$HOOK"
end=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')
(( end - start < 200 )) && pass "fast ($((end - start)) ms)" || bad "slow: $((end - start)) ms"

exit $fail
