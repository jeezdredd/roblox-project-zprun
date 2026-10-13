#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
failed=0
for suite in tests/*/run.luau; do
	[ -f "$suite" ] || continue
	if ! output=$(luau "$suite" 2>&1); then
		echo "FAIL $suite"
		echo "$output" | tail -20
		failed=1
	else
		echo "ok   $suite"
	fi
done
for suite in tests/*/run.py; do
	[ -f "$suite" ] || continue
	if ! output=$(python3 "$suite" 2>&1); then
		echo "FAIL $suite"
		echo "$output" | tail -20
		failed=1
	else
		echo "ok   $suite"
	fi
done
exit $failed
