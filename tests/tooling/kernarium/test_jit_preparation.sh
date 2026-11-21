#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/kernarium-jit-test.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
    -strict-concurrency=complete -warnings-as-errors \
    "$ROOT_DIR/Kernarium/Kernarium/KernariumJit.swift" \
    "$ROOT_DIR/tests/tooling/kernarium/JitPreparationHarness.swift" \
    -o "$work/jit-test"
"$work/jit-test"
