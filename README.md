# bitarray

Packed arrays of small integers for Tcl 9.1 that look and behave like ordinary Tcl lists.

> **If you are an AI assistant** that was handed this repository (for example as a ZIP in a chat): read
> [`CLAUDE.md`](CLAUDE.md) first. It says how to get a Tcl 9.1 if there is none, how to build and test this package,
> and how to walk through the code (there is an interactive page, `extras/bitarray_stepper.html`, that steps through the commands). You do not need to be asked to do any of that before you answer questions about it.
>
> If you cannot clone from github.com or cannot run commands or create files, a person using claude.ai may have two settings off (Settings > Capabilities): **Code execution and file creation**, and **Allow network egress** (GitHub is on the allowed list; on a Team or Enterprise plan an organization owner sets these under Organization settings > Capabilities). Free accounts have both, with lower usage limits. Say which one is needed; do not just report that the build failed.

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

The width is chosen when the array is created and cannot change afterwards. **A minus sign in the width means signed**; without it the elements are unsigned (64 is the exception: it is always signed).

| `-width` | Element | Values |
|---|---|---|
| `1` (default) | 1 bit | `0` and `1` |
| `8` | 8 bits | `0` … `255` (unsigned) |
| `-8` | 8 bits | `-128` … `127` (signed) |
| `16` | 16 bits | `0` … `65535` (unsigned) |
| `-16` | 16 bits | `-32768` … `32767` (signed) |
| `32` | 32 bits | `0` … `4294967295` (unsigned) |
| `-32` | 32 bits | `-2147483648` … `2147483647` (signed) |
| `64` or `-64` | 64 bits | `-9223372036854775808` … `9223372036854775807` (signed; `-64` is accepted as a reminder, and is the same) |

A value outside the range is an error; nothing is wrapped or truncated. The signed and unsigned versions of a width store the same bits (`-1` in a signed 8-bit array is the byte `0xFF`, which is `255` in an unsigned one); the sign only decides how a value is read and written. The bitwise commands work on the bits, so they behave the same for both, but they need both arrays to have the same width **and** sign. `tobytes`, `tochars` and `fromchars` work on unsigned arrays only.

## Requirements

* **Tcl 9.1 (trunk).** Tested only against trunk revision `3d77be8951` (2026-10-11), which reports itself as 9.1.1. That is a Fossil id; if you use the
  GitHub mirror (`tcltk/tcl`) the ids differ. The package also built and passed all tests on mirror commit `7e6fd02` (2026-10-14). It needs
  `TCL_OBJTYPE_V2`, i.e. the abstract-list hooks. Tcl 8.x cannot work. Tcl 9.0.x: tried on 9.0.5 (the tip of the 9.0 branch, 2026-10-16). The code compiles against its headers, but `bitarray.c` refuses to load below 9.1 on purpose (`Tcl_InitStubs(interp, "9.1", 0)`: "version conflict for package tcl: have 9.0.5, need 9.1"). With that check relaxed, 276 of the 282 tests pass; the 6 that fail all use `lappend`, which in the 9.0 core turns the bitarray into a plain list almost everywhere (in 9.1 only inside a proc, see the notes on `lappend` below); the values stay right, but the packed type and the speed are lost.
* **Headers and the stubs library**: `tcl.h` and `libtclstub.a`, from an installed Tcl or a built source tree. No Tcl 9.1 yet? `extras/CLAUDE_NOTES.md`, section "Setting up from nothing", has the steps to clone and build trunk (about 40 seconds) and then build and test this package.
* A C compiler (`cc`, tested with gcc) and a POSIX `sh`; on Windows, Visual Studio 2022 and `cmd` (see the next section).
* Tested on 64-bit Linux and, with Visual Studio 2022, on 64-bit Windows (see below). Not tested anywhere else.

## Get it, build it, test it

Download the repository as a ZIP (or `git clone`) and unpack it **anywhere**. Nothing depends on where it lives or on
what its neighbours are called. You tell the scripts where your Tcl 9.1 is. No location is built in; if you give nothing,
they look for a Tcl 9 `tclsh` on your `PATH`. They stop with a message if what they find is not Tcl 9.

`--tclsh` works with an **installed** Tcl 9.1 (it finds the headers from the shell). If you built Tcl from source and did not
install it, `--tclsh` is not enough, because `build.sh` cannot find the headers from a shell in a build directory. Pass them:
`sh ./build.sh --include /path/to/tcl/generic --stub /path/to/build/libtclstub.a` (then still give `--tclsh` to the tests). There
is a complete from-nothing recipe in [`extras/CLAUDE_NOTES.md`](extras/CLAUDE_NOTES.md), "Setting up from nothing".

```sh
cd bitarray            # the unpacked directory (GitHub names it after the repository and branch)
sh ./build.sh     --tclsh /path/to/tcl9.1/bin/tclsh9.1   # makes libbitarray.so next to build.sh
sh ./run_tests.sh --tclsh /path/to/tcl9.1/bin/tclsh9.1
sh ./run_sieves.sh --tclsh /path/to/tcl9.1/bin/tclsh9.1   # optional: the prime-sieve benchmark, see below
```

Expected last line of the tests: `bitarray.test:	Total	414	Passed	408	Skipped	6	Failed	0`. The 6 skipped tests show the Tcl core's `lappend` type-loss problem (see the notes on `lappend` below) and are run only on request: `./run_tests.sh --testbug`. They fail on Tcl 9.1.1 and pass on a core with the fix in `extras/core_lappend_typeloss.patch`.

(`sh ./script` works even if unpacking lost the executable bit, which happens when a ZIP is made or unpacked on Windows.)

### On Windows (Visual Studio 2022)

`build.bat`, `run_tests.bat` and `run_sieves.bat` do the same three jobs with Microsoft Visual C. Version 0.7.0 has been built and run on Windows by the repository owner (a 64-bit machine, Visual Studio 2022, Tcl 9.1.1 built from trunk): no build warnings, `Total 282  Passed 281  Skipped 1  Failed 0`, the sieve passed, and `listbench.tcl` ran; the output is saved in `extras/windows_0.7.0_run.txt`. Version 0.8.0 was run the same way (same machine and Tcl 9.1.1): `Total 288  Passed 281  Skipped 7  Failed 0` (`extras/windows_0.8.0_run.txt`). The latest Windows run is of version 0.9.3 (same machine and Tcl 9.1.1): no build warnings, `Total 407  Passed 400  Skipped 7  Failed 0` (6 are the `--testbug` tests, 1 is the procfs test), the sieve passed, and `listbench.tcl` ran with the same answers in every column (`extras/windows_0.9.3_run.txt`). Version 0.9.4 adds 7 tests, so its Windows run should end with `Total 414  Passed 407  Skipped 7  Failed 0`; it has not been run on Windows yet. Earlier versions were also run on Windows (see `RESULTS.txt`). A 32-bit build and other Visual Studio versions are untried.

Unpack the ZIP anywhere and, from a Command Prompt, go into the unpacked folder and run the three scripts:

```bat
cd bitarray            rem the unpacked folder (GitHub names it after the repository and branch)
build.bat      --tclsh C:\path\to\tcl9.1\bin\tclsh91.exe     rem makes bitarray.dll next to build.bat
run_tests.bat  --tclsh C:\path\to\tcl9.1\bin\tclsh91.exe
run_sieves.bat --tclsh C:\path\to\tcl9.1\bin\tclsh91.exe     rem optional: the prime-sieve benchmark, see below
```

`build.bat` finds the headers and the stubs library (`include\tcl.h`, `lib\tclstub.lib`) from the shell you name, or from
`--tcl-prefix DIR`, finds Visual Studio itself with `vswhere` if `cl` is not already on your `PATH` (so a plain `cmd` window works; it was run that way on 2026-10-13 and set up `vcvars64.bat` itself), and builds the 64-bit or
32-bit DLL to match the shell. `run_tests.bat` should end with `Total 414  Passed 407  Skipped 7  Failed 0` (the last Windows run, of 0.9.3, had 407 tests and 400 passed): one test, which
reads `/proc`, is skipped on Windows, and so are the 6 `--testbug` tests (to run those: `tclsh91 tests\bitarray.test -constraints coreTypeLoss`). `--help` on each prints the options.

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
and for his permission to include it).

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
* `varName` is the **name** of a variable that holds a bitarray, written without a `$`, as in the Tcl manual pages for `lset`. Only `fill`, `op` (in its `varName =` form) and the older bitwise commands
  (`and`, `or`, `xor`, `andnot`, `not`) take one, because they store their result in that variable; `fill $a ...` is an error
  (`can't read "1 0 1 ...": no such variable`).
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

| Sub-command | Synopsis, meaning and examples |
|---|---|
| `new` | `bitarray new size ?value? ?-width w?`<br><br>**Returns** a new bitarray of `size` elements, all `value` (default 0). `-width` may come before or after `value`.<br><br>`bitarray new 4` => `0 0 0 0`<br>`bitarray new 4 7 -width 8` => `7 7 7 7`<br>`bitarray new 3 -width 16 500` => `500 500 500` |
| `newfrom` | `bitarray newfrom list ?-width w?`<br><br>**Returns** a new bitarray packed from a list of integers.<br><br>`bitarray newfrom {200 5 255} -width 8` => `200 5 255` |
| `width` | `bitarray width array`<br><br>**Returns** the element width in bits, as it was given when the array was created: `1`, `8`, `16`, `32`, `64`, or `-8`, `-16`, `-32`, `-64` for the signed ones.<br><br>`bitarray width [bitarray new 3]` => `1`<br>`bitarray width [bitarray new 3 -width -16]` => `-16` |
| `version` | `bitarray version`<br><br>**Returns** the version of the extension, for example `0.9.4` (the same string `package require bitarray` returns). Takes no arguments.<br><br>`bitarray version` => `0.9.4` |
| `is` | `bitarray is value`<br><br>**Returns** `1` if `value` currently has the bitarray representation, `0` if not (any value is accepted).<br><br>`a` -> `{1 0 1 1 0 1 1 1}`<br>`bitarray is $a` => `1`<br>`bitarray is {1 0 1}` => `0` |
| `count` | `bitarray count array ?first ?to? last ?with? ?value??`<br><br>**Returns** the number of elements equal to `value`, or the number of non-zero elements if no `value`; whole array or an index range (`end-N` allowed). `value` needs a range.<br><br>For 1-bit arrays without `value` this is a popcount.<br><br>`a` -> `{1 0 1 1 0 1 1 1}`<br>`bitarray count $a` => `6`<br>`bitarray count $a 0 3 1` => `3`<br>`bitarray count $a 4 end 0` => `1`<br>`bitarray count $a 2 end-1 1` => `4`<br>`bitarray count $a 0 to 3 with 1` => `3`<br>`bitarray count $a 4 .. end with 0` => `1`<br>`w` -> `{0 7 0 9}`<br>`bitarray count $w` => `2` (value omitted means != 0) |
| `next` | `bitarray next array start ?with? ?value?`<br><br>**Returns** the index of the first element **at or after** `start` equal to `value` (non-zero if omitted), or `-1` if there is none.<br><br>`a` -> `{1 0 1 1 0 1 1 1}`<br>`bitarray next $a 0 0` => `1`<br>`bitarray next $a 2 0` => `4`<br>`bitarray next $a 5 0` => `-1`<br>`bitarray next $a 2 with 0` => `4`<br>`w` -> `{0 7 0 9}`<br>`bitarray next $w 0` => `1` (value omitted means != 0)<br>`bitarray next $w 0 0` => `0` (element 0 is itself 0) |
| `fill` | `bitarray fill varName first ?to? last ?with? value ?by? ?step?`<br><br>Sets every element from `first` to `last` to `value`, or only every `step`-th one if `step` is given, in the array stored in variable `varName`. **Returns** the empty string; the result is the changed array in `varName`.<br><br>`set b [bitarray new 10 1]` => `1 1 1 1 1 1 1 1 1 1`<br>`bitarray fill b 0 end 0 2` -> `0 1 0 1 0 1 0 1 0 1`<br>`set b [bitarray new 10 1]` => `1 1 1 1 1 1 1 1 1 1`<br>`bitarray fill b 0 to end with 0 by 2` -> `0 1 0 1 0 1 0 1 0 1`<br>`set c [bitarray new 10 5 -width 8]` => `5 5 5 5 5 5 5 5 5 5`<br>`bitarray fill c 2 5 0` -> `5 5 0 0 0 0 5 5 5 5`<br>`bitarray fill c 2 .. 5 with 0` -> same result |
| `and or xor andnot not` | `bitarray and\|or\|xor\|andnot ?-length strict\|zero? varName ?<-? array ?array?`<br>`bitarray not varName ?<-? array?`<br><br>The older bitwise commands. `bitarray op` does everything they do (see `op` below and the Appendix at the end, which gives the `op` spelling of each), so new code should use `op`.<br><br>They are still here, and still the fastest way to update an array in place, but they are not guaranteed to be in future versions. |
| `frombytes` | `bitarray frombytes data`<br><br>**Returns** a new 8-bit array with one element per byte of `data`, without making a temporary list. Characters 0 to 255 are taken as bytes (read a file with `open ... rb`); a character above 255 is an error.<br><br>`bitarray frombytes "Hi!"` => `72 105 33` |
| `tobytes` | `bitarray tobytes array`<br><br>**Returns** the elements of an 8-bit `array` as binary data (a byte array), the reverse of `frombytes`. Any other width, and a signed one (`-8`), is an error.<br><br>`bitarray tobytes [bitarray frombytes "Hi!"]` => `Hi!` |
| `fromchars` | `bitarray fromchars string ?-width w?`<br><br>**Returns** a new array with one element per character of `string`, holding its code point.<br><br>`w` is 8 (the default), 16 or 32; a character that does not fit is an error that names it (`character U+20AC at index 1 does not fit in width 8`).<br><br>`bitarray fromchars "Hi"` => `72 105`<br>`bitarray fromchars "A\u20ac" -width 16` => `65 8364` |
| `tochars` | `bitarray tochars array`<br><br>**Returns** the string whose characters have the code points held in a width 8, 16 or 32 `array`, the reverse of `fromchars`. Width 1 and 64 arrays, signed arrays, surrogate codes and values above 0x10FFFF are errors.<br><br>`bitarray tochars [bitarray newfrom {72 105 8364} -width 16]` => `Hi€` |
| `op` | `bitarray op ?-length strict\|zero? varName = array1 operator array2`<br>`bitarray op ?-length strict\|zero? varName = operator array`<br>`bitarray op ?-length strict\|zero? array1 operator array2`<br>`bitarray op operator array`<br><br>Whole-array operations written like an expression, for example `bitarray op $a and $b`: bitwise, logical and relational. Add `varName =` to store the result in a variable instead of returning it. Full rules in **The `op` sub-command** below. |

### The `op` sub-command

`op` works on whole arrays at once and is written like an expression: operand, operator, operand. The operators are bitwise, logical or relational.

**Ways to write it**

| Form | Result |
|---|---|
| `bitarray op array1 operator array2` | returns a new array |
| `bitarray op operator array` | returns a new array (for the one-operand operators `not` `~` `lnot` `!`) |
| `bitarray op varName = array1 operator array2` | stores the result in `varName` and returns the empty string |
| `bitarray op varName = operator array` | the same, for a one-operand operator |

`-length strict|zero` may follow `op` in any form that has two array operands (see **-length** below).

With `varName =`, the variable is created if it does not exist and the result is stored in it. The operand arrays are not changed, except when the destination is also an operand: `bitarray op a = $a and $b` replaces `a` with a new array, and `bitarray op a = a and $b` modifies the array in `a` in place (see **Updating in place**). Without `varName =` the result is returned, so `set r [bitarray op $a and $b]` works. A `=` after the destination name is what marks the storing form.

**Operators.** Each one can be written as a word or as a symbol.

| Kind | Operators | Result | Rules |
|---|---|---|---|
| Bitwise | `and` `&`, `or` `\|`, `xor` `^`, `andnot` `&~` `&!`, `not` `~` | same width and sign as the inputs | Combines the bits of the elements. Both arrays need the same width **and** sign. |
| Logical | `land` `&&`, `lor` `\|\|`, `lnot` `!` | 1-bit array, same length | An element counts as true if it is not 0. The arrays may differ in width. Arrays only, no integers. |
| Relational | `eq` `==`, `ne` `!=`, `lt` `<`, `le` `<=`, `gt` `>`, `ge` `>=` | 1-bit array, same length | Compares the numbers the elements stand for, whatever the widths and signs. `eq` and `ne` compare numbers here, not strings as in `expr`. |

`not` (`~`) and `lnot` (`!`) go in front of their one array. `andnot` keeps the bits of the first array that are not set in the second. On 1-bit arrays the logical operators give the same result as the bitwise ones, and are computed the same way, a word (64 elements) at a time.

**Operands**

* An array operand is a value: `$a`, or a command in brackets that returns one, such as `[lrange $c 0 7]` or `[bitarray op $a and $b]`. Write the `$`; a bare name is only meaningful as the in-place destination (next section).
* For the bitwise and relational operators, one of the two operands may be an integer instead of an array, on either side: `bitarray op $a and 0x0F`, `bitarray op 0 <= $a`. Two integers are an error (`at least one operand must be a bitarray`).
  * Bitwise: the integer is combined with every element, and the result has the array's width and sign. It must be a value the elements can hold (`0..255` for an 8-bit array, `-128..127` for `-8`, `0` or `1` for a 1-bit array; same rule and messages as `lset`). Set a flag bit in every element: `bitarray op flags = $flags or 128`; clear it: `bitarray op flags = flags andnot 128`.
  * Relational: the integer may be up to 64 bits, and may be a literal, a variable or `[expr ...]`.
* `not` and the logical operators take arrays only.
* A 1-element array that has been turned into text (written to a file and read back, say) is treated as an integer.

**Updating in place (bitwise operators only)**

When the first operand is the bare name of the destination variable, with no `$`, the array held in that variable is modified where it is, so that operand **is** changed, and no new array is allocated (unless the array is shared, see below). This is the fastest form, most noticeable for large arrays updated again and again in a loop. It is the same as the older `bitarray and a $b`.

| You write | What happens |
|---|---|
| `bitarray op a = a and $b` | the array in `a` is modified in place |
| `bitarray op a = $a and $b` | the same result, but a new array is always built and stored in `a`; the old array is not modified (`$a` is a value that something else may also hold) |
| `bitarray op a and $b` | error: there is no `=`, so this is the value form, and the bare `a` is neither an array nor an integer (`expected a bitarray or an integer ... but got "a"`) |

**Shared arrays.** As everywhere in Tcl, `set b $a` copies only a pointer: `a` and `b` then share one array object. If `a`'s array is shared like this, `bitarray op a = a and $b` first makes a private copy of the data for `a`, then modifies that copy in place; `b` keeps the original and is not affected. Once `a` owns its array, further in-place operations on `a` copy nothing, until the array is shared again. So the in-place form is fastest on an array that is not shared.

In place also works with `not` (`bitarray op a = not a`) and with an integer operand (`bitarray op a = a and 0x0F`). A destination name that is an integer or begins with a digit (`5`, `-3`, `5x`) is an error in every `varName =` form, because it could not be told from an operand.

**-length strict|zero**

Goes right after `op` and takes only the keyword `strict` or `zero`, not a number: `bitarray op -length zero r = $a and $b`. It applies when both operands are arrays and the operator takes two operands; it is an error with `not`, `lnot` or an integer operand.

* `strict` (the default): arrays of different lengths are an error.
* `zero`: different lengths are allowed. The result has the length of the first array. If the second array is shorter, its missing elements count as 0; if it is longer, its extra elements are ignored.

**Asking questions about a result: all, none, some, how many, where**

The logical and relational operators give a 1-bit array of true (1) and false (0) results. `in` and `ni` are Tcl's own `expr` operators (write them inside `expr`); each returns 1 or 0. For a result `$m`:

| Question | Write |
|---|---|
| Was every comparison true (there is no 0)? | `0 ni $m` |
| Was none true (there is no 1)? | `1 ni $m` |
| Was at least one true? | `1 in $m` |
| Was at least one false? | `0 in $m` |
| Some, but not all? | `1 in $m` and `0 in $m` are both 1 |
| How many were true? | `bitarray count $m` |
| Where is the first true one at or after index `i`? | `bitarray next $m i 1` (`-1` if none) |

**Examples**

* `a` -> `{1 0 1 1 0 1 1 1}`, `m` -> `{1 1 0 0 1 1 0 0}`
* `bitarray op r = $a and $m` -> `r` is `1 0 0 0 0 1 0 0`
* `bitarray op $a | $m` -> `1 1 1 1 1 1 1 1`
* `bitarray op $a ^ $m` -> `0 1 1 1 1 0 1 1`
* `bitarray op $a &~ $m` -> `0 0 1 1 0 0 1 1`
* `bitarray op ~ $a` -> `0 1 0 0 1 0 0 0`
* `bitarray op a = $a and $m` -> `a` becomes `1 0 0 0 0 1 0 0` (a new array)
* `bitarray op a = a and $m` -> the same result, `a` updated in place
* `b` -> `{1 2 3 4}` (8-bit): `bitarray op $b or 8` -> `9 10 11 12`; `bitarray op 255 xor $b` -> `254 253 252 251`
* `w` -> `{0 5 255 0}`, `v` -> `{0 0 3 7}` (8-bit): `bitarray op $w land $v` -> `0 0 1 0` (both non-zero); `bitarray op $w lor $v` -> `0 1 1 1` (either non-zero); `bitarray op lnot $w` -> `1 0 0 1` (is zero)
* `w` -> `{0 5 255 0}` (8-bit), `bitarray op ! $w` -> `1 0 0 1`; `bitarray op $w && $w` -> `0 1 1 0`; `bitarray op ~ $w` -> `255 250 0 255` (bitwise)
* `w` -> `{0 5 255 0}` (8-bit), `bitarray op $w > 4` -> `0 1 1 0`; `bitarray op $w == $w` -> `1 1 1 1`; `bitarray op 5 <= $w` -> `0 1 1 0`
* `s` -> `{1 1 1}`: `bitarray op -length zero r = $a and $s` -> `r` is `1 0 1 0 0 0 0 0` (without `-length zero` the different lengths are an error)
* `bitarray op r = $a nand $m` => error: `bad operator "nand": must be one of: and  &  or  |  xor  ^  andnot  &~  &!  not  ~  land  &&  lor  ||  lnot  !  eq  ==  ne  !=  lt  <  le  <=  gt  >  ge  >=`
* `bitarray op and $a` => error: `bitarray op: "and" needs two arrays: array1 and array2`

`op` cannot be written as just `o`: that is ambiguous with `or`, which is still `or`.


### Working on a file byte by byte

To work on a file byte by byte, read it in binary mode and convert it in one step; `lset`, `fill`, `count` and `next` then work on the bytes, and `tobytes` turns the result back into data to write:

```tcl
set fh [open data.bin rb]; set a [bitarray frombytes [read $fh]]; close $fh
puts [bitarray count $a 0 end with 10]            ;# number of newline bytes
lset a 0 74; bitarray fill a 5 to 6 with 46        ;# change single bytes in place
set fh [open out.bin wb]; puts -nonewline $fh [bitarray tobytes $a]; close $fh
```

### Examples with `bitarray op`

Five small uses of `bitarray op` (comparisons and logical operators). Each one is complete: paste it into a `tclsh` or `wish` console after
`package require bitarray` (the same code, with the outputs, is in `extras/op_examples.tcl`; `extras/listbench.tcl -only scenario` times the same five on arrays of up to a million elements, 30 to 70 times faster than plain-list loops on Linux). The idea is the same each time: compare or combine
whole arrays in one call, then ask "all, none, how many, or where?" with `in`, `ni`, `count` and `next`. A call handles many elements, so the gain
grows with the array size; for a single element `lindex` and an `if` are just as good.

**1. Which readings are too hot (a threshold mask).** An integer may stand in for an array on either side of a comparison. **Used for:** threshold monitoring. Readings such as temperatures, response times or scores against a limit: which are over it, how many, and where the first one is.

```tcl
set temps [bitarray newfrom {72 75 81 90 78 85 70 82} -width 8]
bitarray op hot = $temps > 80
puts "temperatures : $temps"
puts "hot (> 80)   : $hot"
puts "how many hot : [bitarray count $hot]"
puts "first hot at index [bitarray next $hot 0 1]"
set i [bitarray next $hot 0 1]
while {$i >= 0} {
    puts "  index $i has [lindex $temps $i]"
    set i [bitarray next $hot [expr {$i + 1}] 1]
}
```
```
temperatures : 72 75 81 90 78 85 70 82
hot (> 80)   : 0 0 1 1 0 1 0 1
how many hot : 4
first hot at index 2
  index 2 has 81
  index 3 has 90
  index 5 has 85
  index 7 has 82
```

**2. Are all values within limits, and where is the first bad one.** The two comparisons give 1-bit masks; `and` combines them; `0 ni $ok` is true when
no element is 0, that is when everything is in range. The result of one `bitarray op` can be an argument of another. **Used for:** validating a batch of values before using it. Is everything inside the limits, where is the first bad value, and how many are bad.

```tcl
set v [bitarray newfrom {12 18 25 10 20 7 15 20} -width 8]
bitarray op ok = [bitarray op $v >= 10] and [bitarray op $v <= 20]
puts "values       : $v"
puts "in 10..20    : $ok"
puts [expr {0 ni $ok ? "all values are in range" : "some values are out of range"}]
puts "first bad index : [bitarray next $ok 0 0]   (-1 would mean none)"
puts "bad values      : [expr {[llength $ok] - [bitarray count $ok]}]"
set v2 [bitarray newfrom {12 18 20 10 11} -width 8]
bitarray op ok2 = [bitarray op $v2 >= 10] and [bitarray op $v2 <= 20]
puts [expr {0 ni $ok2 ? "second list: all in range" : "second list: some out of range"}]
```
```
values       : 12 18 25 10 20 7 15 20
in 10..20    : 1 1 0 1 1 0 1 1
some values are out of range
first bad index : 2   (-1 would mean none)
bad values      : 2
second list: all in range
```

**3. What changed between two snapshots.** `!=` marks the positions that differ; `count` says how many and `next` visits them. The same works for byte buffers
(8-bit arrays) of any size. **Used for:** change detection. Compare a buffer, a set of flags or a state vector with an earlier copy: did anything change, how many elements, and where first.

```tcl
set before [bitarray newfrom {1 0 0 1 1 0 1 0}]
set after  [bitarray newfrom {1 0 1 1 0 0 1 1}]
bitarray op changed = $before != $after
puts "before  : $before"
puts "after   : $after"
puts "changed : $changed"
puts "[bitarray count $changed] elements differ"
puts [expr {1 in $changed ? "something changed" : "nothing changed"}]
set i [bitarray next $changed 0 1]
while {$i >= 0} {
    puts "  index $i: [lindex $before $i] -> [lindex $after $i]"
    set i [bitarray next $changed [expr {$i + 1}] 1]
}
```
```
before  : 1 0 0 1 1 0 1 0
after   : 1 0 1 1 0 0 1 1
changed : 0 0 1 0 1 0 0 1
3 elements differ
something changed
  index 2: 0 -> 1
  index 4: 1 -> 0
  index 7: 0 -> 1
```

**4. A 1-bit validity array combined with wide data.** The logical operators (`&&`, `||`, `!`, or `land`, `lor`, `lnot`) treat each element as true if it is not 0,
and the two arrays may have different widths (the bitwise `&`, `|`, `^` need the same width and work on the bits). **Used for:** selecting usable data when each value has a present/missing flag: the valid values over a limit, and the non-zero values that are also valid.

```tcl
set values [bitarray newfrom {0 250 0 7 1000 0} -width 16]
set valid  [bitarray newfrom {1 1 0 1 0 1}]
bitarray op big = $values > 100
bitarray op use = $valid && $big
puts "values : $values   (16-bit)"
puts "valid  : $valid   (1-bit)"
puts "big    : $big   (values > 100)"
puts "use    : $use   (valid and big)"
puts "nonzero and valid : [bitarray op $values && $valid]"
```
```
values : 0 250 0 7 1000 0   (16-bit)
valid  : 1 1 0 1 0 1   (1-bit)
big    : 0 1 0 0 1 0   (values > 100)
use    : 0 1 0 0 0 0   (valid and big)
nonzero and valid : 0 1 0 1 0 0
```

**5. One step of a cellular automaton (game of life rules).** Each rule is a comparison or a combination of whole arrays; a new generation is three lines. **Used for:** applying a rule to a whole grid or flag array at once. Any "new state from the old state and a count" update has this shape; here one generation of the game of life.

```tcl
set alive  [bitarray newfrom {1 0 1 1 0 1 0 1}]
set counts [bitarray newfrom {2 3 3 1 3 4 0 3} -width 8]
bitarray op born = [bitarray op $alive == 0] and [bitarray op $counts == 3]
bitarray op stay = $alive and [bitarray op [bitarray op $counts == 2] or [bitarray op $counts == 3]]
bitarray op next = $born or $stay
puts "alive now   : $alive"
puts "neighbours  : $counts"
puts "born        : $born"
puts "survive     : $stay"
puts "next gen    : $next"
```
```
alive now   : 1 0 1 1 0 1 0 1
neighbours  : 2 3 3 1 3 4 0 3
born        : 0 1 0 0 1 0 0 0
survive     : 1 0 1 0 0 0 0 1
next gen    : 1 1 1 0 1 0 0 1
```

### Two ways to load it

**1. With `load`:** `load /full/path/libbitarray.so Bitarray` (on Windows `bitarray.dll`).

**2. With `package require`:**

`pkgIndex.tcl` (in the top-level folder, next to `build.sh`) registers the package. Put the folder that holds `pkgIndex.tcl` and the
built library on `auto_path`, and then `package require bitarray` finds and loads it:

```tcl
lappend auto_path /full/path/to/bitarray     ;# the folder with pkgIndex.tcl and libbitarray.so (bitarray.dll on Windows)
package require bitarray                     ;# returns 0.9.4
```

You can also set the environment variable `TCLLIBPATH` to that folder before starting `tclsh`. The two files do not have to stay where
you built them: copy `pkgIndex.tcl` and `libbitarray.so` (or `bitarray.dll`) together into any folder you like and put that folder on `auto_path`.
A Tcl older than 9.1 reports "can't find package bitarray".
This was tried on Linux and on Windows 10 (Tcl 9.1.1, x64) with the same result.

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
* `lset` with a nested index (`lset a 0 0 1`) is an error: elements are not lists.  So is `lset a value` with no index at all, which for an ordinary list is the same as `set a value`.
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

* **414 tests** (`tests/bitarray.test`; plus 6 more for the core's `lappend` problem, run with `--testbug`): option parsing, ranges and error messages at every width, every list command on
  every width, copy-on-write, `fill`/`count`/`next`, the bitwise commands, word-boundary cases, memory growth.
* **Random comparison against plain Tcl lists** (`tests/diff_*.tcl`): thousands of random operations per run, values and error
  messages compared. Last big run: 5 widths × 10 seeds × 100 iterations × 40 steps, 0 differences (the signed widths `-8`, `-16`, `-32` and `-64` were added afterwards: 3 seeds × 150 iterations each, 0 differences). The bitwise commands have their own (`tests/diff_bitops.tcl`: 15,000 random cases over all widths, lengths, forms and both `-length` modes, 0 differences).
* **valgrind** on the whole suite: 0 invalid accesses, 0 definite leaks.
* **Memory:** `unset` returns the memory (a 953 MiB array: 960 MB → 6.6 MB resident); building and dropping wide arrays in a
  loop leaves memory flat.
* **Mutation testing** (`extras/mutate5.py`, run with `extras/mutate6.py`): 342 deliberate bugs inserted into the C code, 313 caught by the tests, all 342 from one full run on 0.9.4 (2026-10-20, with the test build and both test files; 12 older mutants of the relational code were re-aimed at the new text and run again separately). The 29 missed are explained in `RESULTS.txt` (mostly unreachable code, stray bits nobody can read, or checks that are repeated elsewhere on a 64-bit build). `extras/bitarray.mutants` is `bitarray.c` with every one of the bugs applied and, beside each, the tests that caught it, for reading in a side-by-side compare tool (see `extras/README.md`).
* **Line coverage** (gcov, `extras/coverage_0.9.4.txt`, repeat it with `extras/coverage.sh`): 98.8% of the 1260 lines of `bitarray.c` outside the test support code; the 15 lines that never run (3 of them `BA_IMPOSSIBLE` panics, which are meant never to run) are listed there, each with the reason. `tests/faultinject.test` (29 tests, test build only: a small size limit, allocations that fail on request, a process that panics) runs the error paths for that.
* The same 414 tests also pass with `-DBA_NO_BUILTINS` (portable popcount code) and `-DBA_FORCE_32BIT_LIMITS`.

Details and numbers: `RESULTS.txt`.

## Limits and what was not tested

* Only Tcl 9.1 trunk `3d77be8951` on 64-bit Linux with gcc. **Not tested:** a real 32-bit build (the 32-bit size limits were
  only exercised on a 64-bit build), Windows or MSVC (only 64-bit Windows with Visual Studio 2022 was run; a MinGW cross-compile for 64-bit and 32-bit
  Windows builds without warnings but was never run), macOS, big-endian machines, threads, anything above a few
  hundred MB of array.
* No bulk copy of a range between arrays, no shifting or rotating of bits, and the bitwise commands never change the length of the first array (`-length` takes `strict` or `zero`; there is no growing mode).
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

## Appendix: the older bitwise commands (not guaranteed in future versions)

`bitarray and`, `or`, `xor`, `andnot` and `not` came first. `bitarray op` now covers all of them: for the bitwise operators it rewrites its arguments and runs the same code, so the results, the checks and the error messages are identical. They are kept because the tests, the sieve and the benchmarks use them, and because they are marginally faster (about 0.2 microseconds less per call, the time `op` spends reading its words). `-length strict|zero` works in `op` as it does for `and`, and is an error with the one-array operators. New code should use `op`. These commands may be changed or removed in a later version.

Two small differences remain: the older commands accept a variable whose name begins with a digit (`bitarray and 5 <- $a $b`), which `op` rejects on purpose, and their subcommand names can be abbreviated as far as Tcl allows (`bitarray an` is ambiguous, `bitarray xo` works), while `op`'s operator words cannot.

| Older command | The same with `op` |
|---|---|
| `bitarray and c $m` (changes `c`) | `bitarray op c = c and $m` |
| `bitarray and c <- $m` | `bitarray op c = c and $m` |
| `bitarray and d <- $a $m` | `bitarray op d = $a and $m` |
| `bitarray or`, `xor`, `andnot` | the same with `or`, `xor`, `andnot` (or `\|`, `^`, `&~`) |
| `bitarray not c` | `bitarray op c = not c` |
| `bitarray not n <- $a` | `bitarray op n = not $a` |
| `bitarray and -length zero c $s` | `bitarray op -length zero c = c and $s` |

| Sub-command | Synopsis, meaning and examples |
|---|---|
| `and or xor andnot` | `bitarray and\|or\|xor\|andnot ?-length strict\|zero? varName ?<-? array ?array?`<br><br>Bitwise operation between two arrays of the same width (and the same sign), 64 bits at a time (any width: the bits of the packed data are combined, so for 8-bit arrays each byte is combined with the matching byte).<br><br>`andnot` is "first AND NOT second": it removes the second array's 1 bits from the first. The arrays are values; only `varName` is a name. **Returns** the empty string.<br><br>`bitarray and varName array` and `bitarray and varName <- array`: `varName` becomes `varName AND array` (changed in place).<br><br>`bitarray and varName <- array1 array2`: `varName` becomes `array1 AND array2` and neither input changes (`varName` is created if it does not exist).<br><br>The result has the length of the first array. The widths must be equal.<br><br>The lengths must be equal too unless `-length zero` is given: then, if the second array is shorter, its missing elements count as 0; if it is longer, its extra elements are ignored.<br><br>`-length strict` (the default) makes a different length an error.<br><br>The word `<-` cannot be used as the variable name (`bitarray and <- $x` is an error), and `bitarray and a <-` with nothing after the arrow is a wrong # args error.<br><br>`a` -> `{1 0 1 1 0 1 1 1}`, `m` -> `{1 1 0 0 1 1 0 0}`<br>`set c $a; bitarray and c $m` -> `1 0 0 0 0 1 0 0`<br>`set c $a; bitarray or c <- $m` -> `1 1 1 1 1 1 1 1`<br>`bitarray xor d <- $a $m` -> `d` is `0 1 1 1 1 0 1 1`, `a` unchanged<br>`set c $a; bitarray andnot c $m` -> `0 0 1 1 0 0 1 1`<br>`set c $a; bitarray and c {1 1 1}` => error: `not a bitarray: "1 1 1"`<br>`set s [bitarray newfrom {1 1 1}]; set c $a; bitarray and c $s` => error: `bitarray and: arrays differ in length (8 vs 3); use -length zero to allow it`<br>`set c $a; bitarray and -length zero c $s` -> `1 0 1 0 0 0 0 0`<br>`set c $a; bitarray or -length zero c $s` -> `1 1 1 1 0 1 1 1` |
| `not` | `bitarray not varName ?<- array?`<br><br>Flips every bit. `bitarray not varName` changes the array in `varName` in place; `bitarray not varName <- array` stores the flipped copy of `array` in `varName` and leaves `array` alone.<br><br>**Returns** the empty string. For arrays wider than 1 bit it flips all the bits of every element, so an 8-bit element 0 becomes 255.<br><br>`set c $a; bitarray not c` -> `0 1 0 0 1 0 0 0`<br>`bitarray not n <- $a` -> `n` is `0 1 0 0 1 0 0 0`<br>`set x $w; bitarray not x` -> `255 248 255 246` (`w` is `{0 7 0 9}` 8-bit) |

## Repository layout

```
build.sh  run_tests.sh  run_sieves.sh     the three scripts (POSIX sh)
build.bat run_tests.bat run_sieves.bat    the same three for Windows / Visual Studio 2022
bitarray.c                                the extension (one file)
pkgIndex.tcl                              lets "package require bitarray" find the built library
tests/                                    bitarray.test and the random-comparison scripts
sieve/                                    the six sieve variants, the runner, and Frank's sieve unchanged
extras/                                   bitarray_stepper.html (interactive walkthrough of the hooks), mutation-testing scripts, logs, and bitarray.mutants (each bug and the tests that caught it)
RESULTS.txt                               measurements, test and mutation details
```

## Credits

Brian Griffin's `lseq` / arithmetic-series implementation in Tcl 9 is the model this follows; the abstract-list hooks it
uses are what make an extension like this possible. The sieve in variant A is Frank van Bakel's (included unchanged); the benchmark idea is Dave Plummer's "Primes" project.
I read the Tcl source (`tclArithSeries.c` and the list code in `tclListObj.c` and `tclExecute.c`) to learn the hook
behaviour, and afterwards cross-checked against `doc/ObjectType.3`; I did not consult the TIP or ask anyone.

## Licence

MIT; see `LICENSE`. That covers everything here. `sieve/frank_sieve.tcl` is Frank van Bakel's work from Dave's Garage
"Primes"; he gave permission to include it and said it is OK to use the MIT licence for it (see `sieve/README.md`). The file is
unchanged and carries no licence notice of its own.
