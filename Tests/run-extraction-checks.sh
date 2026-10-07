#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/adder-extraction.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT HUP INT TERM
task_arch=$(uname -m)
xcrun swiftc \
    -module-cache-path "$task_tmp/module-cache" \
    -target "$task_arch-apple-macos14.0" \
    "$task_root/App/PhoneActions.swift" \
    "$task_root/App/ExtractionRules.swift" \
    "$task_root/Tests/ExtractionChecks.swift" \
    -o "$task_tmp/extraction-checks"
"$task_tmp/extraction-checks"
