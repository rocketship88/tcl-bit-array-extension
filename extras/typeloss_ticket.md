# Appending to an abstract list with a Replace hook keeps or loses the type depending on how the command is evaluated

## Summary

An abstract list whose type provides a `replaceProc` can lose its type when elements are appended. In this report:

* **What happens:** "append at the end" takes one of two paths in the core.
  * `Tcl_ListObjReplace`: the type is kept and the Replace hook is called.
  * `Tcl_ListObjAppendElement` / `TclListObjAppendElements`: the object is converted in place to an ordinary list, and the hook
    is never consulted.
* **What decides the path:** only how the command is evaluated.
  * `linsert` of one element at the end: kept if bytecode-compiled, lost if not compiled.
  * `lappend`: lost when compiled inside a proc (compiled local variable), kept at global or namespace level.
* **Effect:** the resulting list is always correct. Only the representation differs, and with it memory use and speed.
* **Reproduction:** stock Tcl only, using the core's own `lstring` test type in the `tcltest` shell (below).
* **Open question:** I do not know whether this is intended. `doc/ObjectType.3` documents `ReplaceProc` only as corresponding to
  `Tcl_ListObjReplace` and says nothing about append, so I am reporting it as an inconsistency to be judged, not as a certain bug.

## Reproduction (no extension needed)

The core test build has an abstract list with a Replace hook, `lstring` (`generic/tclTestABSList.c`, used by `tests/abstractlist.test`).
It exists only in the `tcltest` shell (`make tcltest`); in an ordinary `tclsh` or `wish` the script fails with `invalid command name "lstring"`.

```tcl
# Reproduction with stock Tcl only: needs a tcltest shell (test commands built in), which provides [lstring].
# [lstring] makes an abstract list that HAS a Replace hook.   Usage: tcltest lstring_repro.tcl
proc type {v} { lindex [tcl::unsupported::representation $v] 3 }
proc mk {} { lstring abcdef }
proc compiled {} {
    set b [mk]; set c [linsert $b end z];  puts "linsert end 1 elem  compiled (INST_LREPLACE)     : [type $c]"
    set b [mk]; lappend b z;               puts "lappend 1 elem       compiled in a proc           : [type $b]"
    set b [mk]; lappend b y z;             puts "lappend 2 elems      compiled in a proc           : [type $b]"
}
proc interpreted {} {   ;# command name in a variable => not compiled => the Tcl_*ObjCmd functions run directly
    set li linsert; set la lappend
    set b [mk]; set c [$li $b end z];      puts "linsert end 1 elem   NOT compiled (Tcl_LinsertObjCmd): [type $c]"
    set b [mk]; set c [$li $b end y z];    puts "linsert end 2 elems  NOT compiled                  : [type $c]"
    set b [mk]; set c [$li $b 2 z];        puts "linsert middle       NOT compiled                  : [type $c]"
    set b [mk]; $la b z;                   puts "lappend 1 elem       NOT compiled (Tcl_LappendObjCmd): [type $b]"
}
compiled; interpreted
```

Run as `./tcltest lstring_repro.tcl`. Output:

```
linsert end 1 elem  compiled (INST_LREPLACE)     : lstring
lappend 1 elem       compiled in a proc           : list
lappend 2 elems      compiled in a proc           : list
linsert end 1 elem   NOT compiled (Tcl_LinsertObjCmd): list
linsert end 2 elems  NOT compiled                  : lstring
linsert middle       NOT compiled                  : lstring
lappend 1 elem       NOT compiled (Tcl_LappendObjCmd): lstring
```

## Which core code does what

Form, then path taken in the core, then the type afterwards:

```
kept  linsert $l end X, compiled
      -> INST_LREPLACE -> Tcl_ListObjReplace
LOST  linsert $l end X, NOT compiled (dynamic command name, {*} command word, ...)
      -> Tcl_LinsertObjCmd, special case "insert one element at the end" -> Tcl_ListObjAppendElement
kept  linsert with 2+ elements, or not at the end
      -> Tcl_ListObjReplace
LOST  lappend v X, compiled in a proc (compiled local), 1 element
      -> lappendScalar -> ListAppendInVar -> Tcl_ListObjAppendElement
LOST  lappend v X Y, compiled in a proc
      -> lappendList -> lappendListDirect -> TclListObjAppendElements
kept  lappend compiled at global/namespace level (source, eval, uplevel)
      -> lappendListStk -> Tcl_ListObjReplace
kept  lappend, NOT compiled
      -> Tcl_LappendObjCmd
```

Both paths marked "lost" end in `TclListObjGetRep` -> `SetListFromAny` (`generic/tclListObj.c`), which converts the object to a real list
in place. `Tcl_ListObjReplace` instead calls the type's Replace hook (`TclObjTypeHasProc(listObj, replaceProc)`).

Side observation that made this look random at first: the main script given to `tclsh` is, from my reading of `Tcl_FSEvalFileEx`
(`TclEvalEx`), evaluated directly and not compiled, while a `source`d file and procs are compiled, so the same line of code behaves
differently at the top of the main script than inside a proc. I did not confirm that in a debugger.

## Why it matters

An extension that provides a compact abstract list (I found this with a packed bit-array type that stores 1 bit per element)
loses its representation silently on a single `lappend`. For a ten-million-element array that turns a few MB into an ordinary
list (I measured +76 to 152 MB for `{*}$a` expansion of such an array; I did not measure the cost of the in-place conversion itself).

`lseq` (arithseries) cannot show this, because it has no Replace hook and appending to an arithmetic sequence has to leave the type
anyway; that is why the reproduction uses `lstring`.

## Test coverage

`tests/abstractlist.test` already checks type preservation, so this is not an untested area:

* It has many "no shimmer ..." tests, and some that assert the opposite on purpose ("shimmer lassign", "shimmer lset",
  "!no shimmer lreplace").
* Its `linsert` tests (abstractlist-2.7, 3.7 and the 4.7 variant) insert several elements in the middle of an `lstring`
  (positions 11, 35 and 12). That goes through `Tcl_ListObjReplace`, and the tests confirm the type is kept.

What I found no test for (`lstring` appears in no other test file):

* `lappend` onto an `lstring`.
* `linsert` of a single element at the end.
* The same operation run both compiled and not compiled.

Those would be natural places for a regression test, whichever way this is resolved.

## Possible directions (for discussion only)

* Have `TclListObjAppendElements` (and so `Tcl_ListObjAppendElement`) use the Replace hook when the object has one, the way
  `Tcl_ListObjReplace` does; or
* document that append ignores the hook, so extension authors know to expect the conversion.

## Environment

* Clean checkout of `github.com/tcltk/tcl` at `e36db3376a2d7d4857f6c766bd6133fc7b29e821` (2026-10-02, "Update to the 'official'
  utf8proc 2.12.0"), `git status` clean.
* Linux x86-64, gcc, `./configure --disable-shared && make tcltest`.
* The same results were also seen with an extension on an earlier trunk (`3d77be8951`).
* Independently reproduced by the reporter on a second Linux machine (a virtual machine), with a stock tree built from a Fossil
  check-in whose `tcl::build-info` reads `9.1.1+4991a47b94705ddff07bd81cab83291e5f6d219a8a75b54a32c954e73b05eaae.gcc-1303.tommath-0103`
  (shared build, gcc); `./tcltest lstring_repro.tcl` printed the same seven lines. The reporter built that tree from a stock, unmodified checkout
  fetched a day or two before 2026-10-13. It is a Fossil id, so it is not directly comparable with the git commit above.
* Not tested: other platforms, Tcl 9.0.x (the version-2 abstract-list hooks are 9.1 only), other compilers.

## Note on how this was produced

The analysis and the reproduction script were produced with Claude (an AI assistant made by Anthropic) working with me; the
results above are from runs of the script, and the source references are from reading the files named.
