# Briefing for an AI assistant (and for people)

Written 2026-10-13 by Claude, from the session that produced this repository. It is a map and a summary of what is known,
not a substitute for the files. **Where it disagrees with a file, the file is right**; the code, tests and logs may have
changed since this date. Name functions and tests when you cite things, not line numbers, which drift.

## What this is

`bitarray` is an extension-only C package for Tcl 9.1 (trunk `3d77be8951`, 64-bit Linux, gcc): packed arrays of 1, 8, 16, 32
(unsigned, or signed as -8, -16, -32) or 64 (signed) bit integers that behave like ordinary Tcl lists, through the Tcl 9 abstract-list hooks
(`Tcl_ObjType` version 2, documented in `doc/ObjectType.3` of the Tcl source), the machinery `lseq` uses. It is loaded
with `load ./libbitarray.so Bitarray` (it also does `Tcl_PkgProvide bitarray 0.8.5`; the top-level `pkgIndex.tcl` lets `package require bitarray` find it).
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
| No Tcl 9.1 installed: clone, build, test from nothing | this file, "Setting up from nothing" |
| Walk through the code | this file, "Walking someone through the code", and the interactive `extras/bitarray_stepper.html` |
| The tests (315) | `tests/bitarray.test`; random comparisons against plain lists: `tests/diff_*.tcl`; memory growth: `tests/leak_check.tcl`; size-limit and out-of-memory paths: `tests/faultinject.test` (test build only, run by `extras/coverage.sh`) |
| All measured results, with the commands that produced them | `RESULTS.txt` |
| The sieve variants A-F and Frank's file | `sieve/` (`sieve/README.md`) |
| Mutation testing: the 206 deliberate bugs | `extras/mutate5.py` (the list), `extras/mutate6.py` (runner and report) |
| Which test caught which bug | `extras/mutants.json`, `extras/bitarray.mutants`, `extras/mutation_summary.txt` |
| The `lappend`/`linsert` type loss: cause, reproductions, ticket text | `extras/typeloss_*`, `RESULTS.txt` section 13a |

## Setting up from nothing (a fresh sandbox, no Tcl 9.1)

**If the clone, the package install or any command is refused:** in claude.ai the person may have two settings off, under Settings > Capabilities: *Code execution and file creation* and *Allow network egress* (GitHub is on the allowed list; on a Team or Enterprise plan an organization owner sets them under Organization settings > Capabilities; Free accounts have both, with lower usage limits). Tell them which one, and ask them to turn it on and say so; the exact names may change, see Claude's help article "Create and edit files with Claude".

Tested on 2026-10-15 in an empty directory on 64-bit Linux with gcc, against the then-current GitHub mirror of trunk
(`7e6fd02`, reports itself as 9.1.1): both routes below built without errors and passed all 259 tests. The measurements in
this repository were made on an earlier trunk (`3d77be8951`, a Fossil id; the GitHub mirror uses different ids), so a newer
trunk can differ. Say which revision you used (`git log -1`) when you report numbers.

The Claude sandbox reaches package registries and GitHub, not most other sites, so get Tcl from GitHub, not from core.tcl-lang.org.
Needs `git`, `gcc` and `make`. It takes about 40 seconds. `W` below is **not** a literal name: replace it by the full path of any empty directory you made.
Unpack the repository ZIP inside `W` too, so that it ends up as `W/bitarray` (the ZIP has a top-level `bitarray/` folder).

    cd W
    git clone --depth 1 https://github.com/tcltk/tcl tcl
    mkdir build && cd build
    ../tcl/unix/configure --disable-shared && make -j4
    export TCL_LIBRARY=W/tcl/library      # only if tclsh says it cannot find init.tcl; it was not needed in a later test
    echo 'puts [info patchlevel]' | ./tclsh     # must print 9.1.x; 9.0.x cannot load the package

Route A, straight from the build directory (nothing installed):

    cd W/bitarray
    ./build.sh --include W/tcl/generic --stub W/build/libtclstub.a
    sh ./run_tests.sh --tclsh W/build/tclsh      # expect: Total 315 Passed 309 Skipped 6 Failed 0

Route B, installed into a prefix:

    mkdir b2 && cd b2 && ../tcl/unix/configure --prefix=W/inst && make -j4 && make install
    cd W/bitarray
    ./build.sh --tcl-prefix W/inst
    sh ./run_tests.sh --tclsh W/inst/bin/tclsh9.1     # the installed shell needs no TCL_LIBRARY
    # (an unpacked repo has no libbitarray.so until build.sh has run; delete a stale one if you copied a built tree)

Notes:
* `build.sh --tclsh W/build/tclsh` alone does **not** work for a build directory outside the source tree: the shell does not
  know where its headers are, and the script says so. Use `--include` and `--stub` (route A) or an installed prefix (route B).
* `--tcl-tree` expects the in-tree layout (`generic/tcl.h` and `unix/libtclstub.a` under one directory); use it only if you
  ran `configure` inside `tcl/unix` itself.
* Shell wrapper used in the sessions that produced this repository, which always sets the library path:
  `TCL_LIBRARY=W/tcl/library exec W/build/tclsh "$@"`.
* The benchmark and the mutation tests take the same shell: `W/run.sh extras/listbench.tcl both -verbose -lib ./libbitarray.so`;
  mutation needs `BITARRAY_INCLUDE`, `BITARRAY_STUBLIB` and `BITARRAY_TCLSH` set (see `extras/mutate6.py`) and takes about
  35 minutes. Do it once, before a release, not after each change.
* Not tried: a shared-library Tcl build (`--enable-shared` is the default of `configure`; the tests above used `--disable-shared`),
  Windows (see `README.md`), and trunk revisions other than the two named here.

## Walking someone through the code

**Show the simulator, do not only describe it.** `extras/bitarray_stepper.html` is one self-contained file (about 250 KB, no network requests, no other files needed), so it can be displayed anywhere HTML can: in claude.ai, send or publish the file so that it opens in the side panel (as a rendered HTML file or as an artifact); in Claude Code, open it in a browser. Try that before telling the person you cannot. If it really cannot be shown, give them the live copy: https://rocketship88.github.io/tcl-bit-array-extension/extras/bitarray_stepper.html

If you have built and tested the package (see above) you can walk a person through `bitarray.c` (about 1,670 lines, one
file). **`extras/bitarray_stepper.html` is an interactive version of this walkthrough**: the person opens it in a browser, picks a
command and steps through the core call path, the hook reached, and the bits and words as they change, and can press "Show code"
to see the `bitarray.c` code for the step. It embeds `bitarray.c`, the whole of Tcl's `tcl.h` and the declarations of the Tcl functions `bitarray.c` calls, so a double-click on a Tcl name shows its definition; the names that can be double-clicked are drawn bold in colour (functions, macros, types; a "Color" check box turns the colouring off; a "Fold" check box, off by default, collapses the outermost switch cases and if / else branches, found by brace depth in `foldRegions`; loops are not folded). `python3 extras/embed_source.py --check` tells whether the page is
current, whether every `bitarray.c` function the page names still exists, and whether every Tcl name `bitarray.c` uses can be shown. If `bitarray.c` starts using a new Tcl function, run `python3 extras/make_tcl_refs.py --tcl-generic /path/to/tcl/generic` (a Tcl source tree) and then `embed_source.py`.
**Whenever you change `bitarray.c`, keep the page in sync:** run `python3 extras/embed_source.py`, then check the scenes of the commands you touched (the call paths, the step texts, the model that draws the bits), update them, and run `--check` again. The check only catches missing names, not changed behavior. Its call paths were written from the Tcl source (GitHub mirror `e36db33`) and `bitarray.c` 0.6.0, and its drawings come
from its own small model, not from a running Tcl. Ask what they want to know first; if they just say "walk me through it", this order works. Read the code before you
describe it, and quote it.

1. **The idea.** The header comment of `bitarray.c`: a bitarray is an ordinary `Tcl_Obj` of a custom list type, so `llength`,
   `lindex`, `lset`, `lrange`, `foreach` and so on work on it through the Tcl 9 abstract-list hooks (`Tcl_ObjType` version 2).
   `doc/ObjectType.3` in the Tcl source describes the hooks.
2. **The data.** `struct BitArr` (length, words in use, words allocated, width, the shared 0 and 1 values, a lazily built
   element vector, and the word storage) and `GetElem`/`PutElem`, `NewRep`, `FreeRep`,
   `WrapRep`: how an element of width 1, 8, 16, 32 or 64 is stored and read.
3. **The hooks.** Under "type hooks": `BALength`, `BAIndex`, `BASlice`, `BAReverse`, `BAGetElements`, `BASetElement`,
   `BAReplace` (with its helpers `GetBits`, `PutBits`, `ClearBits`, `MoveElems`), `BAInOper`, `BAUpdateString`, `BADup`, `BAFree`.
   Which core command reaches which hook is the key to the performance story in `performance_analysis.md`.
4. **The commands.** `BitarrayCmd` (one dispatcher, `Tcl_GetIndexFromObj` plus a `switch`): `new`, `newfrom`, `width`, `is`,
   `version`, `frombytes`/`tobytes`, `fromchars`/`tochars`, `count`, `next`, `fill`.
5. **The bitwise operations.** `BitOpCmd`, `BitOpWords` (64 bits at a time), `MaskTail`, `BitOpCompat`, `IsArrow`.
6. **The tests that pin each piece down.** `tests/bitarray.test` (test names are grouped by command: `range-`, `rev-`,
   `shift-`, `bitop-` and so on), the random comparisons against plain lists in `tests/diff_*.tcl`, and, for how good the
   tests are, "Mutation testing" below.

Good places to slow down, because they are where mistakes were found or are easiest to make: the unused bits past the end
of the last word (`MaskTail`, `ClearBits`), `MoveElems` for overlapping moves, the 32-bit size limits (`BA_MAX_BITS`),
and what happens when a bitarray is shared (`Tcl_IsShared` then `Tcl_DuplicateObj`, which calls `BADup`).

## Mutation testing, and how to trace one

Each mutant is one deliberate change to `bitarray.c`. The suite is run against it. **CAUGHT** means at least one test fails or
the run crashes; **MISSED** means every test passed. Current numbers: 210 mutants, 188 caught, 22 missed (one full run on 0.8.1, extras/mutation_round14.txt; the same 22 missed as in rounds 12 and 13; M16 was retired in 0.7.0 because the code it mutated was replaced by `HasBit`, whose mutants are H01 to H10).

Worked example, M04. `BA_MAX_BITS`, the largest array allowed counted in total bits (elements times width), is
`1 << 40`; M04 changes it to `1 << 41`. It is caught by exactly three tests, each asking for an array one element over the
limit: `new-1.5` (2^40 + 1 one-bit elements), `range-x.2` (2^34 + 1 elements at `-width 64`) and `range-x.3` (2^37 + 1
elements at `-width 8`). With the bug, those requests are no longer refused. The tests check that the limit counts bits, not
elements, at three widths. (The `x` in `range-x` is only a label for extra range tests.)

`bitarray.c` carries short side comments (`   // ...`, spaces before them, nothing on obvious lines; added 2026-10-17 without changing the code). A mutant's text in `mutate5.py` is written without them: `mutate6.py` finds each pattern with comments allowed at the line ends and keeps the comment on the lines a mutant leaves alone (the `adapt` function). When adding a comment to a line a mutant touches, nothing needs changing; when adding a new mutant, write its text without the comments.

To trace any mutant: find its id in `extras/mutants.json` (its `tests` list) or in `extras/bitarray.mutants` (the changed
line with a comment at the right), then read those tests in `tests/bitarray.test`.

The 22 missed, and why (full reasons in `RESULTS.txt`, sections 10, 16 and 17): M06, M08, M42 are unreachable because the Tcl core clamps
the indexes first; M07, M31, M36, M38, W26 leave stray bits or bytes beyond the end of the array, which nothing can read;
M33, M34, W14 repeat a size check that an earlier check already makes on a 64-bit build; M35 (capacity doubling) is invisible
at test sizes; H05 (the mask on the last word when `HasBit` looks for a 1) is an equivalent mutant, because shrinking an array clears the bits past its end; W24 changes `memmove` to `memcpy`, undefined for overlapping data in standard C but
identical on glibc. The three added in 0.5.1: S03 and S04 remove the mask on the value read (`GetBits`) or on the value stored (`PutBits`), and each mask makes the other redundant, so either one alone is an equivalent mutant; S10 stops `ClearBits` advancing, which only leaves stray bits beyond the end, like M36. The two added in 0.6.0: B11 and B13 remove the clearing of the unused bits after the end of the data in the last word (a bit mask for 1-bit arrays, a `memset` of the unused bytes for wider ones); nothing reads those bits, so no test can see the difference, the same kind as M36. In the last full run (206 mutants, 282 tests) the tests that failed on none of the mutants are listed in `mutation_summary.txt`. It is not by
itself a defect, since the mutants cover only part of the code, and a crashing mutant stops the run before later tests. The two added after the 0.6.0 speed changes: S13 (the first partial chunk of the left move in `MoveElems` not shortened) and R05 (the last unaligned `lrange` chunk not shortened) only change bits past the moved range or the unused bits of the last word, which nothing can read, the same kind as M36 and B11; the other new ones, R01 to R04 and R06 to R08, are caught. G03 (the signed parse does not mask a negative value to its width) is an equivalent mutant: every user of the parsed value (`PutElem`, `memset`, `NextWide`, `ElemWide`) already truncates it to the width.

The "kind" label on each mutant (`deleted:clause`, `changed:operator`, ...) is worked out automatically from the text; treat
it as a rough label. Almost all mutants delete or edit existing code; only one (W53) adds a new branch.

## What was and was not checked

Checked: 315 tests pass natively and with `-DBA_NO_BUILTINS` and `-DBA_FORCE_32BIT_LIMITS`; valgrind clean (no invalid
accesses, nothing definitely lost); a 200,000-step random comparison against plain lists across all five widths with no
differences; flat memory over 16 million `lindex` calls.

**Not tested:** a real 32-bit build, Windows other than the cases run on 2026-10-13 (64-bit Windows 10 1903 and 22H2, Visual Studio 2022, Tcl 9.1.1: build without warnings, 133 of 134 tests pass with 1 skipped, sieve passes, for version 0.3; version 0.4 on both: 183 of 184 pass with 1 skipped, sieve passes (`RESULTS.txt` section 14); version 0.5 on both: 221 of 222 pass with 1 skipped (section 15); version 0.5.1 passed on Windows (reported by ET; output not saved); version 0.6.0 on one machine: built without warnings, 250 of 251 pass with 1 skipped, sieve passes, `listbench.tcl` ran (first with its incomplete same-answer check, then repaired: 37 operations compared, pass; see `RESULTS.txt` section 17, `extras/windows_0.6.0_run.txt`, `extras/windows_0.6.0_listbench.txt`); version 0.7.0 on one machine (2026-10-16): 282 tests, 281 passed, 1 skipped, sieve passes, `listbench.tcl` ran with 42 operations compared (`extras/windows_0.7.0_run.txt`); `RESULTS.txt` section 12a), a 32-bit Windows build, a MinGW build (a cross-compile built without warnings but was never run), macOS, big-endian machines, threads, Tcl 9.0.x beyond the one try on 9.0.5 on 2026-10-16 (276 of 282 tests passed with the version check relaxed; the 6 failures all involve `lappend`, which the 9.0 core handles by converting the object to a plain list in almost every context (9.1: only in a compiled proc; extras/typeloss_ticket.md); see `RESULTS.txt` section 18) (the package refuses to
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
