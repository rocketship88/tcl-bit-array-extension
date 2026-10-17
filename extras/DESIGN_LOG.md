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
- Always-braces style (no one-line `if (x) stmt;`) was proposed by ET to make folding easier and was NOT adopted after discussion; the fold finder works on brace depth and
  folds only blocks that are braced (switch cases, if / else if / else); loops (for, while, do) are not folded.  Fold is off by default.
- `.nojekyll` at the repository root: GitHub's Jekyll fails on `{{}` in extras/typeloss_ticket_comment.md; it must stay.
- The stepper has no call-stack panel (an early description of it was wrong): it shows memory (variables, heap objects with reference counts, words in hex), a caption naming
  the core function and the Tcl_ObjType hook, and "Show code" with one tab per function in order.
- Tcl 9.1 stays the minimum (9.0.5 refuses to load on purpose; with the check relaxed, 6 tests that use lappend fail).
