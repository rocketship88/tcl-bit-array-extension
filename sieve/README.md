# sieve

The six sieve variants and their runner. Normally you only use `../run_sieves.sh`; the other scripts are helpers for
digging into one variant.

`frank_sieve.tcl` is Frank van Bakel's Tcl sieve (variant A), included **unchanged** — byte for byte the file
`PrimeTcl/solution_1/primes.tcl` in <https://github.com/PlummersSoftwareLLC/Primes> (branch `drag-race`, head
commit `c4e42f00ba91` when I cloned it on 2026-10-12). It is his work (author and date are in its header). That repository has no LICENSE file; its
CONTRIBUTING.md asks contributors to license their code under BSD-3 or a more permissive licence.

**Permission.** The repository owner asked Frank van Bakel in a GitHub issue
(<https://github.com/fvbakel/PrimeTools/issues/1>), and on 2026-10-14 (GitHub's date) he answered: "Yes, you can include the
mentioned file in your project. It is ok to use the MIT licence for that." The file is therefore included with his permission,
and he said the MIT licence is fine for it. The file itself is unchanged and carries no licence notice, so that reply is the record.
`run_sieves.sh --sieve FILE` lets you use your own copy instead.

Variants (`variants.tcl`):

| | |
|---|---|
| A | Frank's `run_sieve`, unchanged (the `bit` proc, a list of 32-bit words) |
| B | same algorithm and data structure, `bit` proc inlined, no extension |
| C | same algorithm on a bitarray, `lindex`/`lset` per bit |
| D | bitarray plus `bitarray fill ... step` and `bitarray next` |
| E | like C but one byte per flag (`bitarray new ... -width 8`) |
| F | like D but one byte per flag (`bitarray new ... -width 8`) |

His original `run_sieve` did not finish within 10 seconds at limit 10 (I believe it loops forever when no further prime is
found after the last factor); B to F include a one-line guard. It does not matter at the benchmark limit of 1,000,000.

Helper scripts, run from the package directory with the extension built and a procs-only copy of Frank's file
(his file without its final `main ...` line) saved as `sieve/frank_procs.tcl`:

    grep -Ev '^main([[:space:]]|$)' primes.tcl > sieve/frank_procs.tcl
    tclsh sieve/check.tcl 1000000          # all six variants must give the same primes (78498)
    tclsh sieve/wall.tcl 1000000           # microseconds per pass, best of 3, variants A to F
    V=C N=3 M=100000 valgrind --tool=callgrind --callgrind-out-file=/dev/null tclsh sieve/cg.tcl
          (run with N=1 and N=3, subtract, divide by 2 = instructions per pass)

These helpers load `./libbitarray.so`, so run them with the package directory as the current directory.
