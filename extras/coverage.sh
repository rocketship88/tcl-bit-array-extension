#!/bin/sh
# coverage.sh -- line coverage of bitarray.c by the tests, measured with gcov (gcc only).
#
#   extras/coverage.sh --tclsh /path/to/tclsh9.1 --include DIR --stub FILE [--out DIR]
#
#   --tclsh FILE    the Tcl 9.1 shell to run the tests with
#   --include DIR   the directory holding tcl.h (a Tcl 9.1 source tree: DIR/generic)
#   --stub FILE     libtclstub.a
#   --out DIR       where to work (default: a new folder coverage_run next to bitarray.c); it is emptied by hand, not by this script
# It builds a TEST version of the extension (gcc -DBA_TEST --coverage, no optimisation) that has the extra command
# "bitarray_test" (a small size limit, allocations that fail on request), runs tests/bitarray.test and tests/faultinject.test
# with it, and runs gcov.  The normal library is not touched.  Prints the totals and the lines that never ran, and writes bitarray.nocoverage (bitarray.c with "// no coverage" at the end of those lines).
# Needs Linux (or another system with gcc and gcov; the test build uses signal handlers and _exit).
HERE=$(cd "$(dirname "$0")/.." && pwd)
die() { echo "coverage.sh: $*" >&2; exit 1; }
T= INC= STUB= OUT="$HERE/coverage_run"
while [ $# -gt 0 ]; do
    case "$1" in
        --tclsh)   [ $# -ge 2 ] || die "$1 needs an argument"; T=$2; shift 2 ;;
        --include) [ $# -ge 2 ] || die "$1 needs an argument"; INC=$2; shift 2 ;;
        --stub)    [ $# -ge 2 ] || die "$1 needs an argument"; STUB=$2; shift 2 ;;
        --out)     [ $# -ge 2 ] || die "$1 needs an argument"; OUT=$2; shift 2 ;;
        -h|--help) sed -n '2,/^# Needs Linux/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option $1 (try --help)" ;;
    esac
done
[ -n "$T" ] && [ -n "$INC" ] && [ -n "$STUB" ] || die "need --tclsh, --include and --stub (try --help)"
command -v gcov >/dev/null 2>&1 || die "gcov not found"
[ -e "$OUT" ] && die "$OUT exists already; remove it or choose another --out"
mkdir -p "$OUT" || die "cannot make $OUT"
cp "$HERE/bitarray.c" "$OUT/" || exit 1
cd "$OUT" || exit 1
${CC:-gcc} -O0 -g --coverage -DBA_TEST -DBA_GCOV -Wall -Wextra -fPIC -shared -DUSE_TCL_STUBS -I "$INC" bitarray.c "$STUB" -o libbitarray.so || die "build failed"
BITARRAY_LIB="$OUT/libbitarray.so"; export BITARRAY_LIB
cd "$HERE" || exit 1
for f in bitarray faultinject; do
    echo "== tests/$f.test"
    "$T" tests/$f.test | grep -E "Total|FAILED|Test file error" 
done
cd "$OUT" || exit 1
gcov -b -c libbitarray.so-bitarray.gcda | sed -n "/File 'bitarray.c'/,/^$/p"
echo "Lines that never ran (line number, text); those marked [can't happen] are BA_IMPOSSIBLE panics, which are meant never to run:"
grep -E '^ +#####:' bitarray.c.gcov | sed 's/^ *#####: *//' | cut -c1-120 | sed "/BA_IMPOSSIBLE/s/\$/   [can't happen]/"
# bitarray.nocoverage: a copy of bitarray.c in which only the lines that never ran end with "   // no coverage", for a side-by-side compare with bitarray.c.
# Lines with a BA_IMPOSSIBLE panic are left unmarked: they are meant never to run, so they are not gaps
awk 'NR == FNR { if ($0 ~ /^ *#####:/) { split($0, a, ":"); miss[a[2] + 0] = 1 } next }
     { if (FNR in miss) print $0 ($0 ~ /BA_IMPOSSIBLE/ ? "" : "   // no coverage"); else print $0 }' bitarray.c.gcov bitarray.c > bitarray.nocoverage
echo "(full listing: $OUT/bitarray.c.gcov; bitarray.c with a marker on the lines that never ran: $OUT/bitarray.nocoverage)"
