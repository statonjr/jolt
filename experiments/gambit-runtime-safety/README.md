# Experimental Gambit runtime policy

**For review, not production use. No ESP32 or Jolt native-C support is claimed.**
This standalone experiment applies a 64-slot public argument policy to a pinned
Gambit runtime/compiler and removes two internal uses of unbounded `apply`.
It does not change Jolt's normal build or include the separate writer fix.

Start with [the patch](gambit.patch), then the [fixtures](fixtures/) and
[review questions](#review-questions). This is new experimental work, not an
upstream Gambit recommendation.

## Patch scope

Against [Gambit revision `2228e4d163582733a3a67a5efcb22f8ebe93c02b`](https://github.com/gambit/gambit/tree/2228e4d163582733a3a67a5efcb22f8ebe93c02b):

- `lib/_eval.scm` and `gsc/_ptree1.scm` check source call operands and formal
  slots. Required, optional, keyword and one rest slot share a limit of 64.
  The evaluator also checks application lowering.
- `lib/_kernel.scm` checks `##apply` before the 65th argument push, using the
  existing exception and stack cleanup path.
- `lib/public-argument-policy.scm` and `.h` hold the Scheme and C policy values.
  The checked-in C header is the snapshot of the Scheme policy value; a future
  policy change MUST keep both synchronized.
- `gsc/_front.scm` folds compiler extrema with binary `max`/`min`, instead of
  applying them to an unbounded list. Empty input still returns `#f`.
- `lib/_repl.scm` uses `##string-concatenate` for `##escape-link` instead of
  applying `##string-append`. The character mapping is unchanged.

These statements describe [this patch](gambit.patch), not stock Gambit.
The global `##apply` restriction affects internal callers and macro expanders,
not just public user calls. The two internal corrections are not an exhaustive
internal-call audit.

## Offline reproduction

The driver currently accepts **Darwin ARM64 only**. It requires installed
Bash, Babashka, Apple Clang, `ar`, `ranlib`, `tar`, `patch`, `shasum`, standard
shell utilities, and a Gambit **v4.9.8** bootstrap compiler. It does not install
or download anything and does not invoke Make. See [run.sh](run.sh) for the
exact checks and [build.sh](build.sh) for the direct static build.

Supply the pinned source archive yourself. The archive used here came from the
GitHub API endpoint
`repos/gambit/gambit/tarball/2228e4d163582733a3a67a5efcb22f8ebe93c02b`.
The driver requires these exact bytes, not merely an archive with the same tag:

```text
SHA256 ddfbc3d9903d927a3c7961ad3e2cf215415cb8914e3df15a3f6a6453a032d6d8
```

From the Jolt checkout, run:

```bash
BOOTSTRAP_GSC="$(command -v gsc)" \
  experiments/gambit-runtime-safety/run.sh \
  /absolute/path/to/gambit.tar.gz \
  /absolute/path/to/new-scratch
```

The scratch parent MUST exist; the scratch directory MUST NOT exist. Use a
path outside this package. Add `--preflight` before the archive argument to
check tools and archive identity without extraction or compilation. Preflight
also creates its own fresh evidence directory. Use a different directory for
the full run.

The driver extracts the archive, applies the patch, configures with
`--disable-shared --disable-openssl --disable-guide CFLAGS=-O0`, regenerates all
five changed Scheme modules and link maps, builds static `gsi`/`gsc`, then runs
the fixtures. Unchanged modules use the archive's pregenerated C; this is not a
full Scheme-to-C self-bootstrap. The bootstrap compiler is version-checked,
not binary-hash-pinned. See [regenerate.sh](regenerate.sh).

Each stage has a deadline between 10 and 120 seconds. Declared deadlines total
570 seconds, plus 18 seconds of possible termination grace. The wrapper takes
a one-time descendant snapshot; cleanup and OS scheduling can exceed that
budget. It is **not a sandbox or a guaranteed wall-clock bound**. See
[bound.clj](bound.clj) and [run.sh](run.sh).

Logs, commands, statuses, timing, generated C and binaries stay in scratch.
The driver retains failed evidence and does not reuse it. Raw logs contain
local paths and SHOULD be sanitized before sharing.

## Observed results

One fresh archive-to-tests run passed on Darwin 25.6.0 ARM64, Bash 3.2.57,
Babashka 1.13.225, Apple Clang 21.0.0, and bootstrap Gambit v4.9.8 build
20260809131432. This table records that run; it is not a cross-platform claim.
The scripts verify the listed result markers in the named scratch logs.

| Check | Observed result | Reproduction evidence |
|---|---|---|
| Interpreter policy harness | 70 passed, 0 failed | `runtime-tests.log` |
| Compiled policy harness | 70 passed, 0 failed | `accepted-execute.log` |
| Static positive compiler cases | 7 passed | `accepted-execute.log`, `STATIC-PASS` |
| Compiler rejection cases | 7 rejected with expected diagnostic and no output C | `reject-*.log`, `policy.log` |
| Evaluator lowering and recovery | 4 passed, 0 failed | `lowering.log` |
| Stress harness | 30 interpreted + 30 compiled-harness checks passed | `stress-interpreted.log`, `stress-execute.log` |
| Compiler `do` controls | 32, 64 and 65 bindings compile and run; all values are one | `do-*-execute.log` |
| Link escaping | 9 passed, 0 failed | `escape.log` |
| Compiler extrema | 6 passed, 0 failed, in rebuilt compiler process | `extrema.log` |

The **158 policy assertions** comprise the first five rows. The 70 assertions
in the compiled harness still use `eval` for source-form checks; they are not
70 independent static compiler boundary tests. The seven static positive and
seven negative compiler cases supply separate compiler coverage. See
[tests.sh](tests.sh), [generate-tests.scm](fixtures/generate-tests.scm), and
[runtime-tests.scm](fixtures/runtime-tests.scm).

Stress covers keyword operand accounting, rejection and recovery, live rest
arguments through GC, repeated rejection/GC, dynamic-wind cleanup, continuation
reentry, internal link escaping, and macro input. Several exercises repeat
100 times; this is finite testing, not a proof. See
[stress.scm](fixtures/stress.scm) and [checks.sh](checks.sh).

All nine stages exited zero; whole-second stage durations summed to 45 seconds
on this host (`stages.log`). **Configure nevertheless printed
`PKG_PROG_PKG_CONFIG: command not found`.** Its exit status was zero; the driver
records the unresolved warning in `configure-warning.txt` and applies no repair.
The successful focused tests do not establish a clean configure or broad
Gambit test-suite result.

Bash syntax checks and ShellCheck passed for all five scripts. Driver refusal
checks covered invalid arguments, existing scratch, missing/wrong bootstrap,
and bad archive hash. Supervisor probes covered success, nonzero child exit,
invalid input, deadline exit 124, and one TERM-resistant descendant case.
These local packaging probes do not expand the runtime coverage above.

## Review questions

1. **Policy boundary:** Should public source calls and internal runtime calls
   share one global `##apply` limit? A macro discarding 65 syntax operands is
   currently rejected; see the macro cases in [stress.scm](fixtures/stress.scm).
2. **Generated-call admission:** Where should checks run after normalization
   and lambda lifting? This patch does not guard every compiled call. The
   successful 65-binding `do` control intentionally demonstrates that source
   operand count is not a universal internal-call or frame bound. Relevant
   upstream code: [`normalize` and lifting in `_ptree2.scm`](https://github.com/gambit/gambit/blob/2228e4d163582733a3a67a5efcb22f8ebe93c02b/gsc/_ptree2.scm),
   [`jump-layout` in `_front.scm`](https://github.com/gambit/gambit/blob/2228e4d163582733a3a67a5efcb22f8ebe93c02b/gsc/_front.scm).
3. **Memory contract:** Argument limits are not frame-size or allocation
   bounds. This patch leaves section geometry, stack/heap allowances, and
   frame limits unchanged. No reduced allocator, all-path memory-safety proof,
   or exact linked-artifact admission audit is supplied. Compare
   [`lib/mem.h`](https://github.com/gambit/gambit/blob/2228e4d163582733a3a67a5efcb22f8ebe93c02b/lib/mem.h)
   and [`gsc/_t-c-1.scm`](https://github.com/gambit/gambit/blob/2228e4d163582733a3a67a5efcb22f8ebe93c02b/gsc/_t-c-1.scm)
   with the limited patch file list.
4. **Compatibility:** What other unbounded internal callers, macro expanders,
   dynamic error paths, or numeric edge cases need coverage before adopting
   this policy? The two internal fixes preserve the covered behavior, not a
   claim that all internal uses are safe.

## Explicit non-results

No hardware was flashed or exercised for this package. It proves neither
ESP32 memory fit nor a working on-device REPL. It does not compile all of Jolt
to native C, alter the supported Jolt targets, or run broad Jolt/Gambit CI.
It is a reviewable host experiment, deliberately independent of those gates.

## Licensing

See [NOTICE.md](NOTICE.md) for provenance and license boundaries. Gambit patch
material is provided under Apache-2.0, with [the license](LICENSE-Gambit.txt)
and upstream copyright notices retained. New package scripts, fixtures and
review documentation use the repository's [EPL-2.0 license](../../LICENSE).
