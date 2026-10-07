#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/adder-generation.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT HUP INT TERM
xcrun swiftc -module-cache-path "$task_tmp/module-cache" \
    "$task_root/App/GenerationMonitor.swift" "$task_root/Tests/GenerationMonitorChecks.swift" \
    -o "$task_tmp/generation-checks"
"$task_tmp/generation-checks"
