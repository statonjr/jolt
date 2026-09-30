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
paths="-:dq,~~bin=$root/bin,~~lib=$root/lib,~~include=$root/include"
run_case() {
    local label=$1 status=0 start=$SECONDS
    shift
    printf '%q ' "$@" > "$label.command"
    printf '\n' >> "$label.command"
    "$@" > "$label.log" 2>&1 || status=$?
    printf '%s\n' "$status" > "$label.status"
    printf '%s\n' "$((SECONDS-start))" > "$label.wall"
    printf 'CASE %s status=%s\n' "$label" "$status"
    return "$status"
}
compile_run() {
    local name=$1
    run_case "$name-generate" "$gsc" "$paths" -f -c -o "$name.c" "$name.scm"
    run_case "$name-link-map" "$gsc" "$paths" -f -link -l "$root/lib/_gambit" -o "${name}_.c" "$name.c"
    run_case "$name-compile" clang -O0 -fwrapv -fno-strict-aliasing -I "$root/include" \
        -o "$name" "$name.c" "${name}_.c" "$root/lib/libgambit.a"
    run_case "$name-execute" "./$name" "$paths"
}
run_case stress-interpreted "$gsi" "$paths" -f stress.scm
compile_run stress
grep -Fxq '(SUMMARY passed 30 failed 0)' stress-interpreted.log
grep -Fxq '(SUMMARY passed 30 failed 0)' stress-execute.log
for n in 32 64 65; do
    compile_run "do-$n"
    if (( n == 65 )); then
        grep -Fxq '(DO-65 length 65 all-one #t)' "do-$n-execute.log"
    else
        grep -Fxq "(DO-CONTROL $n length $n all-one #t)" "do-$n-execute.log"
    fi
done
run_case escape "$gsi" "$paths" -f escape-tests.scm
grep -Fxq '(ESCAPE passed 9 failed 0)' escape.log
run_case extrema "$gsc" "$paths" -f -e '(load "extrema-tests.scm")'
grep -Fxq '(EXTREMA passed 6 failed 0)' extrema.log
printf 'PASS stress=30+30 controls=32,64,65 escape=9 extrema=6\n'
