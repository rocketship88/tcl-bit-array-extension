#!/usr/bin/env python3
"""Mutation testing for bitarray.c: apply each deliberate bug in turn, rebuild, run the test suite, report whether
it was CAUGHT (a test fails or the run crashes) or MISSED.  A development tool; it is not needed to use the extension.

usage (from anywhere):
    BITARRAY_INCLUDE=/opt/tcl9.1/include BITARRAY_STUBLIB=/opt/tcl9.1/lib/libtclstub.a \
    BITARRAY_TCLSH=/opt/tcl9.1/bin/tclsh9.1  python3 extras/mutate5.py  [M01 W17 ...]
Environment:
    BITARRAY_INCLUDE   directory holding tcl.h (and BITARRAY_INCLUDE2, optional, a second one: unix/ of a source tree)
    BITARRAY_STUBLIB   the stubs library file
    BITARRAY_TCLSH     the tclsh to run the tests with
    CC                 compiler (default cc)
    LD_LIBRARY_PATH / TCL_LIBRARY are passed through if your tclsh needs them.
With names given it runs only those mutants.  Takes about 10-30 minutes for all 138 (each runs the whole suite).
"""
import subprocess, os, shutil, sys, re, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = open(os.path.join(ROOT, 'bitarray.c')).read()
TESTFILE = os.path.join(ROOT, 'tests', 'bitarray.test')
for v in ('BITARRAY_INCLUDE', 'BITARRAY_STUBLIB', 'BITARRAY_TCLSH'):
    if v not in os.environ:
        sys.exit('mutate5.py: set %s (see the top of this file)' % v)
INC = [os.environ['BITARRAY_INCLUDE']] + ([os.environ['BITARRAY_INCLUDE2']] if 'BITARRAY_INCLUDE2' in os.environ else [])
STUB = os.environ['BITARRAY_STUBLIB']
TCLSH = os.environ['BITARRAY_TCLSH']
CC = os.environ.get('CC', 'cc')
MUT = [
 # ---- carried over from rounds 1-4 (patterns updated for the width-generic code) ----
 ("M01 GETBIT shift mask 63->31", "#define GETBIT(b,i)\t(((b)->words[(i) >> 6] >> ((i) & 63)) & 1)", "#define GETBIT(b,i)\t(((b)->words[(i) >> 6] >> ((i) & 31)) & 1)"),
 ("M02 SETBIT or -> xor", "#define SETBIT(b,i)\t((b)->words[(i) >> 6] |= (uint64_t)1 << ((i) & 63))", "#define SETBIT(b,i)\t((b)->words[(i) >> 6] ^= (uint64_t)1 << ((i) & 63))"),
 ("M03 CLRBIT loses ~", "&= ~((uint64_t)1 << ((i) & 63)))", "&= ((uint64_t)1 << ((i) & 63)))"),
 ("M04 size limit 2^40 -> 2^41", "#   define BA_MAX_BITS_NORMAL\t((Tcl_WideInt)1 << 40)", "#   define BA_MAX_BITS_NORMAL\t((Tcl_WideInt)1 << 41)"),
 ("M33 new: size check on narrowed value dropped", "if (w < 0 || w > BA_MAX_BITS / width) {", "if (w < 0) {"),
 ("M34 replace: growth limit dropped", "if (wideLen > BA_MAX_BITS / b->width) {", "if (0) {"),
 ("M35 capacity not doubled", "Tcl_Size newCap = b->capWords * 2,", "Tcl_Size newCap = 0,"),
 ("M36 shrink does not clear vacated bits", "ClearBits(b, newLen, oldLen - newLen);", ";"),
 ("M37 MoveElems direction reversed", "    if (to < from) {\n\t/*\n\t * Moving left.", "    if (to > from) {\n\t/*\n\t * Moving left."),
 ('M38 new capacity not zeroed', '\tmemset(&b->words[oldCap], 0,                 // the new words start as 0\n\t\t(size_t)(newCap - oldCap) * sizeof(uint64_t));\n\tb->capWords = newCap;', '\tb->capWords = newCap;'),
 ('M39 rep pointer not updated after realloc', '\tlistObj->internalRep.twoPtrValue.ptr1 = b;   // the object points at the block, which may have moved\n    }', '\t;\n    }'),
 ("M40 word count not updated", "    b->nwords = needWords;\n    Tcl_InvalidateStringRep(listObj);", "    Tcl_InvalidateStringRep(listObj);"),
 ("M41 element cache not dropped by replace", "    /* The element cache refers to the old contents; drop it first. */\n    FreeElems(b);\n", ""),
 ('M42 first-index clamp removed', '    if (first > oldLen) {\n        first = oldLen;\n    }\n    if (numToDelete < 0) {\n        numToDelete = 0;\n    }', '    if (numToDelete < 0) {\n        numToDelete = 0;\n    }'),
 ("M05 index bound > for >=", "if (index < 0 || index >= b->len) {\n\t*elemPtr = NULL;", "if (index < 0 || index > b->len) {\n\t*elemPtr = NULL;"),
 ('M06 slice upper clamp', '    if (to >= b->len) {\n        to = b->len - 1;\n    }', '    if (to > b->len) {\n        to = b->len - 1;\n    }'),
 ("M07 slice tail mask removed", "\t    n->words[n->nwords - 1] &= ~(~(uint64_t)0 << (len & 63));", "\t    ;"),
 ('M08 slice lower clamp removed', '    if (from < 0) {        // clamp the range to the array\n        from = 0;\n    }\n    if (to >= b->len) {\n        to = b->len - 1;\n    }', '    if (to >= b->len) {\n        to = b->len - 1;\n    }'),
 ("M09 reverse (width 1) shift off by one", ">> (64 - m);", ">> (63 - m);"),
 ('M10 setElement append disabled', '    if (idx < 0 || idx > b->len) {   // idx == len is allowed: it appends\n\tIndexError(interp, indexArray[0]);', '    if (idx < 0 || idx >= b->len) {\n\tIndexError(interp, indexArray[0]);'),
 ('M11 setElement never duplicates', '    if (Tcl_IsShared(obj)) {                                                                // never change a shared object: work on a copy\n\tobj = Tcl_DuplicateObj(obj);\n    }\n    if (idx == GETREP(obj)->len) {', '    if (0) {\n\tobj = Tcl_DuplicateObj(obj);\n    }\n    if (idx == GETREP(obj)->len) {'),
 ('M12 Touch keeps string rep', '    FreeElems(GETREP(obj));         // the cached element objects are stale after a change\n    Tcl_InvalidateStringRep(obj);   // and so is the string form', '    FreeElems(GETREP(obj));         // the cached element objects are stale after a change   // and so is the string form'),
 ('M13 Touch keeps element cache', '    FreeElems(GETREP(obj));         // the cached element objects are stale after a change\n    Tcl_InvalidateStringRep(obj);   // and so is the string form', '    Tcl_InvalidateStringRep(obj);   // and so is the string form'),
 ('M14 replace delete clamp removed', '    if (numToDelete > oldLen - first) {\n        numToDelete = oldLen - first;\n    }', '    '),
 ("M15 replace tail move count off by one", "oldLen - (first + numToDelete));", "oldLen - (first + numToDelete) - 1);"),
 ('M17 count first mask', '    fm = ~(uint64_t)0 << (first & 63);                // first word: bits from FIRST up\n    lm = ~(uint64_t)0 >> (63 - (last & 63));          // last word: bits up to LAST\n    if (fw == lw) {\n\treturn BA_POPCOUNT(b->words[fw] & fm & lm);   // one word: the 1 bits inside both masks', '    fm = ~(uint64_t)0 << ((first + 1) & 63);\n    lm = ~(uint64_t)0 >> (63 - (last & 63));          // last word: bits up to LAST\n    if (fw == lw) {\n\treturn BA_POPCOUNT(b->words[fw] & fm & lm);   // one word: the 1 bits inside both masks'),
 ('M18 count last mask', '    lm = ~(uint64_t)0 >> (63 - (last & 63));          // last word: bits up to LAST\n    if (fw == lw) {\n\treturn BA_POPCOUNT(b->words[fw] & fm & lm);   // one word: the 1 bits inside both masks', '    lm = ~(uint64_t)0 >> (62 - (last & 63));\n    if (fw == lw) {\n\treturn BA_POPCOUNT(b->words[fw] & fm & lm);   // one word: the 1 bits inside both masks'),
 ("M19 next start mask removed", "& (~(uint64_t)0 << (start & 63));", "& ~(uint64_t)0;"),
 ("M20 next tail check removed", "return idx < b->len ? idx : -1;", "return idx;"),
 ('M21 fill single-word mask', '\tif (val) {\n\t    b->words[fw] |= (fm & lm);\n\t} else {\n\t    b->words[fw] &= ~(fm & lm);\n\t}', '\tif (val) {\n\t    b->words[fw] |= fm;\n\t} else {\n\t    b->words[fw] &= ~fm;\n\t}'),
 ('M22 fill middle loop <=', '    for (i = fw + 1; i < lw; i++) {                          // whole words in between\n\tb->words[i] = val ? ~(uint64_t)0 : 0;', '    for (i = fw + 1; i <= lw; i++) {\n\tb->words[i] = val ? ~(uint64_t)0 : 0;'),
 ('M23 fill step stop early (1-bit)', '\t\t    if (bit) {\n\t\t        SETBIT(b, i);\n\t\t    } else {\n\t\t        CLRBIT(b, i);\n\t\t    }\n\t\t    if (last - i < step) {     // i + step could pass the end, and overflow, so test last - i\n\t\t        break;\n\t\t    }', '\t\t    if (bit) {\n\t\t        SETBIT(b, i);\n\t\t    } else {\n\t\t        CLRBIT(b, i);\n\t\t    }\n\t\t    if (last - i <= step) {     // i + step could pass the end, and overflow, so test last - i\n\t\t        break;\n\t\t    }'),
 ('M24 fill empty range check removed', '\tif (first > last) {             // an empty range: nothing to do, not an error\n\t    return TCL_OK;\n\t}\n\tif (first < 0 || last >= b->len) {   // out of range is an error', '\tif (first < 0 || last >= b->len) {   // out of range is an error'),
 ("M25 ParseBit fast path accepts longer", "obj->length == 1\n\t    && (obj->bytes[0]", "obj->length >= 1\n\t    && (obj->bytes[0]"),
 ('M26 string rep separator', "\t    if (i + 1 < b->len) {          // a space between elements, none after the last\n\t        *p++ = ' ';\n\t    }", "\t    if (i + 1 < b->len) {          // a space between elements, none after the last\n\t        *p++ = ',';\n\t    }"),
 ("M27 dup copies one word short", "memcpy(d->words, s->words, (size_t)s->nwords * sizeof(uint64_t));", "memcpy(d->words, s->words, (size_t)(s->nwords > 1 ? s->nwords - 1 : s->nwords) * sizeof(uint64_t));"),
 ('M28 new: no memset', '    memset(b, 0, bytes);              // every bit 0, the unused ones past the end too\n    b->len = len;', '    b->len = len;'),
 ('M29 count last clamp', '\t    if (last >= b->len) {\n\t        last = b->len - 1;\n\t    }\n\t}\n\tval = 1;                        // no value given: count the 1s (or the non-zero elements)', '\t    if (last > b->len) {\n\t        last = b->len - 1;\n\t    }\n\t}\n\tval = 1;                        // no value given: count the 1s (or the non-zero elements)'),
 ("M30 elems cache swapped", "b->elems[i] = GETBIT(b, i) ? b->one : b->zero;", "b->elems[i] = GETBIT(b, i) ? b->zero : b->one;"),
 ("M31 new init-one tail not masked", "SetRangeOnes(n, 0, n->len - 1, 1);", "memset(n->words, 0xff, (size_t)n->nwords * 8);"),
 ("M32 replace leaves stale string", "    b->nwords = needWords;\n    Tcl_InvalidateStringRep(listObj);", "    b->nwords = needWords;"),
 # ---- new for widths ----
 ("W01 GetElem 16 wrong offset", "memcpy(&v, p + 2 * (size_t)i, 2); return v;", "memcpy(&v, p + 3 * (size_t)i, 2); return v;"),
 ("W02 GetElem 32 wrong offset", "memcpy(&v, p + 4 * (size_t)i, 4); return v;", "memcpy(&v, p + 2 * (size_t)i, 4); return v;"),
 ("W03 GetElem 64 wrong offset", "memcpy(&v, p + 8 * (size_t)i, 8); return v;", "memcpy(&v, p + 4 * (size_t)i, 8); return v;"),
 ("W04 PutElem 8 ORs instead of assigns", "case 8:  p[i] = (unsigned char)val; break;", "case 8:  p[i] |= (unsigned char)val; break;"),
 ("W05 PutElem 16 wrong offset", "memcpy(p + 2 * (size_t)i, &v, 2); break; }", "memcpy(p + 3 * (size_t)i, &v, 2); break; }"),
 ("W06 PutElem 32 wrong offset", "memcpy(p + 4 * (size_t)i, &v, 4); break; }", "memcpy(p + 2 * (size_t)i, &v, 4); break; }"),
 ("W07 PutElem 64 wrong offset", "case 64: memcpy(p + 8 * (size_t)i, &val, 8); break;", "case 64: memcpy(p + 4 * (size_t)i, &val, 8); break;"),
 ('W08 ElemWide sign only for 32', '    if (b->width == 64) {                                // 64 is always signed\n        return (Tcl_WideInt)(int64_t)val;\n    }', '    if (b->width == 32) {                                // 64 is always signed\n        return (Tcl_WideInt)(int64_t)val;\n    }'),
 ('W09 ElemObj 1 returns zero', '    if (val == 1) {\n        return b->one;\n    }', '    if (val == 1) {\n        return b->zero;\n    }'),
 ("W10 ParseValue upper bound off by one", "v <= (Tcl_WideInt)(((uint64_t)1 << width) - 1)) {", "v <= (Tcl_WideInt)(((uint64_t)1 << width))) {"),
 ("W11 ParseValue accepts -1", "if (v >= 0 && v <= (Tcl_WideInt)", "if (v >= -1 && v <= (Tcl_WideInt)"),
 ('W12 ParseValue 64-bit path skipped', '\tif (width == 64) {                                  // any 64-bit value is valid\n\t    *vp = (uint64_t)v;', '\tif (width == 99) {\n\t    *vp = (uint64_t)v;'),
 ("W13 ParseValue digit fast path too wide", "obj->bytes[0] >= '0' && obj->bytes[0] <= '9') {", "obj->bytes[0] >= '0' && obj->bytes[0] <= 'z') {"),
 ("W14 NewRep limit ignores width", "(Tcl_WideInt)len * width > BA_MAX_BITS", "(Tcl_WideInt)len > BA_MAX_BITS"),
 ("W15 NewRep allocates for 1-bit only", "nwords = WORDS_FOR(len, width);", "nwords = (len + 63) / 64;"),
 ("W16 WORDS_FOR rounds down by one", "* (width) + 63) / 64))", "* (width) + 62) / 64))"),
 ('W17 FreeElems never releases owned elements', '\tif (b->width != 1) {   // 1-bit elements are all the shared 0 and 1\n\t    Tcl_Size i;', '\tif (0) {\n\t    Tcl_Size i;'),
 ("W18 FreeElems also releases shared 0/1", "if (b->elems[i] != b->zero && b->elems[i] != b->one) {", "if (1) {"),
 ('W19 GetElements forgets to take a reference', '\t\tif (e != b->zero && e != b->one) {                   // we own a reference to each new object\n\t\t    Tcl_IncrRefCount(e);\n\t\t}', '\t\t   // we own a reference to each new object'),
 ('W20 GetElements does not record its length', '\tb->elemsLen = b->len;   // FreeElems needs the count\n    }', '    }'),
 ("W21 Slice wide copies from offset 0 units", "memcpy(BYTES(n), BYTES(b) + (size_t)from * EBYTES(b),", "memcpy(BYTES(n), BYTES(b) + (size_t)from,"),
 ("W22 Slice wide copies too few bytes", "\t\t(size_t)len * EBYTES(b));\n    } else if ((from & 63) == 0) {", "\t\t(size_t)len);\n    } else if ((from & 63) == 0) {"),
 ("W23 Reverse 64-bit stores to the neighbouring element", "memcpy(BYTES(n) + 8 * (size_t)i, &v, 8);", "memcpy(BYTES(n) + 8 * (size_t)(i ^ 1), &v, 8);"),
 ("W24 MoveElems wide memmove -> memcpy", "memmove(BYTES(b) + (size_t)to * EBYTES(b),", "memcpy(BYTES(b) + (size_t)to * EBYTES(b),"),
 ("W25 MoveElems wide wrong destination unit", "memmove(BYTES(b) + (size_t)to * EBYTES(b),", "memmove(BYTES(b) + (size_t)to,"),
 ("W26 Replace wide vacated storage not cleared", "\t    memset(BYTES(b) + (size_t)newLen * EBYTES(b), 0,\n\t\t    (size_t)(oldLen - newLen) * EBYTES(b));\n", "\t    ;\n"),
 ("W27 string rep 64-bit printed unsigned", 'n = snprintf(buf, sizeof(buf), "%lld", (long long)ElemWide(b, v));', 'n = snprintf(buf, sizeof(buf), "%llu", (unsigned long long)v);'),
 ('W28 string rep wrong separator (wide)', '\t    if (i) {\n\t        Tcl_DStringAppend(&ds, " ", 1);\n\t    }', '\t    if (i) {\n\t        Tcl_DStringAppend(&ds, ",", 1);\n\t    }'),
 ("W29 in: canonical check dropped", "if (strcmp(buf, s) == 0) {", "if (1) {"),
 ("W30 in: searches nonzero instead of value", "*resPtr = (NextWide(b, 0, 0, val) >= 0);", "*resPtr = (NextWide(b, 0, 1, val) >= 0);"),
 ("W31 CountWide 8-bit nonzero inverted", "total += (p[i] != 0);", "total += (p[i] == 0);"),
 ("W32 CountWide 8-bit equal inverted", "total += (p[i] == c);", "total += (p[i] != c);"),
 ("W33 CountWide generic nonzero inverted", "total += anyNZ ? (e != 0) : (e == val);", "total += anyNZ ? (e == 0) : (e == val);"),
 ("W34 NextWide memchr reads one byte too many", "(size_t)(b->len - start));", "(size_t)(b->len - start + 1));"),
 ('W35 NextWide word skip never stops', '\t    if (w) {     // a non-zero word: the loop below finds which byte\n\t        break;\n\t    }\n\t}', '\t    ;\n\t}'),
 ('W36 NextWide generic compares wrong', '\tif (anyNZ ? (e != 0) : (e == val)) {\n\t    return i;\n\t}', '\tif (anyNZ ? (e != 0) : (e != val)) {\n\t    return i;\n\t}'),
 ("W37 fill 8-bit memset one short", "memset(p + first, c, (size_t)(last - first + 1));", "memset(p + first, c, (size_t)(last - first));"),
 ("W38 fill 8-bit memset wrong start", "memset(p + first, c,", "memset(p, c,"),
 ('W39 fill 8-bit step stop early', '\t\t    p[i] = c;\n\t\t    if (last - i < step) {\n\t\t        break;\n\t\t    }', '\t\t    p[i] = c;\n\t\t    if (last - i <= step) {\n\t\t        break;\n\t\t    }'),
 ('W40 fill generic step stop early', '\t\tPutElem(b, i, val);\n\t\tif (last - i < step) {\n\t\t    break;\n\t\t}', '\t\tPutElem(b, i, val);\n\t\tif (last - i <= step) {\n\t\t    break;\n\t\t}'),
 ('W41 newfrom stores only values above 1', '\t    if (val) {                  // the array starts as all 0\n\t        PutElem(n, i, val);\n\t    }', '\t    if (val > 1) {                  // the array starts as all 0\n\t        PutElem(n, i, val);\n\t    }'),
 ("W42 new 8-bit init one short", "memset(n->words, (int)val, (size_t)n->len);", "memset(n->words, (int)val, (size_t)n->len - 1);"),
 ('W43 new generic init one short', '\t\tfor (i = 0; i < n->len; i++) {\n\t\t    PutElem(n, i, val);\n\t\t}', '\t\tfor (i = 0; i < n->len - 1; i++) {\n\t\t    PutElem(n, i, val);\n\t\t}'),
 ("W44 count zeros of bits off by one", "(Tcl_WideInt)(last - first + 1) - cnt;", "(Tcl_WideInt)(last - first) - cnt;"),
 ("W45 count ignores a given value", "\t    if (ParseValue(interp, valObj, b->width, b->isSigned, &val) != TCL_OK) {\n\t\treturn TCL_ERROR;\n\t    }\n\t    anyNZ = 0;", "\t    if (ParseValue(interp, valObj, b->width, b->isSigned, &val) != TCL_OK) {\n\t\treturn TCL_ERROR;\n\t    }"),
 ("W46 next ignores a given value", "\t    if (ParseValue(interp, valObjN, b->width, b->isSigned, &val) != TCL_OK) {\n\t\treturn TCL_ERROR;\n\t    }\n\t    anyNZ = 0;", "\t    if (ParseValue(interp, valObjN, b->width, b->isSigned, &val) != TCL_OK) {\n\t\treturn TCL_ERROR;\n\t    }"),
 ('W47 -width without argument not detected', '\t    if (i + 1 >= objc) {               // "-width" with nothing after it\n\t        goto usageError;\n\t    }\n\t    if (ParseWidthArg(interp, objv[++i], widthPtr, signedPtr) != TCL_OK) {   // ++i: the width value is used up too', '\t    if (ParseWidthArg(interp, objv[++i], widthPtr, signedPtr) != TCL_OK) {   // ++i: the width value is used up too'),
 ("W48 width 16 rejected", "w != 8 && w != 16 && w != 32", "w != 8 && w != 32"),
 ("W49 dup loses width", "BitArr *s = GETREP(srcPtr), *d = NewRep(NULL, s->len, s->width, s->isSigned);", "BitArr *s = GETREP(srcPtr), *d = NewRep(NULL, s->len, 1, s->isSigned);"),
 ('W50 setElement parses as 1-bit', '    if (ParseValue(interp, valueObj, b->width, b->isSigned, &val) != TCL_OK) {           // check the value first\n        return NULL;\n    }', '    if (ParseValue(interp, valueObj, 1, b->isSigned, &val) != TCL_OK) {           // check the value first\n        return NULL;\n    }'),
 ("W51 replace validates as 1-bit", "if (ParseValue(interp, insertObjs[i], b->width, b->isSigned, &val) != TCL_OK) {", "if (ParseValue(interp, insertObjs[i], 1, b->isSigned, &val) != TCL_OK) {"),
 ("W52 replace sizes storage for 1-bit", "needWords = WORDS_FOR(newLen, b->width);", "needWords = (newLen + 63) / 64;"),
 ('W53 index out of range for wide returns last', '    } else if (b->width == 1) {\n\t*elemPtr = GETBIT(b, index) ? b->one : b->zero;   // the shared 0 or 1 object\n    } else {', '    } else if (b->width == 1) {\n\t*elemPtr = GETBIT(b, index) ? b->one : b->zero;   // the shared 0 or 1 object\n    } else if (index == b->len - 1) {\n\t*elemPtr = b->zero;\n    } else {'),
 ("P01 fill: 'to' not recognised", 'IsWord(objv[k], "to") ||', '0 ||'),
 ("P02 fill: '..' not recognised", '|| IsWord(objv[k], ".."))', '|| 0)'),
 ("P03 fill: 'with' not recognised", '\tif (k < objc && IsWord(objv[k], "with")) {\n\t    k++;\n\t}', '\t;'),
 ("P04 fill: 'by' not recognised", 'if (k < objc && IsWord(objv[k], "by")) {', 'if (0) {'),
 ("P05 fill: extra arguments after 'by step' accepted", '\t    if (k != objc - 1) {\n\t        goto fillUsage;\n\t    }', '\t    ;'),
 ('P06 fill: extra arguments after a bare step accepted', '} else if (k < objc - 1) {', '} else if (0) {'),
 ('P07 IsWord matches a prefix', 'return (size_t)n == strlen(w) &&', 'return'),
 ('P08 fill: range error always names last', 'IndexError(interp, first < 0 ? firstObj : lastObj);', 'IndexError(interp, lastObj);'),
 ("P09 count: 'to' not recognised", 'IsWord(objv[kc], "to") ||', '0 ||'),
 ("P10 count: '..' not recognised", '|| IsWord(objv[kc], ".."))', '|| 0)'),
 ("P11 count: 'with' not recognised", 'if (kc < objc && IsWord(objv[kc], "with")) {', 'if (0) {'),
 ('P12 count: extra arguments accepted', '\t    if (kc != objc) {               // anything left over is a usage error\n\t        goto countUsage;\n\t    }', '\t    ;      // anything left over is a usage error'),
 ('P13 count: a value is never used', 'hasVal = (valObj != NULL);', 'hasVal = 0;'),
 ("P14 next: 'with' not recognised", 'if (kn < objc && IsWord(objv[kn], "with")) {', 'if (0) {'),
 ('P15 next: extra arguments accepted', '\tif (kn != objc) {\n\t    goto nextUsage;\n\t}', '\t;'),
 ('Q01 frombytes copies one byte short', '\tif (nb > 0) {                                   // the bytes are the elements, as they are\n\t    memcpy(n->words, bytes, (size_t)nb);\n\t}', '\tif (nb > 0) {                                       // the bytes are the elements, as they are\n\t    memcpy(n->words, bytes, (size_t)nb - 1);\n\t}'),
 ('Q02 tobytes accepts any width', '\tif (b->width != 8 || b->isSigned) {   // only unsigned 8-bit arrays are bytes\n\t    Tcl_SetObjResult(interp, Tcl_ObjPrintf(\n\t\t    "tobytes: array has width %d; only width 8 can be written as bytes",', '\tif (b->isSigned) {\n\t    Tcl_SetObjResult(interp, Tcl_ObjPrintf(\n\t\t    "tobytes: array has width %d; only width 8 can be written as bytes",'),
 ('Q03 tobytes drops the last byte', '(const unsigned char *)b->words, b->len));', '(const unsigned char *)b->words, b->len > 0 ? b->len - 1 : 0));'),
 ('Q04 fromchars default width 16', '\twidth = 8;                                                 // the default width\n\tif (objc == 5) {', '\twidth = 16;\n\tif (objc == 5) {'),
 ('Q05 fromchars range check off by one', '(uint64_t)ch > maxv', '(uint64_t)ch >= maxv'),
 ('Q06 fromchars accepts width 64', '\tif (isSigned || (width != 8 && width != 16 && width != 32)) {   // not signed, and 8, 16 or 32 only\n\t    Tcl_SetObjResult(interp, Tcl_NewStringObj(\n\t\t    "fromchars: -width must be 8, 16 or 32", -1));', '\tif (isSigned || (width != 8 && width != 16 && width != 32 && width != 64)) {\n\t    Tcl_SetObjResult(interp, Tcl_NewStringObj(\n\t\t    "fromchars: -width must be 8, 16 or 32", -1));'),
 ('Q07 fromchars loses characters 0 and 1', '\t    if (ch) {                           // zero is there already\n\t        PutElem(n, i, (uint64_t)ch);\n\t    }', '\t    if (ch > 1) {                           // zero is there already\n\t        PutElem(n, i, (uint64_t)ch);\n\t    }'),
 ('Q08 tochars accepts surrogates', '(v >= 0xD800 && v <= 0xDFFF)', '0'),
 ('Q09 tochars limit 0x10FFFF -> 0x110000', 'v > 0x10FFFF', 'v > 0x110000'),
 ('Q10 tochars accepts width 64', '\tif ((b->width != 8 && b->width != 16 && b->width != 32) || b->isSigned) {   // unsigned 8, 16 or 32 only\n\t    Tcl_SetObjResult(interp, Tcl_ObjPrintf(\n\t\t    "tochars: array has width %d; need width 8, 16 or 32", SignedWidth(b)));', '\tif ((b->width != 8 && b->width != 16 && b->width != 32 && b->width != 64) || b->isSigned) {\n\t    Tcl_SetObjResult(interp, Tcl_ObjPrintf(\n\t\t    "tochars: array has width %d; need width 8, 16 or 32", SignedWidth(b)));'),
 ('Q11 tochars drops the last character', 'Tcl_NewUnicodeObj(buf, b->len)', 'Tcl_NewUnicodeObj(buf, b->len > 0 ? b->len - 1 : 0)'),
 ('Q12 tochars skips element 0', '\tfor (i = 0; i < b->len; i++) {\n\t    buf[i] = (Tcl_UniChar)GetElem(b, i);\n\t}', '\tfor (i = 1; i < b->len; i++) {\n\t    buf[i] = (Tcl_UniChar)GetElem(b, i);\n\t}'),
 ('Q13 fromchars error names the wrong index', 'ch, i, width));', 'ch, i + 1, width));'),
 # ---- round 8 (0.5.1): the word-at-a-time shift for width-1 arrays ----
 ('S01 GetBits: high word not merged', '    if (s + n > 64) {                                // the run spills into the next word: add its low bits above\n        v |= b->words[k + 1] << (64 - s);\n    }', '    ;        // the run spills into the next word: add its low bits above'),
 ("S02 GetBits: wrong shift for the high word", "v |= b->words[k + 1] << (64 - s);", "v |= b->words[k + 1] << (63 - s);"),
 ("S03 GetBits: result not masked to n bits", "return (n == 64) ? v : (v & (((uint64_t)1 << n) - 1));", "return v;"),
 ("S04 PutBits: value not masked", "    v &= m;\n", ""),
 ("S05 PutBits: other bits of the word not kept", "b->words[k] = (b->words[k] & ~(m << s)) | (v << s);", "b->words[k] = (v << s);"),
 ('S06 PutBits: high word not written', '    if (s + n > 64) {                                                   // the run spills into the next word\n\tuint64_t mh = ((uint64_t)1 << (s + n - 64)) - 1;                // mask for the bits that land in the next word', '    if (0) {\n\tuint64_t mh = ((uint64_t)1 << (s + n - 64)) - 1;                // mask for the bits that land in the next word'),
 ("S07 PutBits: wrong high-word mask", "uint64_t mh = ((uint64_t)1 << (s + n - 64)) - 1;", "uint64_t mh = ((uint64_t)1 << (s + n - 63)) - 1;"),
 ("S08 PutBits: high word keeps nothing", "b->words[k + 1] = (b->words[k + 1] & ~mh) | (v >> (64 - s));", "b->words[k + 1] = (v >> (64 - s));"),
 ("S09 PutBits: wrong shift for the high part", "| (v >> (64 - s));", "| (v >> (63 - s));"),
 ("S10 ClearBits: position not advanced", "\tPutBits(b, from, 0, n);\n\tfrom += n;", "\tPutBits(b, from, 0, n);\n\tfrom += 0;"),
 ("S11 MoveElems left: source off by one", "PutBits(b, d, GetBits(b, q, h), h);", "PutBits(b, d, GetBits(b, q + 1, h), h);"),
 ("S12 MoveElems right: destination off by one", "PutBits(b, to + left, GetBits(b, from + left, n), n);", "PutBits(b, to + left + 1, GetBits(b, from + left, n), n);"),
 ("S13 MoveElems left: first partial chunk not shortened", "int h = (cnt >= 64 - (d & 63)) ? (int)(64 - (d & 63)) : (int)cnt;", "int h = (int)(64 - (d & 63));"),
 ("S14 MoveElems right: last chunk not shortened", "int n = (left >= 64) ? 64 : (int)left;", "int n = 64;"),
 ("S15 ClearBits: last chunk not shortened", "int n = (count >= 64) ? 64 : (int)count;", "int n = 64;"),
 # ---- 0.6.0: and / or / xor / andnot / not ----
 ("B01 and: uses OR on the common words", "BO_LOOP(0, m, y->words[k], xv & yv)", "BO_LOOP(0, m, y->words[k], xv | yv)"),
 ("B02 and: words past the end of y keep x", "BO_LOOP(m, n, 0, xv & yv)", "BO_LOOP(m, n, 0, xv)"),
 ("B03 or: uses XOR on the common words", "BO_LOOP(0, m, y->words[k], xv | yv)", "BO_LOOP(0, m, y->words[k], xv ^ yv)"),
 ("B04 or: words past the end of y are cleared", "BO_LOOP(m, n, 0, xv | yv)", "BO_LOOP(m, n, 0, 0)"),
 ("B05 xor: uses OR on the common words", "BO_LOOP(0, m, y->words[k], xv ^ yv)", "BO_LOOP(0, m, y->words[k], xv | yv)"),
 ("B06 xor: words past the end of y become 0", "BO_LOOP(m, n, 0, xv ^ yv)", "BO_LOOP(m, n, 0, 0)"),
 ("B07 andnot: the NOT is missing", "BO_LOOP(0, m, y->words[k], xv & ~yv)", "BO_LOOP(0, m, y->words[k], xv & yv)"),
 ("B08 andnot: words past the end of y are cleared", "BO_LOOP(m, n, 0, xv & ~yv)", "BO_LOOP(m, n, 0, 0)"),
 ("B09 not: does not flip", "dst->words[k] = ~x->words[k];", "dst->words[k] = x->words[k];"),
 ("B10 common-word count wrong when y is longer", "m = (y->nwords < n) ? y->nwords : n;", "m = (y->nwords < n) ? y->nwords : n / 2;"),
 ('B11 MaskTail width 1: mask removed', '\tif (r) {                                                   // keep those bits, clear the rest\n\t    b->words[b->nwords - 1] &= (((uint64_t)1 << r) - 1);\n\t}', '\t;        // keep those bits, clear the rest'),
 ("B12 MaskTail width 1: wrong remainder", "int r = (int)(bits & 63);", "int r = (int)(bits & 31);"),
 ('B13 MaskTail wide: unused bytes not cleared', '\tif (total > used) {\n\t    memset(BYTES(b) + used, 0, total - used);\n\t}', '\t;'),
 ("B14 width check dropped", "if (x->width != y->width || SignedBits(x) != SignedBits(y)) {", "if (SignedBits(x) != SignedBits(y)) {"),
 ("B15 length check ignores -length zero", "if (!zero && x->len != y->len) {", "if (x->len != y->len) {"),
 ("B16 length check inverted", "if (!zero && x->len != y->len) {", "if (zero && x->len != y->len) {"),
 ('B17 in place: shared value not copied', '\twork = Tcl_IsShared(obj) ? Tcl_DuplicateObj(obj) : obj;   // a shared value is copied first, never changed in place\n\td = GETREP(work);\n\tBitOpWords(d, d, y, op);                                  // d = d OP y (y is NULL for not)', '\twork = obj;\n\td = GETREP(work);\n\tBitOpWords(d, d, y, op);                                  // d = d OP y (y is NULL for not)'),
 ('B18 in place: string form not invalidated', '\tMaskTail(d);                                              // clear the bits past the end\n\tTouch(work);                                              // string form and element cache are out of date', '\tMaskTail(d);                                              // clear the bits past the end                                              // string form and element cache are out of date'),
 ('B19 new result takes the length of the second array', "\tif ((d = NewRep(interp, x->len, x->width, x->isSigned)) == NULL) {                // new result: first array's length, width, sign\n\t    return TCL_ERROR;\n\t}\n\tBitOpWords(d, x, y, op);", '\tif ((d = NewRep(interp, y ? y->len : x->len, x->width, x->isSigned)) == NULL) {\n\t    return TCL_ERROR;\n\t}\n\tBitOpWords(d, x, y, op);'),
 ("B20 arrow with four words not recognised", "(rest == 3 || rest == 4) && IsArrow(objv[idx + 1])", "(rest == 3) && IsArrow(objv[idx + 1])"),
 ("B21 arrow: two sources swapped", "inPlace = 0; srcA = objv[idx + 2]; srcB = objv[idx + 3];", "inPlace = 0; srcA = objv[idx + 3]; srcB = objv[idx + 2];"),
 ("B22 -length mode inverted", "zero = mode;", "zero = !mode;"),
 ('B23 -length value not skipped', '\tzero = mode;     // strict is index 0, zero is index 1\n\tidx += 2;', '\tzero = mode;     // strict is index 0, zero is index 1\n\tidx += 1;'),
 ("B24 arrow with one source: treated as not in place", "inPlace = 1; srcB = objv[idx + 2];", "inPlace = 0; srcA = objv[idx]; srcB = objv[idx + 2];"),
 ("B25 destination named <- accepted", "if (IsWord(dstName, \"<-\")) {", "if (0) {"),
 ("B26 arrow with nothing after it: taken as an array", "} else if (rest == 2 && IsArrow(objv[idx + 1])) {", "} else if (0) {"),
 ("R01 Rev64: the 16-bit swap is missing", "x = ((x >> 16) & 0x0000FFFF0000FFFFULL) | ((x & 0x0000FFFF0000FFFFULL) << 16);", ""),
 ("R02 Rev64: the final 32-bit swap is missing", "return (x >> 32) | (x << 32);", "return x;"),
 ("R03 lreverse width 8 copies instead of reversing", "dst[i] = src[b->len - 1 - i];", "dst[i] = src[i];"),
 ("R04 lrange unaligned: low bit of every chunk cleared", "n->words[i >> 6] = GetBits(b, from + i, m);", "n->words[i >> 6] = GetBits(b, from + i, m) & ~(uint64_t)1;"),
 ("R05 lrange unaligned: chunk length not shortened at the end", "int m = (len - i >= 64) ? 64 : (int)(len - i);", "int m = 64;"),
 ("R06 shift left: aligned source reads the next word", ": b->words[kq];", ": b->words[kq + 1];"),
 ("R07 shift left: upper part shifted by one too many", "(b->words[kq + 1] << (64 - sh))", "(b->words[kq + 1] << (63 - sh))"),
 ('R08 shift left: partial last word dropped', '\tif (cnt > 0) {                                                // partial last word\n\t    PutBits(b, d, GetBits(b, q, (int)cnt), (int)cnt);\n\t}', '\tif (cnt > 1) {                                                // partial last word\n\t    PutBits(b, d, GetBits(b, q, (int)cnt), (int)cnt);\n\t}'),
 # ---- signed widths (0.6.0, added 2026-10-16) ----
 ("G01 signed range: upper end one too high", "if (v >= -lim && v < lim) {", "if (v >= -lim && v <= lim) {"),
 ("G02 signed range: lowest value refused", "if (v >= -lim && v < lim) {", "if (v > -lim && v < lim) {"),
 ("G03 signed parse: negative value not masked to its width", "*vp = (uint64_t)v & (((uint64_t)1 << width) - 1);", "*vp = (uint64_t)v;"),
 ('G04 signed 8: read back as unsigned', '\tif (b->width == 8) {                               // the cast to the signed type of that width sign-extends\n\t    return (Tcl_WideInt)(int8_t)val;\n\t}', '\tif (b->width == 8) {                                // the cast to the signed type of that width sign-extends\n\t    return (Tcl_WideInt)(uint8_t)val;\n\t}'),
 ('G05 signed 16: read back as unsigned', '\tif (b->width == 16) {\n\t    return (Tcl_WideInt)(int16_t)val;\n\t}', '\tif (b->width == 16) {\n\t    return (Tcl_WideInt)(uint16_t)val;\n\t}'),
 ("G06 signed 32: read back as unsigned", "return (Tcl_WideInt)(int32_t)val;", "return (Tcl_WideInt)(uint32_t)val;"),
 ("G07 signed widths never sign-extend", "if (b->isSigned) {\n\tif (b->width == 8)", "if (0) {\n\tif (b->width == 8)"),
 ("G08 new array never signed", "b->isSigned = (unsigned char)(isSigned != 0);", "b->isSigned = 0;"),
 ("G09 slice loses the sign", "NewRep(interp, len, b->width, b->isSigned)", "NewRep(interp, len, b->width, 0)"),
 ("G10 reverse loses the sign", "NewRep(interp, b->len, b->width, b->isSigned)", "NewRep(interp, b->len, b->width, 0)"),
 ("G11 copy loses the sign", "NewRep(NULL, s->len, s->width, s->isSigned)", "NewRep(NULL, s->len, s->width, 0)"),
 ("G12 bitwise result loses the sign", "NewRep(interp, x->len, x->width, x->isSigned)", "NewRep(interp, x->len, x->width, 0)"),
 ("G13 bitwise: signed and unsigned arrays accepted together", "if (x->width != y->width || SignedBits(x) != SignedBits(y)) {", "if (x->width != y->width) {"),
 ("G14 bitwise: 64 and -64 refused together", "return b->isSigned || b->width == 64;", "return b->isSigned;"),
 ("G15 width query drops the sign", "return b->isSigned ? -(int)b->width : (int)b->width;", "return (int)b->width;"),
 ("G16 -width -8 not taken as signed", "*signedPtr = (w < 0);", "*signedPtr = 0;"),
 ("G17 fromchars accepts a signed width", "if (isSigned || (width != 8", "if ((width != 8"),
 ("G18 tobytes accepts a signed array", "if (b->width != 8 || b->isSigned) {", "if (b->width != 8) {"),
 ("G19 tochars accepts a signed array", "(b->width != 8 && b->width != 16 && b->width != 32) || b->isSigned) {", "(b->width != 8 && b->width != 16 && b->width != 32)) {"),
 ("G20 in: canonical text of a signed value unsigned", "snprintf(buf, sizeof(buf), \"%lld\", (long long)ElemWide(b, val));", "snprintf(buf, sizeof(buf), \"%lld\", (long long)val);"),
 ("G21 string form of a signed element unsigned", "n = snprintf(buf, sizeof(buf), \"%lld\", (long long)ElemWide(b, v));", "n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);"),
 ("G22 signed range message: lower end positive", "-(long long)((uint64_t)1 << (width - 1)),", "(long long)((uint64_t)1 << (width - 1)),"),
 ("G23 element object of a signed value unsigned", "return Tcl_NewWideIntObj(ElemWide(b, val));", "return Tcl_NewWideIntObj((Tcl_WideInt)val);"),
 ("G24 -32 not an accepted width", "&& w != -8 && w != -16 && w != -32 && w != -64)", "&& w != -8 && w != -16 && w != -64)"),
 ("G25 width given with a sign kept negative", "*widthPtr = (int)(w < 0 ? -w : w);", "*widthPtr = (int)w;"),
 ('H01 HasBit: looking for 1 stops on a zero word', '\tif (val ? (w != 0) : (w != ~(uint64_t)0)) {\n\t    return 1;\n\t}', '\tif (val ? (w == 0) : (w != ~(uint64_t)0)) {\n\t    return 1;\n\t}'),
 ('H02 HasBit: looking for 0 tests against 0 instead of all ones', '\tif (val ? (w != 0) : (w != ~(uint64_t)0)) {\n\t    return 1;\n\t}', '\tif (val ? (w != 0) : (w != 0)) {\n\t    return 1;\n\t}'),
 ('H03 HasBit: first word skipped', '    for (i = 0; i < lw; i++) {   // the whole words before the last one\n\tw = b->words[i];\n\tif (val ? (w != 0) : (w != ~(uint64_t)0)) {\n\t    return 1;\n\t}', '    for (i = 1; i < lw; i++) {\n\tw = b->words[i];\n\tif (val ? (w != 0) : (w != ~(uint64_t)0)) {\n\t    return 1;\n\t}'),
 ('H04 HasBit: loop also runs over the last word unmasked', '    for (i = 0; i < lw; i++) {   // the whole words before the last one\n\tw = b->words[i];\n\tif (val ? (w != 0) : (w != ~(uint64_t)0)) {\n\t    return 1;\n\t}', '    for (i = 0; i <= lw; i++) {\n\tw = b->words[i];\n\tif (val ? (w != 0) : (w != ~(uint64_t)0)) {\n\t    return 1;\n\t}'),
 ("H05 HasBit: last word, looking for 1, not masked", "((w & lm) != 0)", "(w != 0)"),
 ("H06 HasBit: last word, looking for 0, padding not filled with ones", "((w | ~lm) != ~(uint64_t)0)", "(w != ~(uint64_t)0)"),
 ('H07 HasBit: last word index uses len not len-1', '    lw = (b->len - 1) >> 6;      // index of the last word in use\n    lm = ~(uint64_t)0 >> (63 - ((b->len - 1) & 63));\t/* bits in use */', '    lw = b->len >> 6;\n    lm = ~(uint64_t)0 >> (63 - ((b->len - 1) & 63));\t/* bits in use */'),
 ("H08 HasBit: last word mask one bit too wide", "~(uint64_t)0 >> (63 - ((b->len - 1) & 63));\t/* bits in use */", "~(uint64_t)0 >> (62 - ((b->len - 1) & 63));\t/* bits in use */"),
 ('H09 HasBit: empty array not handled', '    if (b->len == 0) {        // an empty array holds neither 0 nor 1\n        return 0;\n    }\n    lw = (b->len - 1) >> 6;      // index of the last word in use', '    lw = (b->len - 1) >> 6;      // index of the last word in use'),
 ("H10 BAInOper: 1-bit value letter inverted", "HasBit(b, s[0] == '1')", "HasBit(b, s[0] == '0')"),
 # ---- 0.8.1: lpop l INDEX ----
 ('L01 lpop: index == length accepted', '\tif (idx >= b->len) {\n\t    IndexError(interp, indexArray[0]);', '\tif (idx > b->len) {\n\t    IndexError(interp, indexArray[0]);'),
 ("L02 lpop: works on the variable's own object (no copy)", '\tobj = Tcl_DuplicateObj(obj);\n\tif (BAReplace(interp, obj, idx, 1, 0, NULL) != TCL_OK) {', '\tif (BAReplace(interp, obj, idx, 1, 0, NULL) != TCL_OK) {'),
 ('L03 lpop: deletes nothing', 'if (BAReplace(interp, obj, idx, 1, 0, NULL) != TCL_OK) {', 'if (BAReplace(interp, obj, idx, 0, 0, NULL) != TCL_OK) {'),
 ('L04 lpop: branch never taken (the old crash)', '    if (valueObj == NULL) {', '    if (valueObj == NULL && 0) {'),
 ('I01 GetElem: the impossible check does nothing', '    default: BA_IMPOSSIBLE("bad width", b->width);', '    default: return 0;'),
 ('I02 PutElem: the impossible check does nothing', '    default:\n        BA_IMPOSSIBLE("bad width", b->width);', '    default:\n        break;'),
 ('I03 fill: the impossible check returns an error instead', '\t    BA_IMPOSSIBLE("objc too small", objc);', '\t    return TCL_ERROR;'),
 ('I04 BitarrayCmd: the impossible check at the end does nothing', '    BA_IMPOSSIBLE("no case matched", 0);', '    return TCL_OK;'),
 ('I05 GetElem: width 16 falls into the impossible check', '    case 16: { uint16_t v; memcpy(&v, p + 2 * (size_t)i, 2); return v; }', '    case 17: { uint16_t v; memcpy(&v, p + 2 * (size_t)i, 2); return v; }'),
 ('I06 PutElem: width 32 falls into the impossible check', '    case 32: { uint32_t v = (uint32_t)val; memcpy(p + 4 * (size_t)i, &v, 4); break; }', '    case 33: { uint32_t v = (uint32_t)val; memcpy(p + 4 * (size_t)i, &v, 4); break; }'),
 ('I07 PutElem: width 1 is no longer handled before the switch', '    if (b->width == 1) {\n\tif (val) {', '    if (b->width == 2) {\n\tif (val) {'),
]

# ---- bitarray.c carries short side comments ("   // ...") on many lines.  A mutant's text was written without them, so
# ---- find it with the comments allowed at each line end, and keep the comment on every line the mutant leaves alone.
SIDE = re.compile(r' {3,}//[^\n]*')
def strip_side(s): return SIDE.sub('', s)
def adapt(MUT, SRC):
    out = []
    for name, old, new in MUT:
        if SRC.count(old) != 1:
            rx = re.compile(r'(?: {3,}//[^\n]*)?\n'.join(re.escape(x) for x in old.split('\n')))
            ms = list(rx.finditer(SRC))
            if len(ms) == 1:
                m = ms[0].group(0)
                keep = {}
                for line in m.split('\n'):
                    plain = strip_side(line)
                    if plain != line: keep[plain] = line
                new = '\n'.join(keep.get(l, l) for l in new.split('\n'))
                old = m
        out.append((name, old, new))
    return out
MUT = adapt(MUT, SRC)
only = sys.argv[1:]
out=[]
for name, old, new in MUT:
    if only and name.split()[0] not in only: continue
    if SRC.count(old) != 1:
        out.append((name, 'BADPATTERN %d' % SRC.count(old))); print(out[-1]); continue
    d = tempfile.mkdtemp(prefix='bitarray_mut_')
    try:
        open(d+'/bitarray.c','w').write(SRC.replace(old,new))
        cmd = [CC,'-O2','-fPIC','-shared','-DUSE_TCL_STUBS'] + ['-I'+i for i in INC] + [d+'/bitarray.c', STUB, '-o', d+'/libbitarray.so']
        c = subprocess.run(cmd, capture_output=True, text=True)
        if c.returncode:
            out.append((name,'NOCOMPILE')); print(out[-1]); continue
        env = dict(os.environ, BITARRAY_LIB=d+'/libbitarray.so')
        try:
            r = subprocess.run([TCLSH, TESTFILE], cwd=d, env=env, capture_output=True, text=True, timeout=300)
            m = re.search(r'Total\s+(\d+)\s+Passed\s+(\d+).*Failed\s+(\d+)', r.stdout)
            if r.returncode != 0 and not m: res='CAUGHT (crash rc=%d)' % r.returncode
            elif m and int(m.group(3))>0: res='CAUGHT (%s tests fail)' % m.group(3)
            elif r.returncode!=0: res='CAUGHT (rc=%d)'%r.returncode
            else: res='MISSED'
        except subprocess.TimeoutExpired:
            res='CAUGHT (timeout)'
        out.append((name,res)); print(name,'->',res, flush=True)
    finally:
        shutil.rmtree(d, ignore_errors=True)
