#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/displayplus-recovery.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -swift-version 6 -parse-as-library \
    "$PROJECT_ROOT/DisplayPlus/Services/DisplayConnectionService.swift" \
    "$PROJECT_ROOT/tests/DisplayConnectionRecoveryTests.swift" \
    -o "$TEST_DIR/display-recovery-tests"
"$TEST_DIR/display-recovery-tests"
