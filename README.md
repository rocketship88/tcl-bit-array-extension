# bitarray

Packed arrays of small integers for Tcl 9.1 that look and behave like ordinary Tcl lists.

```tcl
load ./libbitarray.so Bitarray

set flags [bitarray new 1000000 1]       ;# one million 1-bit flags, all 1 (125 KB; a list needs 8 MB or more)
lset flags 5 0                           ;# plain list commands work: lindex, lset, lrange, lreverse, lreplace,
puts [lrange $flags 0 9]                 ;#   linsert, lappend, foreach, "in", lsort, lsearch, join, {*}...
bitarray fill flags 3 end 0 3            ;# bulk operations that run in C
puts [bitarray count $flags]             ;# number of 1 bits
puts [bitarray next $flags 0 0]          ;# index of the first 0
```

It is an **extension only** (one C file, built against the Tcl stubs library): no change to the Tcl core. It uses the Tcl 9
abstract-list hooks in `Tcl_ObjType` version 2 — the machinery behind `lseq`'s arithmetic series — and is, as far as I know,
the first thing to use that interface's `SetElement` and `Replace` hooks (no type in the Tcl core implements them). To the rest of Tcl a bitarray
is a list, so existing list code works on it unchanged.

> **Who wrote this.** The code, tests and documentation were written by Claude (an AI model made by Anthropic), working
> with Eric Taylor, who directed the work and reviewed it. It is an independent study, not part of Tcl and not an
> official Tcl project. Everything claimed below was measured or tested; what was *not* tested is listed under
> [Limits](#limits-and-what-was-not-tested).

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
* A C compiler (`cc`, tested with gcc) and a POSIX `sh`.
* Tested on 64-bit Linux only.

## Get it, build it, test it

Download the repository as a ZIP (or `git clone`) and unpack it **anywhere**. Nothing depends on where it lives or on
what its neighbours are called. You tell the scripts where your Tcl 9.1 is. No location is built in; if you give nothing,
they look for a Tcl 9 `tclsh` on your `PATH`. They stop with a message if what they find is not Tcl 9.

```sh
cd bitarray            # the unpacked directory (GitHub names it after the repository and branch)
sh ./build.sh     --tclsh /path/to/tcl9.1/bin/tclsh9.1   # makes libbitarray.so next to build.sh
sh ./run_tests.sh --tclsh /path/to/tcl9.1/bin/tclsh9.1
```

Expected last line of the tests: `bitarray.test:	Total	134	Passed	134	Skipped	0	Failed	0`

(`sh ./script` works even if unpacking lost the executable bit, which happens when a ZIP is made or unpacked on Windows.)

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

`run_sieves.sh` checks and times six prime-sieve programs against one another: Frank van Bakel's Tcl entry in Dave Plummer's
"Primes" drag race (variant A), the same code with a helper proc inlined (B), and four versions that use `bitarray` (C–F).
Frank's file is his work; it is included unchanged as `sieve/frank_sieve.tcl` (see `sieve/README.md` for where it comes from
and its licensing situation).

```sh
sh ./run_sieves.sh --tclsh /path/to/tcl9.1/bin/tclsh9.1
```

(`--sieve FILE` tests another copy of his file instead.)

It first checks that every variant finds the right number of primes (and the identical list of primes) at limits 11 up to
1,000,000, then times one full pass at 1,000,000 (best of three, 1.5 s each). It takes about a minute, writes only a
temporary file, and ends with `RESULT: PASS` or `RESULT: FAIL`.

## Commands

Everything is the one command `bitarray`. Anything else you do to a bitarray is an ordinary list command.

| Command | Meaning |
|---|---|
| `bitarray new SIZE ?VALUE? ?-width W?` | new array of `SIZE` elements, all `VALUE` (default 0). `-width` may come before or after `VALUE`. |
| `bitarray newfrom LIST ?-width W?` | pack a list of integers into a new array |
| `bitarray width BA` | `1`, `8`, `16`, `32` or `64` |
| `bitarray is VALUE` | `1` if `VALUE` currently has the bitarray representation |
| `bitarray count BA ?FIRST LAST ?VALUE??` | number of elements equal to `VALUE`, or non-zero if no `VALUE`; whole array or an index range (`end-N` allowed). `VALUE` needs a range. For 1-bit arrays without `VALUE` this is a popcount. |
| `bitarray next BA START ?VALUE?` | index of the first element at or after `START` equal to `VALUE` (non-zero if omitted), or `-1` |
| `bitarray fill VAR FIRST LAST VALUE ?STEP?` | set every `STEP`-th element from `FIRST` to `LAST` in the array held in variable `VAR`, in place like `lset` (copied first if the value is shared). Returns the empty string. |

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
* `lset`, `lrange`, `lreverse`, `lreplace` and `lappend` keep the type and the width. `linsert` does too, except when it
  inserts exactly one element at or past the end: then the result is an ordinary list (same values). I saw this with the trunk
  build and did not look into why. `concat`, `lmap` and similar also give ordinary lists; `bitarray newfrom` packs one again.
* `lset` with a nested index (`lset a 0 0 1`) is an error: elements are not lists.
* `7 in $a` compares string forms, as for a list: `"007" in $a` and `"0x7" in $a` are false.
* The string form is built only if something asks for it (a million 1-bit elements: 2 MB of text).
* Size limit: 2^40 bits (128 GiB) in total on a 64-bit build, 2^30−1 bits on a 32-bit one. A 64-bit-wide array can hold up to
  2^34 elements, an 8-bit one 2^37, a 1-bit one 2^40.
* Growing (`lappend`, `lset` at the end, `linsert`, `lreplace`) edits the array in place and keeps spare capacity, doubling it
  when full, so appending one at a time costs about the same as for a list (80,000 appends: 44 ms against 41 ms).
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
Whether an extension like this counts as a "faithful" entry in Dave's Garage rules I do not know — I did not read them.

## Quality checks

* **134 tests** (`tests/bitarray.test`): option parsing, ranges and error messages at every width, every list command on
  every width, copy-on-write, `fill`/`count`/`next`, word-boundary cases, memory growth.
* **Random comparison against plain Tcl lists** (`tests/diff_*.tcl`): thousands of random operations per run, values and error
  messages compared. Last big run: 5 widths × 10 seeds × 100 iterations × 40 steps, 0 differences.
* **valgrind** on the whole suite: 0 invalid accesses, 0 definite leaks.
* **Memory:** `unset` returns the memory (a 953 MiB array: 960 MB → 6.6 MB resident); building and dropping wide arrays in a
  loop leaves memory flat.
* **Mutation testing** (`extras/mutate5.py`): 95 deliberate bugs inserted into the C code, 81 caught by the tests; the 14
  missed are explained in `RESULTS.txt` (mostly unreachable code, stray bits nobody can read, or checks that are repeated
  elsewhere on a 64-bit build).
* The same 134 tests also pass with `-DBA_NO_BUILTINS` (portable popcount code) and `-DBA_FORCE_32BIT_LIMITS`.

Details and numbers: `RESULTS.txt`.

## Limits and what was not tested

* Only Tcl 9.1 trunk `3d77be8951` on 64-bit Linux with gcc. **Not tested:** a real 32-bit build (the 32-bit size limits were
  only exercised on a 64-bit build), Windows or MSVC, macOS, big-endian machines, threads, Tcl 9.0.x, anything above a few
  hundred MB of array.
* No and/or/xor between arrays, no bulk copy, no conversion to or from a binary string yet.
* The code is written to be portable (`#if SIZE_MAX` selects the size limit; `memcpy` for multi-byte elements) but that is
  not the same as tested.

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
bitarray.c                                the extension (one file)
tests/                                    bitarray.test and the random-comparison scripts
sieve/                                    the six sieve variants, the runner, and Frank's sieve unchanged
extras/                                   mutation-testing script and logs
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
