# bitarray design log (started 2026-10-17)

Standing rule (ET, 2026-10-17): in a session that cannot ask questions, or when a choice is made by default, write the choice down here:
the question, the options, what was chosen, why, and what each alternative would cost.  Entries are dated.  At the next release they move
into extras/CLAUDE_NOTES.md (section "Design choices"; planned for the next release) so that a fresh Claude that only has the zip can find them.

## 2026-10-17  Shared 0 and 1 objects: one pair per array (current)
Question: `NewRep` creates two small Tcl_Objs (`b->zero`, `b->one`) per bitarray, handed out by `BAIndex` / `BAGetElements` / `ElemObj`.  Could they be shared?
Chosen (unchanged since early versions): one pair per array, released in `FreeRep`.
Why: a Tcl_Obj's reference count is not thread-safe and objects belong to one thread, so a process-wide pair is unsafe; per-array objects need no static
globals and no cleanup on unload; the lifetime is easy to see (the array holds one reference to each until FreeRep).
Cost: 2 small allocations per array (4 allocations per array counting the Tcl_Obj and the block); visible only when many tiny arrays are created
(create: about 6 us for a bitarray against 0.16 us for a list on Linux; the objects are part of that, the memset of the data is the rest).
Alternatives, neither tried or measured: (1) one pair per interpreter, kept in interpreter-associated data (safe: an interpreter lives in one thread);
(2) create them lazily on the first element access, so arrays used only with count/next/the bitwise commands never pay.  Either changes `BitArr`,
`NewRep`, `FreeRep`, `BAFree`, `BADup`, `BAGetElements`; needs the 288 tests, the 206 mutants, and a version bump.  Only worth it if creation cost shows in a measurement.

## 2026-10-17  Lifetime of the objects around `lreverse` (and any hook that returns a new value)
`BAReverse`: `NewRep` makes a new BitArr block (plain memory, not a Tcl_Obj; it also makes the block's own 0 and 1 objects); `WrapRep` makes a new Tcl_Obj that points to the block
(`Tcl_StoreInternalRep` sets typePtr to &bitarrayType and ptr1 to the block); `*newObjPtr` hands it to the core (reference count 0; the core takes its own reference).
Per bitarray: 4 allocations (Tcl_Obj, block, zero, one).  The source is untouched, the result shares no memory with it.  A discarded result is freed by BAFree -> FreeRep;
`set a [lreverse $a]` frees the old value when it is replaced.  Live count = number of bitarray values still held.  Wider arrays: `lindex` of a value other than 0 or 1 makes a fresh number object each call.

## 2026-10-17  Other choices made this session (for the notes)
- Side comments in bitarray.c are `   // ...` (spaces, nothing on obvious lines), not `/* */`: ET's choice (shorter, shown green in the stepper); the file had no `//` before.
- Always-braces style (no one-line `if (x) stmt;`): first proposed by ET to make folding easier and not adopted; ADOPTED on 2026-10-18 (0.8.1) because gcov counts per line and
  a one-line `if (x) return y;` hides an untaken `return`.  The fold finder works on brace depth and folds only blocks that are braced (switch cases, if / else if / else);
  loops (for, while, do) are not folded.  Fold is off by default.
- `.nojekyll` at the repository root: GitHub's Jekyll fails on `{{}` in extras/typeloss_ticket_comment.md; it must stay.
- The stepper has no call-stack panel (an early description of it was wrong): it shows memory (variables, heap objects with reference counts, words in hex), a caption naming
  the core function and the Tcl_ObjType hook, and "Show code" with one tab per function in order.
- Tcl 9.1 stays the minimum (9.0.5 refuses to load on purpose; with the check relaxed, 6 tests that use lappend fail).

## 2026-10-18  `lpop l INDEX` returns a copy (0.8.1)
The core calls the setElementProc hook with valueObj == NULL for `lpop l INDEX`.  BASetElement now handles that: index check, copy, BAReplace(idx, 1, 0), return the copy.
Why a copy even for an unshared array: Tcl_LpopObjCmd does `TclUndoRefCount(newListPtr)` on the hook's result.  TclUndoRefCount only lowers the count (never below 0) and
assumes the callee raised it, as TclLsetFlat does.  The lset command's path (TclLsetList) calls the same hook and does `Tcl_IncrRefCount` itself, so a hook must NOT add a
reference.  The two core callers disagree; returning a new object (count 0) is correct for both.  Cost: an O(n) copy per `lpop l INDEX` (lpop without an index is unaffected).
If the core's lpop is fixed, returning the argument itself for an unshared value would become possible; do not change this without testing both.
The fresh Claude's ticket for lstring (no setElementProc) is the other path through the same function.
Also: `lpop l 1 0` (two indices) on a bitarray ends up on a plain list: the core's lindex with several indices converts the array first (type loss, not ours).

## 2026-10-18  Test hooks in bitarray.c (BA_TEST), 0.8.2
Question: how to reach the out-of-memory and size-limit paths in tests.  Choice: `#ifdef BA_TEST` code in bitarray.c itself (a settable size limit, an allocation wrapper that fails on request, a test
command, signal handlers that call __gcov_dump) rather than an LD_PRELOAD malloc wrapper (it would also fail Tcl's own allocations, and Tcl panics) or a separate copy of the source.
The only change visible to a normal build: Tcl_AttemptAlloc / Tcl_AttemptRealloc are written BA_ALLOC / BA_REALLOC (macros that expand to the same calls); objdump -d is byte-identical.
The test build is Linux only (signals, _exit).  Left unreached on purpose (23 lines in 0.8.2, extras/coverage_0.8.2.txt in that release): code the core makes unreachable (clamps, the 1-bit cases in GetElem/PutElem),
a Tcl_Panic in Tcl's own allocator, Tcl_InitStubs failing.  I did not delete the defensive lines: they protect against callers other than the core.

## 2026-10-18  Can't-happen branches are panics (BA_IMPOSSIBLE), 0.8.3
Question: GetElem / PutElem had `default:` branches (a copy of the 1-bit code, a `return` for width 1) that no caller can reach, and gcov showed them as "not covered", which looked like
missing tests.  Choice (ET's idea): make each of them `BA_IMPOSSIBLE(what, num)`, a Tcl_Panic with the function, the reason, the number and file:line, as an assert is used.  A line that is
reported as never run is then exactly what it should be, and if the code is ever wrong the process stops with a message instead of returning a wrong value.  Cost: a panic ends the process
(there is no error to return); acceptable because these are programming errors.  The same for the check after "to" in fill and the end of BitarrayCmd.  The test build can call GetElem /
PutElem with any width (bitarray_test getelem / putelem), so fi-6.1 to fi-6.3 run the panics in a subprocess.  extras/bitarray.nocoverage does not mark BA_IMPOSSIBLE lines.
The mutation run now builds the test build and runs faultinject.test too, so a mutant that removes or triggers a check is judged by the tests that exercise it.

## 2026-10-19  bitarray op, a front end for the bitwise commands, 0.8.6
Request (ET): `bitarray op a = $b and $c`, with the symbols as well (&& and so on), and `bitarray op a = not $b` for not, told apart by having one word fewer; only a new way of writing the
existing commands.  Choice: OpCmd checks the shape (`?-length m? var = A operator B`, or `var = not A`), looks the operator up in a table, and calls BitOpCmd with the rewritten arguments
(`and var <- A B`), so the results, the checks and the error messages are exactly those of the old forms and one set of code does the work; the test file compares the two.
Spellings accepted: and && &, or || |, xor ^, andnot &~ &!, not ! ~ (my choice of symbols for andnot, the request named only &&; easy to change in the table opWords).  Only `=` is accepted
(`<-` stays for the old commands).  `-length` is allowed with the two-array operators and is an error with not (as for the old not).  An operator that does not fit its number of arrays,
an unknown operator and a missing `=` each have their own message; an array where the operator belongs gives the usage message.  The names in error messages are the old command names
("bitarray and: arrays differ in length ...").  Side effect, mentioned in the README: with `op` there, the abbreviation `o` of the subcommand is ambiguous (it used to mean `or`).
Mutation: 26 mutants for the new code (O01-O26): 23 caught.  O10 (the names of xor and andnot in the messages swapped) was first missed, which showed that no test looked at those messages;
op-4.4 does.  O22 (an IncrRefCount on a temporary object removed) and O23 (the bitarray test in FindOperator removed, only slower) cannot be seen by a script: equivalent.

## 2026-10-19  bitarray op: value form and logical operators, 0.9.0
Request (ET): in `op` the variable on the left should be optional so that `set a [bitarray op $b and $c]` works (3 words, or 2 for not); the operator set should separate bitwise from logical
(`&&`, `||`, `!` as in C and Tcl, plus the words land, lor, lnot); the version becomes 0.9 (no users yet, so no compatibility to keep).  Planned next: relational operators (== != < <= > >=, words
eq ne lt le gt ge) giving a 1-bit array, with a scalar allowed on either side, then a scalar for the bitwise operators (`$a and 1`) last.
Value form: with `varName =` four or five words, without it two or three; the shape tells which.  Operands are values, so `[lrange $c 0 7]`, a variable on both sides (`$a and $b`, `$b and $a`) or the result of another
`bitarray op` already worked and now have tests (op-7.x).  The value form and the logical operators are computed by OpValue (a new array, then either returned or stored); the bitwise operators with a
variable still go through BitOpCmd (in-place update of an unshared variable).
Logical operators: each element is tested for "not 0"; the result is always a 1-bit array of the first array's length.  Unlike the bitwise ones the two arrays may differ in width and signedness (the
use is a wide mask against a 1-bit flag array); lengths must still match unless -length zero.  `&&`, `||`, `!` were aliases of and, or, not in 0.8.6; on 1-bit arrays the results are the same, on wider
arrays they differ.  The bitwise ones keep `&`, `|`, `^`, `&~`, `&!`, `~`.
Mutation: the op mutants are now O01-O40 (O01-O26 re-aimed to the new text, O27-O40 new).  O39 (MaskTail left out of the new array) was first missed: count never looks past the end, so op-7.12 appends a 0 to
the result and checks it stays 0.  O22 and O23 remain equivalent.

## 2026-10-19  bitarray op: relational operators and integer operands, 0.9.1
Request (ET): relational operators == != < <= > >= (also the words ne ge and so on) giving a 1-bit array, so that `in` / `ni` tell "all", "none" or "some" of the pairs; and an integer ("scalar") as an
operand, on either side, which may be a literal, a variable or an [expr].  Choices: the operands are told apart by type: a bitarray is an array, anything else must be an integer of at most 64 bits
(a float, a plain list or a bignum is an error), so `[expr {...}]` and variables work because the command only sees values; two integers are an error.  The comparison is of the numbers, not
the bits: every element fits a Tcl_WideInt (width 64 is signed, the unsigned widths are at most 32), so a signed 16-bit array compares correctly with an unsigned 8-bit one, and `$a == -1` is
false for any unsigned array.  The result has the length of the array operand; with two arrays the lengths must match unless -length zero (the missing elements of the second count as 0);
-length is an error with an integer operand.  Words eq ne lt le gt ge are spellings of the symbols; they compare numbers, not strings as in `expr` (documented).  The error text for a binary
operator with one operand says "operands" for these, since an integer is allowed.  A relational operator needs no new Tcl functions.
lset without an index: ET asked why `lset bar 1` gives "bitarray elements are not lists" (for an ordinary list it is `set bar 1`).  The core hands a hook that case with an index count of 0.
I made the hook return a copy of the value, as `set` would; the process then crashed at the exit of a proc ("alloc: invalid block").  A minimal type with a free procedure (extras not shipped) crashed
the same way, so it is not specific to this extension, but I could not explain it (the reference counts that lset, Tcl_LsetObjCmd and the bytecode keep for a hook's result looked the same to me),
so the change was taken out again: the hook still answers zero indices with the error, test set-1.8a records that, and the difference is item 5 of extras/abstractlist_inconsistencies_ticket.md.
Open: whoever knows the core could say if a hook may return a new object for a count of 0 (and what the reference count of a result must be in the compiled path).
Mutation: O41-O65 for the new code: 24 caught; O55 (a missing element counts as 1) was first missed because the -length zero test compared against a value where 0 and 1 agree.

Benchmarks for `bitarray op` (listbench.tcl, 12 new "bitop" rows, check now compares 54 operations): front end (X = X and Z, which makes a new array and is NOT in place like `bitarray and X $Z`; R = X and Z; value form) against the plain-list lmap loop; land/lor/lnot; ==, !=, <, > 0 and the `1 in` / `0 ni` questions on the result. Linux, 1000 elements: and/or/xor 245-265x faster than a list, op-form X = X and Z about 125x (the front end roughly doubles the 0.25 us of the old command, still sub-microsecond), land/lor/lnot 13-42x, relational 6-12x; at 100,000 elements the relational rows are 7-12x and the logical 14-32x, since they test each element rather than a word at a time. The README now has "Examples with bitarray op" (the five examples, from extras/op_examples.tcl). The old command forms were kept: they update in place without allocating, and the sieve, tests and benchmarks use them; the README shows `op` first.

## 2026-10-19  bitarray op: in-place update with the bare name, 0.9.2
ET asked why `bitarray op a = $a and $b` does not update in place like `bitarray and a $b`: `$a` reaches the command as a value, shared with the variable, so it cannot be changed (the rewrite is `and a <- VALUE $b`, which builds a new array). His idea: write `bitarray op a = a and $b`; a bare word that is the destination's own name cannot be an array or an integer, so it unambiguously means the variable. Done in OpCmd (sameName): the rewrite then drops the arrow and the first source and calls the one-array form. Only for the bitwise operators (the others always make a new array, so there is nothing to save). ET's rule for the edge case: a destination variable name that parses as an integer is an error ("variable name looks like an integer"), checked for every variable form. A different bare word as the first operand is still "not a bitarray". Mutation: O66, O67, O69, O70 caught; O68 (logical operators) dropped as equivalent. mutate6.py --regen now recomputes the recorded line numbers, which went stale when bitarray.c changed.

listbench: the op rows had names longer than the 36-character name column, which pushed the numbers out of line on ET's Windows run (windows_0.9.2_run.txt). Names shortened ("bitop op: X = X and Z (in place)" and so on) and the column now widens to the longest name. Also seen in that run: at 2,000,000 elements the 8-bit rows that allocate a new array are slow (773 us against 131 us in place); not understood, probably the cost of fresh 2 MB blocks on Windows.
Windows at 1,000,000 elements (windows_0.9.2_run_1M.txt): 8-bit new-array rows 94-97 us against 61 in place, so the large gap at 2,000,000 elements (2 MB block) is not an allocation cost in general; probably a large-block threshold, untested.

listbench scenario rows (ET: "use those examples on the much larger sizes, no puts"): five rows, "scenario 1" to "scenario 5", the README examples as computed answers with no output, on data made for them (data scen: X values 0..99, Z = X with every 7th one higher, B 1-bit flags, C counts 0..8). Bitarray column 8-bit (B is 1-bit), the 1-bit column does not apply. The plain-list version uses fused comparisons (one lmap per mask), the fastest way to write it, so the ratio is not flattered. Linux 1,000,000 elements: 31-69 times faster; 100,000: 41-65; 1,000: 19-55 (the 5th is the slowest, seven operations). The check compares the answers at 1000 elements.

## 2026-10-19  bitarray op: integer operand for bitwise operators, 1-bit word paths, 0.9.3
ET un-held both. (1) `bitarray op $a and 1` (either side; and, or, xor, andnot): the integer is checked with ParseValue (the same range rule and messages as lset: an 8-bit array takes 0..255, -8 takes -128..127, a 1-bit array 0 or 1; anything that is not an integer gets the "expected a bitarray or an integer" message), then repeated into every element position of one 64-bit word (ScalarWord, through PutElem on a one-word scratch BitArr so the layout is the array's own), and ScalarApply is the same word loop as for two arrays; andnot is order-sensitive (`1 andnot $a` is 1 & ~a). The result has the array's width and sign. -length with an integer is an error, and so are two integers. Value form, `r = ...` form, and in place with the bare name (`a = a and 6`; copied first if shared). A word that is neither an array nor an integer used to say "not a bitarray: X" and now says the "expected a bitarray or an integer" message (tests op-5.11, 7.10, 10.6 changed). (2) land, lor, lnot with 1-bit operands are the bitwise operators (word at a time), and the relational operators run a word at a time when both operands are 1-bit arrays or one is a 1-bit array and the other an integer (RelBits: for an integer the answer depends only on whether the bit is 0 or 1, so the result is 0s, 1s, the array or its complement). 1,000,000 elements, Linux: land 83,345 -> 9 us for the 1-bit column (was about 2,600 us), == 24 us, > 0 14 us; the 8-bit rows are unchanged. Tests op-11.1 (1-bit against 8-bit data, the same answers, lengths around a word and -length zero) .. 11.10; fi-2.12, 2.13. Mutation testing of this code: not started (ET: wait until asked). Version 0.9.3.

2026-10-19 (0.9.3, ET): the destination name rule is wider: a name that is an integer or begins with a digit ("5", "-3", "5x") is an error in every `op varName = ...` form ("looks like an integer or begins with a digit"); "x5" is fine. listbench: the five bitop rows and the in-place row now use the op spelling (`bitarray op X = X and $Z`, `bitarray op X = not X`), the older commands are not timed any more; the duplicate "X = X and Z (in place)" row was dropped (60 operations compared). The older commands stay in the code and in the tests (README appendix).

## 2026-10-19  bitarray op: friendlier errors, 0.9.4
ET showed that `bitarray op foo = bar` said bad operator "=" and `bitarray op foo = bar and` blamed "bar", each with the whole list of operators. The operator list is now shown only for a bad operator. OpPositionError looks at the other words: "foo = bar and" is a binary operator with one operand ("and needs two arrays"), "foo = bar not" a one-array operator in the wrong place, "and $a $b" an operator in front of both arrays; "foo =" and "foo = bar" say what must follow the "="; arrays in the wrong places (r = $a $a) get the wrong # args message, which now names both forms. When neither of two words is an operator the second is blamed if it is a plain word (not an array or an integer), else the first. Errors found while computing say `bitarray op and:` / `op xor:` / `op lt:` instead of the old command's name (the rewrite hands the old code the name "op and"; relational and logical ones had named non-commands such as "bitarray lt"). Tests: op-12.1 to 12.5; the expected texts of ten op tests changed. Version 0.9.4.

2026-10-19 (0.9.4, ET): the bad operator message lists the operators separated by two spaces instead of commas: bad operator "this": must be one of: and  &  or  |  xor ... (easier to read, and the symbols such as & | , no longer run into the commas).

2026-10-19 (0.9.4, ET): README command tables: the left column is now only the sub-command (new, newfrom, op, ...), under the heading 'Sub-command'; the right column starts with the synopsis lines (with the word bitarray), a blank line, then the description in short paragraphs separated by blank lines, the examples as one block. The same for the two appendix rows.

2026-10-19 (0.9.4, ET): the op row is the first row of the Commands table (it is the command most people should use).

2026-10-19 (0.9.4, ET): tried HTML tables (<td valign="top">) in README.md to get the sub-command name aligned to the top of its row (Visual Studio's preview centres it in a Markdown table cell); in ET's viewer the markup showed as text, so it was reverted to Markdown tables. Open: the vertical alignment in the Visual Studio preview.

2026-10-19 (0.9.4, ET): the op row moved to the end of the Commands table (after tochars): it is by far the longest, and the synopsis already names it.

2026-10-19 (0.9.4, ET): README op row: the Error messages paragraphs were dropped (confusing), the row ends with the note that op cannot be abbreviated to o. Questions ET asked: the value form (no 'varName =') returns the new array and saves nothing; operands are values, so 'a and $b' is an error ('expected a bitarray or an integer ... but got "a"'), and so is 'a and b', which used to say 'not a bitarray: "a"' and now says the same 'expected a bitarray or an integer' message (op-12.6). 413 tests.

2026-10-20 (0.9.5, ET): `bitarray minmax array ?first ?to? last?` returns the list {smallest largest}. Why one command for both: the loop reads each element once either way, so asking for both costs little more than one of them and half of two separate calls; building a two-element list is negligible; ET's idea, with `minmax` as the name. Range words as for count (to, .., end-relative, clamped); an empty array or range is an error (there is no smallest, so no value is invented); 1-bit arrays use CountRange (smallest is 1 only if every element is); widths 8/16/32 (signed or not) and 64 each have their own plain-typed loop (memcpy loads) so the compiler can vectorize it. Considered and not done: an early exit once the type's limits are reached (a branch in the loop costs more than it saves on 8-bit data), a native max or min alone (ET: not needed once minmax exists), returning the indexes too. Measured beforehand with a standalone C program: 1,000,000 elements, both values in one pass, 0.8 to 1.5 ms with -O2 (the plain Tcl route, tcl::mathfunc::max {*}$a, took 76 ms for the max alone).

2026-10-20 (0.9.5, ET): build.sh --fast and --native, build.bat --avx2. First as options (-O2 stayed the default); the same day ET decided the default should be the fastest portable build, so build.sh now defaults to -O3 (--safe = -O2) after the -O3 build passed the tests, faultinject and valgrind; -march=native / AVX2 stay options because they can crash with "illegal instruction" on an older CPU. Considered and not done: gcc's target_clones (a fallback inside one binary; gcc and clang only, and the plain loop is already fast enough for the package) and intrinsics (separate code per width, 64-bit has none before AVX-512).

