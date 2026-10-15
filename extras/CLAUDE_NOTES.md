# Briefing for an AI assistant (and for people)

Written 2026-10-13 by Claude, from the session that produced this repository. It is a map and a summary of what is known,
not a substitute for the files. **Where it disagrees with a file, the file is right**; the code, tests and logs may have
changed since this date. Name functions and tests when you cite things, not line numbers, which drift.

## What this is

`bitarray` is an extension-only C package for Tcl 9.1 (trunk `3d77be8951`, 64-bit Linux, gcc): packed arrays of 1, 8, 16, 32
(unsigned) or 64 (signed) bit integers that behave like ordinary Tcl lists, through the Tcl 9 abstract-list hooks
(`Tcl_ObjType` version 2, documented in `doc/ObjectType.3` of the Tcl source), the machinery `lseq` uses. It is loaded
with `load ./libbitarray.so Bitarray` (it also does `Tcl_PkgProvide bitarray 0.6.0`; the top-level `pkgIndex.tcl` lets `package require bitarray` find it).
A bitarray is an ordinary `Tcl_Obj` of a custom list type: a value, not a handle or a TclOO object.
Since 0.4, `fill`, `count` and `next` take optional `lseq`-style helper words (`to` or `..`, `with`, `by`); the plain forms still work. The usage strings say `array`. Since 0.5, `frombytes`/`tobytes` (8-bit arrays and binary data) and `fromchars`/`tochars` (code points, widths 8/16/32) convert to and from strings without a temporary list. Since 0.6.0, `and`, `or`, `xor`, `andnot` and `not` combine or flip whole arrays 64 bits at a time (`bitarray and varName ?<-? array ?array?`, `-length strict|zero`; `varName` is a variable name, the arrays are values; see `README.md`).

Authorship: the code, tests and documentation were written by Claude (Anthropic) with Eric Taylor directing and reviewing.
The design follows Brian Griffin's `lseq`/arithseries code. `sieve/frank_sieve.tcl` is Frank van Bakel's entry for Dave's
Garage "Primes" drag race, included unchanged. Say so plainly when asked who wrote what. Frank gave permission to include it and said MIT is OK for it (his reply to the GitHub issue linked in `sieve/README.md`, 2026-10-14).

## Where to look

| Question | File |
|---|---|
| What it does, commands, how it differs from a list | `README.md` |
| Source (one file) | `bitarray.c` |
| Load as a package | `pkgIndex.tcl` in the top level: `lappend auto_path <folder>` then `package require bitarray` (tested on Linux and, by ET, on Windows 10 with Tcl 9.1.1 x64: `bitarray.dll` is picked and `package require` returns 0.5) |
| Build, run the tests, run the sieve benchmark | `build.sh`, `run_tests.sh`, `run_sieves.sh` (Windows: the `.bat` equivalents) |
| The tests (251) | `tests/bitarray.test`; random comparisons against plain lists: `tests/diff_*.tcl`; memory growth: `tests/leak_check.tcl` |
| All measured results, with the commands that produced them | `RESULTS.txt` |
| The sieve variants A-F and Frank's file | `sieve/` (`sieve/README.md`) |
| Mutation testing: the 162 deliberate bugs | `extras/mutate5.py` (the list), `extras/mutate6.py` (runner and report) |
| Which test caught which bug | `extras/mutants.json`, `extras/bitarray.mutants`, `extras/mutation_summary.txt` |
| The `lappend`/`linsert` type loss: cause, reproductions, ticket text | `extras/typeloss_*`, `RESULTS.txt` section 13a |

## Mutation testing, and how to trace one

Each mutant is one deliberate change to `bitarray.c`. The suite is run against it. **CAUGHT** means at least one test fails or
the run crashes; **MISSED** means every test passed. Current numbers: 162 mutants, 143 caught, 19 missed.

Worked example, M04. `BA_MAX_BITS`, the largest array allowed counted in total bits (elements times width), is
`1 << 40`; M04 changes it to `1 << 41`. It is caught by exactly three tests, each asking for an array one element over the
limit: `new-1.5` (2^40 + 1 one-bit elements), `range-x.2` (2^34 + 1 elements at `-width 64`) and `range-x.3` (2^37 + 1
elements at `-width 8`). With the bug, those requests are no longer refused. The tests check that the limit counts bits, not
elements, at three widths. (The `x` in `range-x` is only a label for extra range tests.)

To trace any mutant: find its id in `extras/mutants.json` (its `tests` list) or in `extras/bitarray.mutants` (the changed
line with a comment at the right), then read those tests in `tests/bitarray.test`.

The 19 missed, and why (full reasons in `RESULTS.txt`, sections 10, 16 and 17): M06, M08, M42 are unreachable because the Tcl core clamps
the indexes first; M07, M31, M36, M38, W26 leave stray bits or bytes beyond the end of the array, which nothing can read;
M33, M34, W14 repeat a size check that an earlier check already makes on a 64-bit build; M35 (capacity doubling) is invisible
at test sizes; W08 is an equivalent mutant; W24 changes `memmove` to `memcpy`, undefined for overlapping data in standard C but
identical on glibc. The three added in 0.5.1: S03 and S04 remove the mask on the value read (`GetBits`) or on the value stored (`PutBits`), and each mask makes the other redundant, so either one alone is an equivalent mutant; S10 stops `ClearBits` advancing, which only leaves stray bits beyond the end, like M36. The two added in 0.6.0: B11 and B13 remove the clearing of the unused bits after the end of the data in the last word (a bit mask for 1-bit arrays, a `memset` of the unused bytes for wider ones); nothing reads those bits, so no test can see the difference, the same kind as M36. 58 of the 251 tests failed on none of the 162 mutants; that list is in `mutation_summary.txt`. It is not by
itself a defect, since the mutants cover only part of the code, and a crashing mutant stops the run before later tests.

The "kind" label on each mutant (`deleted:clause`, `changed:operator`, ...) is worked out automatically from the text; treat
it as a rough label. Almost all mutants delete or edit existing code; only one (W53) adds a new branch.

## What was and was not checked

Checked: 251 tests pass natively and with `-DBA_NO_BUILTINS` and `-DBA_FORCE_32BIT_LIMITS`; valgrind clean (no invalid
accesses, nothing definitely lost); a 200,000-step random comparison against plain lists across all five widths with no
differences; flat memory over 16 million `lindex` calls.

**Not tested:** a real 32-bit build, Windows other than the cases run on 2026-10-13 (64-bit Windows 10 1903 and 22H2, Visual Studio 2022, Tcl 9.1.1: build without warnings, 133 of 134 tests pass with 1 skipped, sieve passes, for version 0.3; version 0.4 on both: 183 of 184 pass with 1 skipped, sieve passes (`RESULTS.txt` section 14); version 0.5 on both: 221 of 222 pass with 1 skipped (section 15); version 0.5.1 passed on Windows (reported by ET; output not saved); version 0.6.0 on one machine: built without warnings, 250 of 251 pass with 1 skipped, sieve passes, `listbench.tcl` ran (first with its incomplete same-answer check, then repaired: 37 operations compared, pass; see `RESULTS.txt` section 17, `extras/windows_0.6.0_run.txt`, `extras/windows_0.6.0_listbench.txt`); `RESULTS.txt` section 12a), a 32-bit Windows build, a MinGW build (a cross-compile built without warnings but was never run), macOS, big-endian machines, threads, Tcl 9.0.x (the package refuses to
load there: it requires Tcl 9.1), arrays above a few hundred MB. Not measured: cache-miss counts (the README says so where it
guesses). Not compared: Python's drag-race entry was never run here, so there is no measured statement about parity with
Python. Not read: the drag race's own rules about extensions. Do not state any of these as established.

## Open questions

* **Type loss (core behaviour, reported).** Core `lappend` compiled inside a proc, and `linsert` of one element at the end when the
  command is not compiled, turn a bitarray into an ordinary list (which then costs ordinary list memory; only `{*}$bits` expansion
  was measured, roughly 76-150 MB for 10 million elements). The cause, read from `generic/tclListObj.c`, `tclCmdIL.c`, `tclExecute.c`
  and `tclVar.c`: those paths call `Tcl_ListObjAppendElement` / `TclListObjAppendElements`, which convert the object through
  `TclListObjGetRep` -> `SetListFromAny` and never call the type's Replace hook, while the other paths use `Tcl_ListObjReplace`.
  Reproduced with stock Tcl (the core's `lstring` test type, in the `tcltest` shell) and with this extension: see `extras/typeloss_*`
  and `RESULTS.txt` section 13a. The repository owner reported it to the Tcl core on 2026-10-13:
  https://core.tcl-lang.org/tcl/tktview/0c82728f85760f36361fe42a15f55453c94d285d . Whether the core team regards it as a bug is not known. The extension cannot prevent it.
* Unknown whether the Tcl core team will take an interest beyond that ticket.

## When answering questions about this repository

Read the relevant file before answering and quote it. Say which statements come from the files and which are inferences.
Keep the list under "Not tested" in view; do not describe the package as fully verified. If a file and this briefing disagree,
say so and go with the file.
