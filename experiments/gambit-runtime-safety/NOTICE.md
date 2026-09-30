# Provenance and licenses

The patch targets Gambit revision
[`2228e4d163582733a3a67a5efcb22f8ebe93c02b`](https://github.com/gambit/gambit/tree/2228e4d163582733a3a67a5efcb22f8ebe93c02b).
Gambit is Copyright 1994–2026 by Marc Feeley, all rights reserved. Individual
source-file copyright notices remain in the patched files.

Gambit's own [license section](https://github.com/gambit/gambit/blob/2228e4d163582733a3a67a5efcb22f8ebe93c02b/doc/gambit.txi#L20020-L20025)
offers the choice of Apache License 2.0 or LGPL 2.1. This package distributes
the Gambit patch material, including the new shared policy files, under the
Apache-2.0 option. [LICENSE-Gambit.txt](LICENSE-Gambit.txt) is copied from the
pinned source archive. The patch adds prominent experimental modification
notices to each changed or added source file.

The experimental changes are the 64-slot source/application policy, the
pre-push `##apply` check, compiler extrema folds, and list-based link-string
concatenation. They are not presented as endorsed upstream Gambit changes.

The reproduction scripts, test fixtures, supervisor and review documentation
are Jolt experimental work under the repository's [EPL-2.0 license](../../LICENSE).
That license statement does not relicense the Gambit patch or supplied archive.
No Gambit binaries, generated C, source archive, or local build logs are shipped
in this package.
