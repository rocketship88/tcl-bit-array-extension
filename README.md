# bitarray

Packed arrays of small integers for Tcl 9.1 that look and behave like ordinary Tcl lists.

```tcl
load ./libbitarray.so Bitarray

set flags [bitarray new 1000000 1]; puts [llength $flags]   ;# one million 1-bit flags, all 1 (125 KB; a list needs 8 MB or more)
lset flags 5 0; puts [lrange $flags 0 9]                    ;# plain list commands work: lindex, lset, lrange, lreverse, lreplace,
                                                            ;#   linsert, lappend, foreach, "in", lsort, lsearch, join, {*}...
bitarray fill flags 3 end 0 3            ;# bulk operations that run in C
puts [bitarray count $flags]             ;# number of 1 bits
puts [bitarray next $flags 0 0]          ;# index of the first 0
```

Pasting this into an interactive `tclsh`: a bare `set flags [bitarray new ...]` or `lset flags ...` would echo the whole
million-element list, which is why those lines end with a `puts`.

It is an **extension only** (one C file, built against the Tcl stubs library): no change to the Tcl core. It uses the Tcl 9
abstract-list hooks in `Tcl_ObjType` version 2 — the machinery behind `lseq`'s arithmetic series — and is, as far as I know,
the first thing to use that interface's `SetElement` and `Replace` hooks (no type in the Tcl core implements them). To the rest of Tcl a bitarray
is a list, so existing list code works on it unchanged.

> **Who wrote this.** The code, tests and documentation were written by Claude (an AI model made by Anthropic), working
> with Eric Taylor, who directed the work and reviewed it. It is an independent study, not part of Tcl and not an
> official Tcl project. Everything claimed below was measured or tested, except where it says "guess"; what was *not* tested is listed under
> [Limits](#limits-and-what-was-not-tested).

Because an AI wrote it, independent review matters. See [Reviewing it, with or without an AI assistant](#reviewing-it-with-or-without-an-ai-assistant).

## Element widths

The width is chosen when the array is created and cannot change afterwards.

| `-width` | Element | Values |
|---|---|---|
| `1` (default) | 1 bit | `0` and `1` |
| `8` | 8 bits | `0` … `255` (unsigned) |
| `16` | 16 bits | `0` … `65535` (unsigned) |
| `32` | 32 bits | `0` … `4294967295` (unsigned) |
| `64` | 64 bits | `-9223372036854775808` … `9223372036854775807` (signed) |

A value outside the range is an error; nothing is wrapped or truncated.

## Requirements

* **Tcl 9.1 (trunk).** Tested only against trunk revision `3d77be8951` (2026-10-11), which reports itself as 9.1.1. It needs
  `TCL_OBJTYPE_V2`, i.e. the abstract-list hooks. Tcl 8.x cannot work. Tcl 9.0.x was not tried.
* **Headers and the stubs library**: `tcl.h` and `libtclstub.a`, from an installed Tcl or a built source tree.
* A C compiler (`cc`, tested with gcc) and a POSIX `sh`; on Windows, Visual Studio 2022 and `cmd` (see the next section).
* Tested on 64-bit Linux and, with Visual Studio 2022, on 64-bit Windows (see below). Not tested anywhere else.

## Get it, build it, test it

Download the repository as a ZIP (or `git clone`) and unpack it **anywhere**. Nothing depends on where it lives or on
what its neighbours are called. You tell the scripts where your Tcl 9.1 is. No location is built in; if you give nothing,
they look for a Tcl 9 `tclsh` on your `PATH`. They stop with a message if what they find is not Tcl 9.

```sh
cd bitarray            # the unpacked directory (GitHub names it after the repository and branch)
sh ./build.sh     --tclsh /path/to/tcl9.1/bin/tclsh9.1   # makes libbitarray.so next to build.sh
sh ./run_tests.sh --tclsh /path/to/tcl9.1/bin/tclsh9.1
sh ./run_sieves.sh --tclsh /path/to/tcl9.1/bin/tclsh9.1   # optional: the prime-sieve benchmark, see below
```

Expected last line of the tests: `bitarray.test:	Total	222	Passed	222	Skipped	0	Failed	0`

(`sh ./script` works even if unpacking lost the executable bit, which happens when a ZIP is made or unpacked on Windows.)

### On Windows (Visual Studio 2022)

`build.bat`, `run_tests.bat` and `run_sieves.bat` do the same three jobs with Microsoft Visual C. They have been run, by
the repository owner, on two 64-bit Windows 10 machines (versions 1903 and 22H2) with Visual Studio 2022 and a Tcl 9.1.1 built from trunk: the build gave no warnings,
the tests passed (version 0.3: 133 passed, 1 skipped; version 0.4, on both: 183 passed, 1 skipped; version 0.5, which adds the byte and character conversions: 221 passed, 1 skipped, on both) and the sieve passed. A 32-bit build and other Visual Studio versions are untried.
Unpack the ZIP anywhere and, from a Command Prompt, go into the unpacked folder and run the three scripts:

```bat
cd bitarray            rem the unpacked folder (GitHub names it after the repository and branch)
build.bat      --tclsh C:\path\to\tcl9.1\bin\tclsh91.exe     rem makes bitarray.dll next to build.bat
run_tests.bat  --tclsh C:\path\to\tcl9.1\bin\tclsh91.exe
run_sieves.bat --tclsh C:\path\to\tcl9.1\bin\tclsh91.exe     rem optional: the prime-sieve benchmark, see below
```

`build.bat` finds the headers and the stubs library (`include\tcl.h`, `lib\tclstub.lib`) from the shell you name, or from
`--tcl-prefix DIR`, finds Visual Studio itself with `vswhere` if `cl` is not already on your `PATH` (so a plain `cmd` window works; it was run that way on 2026-10-13 and set up `vcvars64.bat` itself), and builds the 64-bit or
32-bit DLL to match the shell. `run_tests.bat` should end with `Total 222  Passed 221  Skipped 1  Failed 0`: one test, which
reads `/proc`, is skipped on Windows. `--help` on each prints the options.

### Telling `build.sh` where Tcl is

Normally one option is enough:

* `--tclsh /path/to/tclsh9.1` — the Tcl 9.1 shell you want to use. The script asks it where it is installed and finds the
  headers and the stubs library itself. Use the same shell for `run_tests.sh`.
* `--tcl-prefix /path/to/tcl9.1` — the directory Tcl was installed into (the one that contains `include/` and `lib/`).
* nothing — if a Tcl 9 `tclsh` is on your `PATH` it is used.

Only if none of those fit (a Tcl you built in its source tree and did not install, or a headers-only layout):
`--tcl-tree DIR` (a built source tree: `DIR/generic/tcl.h` and `DIR/unix/libtclstub.a`), or `--include DIR --stub FILE`
(the directory holding `tcl.h` and the stubs library file `libtclstub.a`; the stubs library is the small static library an
extension links to instead of linking Tcl itself).

Other options: `--cc COMPILER` (default `$CC`, else `cc`), `--out FILE` (default `libbitarray.so` next to the script);
extra compiler and linker flags go in `$CFLAGS` and `$LDFLAGS`. `sh ./build.sh --help` prints all of it.
Nothing is installed anywhere; the only file written is the library.

### `run_tests.sh`

`--tclsh FILE` (use the shell you built against; default: a Tcl 9 `tclsh` on `PATH`, or `$TCLSH`) and
`--lib FILE` (default: `libbitarray.so` next to the script). If your `tclsh` needs `LD_LIBRARY_PATH` (or `TCL_LIBRARY`)
to run, set it in your shell first; the scripts pass the environment through.

### The sieve benchmark (optional)

`run_sieves.sh` (on Windows `run_sieves.bat`, same options) checks and times six prime-sieve programs against one another: Frank van Bakel's Tcl entry in Dave Plummer's
"Primes" drag race (variant A), the same code with a helper proc inlined (B), and four versions that use `bitarray` (C–F).
Frank's file is his work; it is included unchanged as `sieve/frank_sieve.tcl` (see `sieve/README.md` for where it comes from
and its licensing situation).

```sh
sh ./run_sieves.sh --tclsh /path/to/tcl9.1/bin/tclsh9.1        # Linux
```

```bat
run_sieves.bat --tclsh C:\path\to\tcl9.1\bin\tclsh91.exe       rem Windows
```

Build first (`build.sh` or `build.bat`); the sieve loads the library that build made. (`--sieve FILE` tests another copy of his file instead.)

It first checks that every variant finds the right number of primes (and the identical list of primes) at limits 11 up to
1,000,000, then times one full pass at 1,000,000 (best of three, 1.5 s each). It takes about a minute, writes only a
temporary file, and ends with `RESULT: PASS` or `RESULT: FAIL`.

## Commands

Everything is the one command `bitarray`. Anything else you do to a bitarray is an ordinary list command.

The examples below use two arrays, set up once:

```tcl
set a [bitarray newfrom {1 0 1 1 0 1 1 1}]            ;# a -> {1 0 1 1 0 1 1 1}
set w [bitarray newfrom {0 7 0 9} -width 8]           ;# w -> {0 7 0 9}  (8-bit elements)
```

In the synopses and examples below:

* `array` is a bitarray **value**, for example `$a` or the result of `bitarray new 8`, in the way that `list` is a list value in
  `lindex list index`. It is not a variable name.
* `varName` is the **name** of a variable that holds a bitarray, written without a `$`, as in the Tcl manual pages for `lset`. Only `fill` takes one, because it
  changes the array in place; `fill $a ...` is an error (`can't read "1 0 1 ...": no such variable`).
* `?...?` marks an optional part. `size`, `first`, `last`, `start` and `step` are integers; the index arguments `first`, `last` and
  `start` also accept `end` and `end-N`.
* `value` is an integer that fits the width (see the limits below).
* `data` is binary data (a byte array, or a string whose characters are all 0 to 255); `string` is any text.
* `to` (or `..`), `with` and `by` are optional helper words, as in `lseq 5 to 50 by 5`. They only make a command easier to read; leaving them out
  gives the same result, and the plain forms such as `fill b 0 end 0 2` still work.
* `=>` shows what a command returns. Every example was run.
* `->` shows what a variable holds: `a` and `w` above, and, for `fill`, which returns nothing, the array in `varName` after
  completion.

Errors, such as a bad index or a value that does not fit, are ordinary Tcl errors; no command returns a status code. Examples
that do not mention `$a` or `$w` create their own arrays. With no `value` given, `count` and `next` work on non-zero elements.

| Command | Meaning and examples |
|---|---|
| `bitarray new size ?value? ?-width w?` | **Returns** a new bitarray of `size` elements, all `value` (default 0). `-width` may come before or after `value`.<br>`bitarray new 4` => `0 0 0 0`<br>`bitarray new 4 7 -width 8` => `7 7 7 7`<br>`bitarray new 3 -width 16 500` => `500 500 500` |
| `bitarray newfrom list ?-width w?` | **Returns** a new bitarray packed from a list of integers.<br>`bitarray newfrom {200 5 255} -width 8` => `200 5 255` |
| `bitarray width array` | **Returns** the element width in bits: `1`, `8`, `16`, `32` or `64`.<br>`bitarray width [bitarray new 3]` => `1`<br>`bitarray width [bitarray new 3 -width 16]` => `16` |
| `bitarray is value` | **Returns** `1` if `value` currently has the bitarray representation, `0` if not (any value is accepted).<br>`a` -> `{1 0 1 1 0 1 1 1}`<br>`bitarray is $a` => `1`<br>`bitarray is {1 0 1}` => `0` |
| `bitarray count array ?first ?to? last ?with? ?value??` | **Returns** the number of elements equal to `value`, or the number of non-zero elements if no `value`; whole array or an index range (`end-N` allowed). `value` needs a range. For 1-bit arrays without `value` this is a popcount.<br>`a` -> `{1 0 1 1 0 1 1 1}`<br>`bitarray count $a` => `6`<br>`bitarray count $a 0 3 1` => `3`<br>`bitarray count $a 4 end 0` => `1`<br>`bitarray count $a 2 end-1 1` => `4`<br>`bitarray count $a 0 to 3 with 1` => `3`<br>`bitarray count $a 4 .. end with 0` => `1`<br>`w` -> `{0 7 0 9}`<br>`bitarray count $w` => `2` (value omitted means != 0) |
| `bitarray next array start ?with? ?value?` | **Returns** the index of the first element **at or after** `start` equal to `value` (non-zero if omitted), or `-1` if there is none.<br>`a` -> `{1 0 1 1 0 1 1 1}`<br>`bitarray next $a 0 0` => `1`<br>`bitarray next $a 2 0` => `4`<br>`bitarray next $a 5 0` => `-1`<br>`bitarray next $a 2 with 0` => `4`<br>`w` -> `{0 7 0 9}`<br>`bitarray next $w 0` => `1` (value omitted means != 0)<br>`bitarray next $w 0 0` => `0` (element 0 is itself 0) |
| `bitarray fill varName first ?to? last ?with? value ?by? ?step?` | Sets every element from `first` to `last` to `value`, or only every `step`-th one if `step` is given, in the array stored in variable `varName`. **Returns** the empty string; the result is the changed array in `varName`.<br>`set b [bitarray new 10 1]` => `1 1 1 1 1 1 1 1 1 1`<br>`bitarray fill b 0 end 0 2` -> `0 1 0 1 0 1 0 1 0 1`<br>`set b [bitarray new 10 1]` => `1 1 1 1 1 1 1 1 1 1`<br>`bitarray fill b 0 to end with 0 by 2` -> `0 1 0 1 0 1 0 1 0 1`<br>`set c [bitarray new 10 5 -width 8]` => `5 5 5 5 5 5 5 5 5 5`<br>`bitarray fill c 2 5 0` -> `5 5 0 0 0 0 5 5 5 5`<br>`bitarray fill c 2 .. 5 with 0` -> same result |
| `bitarray frombytes data` | **Returns** a new 8-bit array with one element per byte of `data`, without making a temporary list. Characters 0 to 255 are taken as bytes (read a file with `open ... rb`); a character above 255 is an error.<br>`bitarray frombytes "Hi!"` => `72 105 33` |
| `bitarray tobytes array` | **Returns** the elements of an 8-bit `array` as binary data (a byte array), the reverse of `frombytes`. Any other width is an error.<br>`bitarray tobytes [bitarray frombytes "Hi!"]` => `Hi!` |
| `bitarray fromchars string ?-width w?` | **Returns** a new array with one element per character of `string`, holding its code point. `w` is 8 (the default), 16 or 32; a character that does not fit is an error that names it (`character U+20AC at index 1 does not fit in width 8`).<br>`bitarray fromchars "Hi"` => `72 105`<br>`bitarray fromchars "A\u20ac" -width 16` => `65 8364` |
| `bitarray tochars array` | **Returns** the string whose characters have the code points held in a width 8, 16 or 32 `array`, the reverse of `fromchars`. Width 1 and 64 arrays, surrogate codes and values above 0x10FFFF are errors.<br>`bitarray tochars [bitarray newfrom {72 105 8364} -width 16]` => `Hi€` |

To work on a file byte by byte, read it in binary mode and convert it in one step; `lset`, `fill`, `count` and `next` then work on the bytes, and `tobytes` turns the result back into data to write:

```tcl
set fh [open data.bin rb]; set a [bitarray frombytes [read $fh]]; close $fh
puts [bitarray count $a 0 end with 10]            ;# number of newline bytes
lset a 0 74; bitarray fill a 5 to 6 with 46        ;# change single bytes in place
set fh [open out.bin wb]; puts -nonewline $fh [bitarray tobytes $a]; close $fh
```

Load it with `load /full/path/libbitarray.so Bitarray`. There is no `package require` wrapper yet.

A complete example, a sieve of Eratosthenes using the bulk commands:

```tcl
load ./libbitarray.so Bitarray
proc count_primes {max} {                        ;# primes <= max, for max >= 3
    set size [expr {$max / 2 + $max % 2}]        ;# flag i stands for the odd number 2*i+1
    set flags [bitarray new $size 1 -width 8]
    set factor 1
    while {$factor < sqrt($max)} {
        set start [expr {$factor * 3 + 1}]
        if {$start < $size} {
            bitarray fill flags $start end 0 [expr {$factor * 2 + 1}]
        }
        set factor [bitarray next $flags [expr {$factor + 1}]]
        if {$factor < 0} break
    }
    bitarray count $flags                        ;# flag 0 (the number 1) stands in for the prime 2
}
puts [count_primes 1000000]                      ;# 78498
```

## How it differs from a list

All deliberate, and covered by the tests.

* Elements must be integers that fit the width. Any spelling Tcl accepts (`0x10`, `0o17`, `+5`) is accepted and printed back
  in plain decimal. For width 1, `01` is accepted as 1; `10`, `2` and `x` are errors.
* `lset`, `lrange`, `lreverse` and `lreplace` keep the type and the width. Two core commands sometimes do not, and the extension
  cannot prevent it, because the core converts the value before any of the extension's code is called:
  * `lappend` compiled inside a proc (a compiled local variable) turns the bitarray into an ordinary list (same values). At
    global or namespace level (`source`, `eval`, `uplevel`) it keeps the type.
  * `linsert` of exactly one element at the end keeps the type when the command is bytecode-compiled and loses it when it is
    not (for example when it is the main script file given to `tclsh`, or the command name comes from a variable).
  * Cause and a reproduction with stock Tcl only: `extras/typeloss_*` (start with `typeloss_ticket.md`), `RESULTS.txt` section 13a, and Tcl ticket
  https://core.tcl-lang.org/tcl/tktview/0c82728f85760f36361fe42a15f55453c94d285d . Whether the core team considers it a bug is not known.
  * `concat`, `lmap` and similar also give ordinary lists; `bitarray newfrom` packs one again.
* `lset` with a nested index (`lset a 0 0 1`) is an error: elements are not lists.
* `7 in $a` compares string forms, as for a list: `"007" in $a` and `"0x7" in $a` are false.
* The string form is built only if something asks for it (a million 1-bit elements: 2 MB of text).
* Size limit: 2^40 bits (128 GiB) in total on a 64-bit build, 2^30−1 bits on a 32-bit one. A 64-bit-wide array can hold up to
  2^34 elements, an 8-bit one 2^37, a 1-bit one 2^40.
* Growing (`lappend`, `lset` at the end, `linsert`, `lreplace`) edits the array in place and keeps spare capacity, doubling it
  when full, so appending one at a time costs about the same as for a list (80,000 appends: 44 ms against 41 ms; measured at
  global level, where `lappend` keeps the bitarray: inside a proc the first `lappend` converts it to an ordinary list, see above).
* Reading an element returns the shared `0` and `1` objects for those values and a new integer object otherwise;
  `lsort`, `foreach` and `{*}` build a vector of element objects once and drop it on the next change.

## Sieve results

The sieve is a convenient test, not the purpose of the package. One full pass over the odd numbers up to 1,000,000.

Instructions per pass at limit 100,000 (callgrind, so independent of how fast your machine is):

| Variant | Instructions | |
|---|---|---|
| A  Frank's sieve, unchanged | 582,002,161 | |
| B  same, `bit` proc inlined, no extension | 191,532,469 | 3.0x fewer than A |
| C  bitarray, `lindex`/`lset` per bit | 84,045,733 | 6.9x fewer than A |
| D  bitarray, `fill` with step + `next` | 2,076,484 | 280x fewer than A |
| E  as C, 8-bit elements | 83,571,209 | |
| F  as D, 8-bit elements | 1,273,319 | 457x fewer than A |

Measured time per pass at limit 1,000,000 (best of 3), on two stock-clocked desktop machines:

| Variant | i7-4790K | i7-12700K |
|---|---|---|
| A | 695,313 µs (1.44 passes/s) | 394,209 µs (2.54 passes/s) |
| B | 223,324 µs (4.48) | 126,951 µs (7.88) |
| C | 84,082 µs (11.9) | 43,080 µs (23.2) |
| D | 1,573 µs (636) | 808 µs (1,238) |
| E | 83,224 µs (12.0) | 42,353 µs (23.6) |
| F | 1,280 µs (781) | 561 µs (1,783) |

Notes. The 8-bit version (F) uses 1.63x fewer instructions than the 1-bit version (D) but is only 1.23x faster on the
4790K and 1.44x on the 12700K; my guess is cache size (the byte array is 500 KB, the bit array 62 KB), but I did not
measure cache misses. Python's entry in the same drag race, which does the same thing with `bytearray` slice assignment, is
listed at 1,188 passes/s in the results report I was given; that was a different machine, so it is only roughly comparable.
On 64-bit Windows 10 (1903) with Visual C, natively on the same i7-4790K, the same sieve gave A 661,985, B 209,065, C 84,709, D 1,181, E 85,725 and
F 1,217 µs per pass (`RESULTS.txt` section 12a); there D and F are within 3% of each other, unlike on Linux, and I do not know why (a second Windows 10 machine, an i7-12700K, gave A 435,763, B 138,342, C 51,966, D 686, E 52,368, F 568; the same pattern against its Linux numbers: D faster, F equal, the rest slower). The compiler may be part of it, but the OS, C library and Tcl build differ too, so that is not established.
Whether an extension like this counts as a "faithful" entry in Dave's Garage rules I do not know — I did not read them.

## Quality checks

* **222 tests** (`tests/bitarray.test`): option parsing, ranges and error messages at every width, every list command on
  every width, copy-on-write, `fill`/`count`/`next`, word-boundary cases, memory growth.
* **Random comparison against plain Tcl lists** (`tests/diff_*.tcl`): thousands of random operations per run, values and error
  messages compared. Last big run: 5 widths × 10 seeds × 100 iterations × 40 steps, 0 differences.
* **valgrind** on the whole suite: 0 invalid accesses, 0 definite leaks.
* **Memory:** `unset` returns the memory (a 953 MiB array: 960 MB → 6.6 MB resident); building and dropping wide arrays in a
  loop leaves memory flat.
* **Mutation testing** (`extras/mutate5.py`): 123 deliberate bugs inserted into the C code, 109 caught by the tests; the 14
  missed are explained in `RESULTS.txt` (mostly unreachable code, stray bits nobody can read, or checks that are repeated
  elsewhere on a 64-bit build). `extras/bitarray.mutants` is `bitarray.c` with every one of the 123 bugs applied and, beside
  each, the tests that caught it, for reading in a side-by-side compare tool (see `extras/README.md`).
* The same 222 tests also pass with `-DBA_NO_BUILTINS` (portable popcount code) and `-DBA_FORCE_32BIT_LIMITS`.

Details and numbers: `RESULTS.txt`.

## Limits and what was not tested

* Only Tcl 9.1 trunk `3d77be8951` on 64-bit Linux with gcc. **Not tested:** a real 32-bit build (the 32-bit size limits were
  only exercised on a 64-bit build), Windows or MSVC (only 64-bit Windows with Visual Studio 2022 was run; a MinGW cross-compile for 64-bit and 32-bit
  Windows builds without warnings but was never run), macOS, big-endian machines, threads, Tcl 9.0.x, anything above a few
  hundred MB of array.
* No and/or/xor between arrays, no bulk copy, no conversion to or from a binary string yet.
* The code is written to be portable (`#if SIZE_MAX` selects the size limit; `memcpy` for multi-byte elements) but that is
  not the same as tested.

## Reviewing it, with or without an AI assistant

I would like people who are interested in this to read it critically, and to use an AI assistant to do so if that helps.

1. **Give the assistant the repository.** One that can run commands (Claude Code, for example) can clone it, build it and
   run the tests. In a plain chat window, upload the ZIP, or at least `bitarray.c` and `tests/bitarray.test`.
2. **Start it with [`extras/CLAUDE_NOTES.md`](extras/CLAUDE_NOTES.md)**, a map of the files with what was and was not
   checked, written by the assistant that wrote the code.
3. **Things worth asking about:**
   * Read `bitarray.c` function by function (`BAIndex`, `BASlice`, `BASetElement`, `BAReplace`, `MoveElems`, `ParseValue`) for
     memory errors, integer overflow, 32-bit problems and wrong assumptions about the abstract-list hooks in `doc/ObjectType.3`.
   * Pick a mutant in `extras/bitarray.mutants`, find the tests that caught it in `tests/bitarray.test`, and judge whether
     they test what they claim to.
   * The 14 mutants that no test caught are listed in `RESULTS.txt` section 10 with reasons. Are the reasons right?
   * Try to break it: write a test that fails, using `tests/` as a model, or extend the random comparisons in `tests/diff_*.tcl`.
   * Check the explanation of why core `lappend` or `linsert` sometimes turn a bitarray into an ordinary list
     (`extras/typeloss_*`, `RESULTS.txt` section 13a): do the C functions it names do what it says? The extension cannot prevent
     it as far as I can tell; is that right?
   * Port it: a real 32-bit build, Windows, macOS and big-endian machines are all untested.
   * Check every claim in this README against `RESULTS.txt` and the code.
4. **Treat answers as leads, not verdicts.** An assistant can be wrong, as the one that wrote this was more than once while
   it was being built. Check what it says against the files, and run `./run_tests.sh` after any change.

## Troubleshooting

| Message | Cause and fix |
|---|---|
| `I do not know where Tcl 9.1 is` | no Tcl 9 `tclsh` on `PATH`; use `--tcl-prefix`, `--tclsh`, `--tcl-tree` or `--include`/`--stub` |
| `no tcl.h in PREFIX/include` | `--tcl-prefix` must be the directory that *contains* `include/` and `lib/` |
| `no libtclstub*.a …` | the stubs library is missing: install the Tcl development files, or build Tcl in the tree first |
| `… is Tcl '8.6.x'; bitarray needs Tcl 9.1` | wrong Tcl; point at the 9.1 one |
| `… has no TCL_OBJTYPE_V2` | this Tcl 9 predates the abstract-list hooks the extension uses |
| `libtcl9.1.so: cannot open shared object file` | add the directory holding it to `LD_LIBRARY_PATH` |
| `version conflict for package "tcl": have 9.0.x, need 9.1` | the shell running the tests is older than the Tcl the library was built for; use the 9.1 one |
| `undefined symbol: Tcl_…` when loading | the library was built against a different Tcl than the one running it; rebuild with the same one |
| `bad interpreter: …^M` or `\r: command not found` | the scripts got Windows line endings; run `sed -i 's/\r$//' *.sh` (the repository's `.gitattributes` keeps them as LF) |
| `Permission denied` running `./build.sh` | run it as `sh ./build.sh` |

## Repository layout

```
build.sh  run_tests.sh  run_sieves.sh     the three scripts (POSIX sh)
build.bat run_tests.bat run_sieves.bat    the same three for Windows / Visual Studio 2022
bitarray.c                                the extension (one file)
tests/                                    bitarray.test and the random-comparison scripts
sieve/                                    the six sieve variants, the runner, and Frank's sieve unchanged
extras/                                   mutation-testing scripts, logs, and bitarray.mutants (each bug and the tests that caught it)
RESULTS.txt                               measurements, test and mutation details
```

## Credits

Brian Griffin's `lseq` / arithmetic-series implementation in Tcl 9 is the model this follows; the abstract-list hooks it
uses are what make an extension like this possible. The sieve in variant A is Frank van Bakel's (included unchanged); the benchmark idea is Dave Plummer's "Primes" project.
I read the Tcl source (`tclArithSeries.c` and the list code in `tclListObj.c` and `tclExecute.c`) to learn the hook
behaviour, and afterwards cross-checked against `doc/ObjectType.3`; I did not consult the TIP or ask anyone.

## Licence

MIT; see `LICENSE`. That covers everything here except `sieve/frank_sieve.tcl`, which is Frank van Bakel's work from
Dave's Garage "Primes" (see `sieve/README.md`).
