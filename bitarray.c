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
 * Commands (subcommands of the global command "bitarray"; README.md has the full syntax):
 *	new SIZE ?VALUE? ?-width W?        newfrom LIST ?-width W?
 *	width BA      is VALUE      frombytes DATA      tobytes BA
 *	fromchars STRING ?-width W?      tochars BA
 *	count BA ?FIRST ?to? LAST ?with? ?VALUE??     next BA START ?with? ?VALUE?
 *	fill VAR FIRST ?to? LAST ?with? VALUE ?by? ?STEP?   (in place, like lset)
 *	and|or|xor|andnot ?-length strict|zero? VAR ?<-? BA ?BA?   (bitwise, 64 bits at a time)
 *	not VAR ?<- BA?                  (flip every bit)
 *	VAR is a variable name (that array is changed in place, or, after "<-" with two
 *	arrays, created); BA, DATA and STRING are values.  The other operations are
 *	the ordinary list commands, which the abstract-list hooks below implement.
 *	fill and the bitwise commands return the empty string.
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
 * Read N bits (1..64) starting at bit position P, and return them in the low
 * end of the result.  Touches only the words that hold those bits, so it
 * never reads past the end of the data.
 */
static uint64_t
GetBits(const BitArr *b, Tcl_Size p, int n)
{
    Tcl_Size k = p >> 6;
    int s = (int)(p & 63);
    uint64_t v = b->words[k] >> s;

    if (s + n > 64) v |= b->words[k + 1] << (64 - s);
    return (n == 64) ? v : (v & (((uint64_t)1 << n) - 1));
}

/*
 * Store the low N bits (1..64) of V at bit position P, leaving every other
 * bit as it was.  Like GetBits, it touches only the words involved.
 */
static void
PutBits(BitArr *b, Tcl_Size p, uint64_t v, int n)
{
    Tcl_Size k = p >> 6;
    int s = (int)(p & 63);
    uint64_t m = (n == 64) ? ~(uint64_t)0 : (((uint64_t)1 << n) - 1);

    v &= m;
    b->words[k] = (b->words[k] & ~(m << s)) | (v << s);
    if (s + n > 64) {
	uint64_t mh = ((uint64_t)1 << (s + n - 64)) - 1;

	b->words[k + 1] = (b->words[k + 1] & ~mh) | (v >> (64 - s));
    }
}

/* Clear COUNT bits starting at bit position FROM (width-1 arrays). */
static void
ClearBits(BitArr *b, Tcl_Size from, Tcl_Size count)
{
    while (count > 0) {
	int n = (count >= 64) ? 64 : (int)count;

	PutBits(b, from, 0, n);
	from += n;
	count -= n;
    }
}

/*
 * Copy COUNT elements from FROM to TO within one array, as memmove would.
 * Wider elements use memmove.  Width-1 arrays move up to 64 bits at a time;
 * as with memmove, the direction depends on the overlap: moving left works
 * from the front, moving right works from the back, so no bit is overwritten
 * before it has been copied.
 */
static void
MoveElems(BitArr *b, Tcl_Size from, Tcl_Size to, Tcl_Size count)
{
    if (from == to || count <= 0) return;
    if (b->width != 1) {
	memmove(BYTES(b) + (size_t)to * EBYTES(b),
		BYTES(b) + (size_t)from * EBYTES(b), (size_t)count * EBYTES(b));
	return;
    }
    if (to < from) {
	Tcl_Size done = 0;

	while (done < count) {
	    int n = (count - done >= 64) ? 64 : (int)(count - done);

	    PutBits(b, to + done, GetBits(b, from + done, n), n);
	    done += n;
	}
    } else {
	Tcl_Size left = count;

	while (left > 0) {
	    int n = (left >= 64) ? 64 : (int)left;

	    left -= n;
	    PutBits(b, to + left, GetBits(b, from + left, n), n);
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
	    ClearBits(b, newLen, oldLen - newLen);
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

/*
 * IsWord --
 *	True if the string form of OBJ is exactly the word W (used for the
 *	optional helper words "to", "..", "with" and "by").
 */
static int
IsWord(Tcl_Obj *obj, const char *w)
{
    Tcl_Size n;
    const char *s = Tcl_GetStringFromObj(obj, &n);

    return (size_t)n == strlen(w) && memcmp(s, w, (size_t)n) == 0;
}

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

/* ------------------- bitwise operations (0.6.0) -------------------- */

enum { BO_AND, BO_OR, BO_XOR, BO_ANDNOT, BO_NOT };

/*
 * BitOpWords --
 *	dst = x OP y, a word at a time.  Words of y beyond its end count as 0.
 *	dst may be the same as x.  Y is NULL for NOT.  Only the first
 *	dst->nwords words are written; the caller then calls MaskTail.
 */
#define BO_LOOP(FROM, TO, YEXPR, EXPR) \
    for (k = (FROM); k < (TO); k++) { \
	uint64_t xv = x->words[k], yv = (YEXPR); \
	dst->words[k] = (EXPR); \
    }

static void
BitOpWords(BitArr *dst, const BitArr *x, const BitArr *y, int op)
{
    Tcl_Size k, n = dst->nwords, m;

    if (op == BO_NOT) {
	for (k = 0; k < n; k++) dst->words[k] = ~x->words[k];
	return;
    }
    m = (y->nwords < n) ? y->nwords : n;	/* words where y exists */
    switch (op) {
    case BO_AND:
	BO_LOOP(0, m, y->words[k], xv & yv)
	BO_LOOP(m, n, 0, xv & yv)
	break;
    case BO_OR:
	BO_LOOP(0, m, y->words[k], xv | yv)
	BO_LOOP(m, n, 0, xv | yv)
	break;
    case BO_XOR:
	BO_LOOP(0, m, y->words[k], xv ^ yv)
	BO_LOOP(m, n, 0, xv ^ yv)
	break;
    default:	/* BO_ANDNOT */
	BO_LOOP(0, m, y->words[k], xv & ~yv)
	BO_LOOP(m, n, 0, xv & ~yv)
	break;
    }
}

/*
 * MaskTail --
 *	Zero every bit past the end of the data in the last word, restoring
 *	the invariant that count, next and equality rely on.  Width 1 uses a
 *	value mask (bit i is bit i&63 of word i>>6); wider arrays are packed
 *	bytes, so the unused bytes are cleared by address (host-endian safe).
 */
static void
MaskTail(BitArr *b)
{
    Tcl_WideInt bits = (Tcl_WideInt)b->len * b->width;

    if (b->nwords == 0) return;
    if (b->width == 1) {
	int r = (int)(bits & 63);

	if (r) b->words[b->nwords - 1] &= (((uint64_t)1 << r) - 1);
    } else {
	size_t used = (size_t)(bits / 8), total = (size_t)b->nwords * 8;

	if (total > used) memset(BYTES(b) + used, 0, total - used);
    }
}

static int
BitOpCompat(Tcl_Interp *interp, const char *name, const BitArr *x,
	const BitArr *y, int zero)
{
    if (x->width != y->width) {
	Tcl_SetObjResult(interp, Tcl_ObjPrintf(
		"bitarray %s: arrays differ in width (%d vs %d)",
		name, x->width, y->width));
	Tcl_SetErrorCode(interp, "TCL", "VALUE", "BITARRAY", NULL);
	return TCL_ERROR;
    }
    if (!zero && x->len != y->len) {
	Tcl_SetObjResult(interp, Tcl_ObjPrintf(
		"bitarray %s: arrays differ in length (%" TCL_SIZE_MODIFIER
		"d vs %" TCL_SIZE_MODIFIER "d); use -length zero to allow it",
		name, x->len, y->len));
	Tcl_SetErrorCode(interp, "TCL", "VALUE", "BITARRAY", NULL);
	return TCL_ERROR;
    }
    return TCL_OK;
}

/*
 * BitOpCmd --
 *	bitarray and|or|xor|andnot ?-length strict|zero? var array
 *	bitarray and|or|xor|andnot ?-length strict|zero? var <- array
 *	bitarray and|or|xor|andnot ?-length strict|zero? var <- array1 array2
 *	bitarray not var
 *	bitarray not var <- array
 *
 *	VAR is a variable name; the arrays are values.  With one array the
 *	variable is both first input and result (changed in place).  With two
 *	arrays after the arrow the variable only receives array1 OP array2,
 *	which are left alone.  The result always has the length of the first
 *	input.  Width must match; length must match unless -length zero, which
 *	treats missing bits of the second array as 0 and ignores extra ones.
 */
static int
BitOpCmd(Tcl_Interp *interp, Tcl_Size objc, Tcl_Obj *const objv[], int op)
{
    static const char *const modes[] = { "strict", "zero", NULL };
    const char *name = Tcl_GetString(objv[1]);
    int zero = 0, mode, inPlace, isNot = (op == BO_NOT);
    Tcl_Size idx = 2, rest;
    Tcl_Obj *dstName, *srcA = NULL, *srcB = NULL, *obj, *work;
    BitArr *x = NULL, *y = NULL, *d;

    if (!isNot && idx < objc && IsWord(objv[idx], "-length")) {
	if (idx + 1 >= objc) goto usage;
	if (Tcl_GetIndexFromObj(interp, objv[idx + 1], modes, "length mode",
		TCL_EXACT, &mode) != TCL_OK) {
	    return TCL_ERROR;
	}
	zero = mode;
	idx += 2;
    }
    rest = objc - idx;
    if (isNot) {
	if (rest == 1) {
	    inPlace = 1; dstName = objv[idx];
	} else if (rest == 3 && IsWord(objv[idx + 1], "<-")) {
	    inPlace = 0; dstName = objv[idx]; srcA = objv[idx + 2];
	} else {
	    goto usage;
	}
    } else if (rest == 2) {
	inPlace = 1; dstName = objv[idx]; srcB = objv[idx + 1];
    } else if ((rest == 3 || rest == 4) && IsWord(objv[idx + 1], "<-")) {
	dstName = objv[idx];
	if (rest == 3) {
	    inPlace = 1; srcB = objv[idx + 2];
	} else {
	    inPlace = 0; srcA = objv[idx + 2]; srcB = objv[idx + 3];
	}
    } else {
	goto usage;
    }

    if (inPlace) {
	obj = Tcl_ObjGetVar2(interp, dstName, NULL, TCL_LEAVE_ERR_MSG);
	if (obj == NULL) return TCL_ERROR;
	if (NeedBA(interp, obj, &x) != TCL_OK) return TCL_ERROR;
	if (srcB != NULL) {
	    if (NeedBA(interp, srcB, &y) != TCL_OK) return TCL_ERROR;
	    if (BitOpCompat(interp, name, x, y, zero) != TCL_OK) return TCL_ERROR;
	}
	work = Tcl_IsShared(obj) ? Tcl_DuplicateObj(obj) : obj;
	d = GETREP(work);
	BitOpWords(d, d, y, op);
	MaskTail(d);
	Touch(work);
    } else {
	if (NeedBA(interp, srcA, &x) != TCL_OK) return TCL_ERROR;
	if (srcB != NULL) {
	    if (NeedBA(interp, srcB, &y) != TCL_OK) return TCL_ERROR;
	    if (BitOpCompat(interp, name, x, y, zero) != TCL_OK) return TCL_ERROR;
	}
	if ((d = NewRep(interp, x->len, x->width)) == NULL) return TCL_ERROR;
	BitOpWords(d, x, y, op);
	MaskTail(d);
	work = WrapRep(d);
    }
    Tcl_IncrRefCount(work);
    obj = Tcl_ObjSetVar2(interp, dstName, NULL, work, TCL_LEAVE_ERR_MSG);
    Tcl_DecrRefCount(work);
    return obj ? TCL_OK : TCL_ERROR;

  usage:
    Tcl_WrongNumArgs(interp, 2, objv, isNot ? "varName ?<- array?"
	    : "?-length strict|zero? varName ?<-? array ?array?");
    return TCL_ERROR;
}

static int
BitarrayCmd(void *cd, Tcl_Interp *interp, Tcl_Size objc, Tcl_Obj *const objv[])
{
    static const char *const subs[] = {
	"new", "newfrom", "width", "is", "count", "next", "fill",
	"frombytes", "tobytes", "fromchars", "tochars",
	"and", "or", "xor", "andnot", "not", NULL
    };
    enum { S_NEW, S_NEWFROM, S_WIDTH, S_IS, S_COUNT, S_NEXT, S_FILL,
	   S_FROMBYTES, S_TOBYTES, S_FROMCHARS, S_TOCHARS,
	   S_AND, S_OR, S_XOR, S_ANDNOT, S_NOT };
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
    case S_AND:    return BitOpCmd(interp, objc, objv, BO_AND);
    case S_OR:     return BitOpCmd(interp, objc, objv, BO_OR);
    case S_XOR:    return BitOpCmd(interp, objc, objv, BO_XOR);
    case S_ANDNOT: return BitOpCmd(interp, objc, objv, BO_ANDNOT);
    case S_NOT:    return BitOpCmd(interp, objc, objv, BO_NOT);
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
	    Tcl_WrongNumArgs(interp, 2, objv, "array");
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

	int kc = 4, hasVal = 0;
	Tcl_Obj *valObj = NULL;

	if (objc < 3 || objc == 4) goto countUsage;
	if (NeedBA(interp, objv[2], &b) != TCL_OK) return TCL_ERROR;
	first = 0; last = b->len - 1;
	if (objc >= 5) {
	    Tcl_Obj *lastObj;
	    if (IsWord(objv[kc], "to") || IsWord(objv[kc], "..")) kc++;
	    if (kc >= objc) goto countUsage;
	    lastObj = objv[kc++];
	    if (kc < objc && IsWord(objv[kc], "with")) {
		kc++;
		if (kc >= objc) goto countUsage;
	    }
	    if (kc < objc) valObj = objv[kc++];
	    if (kc != objc) goto countUsage;
	    hasVal = (valObj != NULL);
	    if (Tcl_GetIntForIndex(interp, objv[3], b->len - 1, &first) != TCL_OK
		    || Tcl_GetIntForIndex(interp, lastObj, b->len - 1, &last)
		    != TCL_OK) {
		return TCL_ERROR;
	    }
	    if (first < 0) first = 0;
	    if (last >= b->len) last = b->len - 1;
	}
	val = 1;
	if (hasVal) {
	    if (ParseValue(interp, valObj, b->width, &val) != TCL_OK) {
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
    countUsage:
	Tcl_WrongNumArgs(interp, 2, objv, "array ?first ?to? last ?with? ?value??");
	return TCL_ERROR;
    }
    case S_NEXT: {
	int anyNZ = 1;

	int kn = 4;
	Tcl_Obj *valObjN = NULL;

	if (objc < 4) goto nextUsage;
	if (NeedBA(interp, objv[2], &b) != TCL_OK) return TCL_ERROR;
	if (kn < objc && IsWord(objv[kn], "with")) {
	    kn++;
	    if (kn >= objc) goto nextUsage;
	}
	if (kn < objc) valObjN = objv[kn++];
	if (kn != objc) goto nextUsage;
	if (Tcl_GetIntForIndex(interp, objv[3], b->len - 1, &first) != TCL_OK) {
	    return TCL_ERROR;
	}
	val = 1;
	if (valObjN != NULL) {
	    if (ParseValue(interp, valObjN, b->width, &val) != TCL_OK) {
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
    nextUsage:
	Tcl_WrongNumArgs(interp, 2, objv, "array start ?with? ?value?");
	return TCL_ERROR;
    }
    case S_FROMBYTES: {
	const unsigned char *bytes;
	Tcl_Size nb;

	if (objc != 3) {
	    Tcl_WrongNumArgs(interp, 2, objv, "data");
	    return TCL_ERROR;
	}
	bytes = Tcl_GetBytesFromObj(interp, objv[2], &nb);
	if (bytes == NULL) return TCL_ERROR;
	if ((n = NewRep(interp, nb, 8)) == NULL) return TCL_ERROR;
	if (nb > 0) memcpy(n->words, bytes, (size_t)nb);
	Tcl_SetObjResult(interp, WrapRep(n));
	return TCL_OK;
    }
    case S_TOBYTES:
	if (objc != 3) {
	    Tcl_WrongNumArgs(interp, 2, objv, "array");
	    return TCL_ERROR;
	}
	if (NeedBA(interp, objv[2], &b) != TCL_OK) return TCL_ERROR;
	if (b->width != 8) {
	    Tcl_SetObjResult(interp, Tcl_ObjPrintf(
		    "tobytes: array has width %d; only width 8 can be written as bytes",
		    b->width));
	    Tcl_SetErrorCode(interp, "TCL", "VALUE", "BITARRAY", NULL);
	    return TCL_ERROR;
	}
	Tcl_SetObjResult(interp, Tcl_NewByteArrayObj(
		(const unsigned char *)b->words, b->len));
	return TCL_OK;
    case S_FROMCHARS: {
	Tcl_Size nc;
	int ch;
	uint64_t maxv;

	if (objc != 3 && objc != 5) {
	    Tcl_WrongNumArgs(interp, 2, objv, "string ?-width w?");
	    return TCL_ERROR;
	}
	width = 8;
	if (objc == 5) {
	    if (strcmp(Tcl_GetString(objv[3]), "-width") != 0) {
		Tcl_WrongNumArgs(interp, 2, objv, "string ?-width w?");
		return TCL_ERROR;
	    }
	    if (ParseWidthArg(interp, objv[4], &width) != TCL_OK) return TCL_ERROR;
	}
	if (width != 8 && width != 16 && width != 32) {
	    Tcl_SetObjResult(interp, Tcl_NewStringObj(
		    "fromchars: -width must be 8, 16 or 32", -1));
	    Tcl_SetErrorCode(interp, "TCL", "VALUE", "BITARRAY", NULL);
	    return TCL_ERROR;
	}
	maxv = ((uint64_t)1 << width) - 1;
	nc = Tcl_GetCharLength(objv[2]);
	for (i = 0; i < nc; i++) {
	    ch = Tcl_GetUniChar(objv[2], i);
	    if (ch < 0 || (uint64_t)ch > maxv) {
		Tcl_SetObjResult(interp, Tcl_ObjPrintf(
			"character U+%04X at index %" TCL_SIZE_MODIFIER "d does not fit in width %d",
			ch, i, width));
		Tcl_SetErrorCode(interp, "TCL", "VALUE", "BITARRAY", NULL);
		return TCL_ERROR;
	    }
	}
	if ((n = NewRep(interp, nc, width)) == NULL) return TCL_ERROR;
	for (i = 0; i < nc; i++) {
	    ch = Tcl_GetUniChar(objv[2], i);
	    if (ch) PutElem(n, i, (uint64_t)ch);
	}
	Tcl_SetObjResult(interp, WrapRep(n));
	return TCL_OK;
    }
    case S_TOCHARS: {
	Tcl_UniChar *buf;
	uint64_t v;

	if (objc != 3) {
	    Tcl_WrongNumArgs(interp, 2, objv, "array");
	    return TCL_ERROR;
	}
	if (NeedBA(interp, objv[2], &b) != TCL_OK) return TCL_ERROR;
	if (b->width != 8 && b->width != 16 && b->width != 32) {
	    Tcl_SetObjResult(interp, Tcl_ObjPrintf(
		    "tochars: array has width %d; need width 8, 16 or 32", b->width));
	    Tcl_SetErrorCode(interp, "TCL", "VALUE", "BITARRAY", NULL);
	    return TCL_ERROR;
	}
	for (i = 0; i < b->len; i++) {
	    v = GetElem(b, i);
	    if (v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF)) {
		Tcl_SetObjResult(interp, Tcl_ObjPrintf(
			"element %" TCL_SIZE_MODIFIER "d (%" TCL_LL_MODIFIER "u) is not a valid character code",
			i, (unsigned long long)v));
		Tcl_SetErrorCode(interp, "TCL", "VALUE", "BITARRAY", NULL);
		return TCL_ERROR;
	    }
	}
	buf = (Tcl_UniChar *)Tcl_Alloc((size_t)(b->len > 0 ? b->len : 1) * sizeof(Tcl_UniChar));
	for (i = 0; i < b->len; i++) buf[i] = (Tcl_UniChar)GetElem(b, i);
	Tcl_SetObjResult(interp, Tcl_NewUnicodeObj(buf, b->len));
	Tcl_Free(buf);
	return TCL_OK;
    }
    case S_FILL: {
	Tcl_Obj *obj, *work;
	Tcl_WideInt step = 1;
	Tcl_Obj *firstObj, *lastObj, *valueObj;
	Tcl_Size k;

	/*
	 * bitarray fill varName first ?to? last ?with? value ?by? ?step?
	 * The helper words "to" (or "..") "with" and "by" are optional; the step
	 * may also follow the value with no "by".
	 */
	if (objc < 6) goto fillUsage;
	k = 3;
	firstObj = objv[k++];
	if (IsWord(objv[k], "to") || IsWord(objv[k], "..")) k++;
	if (k >= objc) goto fillUsage;
	lastObj = objv[k++];
	if (k < objc && IsWord(objv[k], "with")) k++;
	if (k >= objc) goto fillUsage;
	valueObj = objv[k++];
	if (k < objc && IsWord(objv[k], "by")) {
	    k++;
	    if (k != objc - 1) goto fillUsage;
	} else if (k < objc - 1) {
	    goto fillUsage;
	}
	obj = Tcl_ObjGetVar2(interp, objv[2], NULL, TCL_LEAVE_ERR_MSG);
	if (obj == NULL) return TCL_ERROR;
	if (NeedBA(interp, obj, &b) != TCL_OK) return TCL_ERROR;
	if (Tcl_GetIntForIndex(interp, firstObj, b->len - 1, &first) != TCL_OK
		|| Tcl_GetIntForIndex(interp, lastObj, b->len - 1, &last)
		!= TCL_OK
		|| ParseValue(interp, valueObj, b->width, &val) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (k < objc) {
	    if (Tcl_GetWideIntFromObj(interp, objv[k], &step) != TCL_OK) {
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
	    IndexError(interp, first < 0 ? firstObj : lastObj);
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

      fillUsage:
	Tcl_WrongNumArgs(interp, 2, objv,
		"varName first ?to? last ?with? value ?by? ?step?");
	return TCL_ERROR;
    }
    }
    return TCL_ERROR;
}

DLLEXPORT int
Bitarray_Init(Tcl_Interp *interp)
{
    if (Tcl_InitStubs(interp, "9.1", 0) == NULL) return TCL_ERROR;
    Tcl_CreateObjCommand2(interp, "bitarray", BitarrayCmd, NULL, NULL);
    return Tcl_PkgProvide(interp, "bitarray", "0.6.0");
}
