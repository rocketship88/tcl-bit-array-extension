#!/bin/sh
# run_sieves.sh -- check and time six prime-sieve variants.  Run ./build.sh first.
#
#   ./run_sieves.sh --tclsh /path/to/tclsh9.1
#
# Frank van Bakel's Tcl sieve (variant A) is included unchanged as sieve/frank_sieve.tcl, so --sieve is normally not needed.
# Use --sieve FILE to test another copy (for example a newer one from the Primes repository).
# Variants:
#   A  Frank's sieve, unchanged                       C  bitarray, lindex/lset per bit
#   B  same, bit proc inlined (no extension)          D  bitarray + fill-with-step + next
#                                                     E  like C, one byte per flag (-width 8)
#                                                     F  like D, one byte per flag (-width 8)
# Options:
#   --tclsh FILE    the Tcl 9.1 shell (default: tclsh9.1, tclsh9.0 or tclsh from your PATH, or $TCLSH)
#   --sieve FILE    use this copy of Frank's file instead of sieve/frank_sieve.tcl
#   --lib FILE      the extension to load (default: libbitarray.so next to this script)
#   -h, --help
# The run takes about a minute.  Nothing is written to this directory (a temporary file is made and removed).
HERE=$(cd "$(dirname "$0")" && pwd)
usage() { sed -n '2,/^# The run takes/p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "run_sieves.sh: $*" >&2; exit 1; }

TCLSH_ARG= FRANK= LIB="$HERE/libbitarray.so"
while [ $# -gt 0 ]; do
    case "$1" in
        --tclsh) [ $# -ge 2 ] || die "--tclsh needs an argument"; TCLSH_ARG=$2; shift 2 ;;
        --sieve) [ $# -ge 2 ] || die "--sieve needs an argument"; FRANK=$2; shift 2 ;;
        --lib)   [ $# -ge 2 ] || die "--lib needs an argument"; LIB=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "run_sieves.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

T="$TCLSH_ARG"; [ -n "$T" ] || T="$TCLSH"
if [ -z "$T" ]; then
    for n in tclsh9.1 tclsh9.0 tclsh; do
        p=$(command -v "$n" 2>/dev/null) || continue
        case $(printf 'puts [info patchlevel]\n' | "$p" 2>/dev/null) in 9.*) T=$p; break ;; esac
    done
    [ -n "$T" ] || die "no Tcl 9 shell on your PATH; say which one with --tclsh /path/to/tclsh9.1"
fi
[ -x "$T" ] || { p=$(command -v "$T" 2>/dev/null) && T=$p; }
[ -x "$T" ] || die "$T is not an executable file"
V=$(printf 'puts [info patchlevel]\n' | "$T" 2>&1) || die "could not run $T:
$V
(If it complains about a missing libtcl*.so, add the directory holding it to LD_LIBRARY_PATH.)"
case "$V" in 9.*) ;; *) die "$T is Tcl '$V'; bitarray needs Tcl 9.1 (trunk)" ;; esac
[ -f "$LIB" ] || die "$LIB not found -- run ./build.sh first"

if [ -z "$FRANK" ]; then
    for f in "$HERE"/sieve/*.tcl "$HERE"/sieve/*.txt "$HERE"/*.tcl "$HERE"/*.txt; do
        [ -f "$f" ] || continue
        if grep -Eq '^[[:space:]]*proc[[:space:]]+run_sieve[[:space:]]' "$f" 2>/dev/null; then FRANK=$f; break; fi
    done
fi
[ -n "$FRANK" ] || die "Frank's sieve file not found (it should be sieve/frank_sieve.tcl).  Pass a copy with --sieve FILE, e.g.
    ./run_sieves.sh --tclsh $T --sieve /path/to/primes.tcl"
[ -f "$FRANK" ] || die "$FRANK not found"
grep -Eq '^[[:space:]]*proc[[:space:]]+run_sieve[[:space:]]' "$FRANK" || die "$FRANK does not define 'proc run_sieve'"

TMP=$(mktemp "${TMPDIR:-/tmp}/frank_procs.XXXXXX") || die "cannot make a temporary file"
trap 'rm -f "$TMP"' EXIT HUP INT TERM
# procs-only copy of his file: drop top-level "main ..." calls so it does not run its own 5-second loop
grep -Ev '^main([[:space:]]|$)' "$FRANK" > "$TMP"

echo "sieve file: $FRANK"
cd "$HERE" || exit 1
BITARRAY_LIB="$LIB" FRANK_PROCS="$TMP"; export BITARRAY_LIB FRANK_PROCS
"$T" sieve/run_sieves.tcl
