/*
 * bitarray.c --
 *
 *	A packed array of small integers that looks like a Tcl list
 *	(llength, lindex, lset, lrange, lreverse, lreplace, foreach, "in",
 *	string representation), built on the Tcl 9 abstract-list hooks of
 *	Tcl_ObjType.  Extension only: no core changes.
 *
 *	Element width (chosen when the array is created, fixed afterwards):
 *	    1   bit      values 0 and 1
 *	    8   bits     unsigned, 0 .. 255
 *	    16  bits     unsigned, 0 .. 65535
 *	    32  bits     unsigned, 0 .. 4294967295
 *	    64  bits     signed,   -2^63 .. 2^63-1
 *
 *	Written by Claude (an AI model made by Anthropic) for Eric Taylor.
 *
 * Commands (all in the global command "bitarray"):
 *	bitarray new SIZE ?VALUE? ?-width W?     all elements VALUE (default 0)
 *	bitarray newfrom LIST ?-width W?         list of integers -> bitarray
 *	bitarray width BA                        1, 8, 16, 32 or 64
 *	bitarray is VALUE                        1 if VALUE has the bitarray rep
 *	bitarray count BA ?FIRST LAST ?VALUE??   elements equal to VALUE, or
 *	                                         non-zero if VALUE is omitted
 *	bitarray next BA START ?VALUE?           first index >= START holding
 *	                                         VALUE (default: non-zero), or -1
 *	bitarray fill VARNAME FIRST LAST VALUE ?STEP?
 *	                            set every STEP-th element in FIRST..LAST
 *	                            (in place, like lset; returns empty string)
 */

#include <tcl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/*
 * 32-bit / 64-bit.  Tcl_Size has the width of a pointer, so on a 32-bit build
 * it is 32 bits.  BA_MAX_BITS is the largest array we allow, counted in TOTAL
 * BITS of storage (elements times element width); sizes are always checked as
 * 64-bit values BEFORE they are narrowed to Tcl_Size.
 *   64-bit: 2^40 bits (128 GiB).
 *   32-bit: 2^30 - 1 bits (128 MiB), so that 2*len-1 (the string
 *           representation) and len+63 cannot overflow a signed 32-bit size.
 */
#if SIZE_MAX > 0xFFFFFFFFu && !defined(BA_FORCE_32BIT_LIMITS)
#   define BA_MAX_BITS	((Tcl_WideInt)1 << 40)
#else
#   define BA_MAX_BITS	((Tcl_WideInt)0x3FFFFFFF)
#endif

/*
 * Population count and count-trailing-zeros on a 64-bit word.  GCC and clang
 * have builtins; anywhere else (or with -DBA_NO_BUILTINS) use plain C.
 */
#if (defined(__GNUC__) || defined(__clang__)) && !defined(BA_NO_BUILTINS)
#   define BA_POPCOUNT(x)	__builtin_popcountll(x)
#   define BA_CTZ(x)		__builtin_ctzll(x)
#else
static int
BaPopcount(uint64_t x)
{
    x = x - ((x >> 1) & 0x5555555555555555ULL);
    x = (x & 0x3333333333333333ULL) + ((x >> 2) & 0x3333333333333333ULL);
    x = (x + (x >> 4)) & 0x0F0F0F0F0F0F0F0FULL;
    return (int)((x * 0x0101010101010101ULL) >> 56);
}
static int
BaCtz(uint64_t x)		/* x must be non-zero */
{
    int n = 0;

    if (!(x & 0xFFFFFFFFULL)) { n += 32; x >>= 32; }
    if (!(x & 0xFFFFULL))     { n += 16; x >>= 16; }
    if (!(x & 0xFFULL))       { n += 8;  x >>= 8; }
    if (!(x & 0xFULL))        { n += 4;  x >>= 4; }
    if (!(x & 0x3ULL))        { n += 2;  x >>= 2; }
    if (!(x & 0x1ULL))        { n += 1; }
    return n;
}
#   define BA_POPCOUNT(x)	BaPopcount(x)
#   define BA_CTZ(x)		BaCtz(x)
#endif

typedef struct BitArr {
    Tcl_Size len;		/* Number of elements. */
    Tcl_Size nwords;		/* 64-bit words in use: (len*width + 63) / 64. */
    Tcl_Size capWords;		/* Words allocated (>= nwords); every bit at or
				 * beyond the end of the data, up to the
				 * capacity, is 0. */
    int width;			/* Bits per element: 1, 8, 16, 32 or 64. */
    Tcl_Obj *zero, *one;	/* Shared element values handed out by index. */
    Tcl_Obj **elems;		/* Lazily built element vector, or NULL. */
    Tcl_Size elemsLen;		/* Number of entries in elems. */
    uint64_t words[1];		/* Storage (at least one word is always
				 * present).  Width 1: bit i is bit (i&63) of
				 * word i>>6.  Wider: elements packed as bytes
				 * in host order, read and written only through
				 * GetElem/PutElem. */
} BitArr;

static Tcl_ObjTypeLengthProc	BALength;
static Tcl_ObjTypeIndexProc	BAIndex;
static Tcl_ObjTypeSliceProc	BASlice;
static Tcl_ObjTypeReverseProc	BAReverse;
static Tcl_ObjTypeGetElements	BAGetElements;
static Tcl_ObjTypeSetElement	BASetElement;
static Tcl_ObjTypeReplaceProc	BAReplace;
static Tcl_ObjTypeInOperatorProc BAInOper;
static Tcl_FreeInternalRepProc	BAFree;
static Tcl_DupInternalRepProc	BADup;
static Tcl_UpdateStringProc	BAUpdateString;

static const Tcl_ObjType bitarrayType = {
    "bitarray", BAFree, BADup, BAUpdateString, NULL,
    TCL_OBJTYPE_V2(BALength, BAIndex, BASlice, BAReverse, BAGetElements,
	    BASetElement, BAReplace, BAInOper)
};

#define GETREP(o)	((BitArr *)(o)->internalRep.twoPtrValue.ptr1)
#define ISBA(o)		((o)->typePtr == &bitarrayType)
#define GETBIT(b,i)	(((b)->words[(i) >> 6] >> ((i) & 63)) & 1)
#define SETBIT(b,i)	((b)->words[(i) >> 6] |= (uint64_t)1 << ((i) & 63))
#define CLRBIT(b,i)	((b)->words[(i) >> 6] &= ~((uint64_t)1 << ((i) & 63)))
#define BYTES(b)	((unsigned char *)(b)->words)
#define EBYTES(b)	((size_t)(b)->width / 8)    /* width > 1 only */

/* Words needed for LEN elements of WIDTH bits (caller has range-checked). */
#define WORDS_FOR(len, width) \
	((Tcl_Size)(((Tcl_WideInt)(len) * (width) + 63) / 64))

/* ---------------------------------------------------------------- */

/*
 * Read or write element I.  The value is the raw unsigned bit pattern; for
 * width 64 the caller reinterprets it as signed.  Multi-byte elements go
 * through memcpy, which compilers turn into a single load or store and which
 * avoids strict-aliasing and alignment problems.
 */
static uint64_t
GetElem(const BitArr *b, Tcl_Size i)
{
    const unsigned char *p = (const unsigned char *)b->words;

    if (b->width == 1) return GETBIT(b, i);
    switch (b->width) {
    case 8:  return p[i];
    case 16: { uint16_t v; memcpy(&v, p + 2 * (size_t)i, 2); return v; }
    case 32: { uint32_t v; memcpy(&v, p + 4 * (size_t)i, 4); return v; }
    case 64: { uint64_t v; memcpy(&v, p + 8 * (size_t)i, 8); return v; }
    default: return GETBIT(b, i);
    }
}

static void
PutElem(BitArr *b, Tcl_Size i, uint64_t val)
{
    unsigned char *p = BYTES(b);

    if (b->width == 1) {
	if (val) SETBIT(b, i); else CLRBIT(b, i);
	return;
    }
    switch (b->width) {
    case 8:  p[i] = (unsigned char)val; break;
    case 16: { uint16_t v = (uint16_t)val; memcpy(p + 2 * (size_t)i, &v, 2); break; }
    case 32: { uint32_t v = (uint32_t)val; memcpy(p + 4 * (size_t)i, &v, 4); break; }
    case 64: memcpy(p + 8 * (size_t)i, &val, 8); break;
    default: if (val) SETBIT(b, i); else CLRBIT(b, i); break;
    }
}

static BitArr *
NewRep(Tcl_Interp *interp, Tcl_Size len, int width)
{
    Tcl_Size nwords;
    size_t bytes;
    BitArr *b;

    if (len < 0 || (Tcl_WideInt)len * width > BA_MAX_BITS) {
	if (interp) {
	    Tcl_SetObjResult(interp, Tcl_NewStringObj(
		    "bitarray size out of range", -1));
	    Tcl_SetErrorCode(interp, "TCL", "VALUE", "SIZE", NULL);
	}
	return NULL;
    }
    nwords = WORDS_FOR(len, width);
    bytes = sizeof(BitArr) + (nwords ? nwords - 1 : 0) * sizeof(uint64_t);
    b = (BitArr *)Tcl_AttemptAlloc(bytes);
    if (b == NULL) {
	if (interp) {
	    Tcl_SetObjResult(interp, Tcl_NewStringObj("out of memory", -1));
	    Tcl_SetErrorCode(interp, "TCL", "MEMORY", NULL);
	}
	return NULL;
    }
    memset(b, 0, bytes);
    b->len = len;
    b->nwords = nwords;
    b->capWords = nwords;
    b->width = width;
    b->zero = Tcl_NewWideIntObj(0);
    b->one = Tcl_NewWideIntObj(1);
    Tcl_IncrRefCount(b->zero);
    Tcl_IncrRefCount(b->one);
    return b;
}

static void
FreeElems(BitArr *b)
{
    if (b->elems) {
	if (b->width != 1) {
	    Tcl_Size i;

	    /* Entries other than the shared 0/1 objects are owned by us. */
	    for (i = 0; i < b->elemsLen; i++) {
		if (b->elems[i] != b->zero && b->elems[i] != b->one) {
		    Tcl_DecrRefCount(b->elems[i]);
		}
	    }
	}
	Tcl_Free(b->elems);
	b->elems = NULL;
	b->elemsLen = 0;
    }
}

static void
FreeRep(BitArr *b)
{
    FreeElems(b);
    Tcl_DecrRefCount(b->zero);
    Tcl_DecrRefCount(b->one);
    Tcl_Free(b);
}

static Tcl_Obj *
WrapRep(BitArr *b)
{
    Tcl_Obj *obj = Tcl_NewObj();
    Tcl_ObjInternalRep ir;

    Tcl_InvalidateStringRep(obj);
    ir.twoPtrValue.ptr1 = b;
    ir.twoPtrValue.ptr2 = NULL;
    Tcl_StoreInternalRep(obj, &bitarrayType, &ir);
    return obj;
}

static void
Touch(Tcl_Obj *obj)
{
    FreeElems(GETREP(obj));
    Tcl_InvalidateStringRep(obj);
}

/* Element VAL as a Tcl value (new object, reference count 0, unless 0 or 1). */
static Tcl_Obj *
ElemObj(const BitArr *b, uint64_t val)
{
    if (val == 0) return b->zero;
    if (val == 1) return b->one;
    return Tcl_NewWideIntObj(b->width == 64 ? (Tcl_WideInt)(int64_t)val
	    : (Tcl_WideInt)val);
}

static void
SetRangeOnes(BitArr *b, Tcl_Size first, Tcl_Size last, int val)
{
    Tcl_Size fw = first >> 6, lw = last >> 6, i;
    uint64_t fm = ~(uint64_t)0 << (first & 63);
    uint64_t lm = ~(uint64_t)0 >> (63 - (last & 63));

    if (fw == lw) {
	if (val) b->words[fw] |= (fm & lm); else b->words[fw] &= ~(fm & lm);
	return;
    }
    if (val) b->words[fw] |= fm; else b->words[fw] &= ~fm;
    for (i = fw + 1; i < lw; i++) {
	b->words[i] = val ? ~(uint64_t)0 : 0;
    }
    if (val) b->words[lw] |= lm; else b->words[lw] &= ~lm;
}

static Tcl_WideInt
CountRange(BitArr *b, Tcl_Size first, Tcl_Size last)
{
    Tcl_Size fw, lw, i;
    uint64_t fm, lm;
    Tcl_WideInt total;

    if (first > last) return 0;
    fw = first >> 6; lw = last >> 6;
    fm = ~(uint64_t)0 << (first & 63);
    lm = ~(uint64_t)0 >> (63 - (last & 63));
    if (fw == lw) {
	return BA_POPCOUNT(b->words[fw] & fm & lm);
    }
    total = BA_POPCOUNT(b->words[fw] & fm);
    for (i = fw + 1; i < lw; i++) {
	total += BA_POPCOUNT(b->words[i]);
    }
    return total + BA_POPCOUNT(b->words[lw] & lm);
}

static Tcl_Size
NextBit(BitArr *b, Tcl_Size start, int val)
{
    Tcl_Size w;
    uint64_t cur;

    if (start < 0) start = 0;
    if (start >= b->len) return -1;
    w = start >> 6;
    cur = (val ? b->words[w] : ~b->words[w]) & (~(uint64_t)0 << (start & 63));
    for (;;) {
	if (cur) {
	    Tcl_Size idx = (w << 6) + BA_CTZ(cur);
	    return idx < b->len ? idx : -1;
	}
	if (++w >= b->nwords) return -1;
	cur = val ? b->words[w] : ~b->words[w];
    }
}

/*
 * Counting and searching for widths above 1.  ANYNZ means "any non-zero
 * element"; otherwise elements equal to VAL (a raw bit pattern).
 */
static Tcl_WideInt
CountWide(const BitArr *b, Tcl_Size first, Tcl_Size last, int anyNZ,
	uint64_t val)
{
    Tcl_WideInt total = 0;
    Tcl_Size i;

    if (first > last) return 0;
    if (b->width == 8) {
	const unsigned char *p = (const unsigned char *)b->words;

	if (anyNZ) {
	    for (i = first; i <= last; i++) total += (p[i] != 0);
	} else {
	    unsigned char c = (unsigned char)val;

	    for (i = first; i <= last; i++) total += (p[i] == c);
	}
	return total;
    }
    for (i = first; i <= last; i++) {
	uint64_t e = GetElem(b, i);

	total += anyNZ ? (e != 0) : (e == val);
    }
    return total;
}

static Tcl_Size
NextWide(const BitArr *b, Tcl_Size start, int anyNZ, uint64_t val)
{
    Tcl_Size i;

    if (start < 0) start = 0;
    if (start >= b->len) return -1;
    if (b->width == 8) {
	const unsigned char *p = (const unsigned char *)b->words;

	if (!anyNZ) {
	    const unsigned char *q = (const unsigned char *)memchr(p + start,
		    (int)val, (size_t)(b->len - start));

	    return q ? (Tcl_Size)(q - p) : -1;
	}
	i = start;
	for (; i < b->len && (i & 7); i++) {
	    if (p[i]) return i;
	}
	for (; i + 8 <= b->len; i += 8) {
	    uint64_t w;

	    memcpy(&w, p + i, 8);
	    if (w) break;
	}
	for (; i < b->len; i++) {
	    if (p[i]) return i;
	}
	return -1;
    }
    for (i = start; i < b->len; i++) {
	uint64_t e = GetElem(b, i);

	if (anyNZ ? (e != 0) : (e == val)) return i;
    }
    return -1;
}

static int
ParseBit(Tcl_Interp *interp, Tcl_Obj *obj, int *bitPtr)
{
    Tcl_WideInt v;

    /* Fast path: a literal 0 or 1 that already has a string representation. */
    if (obj->bytes != NULL && obj->length == 1
	    && (obj->bytes[0] == '0' || obj->bytes[0] == '1')) {
	*bitPtr = obj->bytes[0] - '0';
	return TCL_OK;
    }
    if (Tcl_GetWideIntFromObj(NULL, obj, &v) != TCL_OK || (v != 0 && v != 1)) {
	if (interp) {
	    Tcl_SetObjResult(interp, Tcl_ObjPrintf(
		    "expected 0 or 1 but got \"%s\"", Tcl_GetString(obj)));
	    Tcl_SetErrorCode(interp, "TCL", "VALUE", "BITARRAY", NULL);
	}
	return TCL_ERROR;
    }
    *bitPtr = (int)v;
    return TCL_OK;
}

/*
 * Parse an element value for an array of WIDTH bits into its raw bit pattern.
 * Widths 8, 16 and 32 are unsigned; width 64 is signed.
 */
static int
ParseValue(Tcl_Interp *interp, Tcl_Obj *obj, int width, uint64_t *vp)
{
    Tcl_WideInt v;

    if (width == 1) {
	int bit;

	if (ParseBit(interp, obj, &bit) != TCL_OK) return TCL_ERROR;
	*vp = (uint64_t)bit;
	return TCL_OK;
    }
    if (obj->bytes != NULL && obj->length == 1
	    && obj->bytes[0] >= '0' && obj->bytes[0] <= '9') {
	*vp = (uint64_t)(obj->bytes[0] - '0');
	return TCL_OK;
    }
    if (Tcl_GetWideIntFromObj(NULL, obj, &v) == TCL_OK) {
	if (width == 64) {
	    *vp = (uint64_t)v;
	    return TCL_OK;
	}
	if (v >= 0 && v <= (Tcl_WideInt)(((uint64_t)1 << width) - 1)) {
	    *vp = (uint64_t)v;
	    return TCL_OK;
	}
    }
    if (interp) {
	if (width == 64) {
	    Tcl_SetObjResult(interp, Tcl_ObjPrintf(
		    "expected integer in range -9223372036854775808..9223372036854775807"
		    " but got \"%s\"", Tcl_GetString(obj)));
	} else {
	    Tcl_SetObjResult(interp, Tcl_ObjPrintf(
		    "expected integer in range 0..%lld but got \"%s\"",
		    (long long)(((uint64_t)1 << width) - 1), Tcl_GetString(obj)));
	}
	Tcl_SetErrorCode(interp, "TCL", "VALUE", "BITARRAY", NULL);
    }
    return TCL_ERROR;
}

static void
IndexError(Tcl_Interp *interp, Tcl_Obj *idxObj)
{
    if (interp) {
	Tcl_SetObjResult(interp, Tcl_ObjPrintf("index \"%s\" out of range",
		Tcl_GetString(idxObj)));
	Tcl_SetErrorCode(interp, "TCL", "VALUE", "INDEX", "OUTOFRANGE", NULL);
    }
}

/* ------------------------- type hooks ----------------------------- */

static void
BAFree(Tcl_Obj *objPtr)
{
    FreeRep(GETREP(objPtr));
    objPtr->typePtr = NULL;
}

static void
BADup(Tcl_Obj *srcPtr, Tcl_Obj *copyPtr)
{
    BitArr *s = GETREP(srcPtr), *d = NewRep(NULL, s->len, s->width);
    Tcl_ObjInternalRep ir;

    if (d == NULL) Tcl_Panic("bitarray: out of memory in dup");
    memcpy(d->words, s->words, (size_t)s->nwords * sizeof(uint64_t));
    ir.twoPtrValue.ptr1 = d;
    ir.twoPtrValue.ptr2 = NULL;
    Tcl_StoreInternalRep(copyPtr, &bitarrayType, &ir);
}

static void
BAUpdateString(Tcl_Obj *objPtr)
{
    BitArr *b = GETREP(objPtr);
    char *p;
    Tcl_Size i;

    if (b->len == 0) {
	Tcl_InitStringRep(objPtr, NULL, 0);
	return;
    }
    if (b->width == 1) {
	p = Tcl_InitStringRep(objPtr, NULL, 2 * b->len - 1);
	if (p == NULL) Tcl_Panic("bitarray: out of memory in string rep");
	for (i = 0; i < b->len; i++) {
	    *p++ = (char)('0' + GETBIT(b, i));
	    if (i + 1 < b->len) *p++ = ' ';
	}
    } else {
	Tcl_DString ds;
	char buf[32];
	int n;

	Tcl_DStringInit(&ds);
	for (i = 0; i < b->len; i++) {
	    uint64_t v = GetElem(b, i);

	    if (i) Tcl_DStringAppend(&ds, " ", 1);
	    if (b->width == 64) {
		n = snprintf(buf, sizeof(buf), "%lld", (long long)(int64_t)v);
	    } else {
		n = snprintf(buf, sizeof(buf), "%llu", (unsigned long long)v);
	    }
	    Tcl_DStringAppend(&ds, buf, n);
	}
	Tcl_InitStringRep(objPtr, Tcl_DStringValue(&ds),
		(Tcl_Size)Tcl_DStringLength(&ds));
	Tcl_DStringFree(&ds);
    }
}

static Tcl_Size
BALength(Tcl_Obj *objPtr)
{
    return GETREP(objPtr)->len;
}

static int
BAIndex(Tcl_Interp *interp, Tcl_Obj *objPtr, Tcl_Size index, Tcl_Obj **elemPtr)
{
    BitArr *b = GETREP(objPtr);

    (void)interp;
    if (index < 0 || index >= b->len) {
	*elemPtr = NULL;
    } else if (b->width == 1) {
	*elemPtr = GETBIT(b, index) ? b->one : b->zero;
    } else {
	*elemPtr = ElemObj(b, GetElem(b, index));
    }
    return TCL_OK;
}

static int
BASlice(Tcl_Interp *interp, Tcl_Obj *objPtr, Tcl_Size from, Tcl_Size to,
	Tcl_Obj **newObjPtr)
{
    BitArr *b = GETREP(objPtr), *n;
    Tcl_Size i, len;

    if (from < 0) from = 0;
    if (to >= b->len) to = b->len - 1;
    if (from > to || from >= b->len) {
	*newObjPtr = Tcl_NewObj();
	return TCL_OK;
    }
    len = to - from + 1;
    if ((n = NewRep(interp, len, b->width)) == NULL) return TCL_ERROR;
    if (b->width != 1) {
	memcpy(BYTES(n), BYTES(b) + (size_t)from * EBYTES(b),
		(size_t)len * EBYTES(b));
    } else if ((from & 63) == 0) {
	memcpy(n->words, &b->words[from >> 6],
		(size_t)n->nwords * sizeof(uint64_t));
	if (len & 63) {
	    n->words[n->nwords - 1] &= ~(~(uint64_t)0 << (len & 63));
	}
    } else {
	for (i = 0; i < len; i++) {
	    if (GETBIT(b, from + i)) SETBIT(n, i);
	}
    }
    *newObjPtr = WrapRep(n);
    return TCL_OK;
}

static int
BAReverse(Tcl_Interp *interp, Tcl_Obj *objPtr, Tcl_Obj **newObjPtr)
{
    BitArr *b = GETREP(objPtr), *n;
    Tcl_Size i;

    if ((n = NewRep(interp, b->len, b->width)) == NULL) return TCL_ERROR;
    if (b->width == 1) {
	for (i = 0; i < b->len; i++) {
	    if (GETBIT(b, b->len - 1 - i)) SETBIT(n, i);
	}
    } else {
	for (i = 0; i < b->len; i++) {
	    PutElem(n, i, GetElem(b, b->len - 1 - i));
	}
    }
    *newObjPtr = WrapRep(n);
    return TCL_OK;
}

static int
BAGetElements(Tcl_Interp *interp, Tcl_Obj *objPtr, Tcl_Size *objcPtr,
	Tcl_Obj ***objvPtr)
{
    BitArr *b = GETREP(objPtr);
    Tcl_Size i;

    if (b->elems == NULL) {
	if ((size_t)b->len > (size_t)-1 / sizeof(Tcl_Obj *) / 2) {
	    if (interp) {
		Tcl_SetObjResult(interp, Tcl_NewStringObj("out of memory", -1));
	    }
	    return TCL_ERROR;
	}
	b->elems = (Tcl_Obj **)Tcl_AttemptAlloc(
		(size_t)(b->len ? b->len : 1) * sizeof(Tcl_Obj *));
	if (b->elems == NULL) {
	    if (interp) {
		Tcl_SetObjResult(interp, Tcl_NewStringObj("out of memory", -1));
	    }
	    return TCL_ERROR;
	}
	if (b->width == 1) {
	    for (i = 0; i < b->len; i++) {
		b->elems[i] = GETBIT(b, i) ? b->one : b->zero;
	    }
	} else {
	    for (i = 0; i < b->len; i++) {
		Tcl_Obj *e = ElemObj(b, GetElem(b, i));

		if (e != b->zero && e != b->one) Tcl_IncrRefCount(e);
		b->elems[i] = e;
	    }
	}
	b->elemsLen = b->len;
    }
    *objcPtr = b->len;
    *objvPtr = b->elems;
    return TCL_OK;
}

static Tcl_Obj *
BASetElement(Tcl_Interp *interp, Tcl_Obj *listPtr, Tcl_Size indexCount,
	Tcl_Obj *const indexArray[], Tcl_Obj *valueObj)
{
    BitArr *b;
    Tcl_Size idx;
    uint64_t val;
    Tcl_Obj *obj = listPtr;

    if (indexCount != 1) {
	if (interp) {
	    Tcl_SetObjResult(interp, Tcl_NewStringObj(
		    "bitarray elements are not lists", -1));
	    Tcl_SetErrorCode(interp, "TCL", "VALUE", "BITARRAY", NULL);
	}
	return NULL;
    }
    b = GETREP(listPtr);
    if (Tcl_GetIntForIndex(interp, indexArray[0], b->len - 1, &idx) != TCL_OK) {
	return NULL;
    }
    if (idx == TCL_SIZE_MAX && b->len == 0) {
	idx = 0;		/* Same special case as the core's TclLsetFlat. */
    }
    if (idx < 0 || idx > b->len) {
	IndexError(interp, indexArray[0]);
	return NULL;
    }
    if (ParseValue(interp, valueObj, b->width, &val) != TCL_OK) return NULL;
    if (Tcl_IsShared(obj)) {
	obj = Tcl_DuplicateObj(obj);
    }
    if (idx == GETREP(obj)->len) {
	/* lset on a list with index == length appends. */
	if (BAReplace(interp, obj, idx, 0, 1, &valueObj) != TCL_OK) {
	    if (obj != listPtr) Tcl_BounceRefCount(obj);
	    return NULL;
	}
	return obj;
    }
    b = GETREP(obj);
    PutElem(b, idx, val);
    Touch(obj);
    return obj;
}

/*
 * Copy COUNT elements from FROM to TO within one array, as memmove would.
 */
static void
MoveElems(BitArr *b, Tcl_Size from, Tcl_Size to, Tcl_Size count)
{
    Tcl_Size i;

    if (from == to || count <= 0) return;
    if (b->width != 1) {
	memmove(BYTES(b) + (size_t)to * EBYTES(b),
		BYTES(b) + (size_t)from * EBYTES(b), (size_t)count * EBYTES(b));
	return;
    }
    if (to < from) {
	for (i = 0; i < count; i++) {
	    if (GETBIT(b, from + i)) SETBIT(b, to + i); else CLRBIT(b, to + i);
	}
    } else {
	for (i = count - 1; i >= 0; i--) {
	    if (GETBIT(b, from + i)) SETBIT(b, to + i); else CLRBIT(b, to + i);
	}
    }
}

/*
 * lreplace / linsert / lappend.  Edits the array in place.  The array keeps
 * spare capacity and doubles it when full, so appending one element at a time
 * costs O(1) on average, as it does for a list.  The caller guarantees the
 * object is not shared.
 */
static int
BAReplace(Tcl_Interp *interp, Tcl_Obj *listObj, Tcl_Size first,
	Tcl_Size numToDelete, Tcl_Size numToInsert, Tcl_Obj *const insertObjs[])
{
    BitArr *b = GETREP(listObj);
    Tcl_Size i, newLen, oldLen = b->len, needWords;
    Tcl_WideInt wideLen;
    uint64_t val;

    if (first < 0) first = 0;
    if (first > oldLen) first = oldLen;
    if (numToDelete < 0) numToDelete = 0;
    if (numToDelete > oldLen - first) numToDelete = oldLen - first;
    for (i = 0; i < numToInsert; i++) {
	if (ParseValue(interp, insertObjs[i], b->width, &val) != TCL_OK) {
	    return TCL_ERROR;
	}
    }
    wideLen = (Tcl_WideInt)oldLen - numToDelete + numToInsert;
    if (wideLen > BA_MAX_BITS / b->width) {
	if (interp) {
	    Tcl_SetObjResult(interp, Tcl_NewStringObj(
		    "bitarray size out of range", -1));
	    Tcl_SetErrorCode(interp, "TCL", "VALUE", "SIZE", NULL);
	}
	return TCL_ERROR;
    }
    newLen = (Tcl_Size)wideLen;
    needWords = WORDS_FOR(newLen, b->width);

    /* Grow the allocation (doubling) if the new length does not fit. */
    if (needWords > b->capWords) {
	Tcl_Size maxWords = (Tcl_Size)((BA_MAX_BITS + 63) / 64);
	Tcl_Size newCap = b->capWords * 2, oldCap = b->capWords;
	BitArr *nb;

	if (newCap < 4) newCap = 4;
	if (newCap < needWords) newCap = needWords;
	if (newCap > maxWords) newCap = maxWords;
	nb = (BitArr *)Tcl_AttemptRealloc(b,
		sizeof(BitArr) + (size_t)(newCap - 1) * sizeof(uint64_t));
	if (nb == NULL && newCap > needWords) {
	    newCap = needWords;
	    nb = (BitArr *)Tcl_AttemptRealloc(b,
		    sizeof(BitArr) + (size_t)(newCap - 1) * sizeof(uint64_t));
	}
	if (nb == NULL) {
	    if (interp) {
		Tcl_SetObjResult(interp, Tcl_NewStringObj("out of memory", -1));
		Tcl_SetErrorCode(interp, "TCL", "MEMORY", NULL);
	    }
	    return TCL_ERROR;
	}
	b = nb;
	memset(&b->words[oldCap], 0,
		(size_t)(newCap - oldCap) * sizeof(uint64_t));
	b->capWords = newCap;
	listObj->internalRep.twoPtrValue.ptr1 = b;
    }

    /* The element cache refers to the old contents; drop it first. */
    FreeElems(b);

    /* Slide the tail, write the inserted values, clear what was vacated. */
    MoveElems(b, first + numToDelete, first + numToInsert,
	    oldLen - (first + numToDelete));
    for (i = 0; i < numToInsert; i++) {
	ParseValue(NULL, insertObjs[i], b->width, &val);
	PutElem(b, first + i, val);
    }
    if (newLen < oldLen) {
	if (b->width == 1) {
	    for (i = newLen; i < oldLen; i++) CLRBIT(b, i);
	} else {
	    memset(BYTES(b) + (size_t)newLen * EBYTES(b), 0,
		    (size_t)(oldLen - newLen) * EBYTES(b));
	}
    }
    b->len = newLen;
    b->nwords = needWords;
    Tcl_InvalidateStringRep(listObj);
    return TCL_OK;
}

static int
BAInOper(Tcl_Interp *interp, Tcl_Obj *valueObj, Tcl_Obj *listObj, int *resPtr)
{
    BitArr *b = GETREP(listObj);
    const char *s = Tcl_GetString(valueObj);
    Tcl_WideInt ones;

    (void)interp;
    *resPtr = 0;
    if (b->width == 1) {
	if (s[0] && !s[1] && (s[0] == '0' || s[0] == '1')) {
	    ones = CountRange(b, 0, b->len - 1);
	    *resPtr = (s[0] == '1') ? (ones > 0) : (ones < b->len);
	}
    } else {
	/*
	 * "in" compares string forms, so only the canonical decimal spelling
	 * of an element matches ("007" does not match 7).
	 */
	uint64_t val;
	char buf[32];

	if (ParseValue(NULL, valueObj, b->width, &val) == TCL_OK) {
	    if (b->width == 64) {
		snprintf(buf, sizeof(buf), "%lld", (long long)(int64_t)val);
	    } else {
		snprintf(buf, sizeof(buf), "%llu", (unsigned long long)val);
	    }
	    if (strcmp(buf, s) == 0) {
		*resPtr = (NextWide(b, 0, 0, val) >= 0);
	    }
	}
    }
    return TCL_OK;
}

/* --------------------------- commands ----------------------------- */

static int
NeedBA(Tcl_Interp *interp, Tcl_Obj *obj, BitArr **bPtr)
{
    if (!ISBA(obj)) {
	Tcl_SetObjResult(interp, Tcl_ObjPrintf("not a bitarray: \"%.40s\"",
		Tcl_GetString(obj)));
	Tcl_SetErrorCode(interp, "TCL", "VALUE", "BITARRAY", NULL);
	return TCL_ERROR;
    }
    *bPtr = GETREP(obj);
    return TCL_OK;
}

static int
ParseWidthArg(Tcl_Interp *interp, Tcl_Obj *obj, int *widthPtr)
{
    Tcl_WideInt w;

    if (Tcl_GetWideIntFromObj(NULL, obj, &w) != TCL_OK
	    || (w != 1 && w != 8 && w != 16 && w != 32 && w != 64)) {
	Tcl_SetObjResult(interp, Tcl_ObjPrintf(
		"bad width \"%s\": must be 1, 8, 16, 32 or 64",
		Tcl_GetString(obj)));
	Tcl_SetErrorCode(interp, "TCL", "VALUE", "BITARRAY", NULL);
	return TCL_ERROR;
    }
    *widthPtr = (int)w;
    return TCL_OK;
}

/*
 * Scan the optional arguments of "new" and "newfrom" starting at objv[FROM]:
 * "-width W" anywhere, and (for "new" only) one bare VALUE.
 */
static int
ParseCreateArgs(Tcl_Interp *interp, Tcl_Size objc, Tcl_Obj *const objv[],
	Tcl_Size from, int allowValue, int *widthPtr, Tcl_Obj **valuePtr,
	const char *usage)
{
    Tcl_Size i;

    *widthPtr = 1;
    *valuePtr = NULL;
    for (i = from; i < objc; i++) {
	if (strcmp(Tcl_GetString(objv[i]), "-width") == 0) {
	    if (i + 1 >= objc) goto usageError;
	    if (ParseWidthArg(interp, objv[++i], widthPtr) != TCL_OK) {
		return TCL_ERROR;
	    }
	} else if (allowValue && *valuePtr == NULL) {
	    *valuePtr = objv[i];
	} else {
	    goto usageError;
	}
    }
    return TCL_OK;

  usageError:
    Tcl_WrongNumArgs(interp, 2, objv, usage);
    return TCL_ERROR;
}

static int
BitarrayCmd(void *cd, Tcl_Interp *interp, Tcl_Size objc, Tcl_Obj *const objv[])
{
    static const char *const subs[] = {
	"new", "newfrom", "width", "is", "count", "next", "fill", NULL
    };
    enum { S_NEW, S_NEWFROM, S_WIDTH, S_IS, S_COUNT, S_NEXT, S_FILL };
    int sub, bit, width;
    BitArr *b = NULL, *n;
    Tcl_Size i, first, last;
    Tcl_WideInt w;
    uint64_t val;
    Tcl_Obj *valObj;

    (void)cd;
    if (objc < 2) {
	Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?arg ...?");
	return TCL_ERROR;
    }
    if (Tcl_GetIndexFromObj(interp, objv[1], subs, "subcommand", 0, &sub)
	    != TCL_OK) {
	return TCL_ERROR;
    }
    switch (sub) {
    case S_NEW:
	if (objc < 3) {
	    Tcl_WrongNumArgs(interp, 2, objv, "size ?value? ?-width w?");
	    return TCL_ERROR;
	}
	if (Tcl_GetWideIntFromObj(interp, objv[2], &w) != TCL_OK) return TCL_ERROR;
	if (ParseCreateArgs(interp, objc, objv, 3, 1, &width, &valObj,
		"size ?value? ?-width w?") != TCL_OK) {
	    return TCL_ERROR;
	}
	val = 0;
	if (valObj != NULL && ParseValue(interp, valObj, width, &val) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (w < 0 || w > BA_MAX_BITS / width) {
	    Tcl_SetObjResult(interp, Tcl_NewStringObj(
		    "bitarray size out of range", -1));
	    Tcl_SetErrorCode(interp, "TCL", "VALUE", "SIZE", NULL);
	    return TCL_ERROR;
	}
	if ((n = NewRep(interp, (Tcl_Size)w, width)) == NULL) return TCL_ERROR;
	if (val && n->len > 0) {
	    if (width == 1) {
		SetRangeOnes(n, 0, n->len - 1, 1);
	    } else if (width == 8) {
		memset(n->words, (int)val, (size_t)n->len);
	    } else {
		for (i = 0; i < n->len; i++) PutElem(n, i, val);
	    }
	}
	Tcl_SetObjResult(interp, WrapRep(n));
	return TCL_OK;
    case S_NEWFROM: {
	Tcl_Size ec;
	Tcl_Obj **ev;

	if (objc < 3) {
	    Tcl_WrongNumArgs(interp, 2, objv, "list ?-width w?");
	    return TCL_ERROR;
	}
	if (ParseCreateArgs(interp, objc, objv, 3, 0, &width, &valObj,
		"list ?-width w?") != TCL_OK) {
	    return TCL_ERROR;
	}
	if (Tcl_ListObjGetElements(interp, objv[2], &ec, &ev) != TCL_OK) {
	    return TCL_ERROR;
	}
	for (i = 0; i < ec; i++) {
	    if (ParseValue(interp, ev[i], width, &val) != TCL_OK) return TCL_ERROR;
	}
	if ((n = NewRep(interp, ec, width)) == NULL) return TCL_ERROR;
	for (i = 0; i < ec; i++) {
	    ParseValue(NULL, ev[i], width, &val);
	    if (val) PutElem(n, i, val);
	}
	Tcl_SetObjResult(interp, WrapRep(n));
	return TCL_OK;
    }
    case S_WIDTH:
	if (objc != 3) {
	    Tcl_WrongNumArgs(interp, 2, objv, "bitarray");
	    return TCL_ERROR;
	}
	if (NeedBA(interp, objv[2], &b) != TCL_OK) return TCL_ERROR;
	Tcl_SetObjResult(interp, Tcl_NewWideIntObj(b->width));
	return TCL_OK;
    case S_IS:
	if (objc != 3) {
	    Tcl_WrongNumArgs(interp, 2, objv, "value");
	    return TCL_ERROR;
	}
	Tcl_SetObjResult(interp, Tcl_NewBooleanObj(ISBA(objv[2])));
	return TCL_OK;
    case S_COUNT: {
	int anyNZ = 1;
	Tcl_WideInt cnt;

	if (objc != 3 && objc != 5 && objc != 6) {
	    Tcl_WrongNumArgs(interp, 2, objv, "bitarray ?first last ?value??");
	    return TCL_ERROR;
	}
	if (NeedBA(interp, objv[2], &b) != TCL_OK) return TCL_ERROR;
	first = 0; last = b->len - 1;
	if (objc >= 5) {
	    if (Tcl_GetIntForIndex(interp, objv[3], b->len - 1, &first) != TCL_OK
		    || Tcl_GetIntForIndex(interp, objv[4], b->len - 1, &last)
		    != TCL_OK) {
		return TCL_ERROR;
	    }
	    if (first < 0) first = 0;
	    if (last >= b->len) last = b->len - 1;
	}
	val = 1;
	if (objc == 6) {
	    if (ParseValue(interp, objv[5], b->width, &val) != TCL_OK) {
		return TCL_ERROR;
	    }
	    anyNZ = 0;
	}
	if (b->width == 1) {
	    cnt = CountRange(b, first, last);
	    if (!anyNZ && val == 0) {
		cnt = (first > last) ? 0 : (Tcl_WideInt)(last - first + 1) - cnt;
	    }
	} else {
	    cnt = CountWide(b, first, last, anyNZ, val);
	}
	Tcl_SetObjResult(interp, Tcl_NewWideIntObj(cnt));
	return TCL_OK;
    }
    case S_NEXT: {
	int anyNZ = 1;

	if (objc != 4 && objc != 5) {
	    Tcl_WrongNumArgs(interp, 2, objv, "bitarray start ?value?");
	    return TCL_ERROR;
	}
	if (NeedBA(interp, objv[2], &b) != TCL_OK) return TCL_ERROR;
	if (Tcl_GetIntForIndex(interp, objv[3], b->len - 1, &first) != TCL_OK) {
	    return TCL_ERROR;
	}
	val = 1;
	if (objc == 5) {
	    if (ParseValue(interp, objv[4], b->width, &val) != TCL_OK) {
		return TCL_ERROR;
	    }
	    anyNZ = 0;
	}
	if (b->width == 1) {
	    Tcl_SetObjResult(interp, Tcl_NewWideIntObj(
		    NextBit(b, first, (int)val)));
	} else {
	    Tcl_SetObjResult(interp, Tcl_NewWideIntObj(
		    NextWide(b, first, anyNZ, val)));
	}
	return TCL_OK;
    }
    case S_FILL: {
	Tcl_Obj *obj, *work;
	Tcl_WideInt step = 1;

	if (objc != 6 && objc != 7) {
	    Tcl_WrongNumArgs(interp, 2, objv, "varName first last value ?step?");
	    return TCL_ERROR;
	}
	obj = Tcl_ObjGetVar2(interp, objv[2], NULL, TCL_LEAVE_ERR_MSG);
	if (obj == NULL) return TCL_ERROR;
	if (NeedBA(interp, obj, &b) != TCL_OK) return TCL_ERROR;
	if (Tcl_GetIntForIndex(interp, objv[3], b->len - 1, &first) != TCL_OK
		|| Tcl_GetIntForIndex(interp, objv[4], b->len - 1, &last)
		!= TCL_OK
		|| ParseValue(interp, objv[5], b->width, &val) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (objc == 7) {
	    if (Tcl_GetWideIntFromObj(interp, objv[6], &step) != TCL_OK) {
		return TCL_ERROR;
	    }
	    if (step < 1) {
		Tcl_SetObjResult(interp, Tcl_NewStringObj(
			"step must be >= 1", -1));
		Tcl_SetErrorCode(interp, "TCL", "VALUE", "BITARRAY", NULL);
		return TCL_ERROR;
	    }
	}
	if (first > last) return TCL_OK;
	if (first < 0 || last >= b->len) {
	    IndexError(interp, first < 0 ? objv[3] : objv[4]);
	    return TCL_ERROR;
	}
	if (step > (Tcl_WideInt)last - first + 1) {
	    step = (Tcl_WideInt)last - first + 1;	/* same result, and it fits Tcl_Size */
	}
	work = Tcl_IsShared(obj) ? Tcl_DuplicateObj(obj) : obj;
	b = GETREP(work);
	bit = (int)val;
	if (b->width == 1) {
	    if (step == 1) {
		SetRangeOnes(b, first, last, bit);
	    } else {
		for (i = first; ; i += (Tcl_Size)step) {
		    if (bit) SETBIT(b, i); else CLRBIT(b, i);
		    if (last - i < step) break;
		}
	    }
	} else if (b->width == 8) {
	    unsigned char *p = BYTES(b), c = (unsigned char)val;

	    if (step == 1) {
		memset(p + first, c, (size_t)(last - first + 1));
	    } else {
		for (i = first; ; i += (Tcl_Size)step) {
		    p[i] = c;
		    if (last - i < step) break;
		}
	    }
	} else {
	    for (i = first; ; i += (Tcl_Size)step) {
		PutElem(b, i, val);
		if (last - i < step) break;
	    }
	}
	Touch(work);
	Tcl_IncrRefCount(work);
	obj = Tcl_ObjSetVar2(interp, objv[2], NULL, work, TCL_LEAVE_ERR_MSG);
	Tcl_DecrRefCount(work);
	return obj ? TCL_OK : TCL_ERROR;
    }
    }
    return TCL_ERROR;
}

int
Bitarray_Init(Tcl_Interp *interp)
{
    if (Tcl_InitStubs(interp, "9.1", 0) == NULL) return TCL_ERROR;
    Tcl_CreateObjCommand2(interp, "bitarray", BitarrayCmd, NULL, NULL);
    return Tcl_PkgProvide(interp, "bitarray", "0.3");
}
