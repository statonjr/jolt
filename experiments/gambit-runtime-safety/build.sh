#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
if (( $# != 2 )) || [[ $1 != /* || ! -d $1/source ]]; then
    printf 'Usage: %s /absolute/scratch runtime|compiler\n' "$0" >&2; exit 2
fi
cd "$1/source"
mode="$2"
if test ! -e include/stamp.h; then printf '\n' > include/stamp.h; fi
cc=(clang -O0 -Wno-unused -Wno-write-strings -Wdisabled-optimization
    -fwrapv -fno-strict-aliasing -fno-trapping-math -fno-math-errno
    -fPIC -fno-common -Iinclude -DHAVE_CONFIG_H)
runtime_defs=("-D___GAMBITDIR=\"$PWD\"" '-D___GAMBITDIR_USERLIB="~/.gambit_userlib"'
    '-D___GAMBITDIR_INSTLIB="~~userlib"' '-D___SYS_TYPE_CPU="aarch64"'
    '-D___SYS_TYPE_VENDOR="apple"' "-D___SYS_TYPE_OS=\"darwin$(uname -r)\""
    '-D___CONFIGURE_COMMAND="./configure --disable-shared --disable-openssl --disable-guide CFLAGS=-O0"'
    '-D___OBJ_EXTENSION=".o"' '-D___EXE_EXTENSION=""' '-D___BAT_EXTENSION=""')
compile_pairwise() {
    local first='' file
    for file in "$@"; do
        printf 'COMPILE %s\n' "$file"
        if [[ "$file" == lib/* ]]; then
            "${cc[@]}" "${runtime_defs[@]}" -Ilib -D___PRIMAL -D___LIBRARY -c "$file.c" -o "$file.o" &
        elif [[ "$file" == */_gsi || "$file" == */_gsi_ || "$file" == */_gsc || "$file" == */_gsc_ ]]; then
            "${cc[@]}" -c "$file.c" -o "$file.o" &
        else
            "${cc[@]}" -D___LIBRARY -c "$file.c" -o "$file.o" &
        fi
        if test -z "$first"; then first=$!; else wait "$first"; wait "$!"; first=''; fi
    done
    if test -n "$first"; then wait "$first"; fi
}
set -x
case "$mode" in
runtime)
    names=(main setup mem os_setup os_base os_thread os_time os_shell os_files
        os_dyn os_tty os_io c_intf actlog _kernel _system _num _std _eval
        _module _io _nonstd _thread _repl _gambit)
    files=()
    objects=()
    for name in "${names[@]}"; do files+=("lib/$name"); objects+=("lib/$name.o"); done
    compile_pairwise "${files[@]}" gsi/_gsilib gsi/_gambitgsi gsi/_gsi gsi/_gsi_
    test ! -e lib/libgambit.a
    ar rc lib/libgambit.a "${objects[@]}"
    ranlib lib/libgambit.a
    "${cc[@]}" -o gsi/gsi gsi/_gsi.o gsi/_gsi_.o gsi/_gsilib.o gsi/_gambitgsi.o lib/libgambit.a
    ;;
compiler)
    names=(_host _utils _source _parms _env _ptree1 _ptree2 _gvm _back _front
        _prims _assert _asm _x86 _arm _riscv _codegen _t-univ-1 _t-univ-2
        _t-univ-3 _t-univ-4 _t-cpu-abstract-machine _t-cpu-primitives
        _t-cpu-object-desc _t-cpu-utils _t-cpu-backend-x86 _t-cpu-backend-arm
        _t-cpu-backend-riscv _t-cpu _t-c-1 _t-c-2 _t-c-3 _gsclib _gambitgsc)
    files=()
    objects=()
    for name in "${names[@]}"; do files+=("gsc/$name"); objects+=("gsc/$name.o"); done
    compile_pairwise "${files[@]}" gsc/_gsc gsc/_gsc_
    test ! -e gsc/libgambitgsc.a
    ar rc gsc/libgambitgsc.a "${objects[@]}"
    ranlib gsc/libgambitgsc.a
    "${cc[@]}" -o gsc/gsc gsc/_gsc.o gsc/_gsc_.o gsc/libgambitgsc.a lib/libgambit.a
    ;;
*) exit 2 ;;
esac
