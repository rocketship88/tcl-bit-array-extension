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
