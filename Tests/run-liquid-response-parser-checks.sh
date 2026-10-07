#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/adder-response.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT HUP INT TERM
xcrun swiftc -module-cache-path "$task_tmp/module-cache" \
    "$task_root/App/LiquidResponseParser.swift" "$task_root/Tests/LiquidResponseParserChecks.swift" \
    -o "$task_tmp/response-checks"
"$task_tmp/response-checks"
