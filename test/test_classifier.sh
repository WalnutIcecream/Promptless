#!/usr/bin/env bash
# Test suite for promptless.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/classifier.sh"

tests_passed=0
tests_failed=0

RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'

assert_command() {
    local input="$1"
    is_shell_command "$input"
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        printf "${GREEN}PASS${RESET}  [cmd]  %s\n" "$input"
        ((tests_passed++))
    else
        printf "${RED}FAIL${RESET}  [cmd]  %s (classified as prompt)\n" "$input"
        ((tests_failed++))
    fi
}

assert_prompt() {
    local input="$1"
    is_shell_command "$input"
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        printf "${GREEN}PASS${RESET}  [nlp]  %s\n" "$input"
        ((tests_passed++))
    else
        printf "${RED}FAIL${RESET}  [nlp]  %s (classified as command)\n" "$input"
        ((tests_failed++))
    fi
}

echo "=== Known Commands ==="
assert_command "ls -la"
assert_command "git status"
assert_command "cd /tmp"
assert_command "echo hello"
assert_command "export FOO=bar"
assert_command "source ~/.bashrc"
assert_command "./script.sh --verbose"

echo ""
echo "=== Natural Language Prompts ==="
assert_prompt "find all JavaScript files in the src directory"
assert_prompt "how do I set up a new React project?"
assert_prompt "what is the git command to undo a commit"
assert_prompt "create a new file called config.json"
assert_prompt "show me the total disk usage"
assert_prompt "explain how to use grep recursively"
assert_prompt "can you help me write a Python script?"
assert_prompt "fix the bug in the authentication module"
assert_prompt "deploy the latest release to production"
assert_prompt "suggest a good library for date parsing"
assert_prompt "check if the server is running"
assert_prompt "update all npm packages in the project"
assert_prompt "delete the temp directory and all its contents"
assert_prompt "build a Docker image from this Dockerfile"
assert_prompt "review the pull request for security issues"
assert_prompt "convert this PDF to markdown format"
assert_prompt "summarize the changes in the latest commit"
assert_prompt "analyze the performance of this function"
assert_prompt "compare the two JSON files for differences"
assert_prompt "generate a random UUID"

echo ""
echo "=== Edge Cases ==="
assert_command ""
assert_command "\\ls"
assert_command "\# comment"
assert_command "echo hello | grep world"
assert_command "ls --color=auto"
assert_command "grep -r pattern ."
assert_command "ls > /tmp/out"
assert_command "singleword"
assert_command "maybecommand"
assert_prompt "teach me how to use git rebase"

echo ""
printf "Results: ${GREEN}%d passed${RESET}, ${RED}%d failed${RESET}\n" "$tests_passed" "$tests_failed"
[[ $tests_failed -eq 0 ]]
