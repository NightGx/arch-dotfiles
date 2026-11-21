#!/usr/bin/env bash
# Run every suite. Each one builds its own throwaway HOME, so this is safe to
# run on the machine you actually use.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

total_pass=0 total_fail=0 failed_suites=()
for suite in test-switch test-menu test-looks test-install; do
  printf '\n\033[1m══ %s ══\033[0m\n' "$suite"
  out=$(bash "$HERE/$suite.sh" 2>&1); rc=$?
  printf '%s\n' "$out"
  line=$(printf '%s\n' "$out" | grep -E '^passed [0-9]+, failed [0-9]+' | tail -1)
  if [[ -n $line ]]; then
    p=${line#passed }; p=${p%%,*}
    f=${line##*failed }
    total_pass=$(( total_pass + p ))
    total_fail=$(( total_fail + f ))
  fi
  (( rc == 0 )) || failed_suites+=("$suite")
done

printf '\n\033[1m══ total ══\033[0m\n'
printf 'passed %d, failed %d\n' "$total_pass" "$total_fail"
if (( ${#failed_suites[@]} )); then
  printf '\033[31mfailing suites:\033[0m %s\n' "${failed_suites[*]}"
  exit 1
fi
printf '\033[32mall suites green\033[0m\n'
