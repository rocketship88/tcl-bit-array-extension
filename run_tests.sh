#!/bin/sh
# run_tests.sh -- run the bitarray test suite.  Run ./build.sh first.
#
#   ./run_tests.sh --tclsh /path/to/tclsh9.1
#   ./run_tests.sh                       (uses tclsh9.1, tclsh9.0 or tclsh from your PATH, or $TCLSH, if it is Tcl 9)
# Options:
#   --tclsh FILE    the Tcl 9.1 shell to test with (use the one you built against)
#   --lib FILE      the extension to load (default: libbitarray.so next to this script)
#   -h, --help
# Expected last line:   bitarray.test:	Total	184	Passed	184	Skipped	0	Failed	0
# If the shell cannot find libtcl9.1.so, put its directory in LD_LIBRARY_PATH; the scripts pass the environment through.
HERE=$(cd "$(dirname "$0")" && pwd)
usage() { sed -n '2,/^# If the shell cannot/p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "run_tests.sh: $*" >&2; exit 1; }

TCLSH_ARG= LIB="$HERE/libbitarray.so"
while [ $# -gt 0 ]; do
    case "$1" in
        --tclsh) [ $# -ge 2 ] || die "--tclsh needs an argument"; TCLSH_ARG=$2; shift 2 ;;
        --lib)   [ $# -ge 2 ] || die "--lib needs an argument"; LIB=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "run_tests.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
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

echo "tclsh: $T   (Tcl $V)"
echo "lib:   $LIB"
cd "$HERE" || exit 1
BITARRAY_LIB="$LIB"; export BITARRAY_LIB
exec "$T" tests/bitarray.test
