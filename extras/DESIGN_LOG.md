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
