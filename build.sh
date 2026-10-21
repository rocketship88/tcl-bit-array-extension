#!/bin/sh
# build.sh -- build libbitarray.so against a Tcl 9.1 installation or source tree.
#
# Tell it where Tcl 9.1 is, with ONE of:
#   --tclsh FILE        the tclsh9.1 you want to use (it works out the rest).  This is the usual choice.
#   --tcl-prefix DIR    the directory Tcl was installed into (it holds include/ and lib/)
#   (nothing)           a Tcl 9 tclsh on your PATH is used, same as --tclsh
# Advanced, only if the above do not fit:
#   --tcl-tree DIR      a Tcl source tree you have built yourself: DIR/generic/tcl.h, DIR/unix/libtclstub.a
#   --include DIR --stub FILE   the directory holding tcl.h, and the stubs library file (libtclstub.a)
# Other options:
#   --cc COMPILER               default: $CC, else cc          (extra flags: $CFLAGS and $LDFLAGS)
#   --out FILE                  default: libbitarray.so next to this script
#   --safe                      compile with -O2 instead of the default -O3 (the most conservative build; slower in the element loops)
#   --native                    -O3 plus -march=native: also uses the newest instructions of THIS machine's CPU (AVX2 and so on).
#                               NOT PORTABLE: the library may crash with "illegal instruction" on an older CPU.  Use it only on the machine that builds it.
# SSE2 (16 bytes at a time) is used by default for the 8-bit logical and relational operators on x86-64 (every x86-64 CPU has it).
# To leave it out:  CFLAGS=-DBA_NO_SSE2 ./build.sh ...    (the plain loops do the same work, slower).
# (The default, -O3, uses no CPU-specific instructions, so it runs wherever -O2 does.)
#   -h, --help
# Examples:
#   ./build.sh --tclsh /opt/tcl9.1/bin/tclsh9.1
#   ./build.sh --tcl-prefix /opt/tcl9.1
# Nothing is installed and nothing outside the output file is written.
HERE=$(cd "$(dirname "$0")" && pwd)

usage() { sed -n '2,/^# Nothing is installed/p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "build.sh: $*" >&2; exit 1; }
need_arg() { [ "$2" -ge 2 ] || die "option $1 needs an argument (try --help)"; }

PREFIX= TREE= TCLSH_ARG= INC= STUB= OUT="$HERE/libbitarray.so" OPT=-O3 MODE=default
CC_CMD="${CC:-cc}"
while [ $# -gt 0 ]; do
    case "$1" in
        --tcl-prefix) need_arg "$1" $#; PREFIX=$2; shift 2 ;;
        --tcl-tree)   need_arg "$1" $#; TREE=$2; shift 2 ;;
        --tclsh)      need_arg "$1" $#; TCLSH_ARG=$2; shift 2 ;;
        --include)    need_arg "$1" $#; INC=$2; shift 2 ;;
        --stub)       need_arg "$1" $#; STUB=$2; shift 2 ;;
        --cc)         need_arg "$1" $#; CC_CMD=$2; shift 2 ;;
        --out)        need_arg "$1" $#; OUT=$2; shift 2 ;;
        --safe)       OPT=-O2; MODE=safe; shift ;;
        --native)     OPT="-O3 -march=native"; MODE=native; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "build.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# first_stub DIR...: print the first stubs library found in the given directories
first_stub() {
    for d in "$@"; do
        for f in "$d"/libtclstub*.a "$d"/libtclstub*.lib; do
            [ -f "$f" ] && { echo "$f"; return 0; }
        done
    done
    return 1
}

# Ask a tclsh where it lives.  Sets TCLSH_VERSION, TCLSH_PREFIX (two levels above the executable)
# and TCLSH_CFG_INC / TCLSH_CFG_LIB (what the shell says it was configured with).
ask_tclsh() {
    out=$(printf '%s\n' 'puts [info patchlevel]' \
          'puts [file dirname [file dirname [file normalize [info nameofexecutable]]]]' \
          'if {[catch {tcl::pkgconfig get includedir,runtime} i]} {set i {}}' \
          'if {[catch {tcl::pkgconfig get libdir,runtime} l]} {set l {}}' \
          'puts $i' 'puts $l' | "$1" 2>&1) || die "could not run $1:
$out
(If it complains about a missing libtcl*.so, add the directory holding it to LD_LIBRARY_PATH.)"
    TCLSH_VERSION=$(printf '%s\n' "$out" | sed -n 1p)
    TCLSH_PREFIX=$(printf '%s\n' "$out" | sed -n 2p)
    TCLSH_CFG_INC=$(printf '%s\n' "$out" | sed -n 3p)
    TCLSH_CFG_LIB=$(printf '%s\n' "$out" | sed -n 4p)
    case "$TCLSH_VERSION" in
        9.*) ;;
        *) die "$1 is Tcl '$TCLSH_VERSION'; bitarray needs Tcl 9.1 (trunk). Pass the right one with --tclsh or --tcl-prefix." ;;
    esac
}

INC2=
if [ -n "$INC$STUB" ]; then
    [ -n "$INC" ] && [ -n "$STUB" ] || die "--include and --stub must be given together"
    [ -f "$INC/tcl.h" ] || die "no tcl.h in $INC"
    [ -f "$STUB" ] || die "stubs library $STUB does not exist"
    HOW="--include/--stub"
elif [ -n "$PREFIX" ]; then
    [ -f "$PREFIX/include/tcl.h" ] || die "no tcl.h in $PREFIX/include (is --tcl-prefix the install prefix, the directory that holds include/ and lib/?)"
    INC="$PREFIX/include"
    STUB=$(first_stub "$PREFIX/lib" "$PREFIX/lib64") || die "no libtclstub*.a in $PREFIX/lib or $PREFIX/lib64"
    HOW="--tcl-prefix $PREFIX"
elif [ -n "$TREE" ]; then
    [ -f "$TREE/generic/tcl.h" ] || die "no generic/tcl.h in $TREE (is --tcl-tree a Tcl source tree?)"
    STUB=$(first_stub "$TREE/unix") || die "no libtclstub*.a in $TREE/unix -- build Tcl there first (./configure && make)"
    INC="$TREE/generic"; INC2="$TREE/unix"
    HOW="--tcl-tree $TREE"
else
    T="$TCLSH_ARG"; [ -n "$T" ] || T="$TCLSH"
    if [ -z "$T" ]; then
        for n in tclsh9.1 tclsh9.0 tclsh; do
            p=$(command -v "$n" 2>/dev/null) || continue
            case $(printf 'puts [info patchlevel]\n' | "$p" 2>/dev/null) in 9.*) T=$p; break ;; esac
        done
    fi
    [ -n "$T" ] || die "I do not know where Tcl 9.1 is.  Say so with one of:
    --tcl-prefix DIR    (the install prefix: DIR/include/tcl.h, DIR/lib/libtclstub.a)
    --tclsh FILE        (a tclsh9.1)
    --tcl-tree DIR      (a built source tree)
    --include DIR --stub FILE
  (try --help).  No Tcl 9 shell was found on your PATH."
    [ -x "$T" ] || { p=$(command -v "$T" 2>/dev/null) && T=$p; }
    [ -x "$T" ] || die "$T is not an executable file"
    ask_tclsh "$T"
    for p in "$TCLSH_PREFIX"; do
        if [ -f "$p/include/tcl.h" ] && first_stub "$p/lib" "$p/lib64" >/dev/null; then
            INC="$p/include"; STUB=$(first_stub "$p/lib" "$p/lib64"); break
        fi
    done
    if [ -z "$INC" ] && [ -f "$TCLSH_CFG_INC/tcl.h" ] && first_stub "$TCLSH_CFG_LIB" >/dev/null; then
        INC="$TCLSH_CFG_INC"; STUB=$(first_stub "$TCLSH_CFG_LIB")
    fi
    [ -n "$INC" ] || die "found $T (Tcl $TCLSH_VERSION) but not its headers: looked for tcl.h in
    $TCLSH_PREFIX/include and $TCLSH_CFG_INC.
  Pass the install prefix with --tcl-prefix, or --include DIR --stub FILE."
    HOW="tclsh $T (Tcl $TCLSH_VERSION)"
fi

# The header must be Tcl 9 with the version-2 object type (abstract lists).
grep -q 'define[[:space:]]*TCL_MAJOR_VERSION[[:space:]]*9' "$INC/tcl.h" ||
    die "$INC/tcl.h is not a Tcl 9 header; bitarray needs Tcl 9.1 (trunk)"
grep -q 'define[[:space:]]*TCL_OBJTYPE_V2' "$INC/tcl.h" ||
    die "$INC/tcl.h has no TCL_OBJTYPE_V2: this Tcl 9 is too old for the abstract-list hooks bitarray uses"

echo "found Tcl via $HOW"
echo "headers: $INC${INC2:+ $INC2}"
echo "stubs:   $STUB"
if [ -n "$INC2" ]; then set -- -I"$INC" -I"$INC2"; else set -- -I"$INC"; fi
case "$MODE" in
    safe)   LABEL="--safe: -O2" ;;
    native) LABEL="--native: -O3 -march=native (NOT PORTABLE)" ;;
    *)      LABEL="default: -O3 (portable: no CPU-specific instructions)" ;;
esac
echo "options:  $LABEL; compiler command: $CC_CMD $OPT -Wall -Wextra -fPIC -shared -DUSE_TCL_STUBS${CFLAGS:+ $CFLAGS}${LDFLAGS:+ $LDFLAGS}"
# $CC_CMD, $CFLAGS and $LDFLAGS are deliberately unquoted (they may hold several words)
$CC_CMD $OPT -Wall -Wextra -fPIC -shared -DUSE_TCL_STUBS $CFLAGS "$@" "$HERE/bitarray.c" "$STUB" $LDFLAGS -o "$OUT" ||
    die "compilation failed"
echo "built $OUT"
case "$MODE" in
    native) echo "note: built with -O3 -march=native (--native).  THIS LIBRARY MAY NOT BE PORTABLE: it uses the newest instructions of this machine's CPU and can crash with \"illegal instruction\" on an older one.  Do not copy it to another computer; build it there instead.  Run ./run_tests.sh after building." ;;
esac
