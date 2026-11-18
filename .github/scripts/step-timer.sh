#!/usr/bin/env bash
# Source this file, then wrap a command with `timed <label> <command ...>`. The seconds it took are appended
# to $RUNNER_TEMP/timings.txt as `<label>_s=<seconds>`, and the command's own exit code is returned, so a
# failing command still fails the step and its time is still recorded. The Summary step prints the file.
timed() {
  local label="$1"; shift
  local t0 t1 rc
  t0=$(date +%s.%N)
  "$@" && rc=0 || rc=$?
  t1=$(date +%s.%N)
  printf '%s_s=%.1f\n' "$label" "$(echo "$t1 - $t0" | bc)" | tee -a "$RUNNER_TEMP/timings.txt"
  return "$rc"
}
