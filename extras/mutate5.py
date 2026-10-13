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
With names given it runs only those mutants.  Takes about 10-30 minutes for all 95 (each runs the whole suite).
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
 ("M04 size limit 2^40 -> 2^41", "#   define BA_MAX_BITS\t((Tcl_WideInt)1 << 40)", "#   define BA_MAX_BITS\t((Tcl_WideInt)1 << 41)"),
 ("M33 new: size check on narrowed value dropped", "if (w < 0 || w > BA_MAX_BITS / width) {", "if (w < 0) {"),
 ("M34 replace: growth limit dropped", "if (wideLen > BA_MAX_BITS / b->width) {", "if (0) {"),
 ("M35 capacity not doubled", "Tcl_Size newCap = b->capWords * 2,", "Tcl_Size newCap = 0,"),
 ("M36 shrink does not clear vacated bits", "for (i = newLen; i < oldLen; i++) CLRBIT(b, i);", ";"),
 ("M37 MoveElems direction reversed", "    if (to < from) {\n\tfor (i = 0; i < count; i++) {", "    if (to > from) {\n\tfor (i = 0; i < count; i++) {"),
 ("M38 new capacity not zeroed", "\tmemset(&b->words[oldCap], 0,\n\t\t(size_t)(newCap - oldCap) * sizeof(uint64_t));\n", ""),
 ("M39 rep pointer not updated after realloc", "\tlistObj->internalRep.twoPtrValue.ptr1 = b;\n    }\n", "\t;\n    }\n"),
 ("M40 word count not updated", "    b->nwords = needWords;\n    Tcl_InvalidateStringRep(listObj);", "    Tcl_InvalidateStringRep(listObj);"),
 ("M41 element cache not dropped by replace", "    /* The element cache refers to the old contents; drop it first. */\n    FreeElems(b);\n", ""),
 ("M42 first-index clamp removed", "    if (first > oldLen) first = oldLen;\n", ""),
 ("M05 index bound > for >=", "if (index < 0 || index >= b->len) {\n\t*elemPtr = NULL;", "if (index < 0 || index > b->len) {\n\t*elemPtr = NULL;"),
 ("M06 slice upper clamp", "if (to >= b->len) to = b->len - 1;", "if (to > b->len) to = b->len - 1;"),
 ("M07 slice tail mask removed", "\t    n->words[n->nwords - 1] &= ~(~(uint64_t)0 << (len & 63));", "\t    ;"),
 ("M08 slice lower clamp removed", "if (from < 0) from = 0;\n    if (to >= b->len)", "if (to >= b->len)"),
 ("M09 reverse off by one", "GETBIT(b, b->len - 1 - i)", "GETBIT(b, b->len - i)"),
 ("M10 setElement append disabled", "if (idx < 0 || idx > b->len) {\n\tIndexError(interp, indexArray[0]);", "if (idx < 0 || idx >= b->len) {\n\tIndexError(interp, indexArray[0]);"),
 ("M11 setElement never duplicates", "if (Tcl_IsShared(obj)) {\n\tobj = Tcl_DuplicateObj(obj);\n    }\n    if (idx ==", "if (0) {\n\tobj = Tcl_DuplicateObj(obj);\n    }\n    if (idx =="),
 ("M12 Touch keeps string rep", "    FreeElems(GETREP(obj));\n    Tcl_InvalidateStringRep(obj);", "    FreeElems(GETREP(obj));"),
 ("M13 Touch keeps element cache", "    FreeElems(GETREP(obj));\n    Tcl_InvalidateStringRep(obj);", "    Tcl_InvalidateStringRep(obj);"),
 ("M14 replace delete clamp removed", "if (numToDelete > oldLen - first) numToDelete = oldLen - first;", ""),
 ("M15 replace tail move count off by one", "oldLen - (first + numToDelete));", "oldLen - (first + numToDelete) - 1);"),
 ("M16 in-operator zero test", "(ones < b->len)", "(ones <= b->len)"),
 ("M17 count first mask", "    fm = ~(uint64_t)0 << (first & 63);\n    lm = ~(uint64_t)0 >> (63 - (last & 63));\n    if (fw == lw) {\n\treturn", "    fm = ~(uint64_t)0 << ((first + 1) & 63);\n    lm = ~(uint64_t)0 >> (63 - (last & 63));\n    if (fw == lw) {\n\treturn"),
 ("M18 count last mask", "lm = ~(uint64_t)0 >> (63 - (last & 63));\n    if (fw == lw) {\n\treturn", "lm = ~(uint64_t)0 >> (62 - (last & 63));\n    if (fw == lw) {\n\treturn"),
 ("M19 next start mask removed", "& (~(uint64_t)0 << (start & 63));", "& ~(uint64_t)0;"),
 ("M20 next tail check removed", "return idx < b->len ? idx : -1;", "return idx;"),
 ("M21 fill single-word mask", "if (val) b->words[fw] |= (fm & lm); else b->words[fw] &= ~(fm & lm);", "if (val) b->words[fw] |= fm; else b->words[fw] &= ~fm;"),
 ("M22 fill middle loop <=", "for (i = fw + 1; i < lw; i++) {\n\tb->words[i] = val", "for (i = fw + 1; i <= lw; i++) {\n\tb->words[i] = val"),
 ("M23 fill step stop early (1-bit)", "if (bit) SETBIT(b, i); else CLRBIT(b, i);\n\t\t    if (last - i < step) break;", "if (bit) SETBIT(b, i); else CLRBIT(b, i);\n\t\t    if (last - i <= step) break;"),
 ("M24 fill empty range check removed", "\tif (first > last) return TCL_OK;\n", ""),
 ("M25 ParseBit fast path accepts longer", "obj->length == 1\n\t    && (obj->bytes[0]", "obj->length >= 1\n\t    && (obj->bytes[0]"),
 ("M26 string rep separator", "if (i + 1 < b->len) *p++ = ' ';", "if (i + 1 < b->len) *p++ = ',';"),
 ("M27 dup copies one word short", "memcpy(d->words, s->words, (size_t)s->nwords * sizeof(uint64_t));", "memcpy(d->words, s->words, (size_t)(s->nwords > 1 ? s->nwords - 1 : s->nwords) * sizeof(uint64_t));"),
 ("M28 new: no memset", "    memset(b, 0, bytes);\n", ""),
 ("M29 count last clamp", "if (last >= b->len) last = b->len - 1;\n\t}\n\tval = 1;", "if (last > b->len) last = b->len - 1;\n\t}\n\tval = 1;"),
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
 ("W08 ElemObj sign only for 32", "b->width == 64 ? (Tcl_WideInt)(int64_t)val", "b->width == 32 ? (Tcl_WideInt)(int64_t)val"),
 ("W09 ElemObj 1 returns zero", "if (val == 1) return b->one;", "if (val == 1) return b->zero;"),
 ("W10 ParseValue upper bound off by one", "v <= (Tcl_WideInt)(((uint64_t)1 << width) - 1)) {", "v <= (Tcl_WideInt)(((uint64_t)1 << width))) {"),
 ("W11 ParseValue accepts -1", "if (v >= 0 && v <= (Tcl_WideInt)", "if (v >= -1 && v <= (Tcl_WideInt)"),
 ("W12 ParseValue 64-bit path skipped", "if (width == 64) {\n\t    *vp = (uint64_t)v;", "if (width == 99) {\n\t    *vp = (uint64_t)v;"),
 ("W13 ParseValue digit fast path too wide", "obj->bytes[0] >= '0' && obj->bytes[0] <= '9') {", "obj->bytes[0] >= '0' && obj->bytes[0] <= 'z') {"),
 ("W14 NewRep limit ignores width", "(Tcl_WideInt)len * width > BA_MAX_BITS", "(Tcl_WideInt)len > BA_MAX_BITS"),
 ("W15 NewRep allocates for 1-bit only", "nwords = WORDS_FOR(len, width);", "nwords = (len + 63) / 64;"),
 ("W16 WORDS_FOR rounds down by one", "* (width) + 63) / 64))", "* (width) + 62) / 64))"),
 ("W17 FreeElems never releases owned elements", "\tif (b->width != 1) {\n\t    Tcl_Size i;", "\tif (0) {\n\t    Tcl_Size i;"),
 ("W18 FreeElems also releases shared 0/1", "if (b->elems[i] != b->zero && b->elems[i] != b->one) {", "if (1) {"),
 ("W19 GetElements forgets to take a reference", "if (e != b->zero && e != b->one) Tcl_IncrRefCount(e);", ""),
 ("W20 GetElements does not record its length", "\tb->elemsLen = b->len;\n", ""),
 ("W21 Slice wide copies from offset 0 units", "memcpy(BYTES(n), BYTES(b) + (size_t)from * EBYTES(b),", "memcpy(BYTES(n), BYTES(b) + (size_t)from,"),
 ("W22 Slice wide copies too few bytes", "\t\t(size_t)len * EBYTES(b));\n    } else if ((from & 63) == 0) {", "\t\t(size_t)len);\n    } else if ((from & 63) == 0) {"),
 ("W23 Reverse wide off by one", "PutElem(n, i, GetElem(b, b->len - 1 - i));", "PutElem(n, i, GetElem(b, b->len - i));"),
 ("W24 MoveElems wide memmove -> memcpy", "memmove(BYTES(b) + (size_t)to * EBYTES(b),", "memcpy(BYTES(b) + (size_t)to * EBYTES(b),"),
 ("W25 MoveElems wide wrong destination unit", "memmove(BYTES(b) + (size_t)to * EBYTES(b),", "memmove(BYTES(b) + (size_t)to,"),
 ("W26 Replace wide vacated storage not cleared", "\t    memset(BYTES(b) + (size_t)newLen * EBYTES(b), 0,\n\t\t    (size_t)(oldLen - newLen) * EBYTES(b));\n", "\t    ;\n"),
 ("W27 string rep 64-bit printed unsigned", 'n = snprintf(buf, sizeof(buf), "%lld", (long long)(int64_t)v);', 'n = snprintf(buf, sizeof(buf), "%llu", (unsigned long long)v);'),
 ("W28 string rep wrong separator (wide)", 'if (i) Tcl_DStringAppend(&ds, " ", 1);', 'if (i) Tcl_DStringAppend(&ds, ",", 1);'),
 ("W29 in: canonical check dropped", "if (strcmp(buf, s) == 0) {", "if (1) {"),
 ("W30 in: searches nonzero instead of value", "*resPtr = (NextWide(b, 0, 0, val) >= 0);", "*resPtr = (NextWide(b, 0, 1, val) >= 0);"),
 ("W31 CountWide 8-bit nonzero inverted", "total += (p[i] != 0);", "total += (p[i] == 0);"),
 ("W32 CountWide 8-bit equal inverted", "total += (p[i] == c);", "total += (p[i] != c);"),
 ("W33 CountWide generic nonzero inverted", "total += anyNZ ? (e != 0) : (e == val);", "total += anyNZ ? (e == 0) : (e == val);"),
 ("W34 NextWide memchr reads one byte too many", "(size_t)(b->len - start));", "(size_t)(b->len - start + 1));"),
 ("W35 NextWide word skip never stops", "\t    if (w) break;\n", "\t    ;\n"),
 ("W36 NextWide generic compares wrong", "if (anyNZ ? (e != 0) : (e == val)) return i;", "if (anyNZ ? (e != 0) : (e != val)) return i;"),
 ("W37 fill 8-bit memset one short", "memset(p + first, c, (size_t)(last - first + 1));", "memset(p + first, c, (size_t)(last - first));"),
 ("W38 fill 8-bit memset wrong start", "memset(p + first, c,", "memset(p, c,"),
 ("W39 fill 8-bit step stop early", "p[i] = c;\n\t\t    if (last - i < step) break;", "p[i] = c;\n\t\t    if (last - i <= step) break;"),
 ("W40 fill generic step stop early", "PutElem(b, i, val);\n\t\tif (last - i < step) break;", "PutElem(b, i, val);\n\t\tif (last - i <= step) break;"),
 ("W41 newfrom stores only values above 1", "if (val) PutElem(n, i, val);", "if (val > 1) PutElem(n, i, val);"),
 ("W42 new 8-bit init one short", "memset(n->words, (int)val, (size_t)n->len);", "memset(n->words, (int)val, (size_t)n->len - 1);"),
 ("W43 new generic init one short", "for (i = 0; i < n->len; i++) PutElem(n, i, val);", "for (i = 0; i < n->len - 1; i++) PutElem(n, i, val);"),
 ("W44 count zeros of bits off by one", "(Tcl_WideInt)(last - first + 1) - cnt;", "(Tcl_WideInt)(last - first) - cnt;"),
 ("W45 count ignores a given value", "\t    if (ParseValue(interp, objv[5], b->width, &val) != TCL_OK) {\n\t\treturn TCL_ERROR;\n\t    }\n\t    anyNZ = 0;", "\t    if (ParseValue(interp, objv[5], b->width, &val) != TCL_OK) {\n\t\treturn TCL_ERROR;\n\t    }"),
 ("W46 next ignores a given value", "\t    if (ParseValue(interp, objv[4], b->width, &val) != TCL_OK) {\n\t\treturn TCL_ERROR;\n\t    }\n\t    anyNZ = 0;", "\t    if (ParseValue(interp, objv[4], b->width, &val) != TCL_OK) {\n\t\treturn TCL_ERROR;\n\t    }"),
 ("W47 -width without argument not detected", "\t    if (i + 1 >= objc) goto usageError;\n", ""),
 ("W48 width 16 rejected", "w != 8 && w != 16 && w != 32", "w != 8 && w != 32"),
 ("W49 dup loses width", "BitArr *s = GETREP(srcPtr), *d = NewRep(NULL, s->len, s->width);", "BitArr *s = GETREP(srcPtr), *d = NewRep(NULL, s->len, 1);"),
 ("W50 setElement parses as 1-bit", "if (ParseValue(interp, valueObj, b->width, &val) != TCL_OK) return NULL;", "if (ParseValue(interp, valueObj, 1, &val) != TCL_OK) return NULL;"),
 ("W51 replace validates as 1-bit", "if (ParseValue(interp, insertObjs[i], b->width, &val) != TCL_OK) {", "if (ParseValue(interp, insertObjs[i], 1, &val) != TCL_OK) {"),
 ("W52 replace sizes storage for 1-bit", "needWords = WORDS_FOR(newLen, b->width);", "needWords = (newLen + 63) / 64;"),
 ("W53 index out of range for wide returns last", "} else if (b->width == 1) {\n\t*elemPtr = GETBIT(b, index) ? b->one : b->zero;\n    } else {", "} else if (b->width == 1) {\n\t*elemPtr = GETBIT(b, index) ? b->one : b->zero;\n    } else if (index == b->len - 1) {\n\t*elemPtr = b->zero;\n    } else {"),
]
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
