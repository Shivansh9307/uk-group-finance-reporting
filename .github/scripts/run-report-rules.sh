#!/usr/bin/env bash
# Runs Fab Inspector (formerly PBI-Inspector) on a PBIR report folder and decides the exit code
# from its JSON results, because the CLI exits 0 even when a rule fails (observed with v4.0.0
# using -formats Console,JSON).
# Usage: run-report-rules.sh <fab-inspector exe> <report folder> <rules.json> <output dir>
# Exit: 0 = no failed error-level rule, 1 = at least one failed error-level rule.
set -uo pipefail
exe="$1"; report="$2"; rules="$3"; out="$4"
rm -rf "$out"; mkdir -p "$out"

t0=$(date +%s.%N)
# -formats: Console prints results; JSON writes TestRun_<id>.json to -output. Adding GitHub to the
# list switches the CLI to annotation-only output and drops the JSON file, so it is not used here.
# -verbose true: without it only failures are recorded, and a clean run writes no JSON file at all.
"$exe" -fabricitem "$report" -rules "$rules" -formats "Console,JSON" -output "$out" -overwriteoutput true -verbose true
code=$?
echo "fab-inspector exit code: $code ($(echo "$(date +%s.%N) - $t0" | bc) s)"

json="$(ls "$out"/TestRun_*.json 2>/dev/null | head -n 1)"
if [[ -z "$json" ]]; then
  echo "::error::no JSON results written to $out"
  exit 1
fi
# LogType 0 is "error", 1 is "warning" in the results file.
errors=$(jq '[.Results[] | select(.Pass == false and .LogType == 0)] | length' "$json")
warnings=$(jq '[.Results[] | select(.Pass == false and .LogType != 0)] | length' "$json")
jq -r '.Results[] | select(.Pass == false)
       | "::\(if .LogType == 0 then "error" else "warning" end)::\(.RuleId) on page \(.ParentDisplayName): \(.Message)"' "$json"
echo "failed rules: $errors error-level, $warnings warning-level"
[[ "$errors" -eq 0 ]]
