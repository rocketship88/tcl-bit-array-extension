# Apparent inconsistencies in the abstract list API (minor, for discussion)

Type: Documentation / Minor.  Priority: low.  Component: lists, `Tcl_ObjType` v2 hooks.
Version: Tcl 9.1.1 source tree, Linux x86-64, gcc.  Not rechecked on trunk.

## Why this report

I am writing an extension that implements a packed bit array as an abstract list (all the v2 hooks), and I have been testing
its behaviour against the core's own abstract lists.  Along the way I found several places where the core behaves
differently from what the manual says, or differently from one path to another.  None of them is serious: I do not know
which of them are intended, so this is a list for people who know the design to comment on, not a set of confirmed bugs.
Every item has a short script; the ones that need C use a 30-line probe.  Everything is reproducible with the core's own
`lstring` test type (`tcltest` shell, `make tcltest`), no extension needed.  The scripts are at the end of this report, so it is
self-contained: save each block to a file with the name in its heading.

Each item says what is **observed** (run, output shown) and what is only **my reading** of the source.

Related, filed separately: lappend type loss (0c82728f85); two more reports from 2026-10-18 [numbers to be added].

## 1. `Tcl_ListObjReplace` passes its arguments to a Replace hook unnormalized

**Observed.**  For a list with a `replaceProc`, `Tcl_ListObjReplace` calls the hook before it clamps `first` and
`numToDelete`; the clamping that follows is only for ordinary lists (`generic/tclListObj.c`, near line 2187).
`Tcl_ListObjRange` does the opposite: it normalizes the range with `TclNormalizeRangeLimits` and only then calls the
`sliceProc`.  The manual page of `Tcl_ListObjReplace` (doc/ListObj.3) defines the meaning of out-of-range values (first <= 0 is
the start; first >= length appends; count <= 0 deletes nothing), and doc/ObjectType.3 says the ReplaceProc "correlates to the
Tcl_ListObjReplace C API".  The core's only Replace hook, `LStringReplace` (generic/tclTestABSList.c), copies those rules into a
comment but does not apply them.

The same documented call on an ordinary list and on `lstring` (probe `abstractlist_replprobe.c` and script
`abstractlist_replace_repro.tcl`, both below; result = {length, string}):

```
first count : ordinary list a..f   |  lstring abcdef
    1     2 : 4 {a d e f}          |  4 {a d e f}
   -3     2 : 4 {c d e f}          |  4 {c d e f}
    3    99 : 3 {a b c}            |  -93 {}                 <- negative length
   99     1 : 6 {a b c d e f}      |  5 {a b c d e}          <- deleted the last element
    2    -5 : 6 {a b c d e f}      |  11 {a b }              <- garbage
```

Scripts cannot reach this: `lreplace` and `linsert` clamp their indexes before they call.  Only a C caller of the public
function does.

**Question.**  Is a hook expected to do the clamping itself (then ObjectType.3 should say so, and `LStringReplace` should do it),
or should `Tcl_ListObjReplace` normalize before dispatching, as `Tcl_ListObjRange` already does?  The second is a few lines.

## 2. `lpop l INDEX` calls the SetElement hook with a NULL value: undocumented, and the reference-count contract differs from `lset`

**Observed.**
* doc/ObjectType.3 (SetElement) says only that the function "correlates to the `lset` command".  That the value is NULL for
  `lpop` appears only in comments on `TclLsetFlat` (generic/tclListObj.c, "NULL to 'lpop'") and in `Tcl_LpopObjCmd`.
* `Tcl_LpopObjCmd` (generic/tclCmdIL.c, near line 2668) calls the hook and then `TclUndoRefCount(listPtr)`, under the comment
  "TclLsetFlat adds a ref count which is handled".  `TclLsetList` (lset) does the opposite: it calls the hook and does
  `Tcl_IncrRefCount` itself.  So a hook has to return an object with an extra reference for lpop but not for lset; nothing says so.
* With `lstring`, which returns the same object when it is unshared, `lpop b 1` leaves the variable's value with one reference too
  few (`abstractlist_lpop_refcount_repro.tcl`):

```
after lset b 1 X : refcount 4
after lpop b 1   : refcount 3
```

  and a later use ends in `alloc: invalid block` (TCL_MEM_DEBUG) or a segmentation fault; the script in the file does it with two
  commands and an `uplevel`.  I did not trace why it needs that particular shape.

I hit the same asymmetry in my extension (a hook that returned the same object crashed `lpop l INDEX`; returning a fresh copy
fixed it), which is how I came to look.

**Question.**  Is the intended contract "return an object with reference count 0 for lpop"?  If so it should be in ObjectType.3, and
`LStringSetElem` should follow it.

## 3. Type loss: which operations keep an abstract list, which turn it into an ordinary list

**Observed** (`abstractlist_typeloss_repro.tcl`, `lstring`; all values are correct, only the type changes):

```
nested lset into an element        : a Z c d e f / list
dict lappend onto a dict value     : a b c d e f Z / list
linsert end, not bytecode-compiled : list
lappend (global level)             : lstring
lappend in a proc                  : list
```

* `lappend` and `linsert ... end`: ticket 0c82728f85 (the append paths bypass the Replace hook).
* `lset l 0 1 Z` where element 0 is the abstract list, and `dict lappend d k Z` where the value is: the same effect, by a different
  path; I have not read those paths as closely.

**Question.**  Is keeping the type meant to be guaranteed anywhere, or best effort?  If best effort, a line in ObjectType.3 would
save implementers from discovering it.

## 4. Smaller: `lstring` resolves `end` one past the last element

**Observed.**  `LStringSetElem` calls `Tcl_GetIntForIndex(interp, indices[0], lstringRepPtr->strlen, ...)`: the end value is
`strlen`, not `strlen - 1`.  `lset b end X` on `lstring abcdef` gives `a b c d e f X` (appends) instead of `a b c d e X`, and
`lpop b end` returns `f` and leaves the list unchanged.  Probably just a test-type slip, but it is the reference implementation, and
an extension that copies it would inherit it.

## 5. Smaller: `lset listVar value` (no index) reaches the SetElement hook with an index count of 0

**Observed.**  For an ordinary list, `lset l value` is documented in the source as a synonym for `set l value`
(`TclLsetFlat`: "If there are no indices, simply return the new value").  `Tcl_LsetObjCmd` and `INST_LSET_FLAT` hand a type that has a
SetElement hook the call `hook(interp, list, 0, objv+2, value)` without that shortcut, so the hook decides what zero indices mean.
The core's own `lstring` hook (`LStringSetElem`) reads `indices[0]` without checking the count; with a count of 0 that is the value argument, so

    % set s [lstring abcdef]
    % lset s X
    bad index "X": must be integer?[+-]integer? or end?[+-]integer?

(for an ordinary list `lset l X` just gives `X`).  The hook documentation does not say whether a count of 0 can occur or what it should mean.
Our extension answers it with an error ("elements are not lists").

## What I am not claiming

* Not a security or correctness problem for scripts: items 1 and 4 need a C caller or a test type; item 3 never gives wrong values; item 5 is an error message where an ordinary list would take the value.
* I have not looked at trunk, or at other abstract list types (`lseq`/arithseries, `lrange`).
* Items 1 and 2 are the ones I would most like to hear are intended or not, because a hook implementer cannot tell.

## Scripts

Run the Tcl scripts with the `tcltest` shell (`./tcltest FILE`), from the Tcl build directory.

### abstractlist_replprobe.c

Build: `gcc -fPIC -shared -DUSE_TCL_STUBS -I TCLSRC/generic abstractlist_replprobe.c TCLBUILD/libtclstub.a -o libreplprobe.so`

```c
/* abstractlist_replprobe.c -- replprobe TYPE FIRST COUNT: make an abstract list with "lstring abcdef" (or a plain list "a b c d e f"), call the public
 * Tcl_ListObjReplace(interp, list, FIRST, COUNT, 0, NULL) on it (unshared), and report the result. */
#include <tcl.h>
static int ProbeCmd(void *cd, Tcl_Interp *interp, Tcl_Size objc, Tcl_Obj *const objv[])
{
    Tcl_WideInt first, count;
    Tcl_Obj *l, *res;
    Tcl_Size len;
    if (objc != 4) { Tcl_WrongNumArgs(interp, 1, objv, "lstring|plain first count"); return TCL_ERROR; }
    if (Tcl_GetWideIntFromObj(interp, objv[2], &first) != TCL_OK || Tcl_GetWideIntFromObj(interp, objv[3], &count) != TCL_OK) return TCL_ERROR;
    if (Tcl_EvalEx(interp, Tcl_GetString(objv[1])[0] == 'l' ? "lstring abcdef" : "list a b c d e f", -1, 0) != TCL_OK) return TCL_ERROR;
    l = Tcl_DuplicateObj(Tcl_GetObjResult(interp)); Tcl_IncrRefCount(l); Tcl_ResetResult(interp);
    if (Tcl_ListObjReplace(interp, l, (Tcl_Size)first, (Tcl_Size)count, 0, NULL) != TCL_OK) { Tcl_DecrRefCount(l); return TCL_ERROR; }
    Tcl_ListObjLength(interp, l, &len);
    res = Tcl_NewListObj(0, NULL);
    Tcl_ListObjAppendElement(NULL, res, Tcl_NewWideIntObj(len));
    Tcl_ListObjAppendElement(NULL, res, Tcl_NewStringObj(Tcl_GetString(l), -1));
    Tcl_DecrRefCount(l);
    Tcl_SetObjResult(interp, res);
    return TCL_OK;
}
int Replprobe_Init(Tcl_Interp *interp)
{
    if (Tcl_InitStubs(interp, "9.1", 0) == NULL) return TCL_ERROR;
    Tcl_CreateObjCommand2(interp, "replprobe", ProbeCmd, NULL, NULL);
    return TCL_OK;
}
```

### abstractlist_replace_repro.tcl (item 1)

```tcl
# Calls the public Tcl_ListObjReplace(first, count, 0 new elements) on an ordinary list and on the core's own abstract list
# [lstring] (it has a Replace hook).  Needs the tcltest shell (it has [lstring]) and the probe in abstractlist_replprobe.c:
#   gcc -fPIC -shared -DUSE_TCL_STUBS -I TCLSRC/generic abstractlist_replprobe.c TCLBUILD/libtclstub.a -o libreplprobe.so
#   ./tcltest abstractlist_replace_repro.tcl
load ./libreplprobe.so Replprobe
puts "first count : ordinary list a..f -> {length string}   |   lstring abcdef -> {length string}"
foreach {f c} {1 2  -3 2  3 99  99 1  2 -5} {
    puts [format "%5d %5d : %-24s | %s" $f $c [replprobe plain $f $c] [replprobe lstring $f $c]]
}
```

### abstractlist_lpop_refcount_repro.tcl (item 2)

```tcl
# lpop with an index on the core's abstract list [lstring] (tcltest shell, built with TCL_MEM_DEBUG) leaves the object with one
# reference too few.  The object's refcount, seen through [tcl::unsupported::representation], after [lset] and after [lpop]:
proc rc {v} { regexp {refcount of (\d+)} [tcl::unsupported::representation $v] -> n; set n }
set b [lstring abcdef]; lset b 1 X;  puts "after lset b 1 X : refcount [rc $b]"
set b [lstring abcdef]; lpop b 1;    puts "after lpop b 1   : refcount [rc $b]"
# and a script that ends with "alloc: invalid block" in a TCL_MEM_DEBUG build:
proc show {script} { uplevel 1 $script }
set b [lstring abcdef]
show {list [lpop b 1] $b}
puts "before the assignment"
set b 0
puts "not reached"
```

The last two commands crash; I saw both `alloc: invalid block` and a segmentation fault.

### abstractlist_typeloss_repro.tcl (item 3)

```tcl
# Which operations turn an abstract list into an ordinary list (tcltest shell, [lstring]); the values are all correct.
proc type {v} { lindex [tcl::unsupported::representation $v] 3 }
set e [lstring abcdef]; set l [list $e y]; lset l 0 1 Z
puts "nested lset into an element        : [lindex $l 0] / [type [lindex $l 0]]"
set d [dict create k [lstring abcdef]]; dict lappend d k Z
puts "dict lappend onto a dict value     : [dict get $d k] / [type [dict get $d k]]"
set li linsert; set b [lstring abcdef]; set c [$li $b end z]
puts "linsert end, not bytecode-compiled : [type $c]"
set b [lstring abcdef]; lappend b z
puts "lappend (global level, see ticket 0c82728f85) : [type $b]"
proc f {} { set b [lstring abcdef]; lappend b z; type $b }
puts "lappend in a proc                  : [f]"
```
