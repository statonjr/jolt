#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
if (( $# != 1 )) || [[ $1 != /* || ! -d $1/source ]]; then
    printf 'Usage: %s /absolute/scratch (run through run.sh)\n' "$0" >&2; exit 2
fi
cd "$1"
cd source
root="$PWD"
gsc=${BOOTSTRAP_GSC:?run.sh MUST supply the checked bootstrap compiler}
runtime='(define-cond-expand-feature|enable-type-checking|)(define-cond-expand-feature|disable-auto-forcing|)(define-cond-expand-feature|enable-sharp-dot|)(define-cond-expand-feature|enable-bignum|)(define-cond-expand-feature|enable-ratnum|)(define-cond-expand-feature|enable-cpxnum|)(define-cond-expand-feature|enable-s8vector|)(define-cond-expand-feature|enable-u16vector|)(define-cond-expand-feature|enable-s16vector|)(define-cond-expand-feature|enable-u32vector|)(define-cond-expand-feature|enable-s32vector|)(define-cond-expand-feature|enable-u64vector|)(define-cond-expand-feature|enable-s64vector|)(define-cond-expand-feature|enable-f32vector|)(define-cond-expand-feature|disable-smp|)(##include"../lib/header.scm")'
paths="-:dq,~~bin=$root/bin,~~lib=$root/lib,~~include=$root/include"
set -x
for map in lib/_gambit gsc/_gambitgsc gsc/_gsc_ gsi/_gambitgsi gsi/_gsi_; do
    test ! -e "$map.pre-regenerate.c"
    mv "$map.c" "$map.pre-regenerate.c"
done
cd lib
for module in _kernel _eval _repl; do
    "$gsc" "$paths" -f -c -prelude "$runtime" "$module.scm"
    test -s "$module.c"
done
"$gsc" "$paths" -f -warnings -link -flat -o _gambit.c -preload \
    _kernel.c _system.c _num.c _std.c _eval.c _module.c _io.c _nonstd.c _thread.c _repl.c
cd ../gsc
for module in _ptree1 _front; do
    "$gsc" "$paths" -f -c -prelude '(##namespace("c#"))(##include"../lib/header.scm")' "$module.scm"
    test -s "$module.c"
done
modules=(_host _utils _source _parms _env _ptree1 _ptree2 _gvm _back _front
    _prims _assert _asm _x86 _arm _riscv _codegen _t-univ-1 _t-univ-2
    _t-univ-3 _t-univ-4 _t-cpu-abstract-machine _t-cpu-primitives
    _t-cpu-object-desc _t-cpu-utils _t-cpu-backend-x86 _t-cpu-backend-arm
    _t-cpu-backend-riscv _t-cpu _t-c-1 _t-c-2 _t-c-3 _gsclib)
inputs=()
for module in "${modules[@]}"; do inputs+=("$module.c"); done
test ! -e _gambitgsc.c
"$gsc" "$paths" -f -warnings -link -l ../lib/_gambit -o _gambitgsc.c -preload "${inputs[@]}"
test -s _gambitgsc.c
"$gsc" "$paths" -f -warnings -link -l _gambitgsc -o _gsc_.c -preload _gsc.c
cd ../gsi
"$gsc" "$paths" -f -warnings -link -l ../lib/_gambit -o _gambitgsi.c -preload _gsilib.c
"$gsc" "$paths" -f -warnings -link -l _gambitgsi -o _gsi_.c -preload _gsi.c
cd ..
shasum -a 256 lib/_kernel.c lib/_eval.c lib/_repl.c lib/_gambit.c gsc/_ptree1.c gsc/_front.c gsc/_gambitgsc.c gsc/_gsc_.c gsi/_gambitgsi.c gsi/_gsi_.c > ../regenerated.sha256
