Follow-up with a tested fix: a patch (9 lines added, 2 removed) and six tests, both below. Against trunk of 2026-10-15, commit 102a512.

Compiled lappend in a proc turns an abstract-list value into an ordinary list in every form I tried, on 9.1.1 and on trunk:

    lappend v x
    lappend v {*}$list
    lappend v {*}{a b}
    lappend A(k) x
    lappend A(k) {*}$list
    lappend $name x

The causes are two calls that convert the object in place and never reach the type's Replace hook:

* ListAppendInVar in tclVar.c calls Tcl_ListObjAppendElement. This handles lappend v x, array elements and lappend $name x.
* lappendListDirect in tclExecute.c calls TclListObjAppendElements. This handles lappend v {*}list, including array elements.

The patch changes both to Tcl_ListObjReplace (insert at the end). The branch of INST_LAPPEND_LIST that already calls Tcl_ListObjReplace keeps the type, as do uncompiled lappend and lappend at the top level of a script.

Checked, with the test type "lstring" from tclTestABSList.c (it has a Replace hook):
* The six tests below fail on unpatched trunk (the value becomes a "list") and pass with the patch.
* With the patch, abstractlist.test, listTypes.test, list.test, listObj.test and listRep.test: 11526 tests, 0 failed.

Not checked: whether any caller relies on the type being lost, whether the extra length lookup costs anything measurable for plain lists, and the other callers of TclListObjAppendElements.

Patch (apply with patch -p1):

--- a/generic/tclExecute.c
+++ b/generic/tclExecute.c
@@ -3624,7 +3624,7 @@ TEBCresume(
 	    varPtr->value.objPtr = objResultPtr = newValue;
 	    Tcl_IncrRefCount(newValue);
 	}
-	if (TclListObjAppendElements(interp, objResultPtr, objc, objv)
+	if (Tcl_ListObjReplace(interp, objResultPtr, len, 0, objc, objv)
 		!= TCL_OK) {
 	    TRACE_ERROR(interp);
 	    goto gotError;
--- a/generic/tclVar.c
+++ b/generic/tclVar.c
@@ -1872,7 +1872,14 @@ ListAppendInVar(
 	Tcl_IncrRefCount(oldValuePtr);	/* Since var is referenced. */
     }
 
-    return Tcl_ListObjAppendElement(interp, oldValuePtr, newValuePtr);
+    {
+	Tcl_Size len;
+
+	if (TclListObjLength(interp, oldValuePtr, &len) != TCL_OK) {
+	    return TCL_ERROR;
+	}
+	return Tcl_ListObjReplace(interp, oldValuePtr, len, 0, 1, &newValuePtr);
+    }
 }
 
 static inline void

Tests (they go in tests/abstractlist.test just before the "# cleanup" line, and use the testobj and lstring constraints that file already defines; with them the file runs 129 tests, 6 more than before: 6 fail on unpatched trunk, 0 fail with the patch):

# lappend must keep an abstract list's type (the type has a Replace hook).  The tests use apply so the
# lappend is compiled inside a proc body, which is where the type used to be lost.
test abstractlist-lappend-1.1 {lappend of one element keeps the abstract list type} -constraints {testobj lstring} -body {
    apply {{} {set l [lstring abc]; lappend l d; list [testobj objtype $l] $l}}
} -result {lstring {a b c d}}
test abstractlist-lappend-1.2 {lappend {*}$list keeps the abstract list type} -constraints {testobj lstring} -body {
    apply {{} {set l [lstring abc]; set x {d e}; lappend l {*}$x; list [testobj objtype $l] $l}}
} -result {lstring {a b c d e}}
test abstractlist-lappend-1.3 {lappend {*}{literal list} keeps the abstract list type} -constraints {testobj lstring} -body {
    apply {{} {set l [lstring abc]; lappend l {*}{d e}; list [testobj objtype $l] $l}}
} -result {lstring {a b c d e}}
test abstractlist-lappend-1.4 {lappend to an array element keeps the abstract list type} -constraints {testobj lstring} -body {
    apply {{} {set A(x) [lstring abc]; lappend A(x) d; list [testobj objtype $A(x)] $A(x)}}
} -result {lstring {a b c d}}
test abstractlist-lappend-1.5 {lappend {*}$list to an array element keeps the abstract list type} -constraints {testobj lstring} -body {
    apply {{} {set A(x) [lstring abc]; set x {d e}; lappend A(x) {*}$x; list [testobj objtype $A(x)] $A(x)}}
} -result {lstring {a b c d e}}
test abstractlist-lappend-1.6 {lappend $name keeps the abstract list type} -constraints {testobj lstring} -body {
    apply {{} {set l [lstring abc]; set n l; lappend $n d; list [testobj objtype $l] $l}}
} -result {lstring {a b c d}}
