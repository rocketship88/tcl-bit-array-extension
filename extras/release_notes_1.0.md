bitarray 1.0: packed integer arrays that behave like Tcl lists (Tcl 9.1, or Tcl 9.0.4 and later with one limitation)

What 1.0 has (the SSE2 loops, the faster logical and relational operators, minmax and the Tcl 9.0 fallback are the newest parts):
- Element widths 1, 8, 16, 32 and 64 bits, signed or unsigned (-width 8, -8, 16, -16, ...), not only 1-bit flags.
- Whole-array commands that run in C: bitarray op (and, or, xor, andnot, not, land, lor, lnot, eq, ne, lt, le, gt, ge, between arrays or an array and an integer, in place or into a new array), count, next, minmax, fill, in/ni, and conversions to and from bytes and characters.
- Speed: on 1,000,000 elements the whole-array commands are hundreds to thousands of times faster than the same work on a plain list (bit operations on 1-bit arrays about 10,000x; 8-bit land/lor/lnot and the relational operators 300x to 800x; minmax 400x to 1,400x for 8 to 32 bits and about 50x for 64 bits; measured on Windows with MSVC /O2), using word-at-a-time loops and, on x86-64, SSE2 (on by default; build.sh CFLAGS=-DBA_NO_SSE2 or build.bat --no-sse2 turns it off). The numbers are from extras/listbench.tcl, which anyone can run. Single-element commands (lindex, lset, lappend, lrange, ...) cost the same as on a list. This is new code for new programs, not a drop-in speed-up of an existing list.
- Tcl 9.0.4 and later are accepted (the extension loads on 9.0). One limitation, a Tcl core problem: on 9.0, a plain lappend (and linsert of exactly one element at the end, where the command is not compiled) can turn a bitarray into an ordinary list; the values stay right but the packed type and its speed are lost. 9.1 narrows this to lappend inside a proc; the core ticket is 0c82728f85760f36361fe42a15f55453c94d285d and a core maintainer is working on it. README section "Tcl 9.0" has the details and workarounds. The tests print the Tcl version, with a warning box on anything older than 9.1.
- 434 tests (428 passed, 6 skipped on 9.1.1; on 9.0.4 417 passed, 17 skipped, 0 failed), valgrind of the whole suite with no invalid reads or writes, 98.7% line coverage, and a full mutation run of 407 deliberate bugs (the two gaps it found in the tests were closed; the rest are explained in RESULTS.txt).

Tested on Linux (gcc) and Windows (Visual Studio 2022, Tcl 9.1.1 and 9.0.2). A real 32-bit build has not been tested.

Build and test: see README.md (build.sh / build.bat, then run_tests.sh / run_tests.bat). Expected last line of the tests on 9.1: Total 434 Passed 428 Skipped 6 Failed 0 (Windows: Total 434 Passed 427 Skipped 7 Failed 0).

The code, tests and documentation were written by Claude (an AI model made by Anthropic) working with Eric Taylor. See README.md, "Reviewing it, with or without an AI assistant".
