#!/bin/bash
set -euo pipefail

# Requires macOS, Xcode command-line tools, and an unlocked default login Keychain.
# The test checks Keychain availability before creating disposable UUID-named items.
# It never reads or refreshes real Claude credentials and removes its test items.
if [[ "$(uname -s)" != Darwin ]]; then
    echo "This test requires macOS and an unlocked default login Keychain." >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/atoll-keychain-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
cd "$repo_root"

swiftc DynamicIsland/managers/LLMUsage/Quota/KeychainReader.swift \
    tests/test_claude_keychain.swift -o "$test_dir/test_claude_keychain"
"$test_dir/test_claude_keychain"
