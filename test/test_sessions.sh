#!/usr/bin/env bash
# Test suite for the /session picker (lib/sessions.py).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PY="${SCRIPT_DIR}/../lib/sessions.py"

tests_passed=0
tests_failed=0

RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'

JSON='[
 {"id":"ses_a","title":"Alpha session","updated":2000,"directory":"/x"},
 {"id":"ses_b","title":"Beta session","updated":1000,"directory":"/x"},
 {"id":"ses_c","title":"Gamma session","updated":3000,"directory":"/y"}
]'

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf "${GREEN}PASS${RESET}  %s\n" "$desc"
        ((tests_passed++))
    else
        printf "${RED}FAIL${RESET}  %s\n" "$desc"
        printf "       expected: %s\n" "$expected"
        printf "       actual:   %s\n" "$actual"
        ((tests_failed++))
    fi
}

echo "=== list ==="
actual="$(python3 "$PY" list --json "$JSON" --dir /x | cut -f1 | tr '\n' ' ')"
check "filters to directory /x, sorted newest first" "ses_a ses_b " "$actual"

actual="$(python3 "$PY" list --json "$JSON" | cut -f1 | tr '\n' ' ')"
check "no --dir shows all, sorted newest first" "ses_c ses_a ses_b " "$actual"

actual="$(python3 "$PY" list --json "$JSON" --dir /y | cut -f1-2)"
check "returns id and title" "ses_c	Gamma session" "$actual"

echo ""
echo "=== pick ==="
actual="$(printf '1\n' | python3 "$PY" pick --json "$JSON" --dir /x)"
check "selects session by number" "ses_a" "$actual"

actual="$(printf '2\n' | python3 "$PY" pick --json "$JSON" --dir /x)"
check "selects second session" "ses_b" "$actual"

actual="$(printf 'n\n' | python3 "$PY" pick --json "$JSON" --dir /x)"
check "new session sentinel" "__PROMPTLESS_NEW__" "$actual"

actual="$(printf 'q\n' | python3 "$PY" pick --json "$JSON" --dir /x)"
check "cancel sentinel" "__PROMPTLESS_CANCEL__" "$actual"

actual="$(printf 'zz\n2\n' | python3 "$PY" pick --json "$JSON" --dir /x)"
check "retries on invalid input" "ses_b" "$actual"

echo ""
printf "Results: ${GREEN}%d passed${RESET}, ${RED}%d failed${RESET}\n" "$tests_passed" "$tests_failed"
[[ $tests_failed -eq 0 ]]
