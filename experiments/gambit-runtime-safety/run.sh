#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
usage() {
    printf 'Usage: %s [--preflight] /absolute/archive.tar.gz /absolute/NEW-scratch\n' "$0"
}
if [[ ${1:-} == --help ]]; then usage; exit 0; fi
preflight_only=0
if [[ ${1:-} == --preflight ]]; then preflight_only=1; shift; fi
if (( $# != 2 )); then usage >&2; exit 2; fi
archive=$1
scratch=$2
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
[[ $archive == /* && -f $archive ]] || fail 'Archive MUST be an absolute file path.'
[[ $scratch == /* && ! -e $scratch && ! -L $scratch ]] || fail 'Scratch MUST be an absolute, nonexistent path.'
[[ -d $(dirname "$scratch") ]] || fail 'Scratch parent directory MUST exist.'
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || fail 'Only Darwin arm64 is supported by this experiment.'
for tool in bash bb clang ar ranlib tar patch shasum grep cp mv mkdir dirname basename uname; do
    command -v "$tool" >/dev/null || fail "Missing tool: $tool"
done
bootstrap=${BOOTSTRAP_GSC:-}
if [[ -z $bootstrap ]]; then
    bootstrap=$(command -v gsc4.9.8 || command -v gsc || true)
fi
[[ -n $bootstrap ]] || fail 'Set BOOTSTRAP_GSC to Gambit v4.9.8.'
bootstrap=$(command -v "$bootstrap") || fail 'BOOTSTRAP_GSC is not executable.'
[[ $bootstrap == /* && -x $bootstrap ]] || fail 'BOOTSTRAP_GSC MUST resolve to an absolute executable path.'
package=$(cd "$(dirname "$0")" && pwd -P)
[[ -f $package/bound.clj ]] || fail 'Missing bound.clj.'
if (( ! preflight_only )); then
    [[ -s $package/gambit.patch ]] || fail 'Missing gambit.patch.'
fi
scratch_parent=$(cd "$(dirname "$scratch")" && pwd -P)
scratch="$scratch_parent/$(basename "$scratch")"
case "$scratch/" in "$package/"*) fail 'Scratch MUST be outside the package.' ;; esac
mkdir "$scratch"
scratch=$(cd "$scratch" && pwd -P)
export BOOTSTRAP_GSC="$bootstrap"
export LC_ALL=C
stage() {
    local name=$1 seconds=$2 status=0 start=$SECONDS
    shift 2
    printf '%q ' bb --config /dev/null "$package/bound.clj" "$seconds" "$@" > "$scratch/$name.command"
    printf '\n' >> "$scratch/$name.command"
    printf 'START %s deadline=%ss grace=2s\n' "$name" "$seconds" >> "$scratch/stages.log"
    bb --config /dev/null "$package/bound.clj" "$seconds" "$@" > "$scratch/$name.log" 2>&1 || status=$?
    printf '%s\n' "$status" > "$scratch/$name.status"
    printf '%s\n' "$((SECONDS-start))" > "$scratch/$name.wall"
    printf 'END %s status=%s wall=%ss\n' "$name" "$status" "$((SECONDS-start))" >> "$scratch/stages.log"
    if (( status != 0 )); then
        printf 'Stage %s failed (%s); see %s/%s.log\n' "$name" "$status" "$scratch" "$name" >&2
        exit "$status"
    fi
}
printf 'deadline_sum=570 grace_sum=18 declared_sum=588 seconds\n' > "$scratch/budgets.txt"
# The child shell expands this command string.
# shellcheck disable=SC2016
stage preflight 10 bash -c '
    set -euo pipefail
    IFS=$'"'"'\n\t'"'"'
    uname -smr
    bash --version
    bb --config /dev/null --version
    clang --version
    version=$("$BOOTSTRAP_GSC" -v 2>&1)
    printf "%s\n" "$version"
    [[ $version == v4.9.8\ * ]] || { printf "Expected Gambit v4.9.8\n" >&2; exit 2; }
    bb --config /dev/null -e "(assert (resolve (symbol \"parse-long\")))"
'
# The child shell expands this command string.
# shellcheck disable=SC2016
stage prepare 20 bash -c '
    set -euo pipefail
    IFS=$'"'"'\n\t'"'"'
    archive=$1 scratch=$2 package=$3 preflight_only=$4
    sum=$(shasum -a 256 "$archive")
    printf "%s\n" "$sum"
    [[ ${sum%% *} == ddfbc3d9903d927a3c7961ad3e2cf215415cb8914e3df15a3f6a6453a032d6d8 ]] || { printf "Archive SHA256 mismatch\n" >&2; exit 2; }
    if (( ! preflight_only )); then
        mkdir "$scratch/source"
        tar -xf "$archive" --strip-components=1 -C "$scratch/source"
        cp "$package"/fixtures/*.scm "$scratch/"
    fi
' review-prepare "$archive" "$scratch" "$package" "$preflight_only"
if (( preflight_only )); then printf 'Preflight passed; evidence: %s\n' "$scratch"; exit 0; fi
# The child shells expand these command strings.
# shellcheck disable=SC2016
stage patch 10 bash -c 'set -euo pipefail; IFS=$'"'"'\n\t'"'"'; cd "$1/source"; patch --batch --forward -p1 < "$2/gambit.patch"' review-patch "$scratch" "$package"
# shellcheck disable=SC2016
stage configure 40 bash -c 'set -euo pipefail; IFS=$'"'"'\n\t'"'"'; cd "$1/source"; ./configure --disable-shared --disable-openssl --disable-guide CFLAGS=-O0' review-configure "$scratch"
if grep -Fq PKG_PROG_PKG_CONFIG "$scratch/configure.log"; then
    printf 'UNRESOLVED: configure emitted PKG_PROG_PKG_CONFIG; retained in configure.log. No repair was applied.\n' > "$scratch/configure-warning.txt"
else
    printf 'No PKG_PROG_PKG_CONFIG text observed in configure.log.\n' > "$scratch/configure-warning.txt"
fi
stage regenerate 60 bash "$package/regenerate.sh" "$scratch"
stage runtime-build 120 bash "$package/build.sh" "$scratch" runtime
stage compiler-build 120 bash "$package/build.sh" "$scratch" compiler
stage policy 50 bash "$package/tests.sh" "$scratch"
stage checks 40 bash "$package/checks.sh" "$scratch"
printf 'PASS bounded experimental reproduction; evidence: %s\n' "$scratch"
