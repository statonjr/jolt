#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
if (( $# != 1 )) || [[ $1 != /* || ! -d $1/source ]]; then
    printf 'Usage: %s /absolute/scratch (run through run.sh)\n' "$0" >&2; exit 2
fi
cd "$1"
root="$PWD/source"
gsi="$root/gsi/gsi"
gsc="$root/gsc/gsc"
paths="-:d-,~~bin=$root/bin,~~lib=$root/lib,~~include=$root/include"
fail=0
run_case() {
    local label="$1" status=0 start=$SECONDS
    shift
    printf '%q ' "$@" > "$label.command"
    printf '\n' >> "$label.command"
    "$@" > "$label.log" 2>&1 || status=$?
    printf '%s\n' "$status" > "$label.status"
    printf '%s\n' "$((SECONDS-start))" > "$label.wall"
    printf 'CASE %s status=%s\n' "$label" "$status"
    return "$status"
}
run_case runtime-tests "$gsi" "$paths" -f runtime-tests.scm || fail=$((fail+1))
run_case generate-tests "$gsi" "$paths" -f generate-tests.scm
for mode in direct macro positional optional keyword rest mixed; do
    status=0
    run_case "reject-$mode" "$gsc" "$paths" -f -c -o "reject-$mode.c" "reject-$mode.scm" || status=$?
    diagnostic='Public parameter slot limit is 64'
    if [[ "$mode" == direct || "$mode" == macro ]]; then diagnostic='Public argument limit is 64'; fi
    if (( status == 0 )) || test -e "reject-$mode.c" || ! grep -Fq "$diagnostic" "reject-$mode.log"; then
        printf 'FAIL compiler rejection %s\n' "$mode"
        fail=$((fail+1))
    else
        printf 'PASS compiler rejection %s\n' "$mode"
    fi
done
run_case accepted-generate "$gsc" "$paths" -f -c -o accepted.c accepted.scm
run_case accepted-link-map "$gsc" "$paths" -f -link -l "$root/lib/_gambit" -o accepted_.c accepted.c
run_case accepted-compile clang -O0 -fwrapv -fno-strict-aliasing -I "$root/include" \
    -o accepted accepted.c accepted_.c "$root/lib/libgambit.a"
run_case accepted-execute ./accepted "$paths" || fail=$((fail+1))
grep -Fxq '(SUMMARY passed 70 failed 0)' runtime-tests.log || fail=$((fail+1))
grep -Fxq '(SUMMARY passed 70 failed 0)' accepted-execute.log || fail=$((fail+1))
[[ $(grep -c '^[(]STATIC-PASS ' accepted-execute.log) == 7 ]] || fail=$((fail+1))
run_case lowering "$gsi" "$paths" -f lowering-tests.scm || fail=$((fail+1))
grep -Fxq '(SUMMARY passed 4 failed 0)' lowering.log || fail=$((fail+1))
printf 'POLICY expected=158 (70 runtime + 70 compiled + 7 static + 7 rejected + 4 lowering) failed=%s\n' "$fail"
exit "$fail"
