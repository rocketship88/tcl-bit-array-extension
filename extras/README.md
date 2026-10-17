# extras

Development material; none of it is needed to build or use the extension.

* `bitarray_stepper.html` — an interactive page (open it in a browser; no network needed). Pick a command (`lset`, `lrange`, `lreplace`, a queue of bits, the bitwise operations and others), then step through what the Tcl core and `bitarray.c` do with it: the call stack, which `Tcl_ObjType` hook is reached, and the bits and 64-bit words as they change. "Show code" brings up the `bitarray.c` code for the step and "Show memory" returns. Names you can double-click in the code (functions, macros and types of `bitarray.c`, and Tcl names such as `Tcl_Obj`, `TCL_OK` or `Tcl_NewObj`, whose definition from `tcl.h` is shown one level deep) are drawn bold in colour, comments green; the "Color" check box turns this off. The "Fold" check box (off by default) collapses the outermost blocks of a function (each `case` of a `switch`, each branch of an `if` / `else if` / `else` chain) into "… N lines" rows to click open; the block holding the highlighted line stays open. `bitarray.c`, `tcl.h` (`tcl_9.1.1.h`) and the Tcl function declarations that `bitarray.c` uses (`tcl_decls_used.txt`, made by `make_tcl_refs.py` from a Tcl source tree) are embedded in the page by `embed_source.py` (a browser page cannot read other files); run `python3 extras/embed_source.py` after changing `bitarray.c`, and `python3 extras/embed_source.py --check` to see whether the page is current (it also fails if the page names a `bitarray.c` function that no longer exists). The explanations and the drawings in the page are written by hand: when the behavior of a command changes, the matching scene in the page has to be updated too. The page has a button to load a different `bitarray.c`.
* `mutate5.py` — mutation testing. Applies the deliberate bugs listed in it (206 in 0.8.0) to `bitarray.c` one at a time, rebuilds, runs the test suite and
  reports each as CAUGHT or MISSED. The environment variables it needs are listed at the top of the file. It takes 10–30
  minutes. The first four rounds' logs are kept for history; `mutation_round5.txt` is the 0.3 run
  (95 mutants: 81 caught, 14 missed, reasons in `../RESULTS.txt`; `mutation_round6.txt` is the 0.4 run with 110 mutants, 96 caught, 14 missed, `mutation_round7.txt` the 0.5 run with 123 mutants, 109 caught, 14 missed, and `mutation_round8.txt` the 0.5.1 run with 138 mutants, 121 caught, 17 missed, and `mutation_round9.txt` the first 0.6.0 run with 164 mutants, 145 caught, 19 missed, and `mutation_round10.txt` the run after the speed changes (lrange, lreverse, lreplace, ledit) with 172 mutants, 151 caught, 21 missed, and `mutation_round11.txt` the 25 mutants added for the signed widths, run one by one: 24 caught, 1 missed) and `mutation_round5_first_run.txt` is the run before the memory-growth
  test was added (79 caught, 16 missed).
* `mutation_round1.txt` … `mutation_round4.txt` — logs from the 0.1 and 0.2 versions of the code. They were produced by an
  earlier script (`mutate.py`, not included: `mutate5.py` contains all of its mutants, updated to the current code).

* `mutate6.py` — the same 206 mutants (it reads the list from `mutate5.py`), but it keeps a full record and writes:
  * `bitarray.mutants` — `bitarray.c` with every mutant applied, each mutated line followed at the right by a comment:
    mutant id, kind (`deleted:clause`, `changed:operator`, ...), the result, and the **names of the tests that failed**
    (or the test that was running when the run crashed). Open it beside `bitarray.c` in a side-by-side compare tool; the
    changed lines then line up with the originals, and you can scroll right for the comments. Where two mutants touch the
    same lines the code shows the first and the comment gives the other's replacement text. A comment too wide for its
    column goes on its own line below. The comment column and tab stops assume tabs of width 8.
  * `bitarray.mutants.stacked` — the same, but where mutants share lines every version is written one under the other.
  * `mutation_summary.txt` — one line per mutant, how many mutants each test failed on, the tests that failed on none, and the
    mutants that crashed the run. `mutants.json` — everything, machine readable.

  These files describe the `bitarray.c` in this repository; run `mutate6.py` again after changing it (about 35 minutes on two
  cores; an interrupted run resumes). The kind of each mutant is classified automatically from the text, so treat it as a rough label.

* `listbench.tcl` — times the Tcl list commands (create, `llength`, `lindex`, `lset`, `lappend`, `lrange`, `lreverse`, `lreplace`,
  `linsert`, `ledit`, `lremove`, `lassign`, `lsearch`, `lsort`, `foreach`, `lmap`, `join`, `in`) and the bitarray's own `fill`, `count`, `next` and bitwise commands (`and`, `or`, `xor`, `andnot`, `not`; their rows are named `bitop ...`, so `-only 'bitop*'` picks them, and the plain-list side is a one-line `lmap`) (against small helper procs written for a plain list: `ledit` with `lrepeat`, a `lset` loop for a step, `lsearch -all`, `lsearch -start`) on a plain list and on a 1-bit and
  an 8-bit bitarray, with 1,000, 100,000 and 1,000,000 elements. `tclsh9.1 extras/listbench.tcl l` times plain lists only and needs
  no extension, so anyone can try it on their machine; `b` times only the bitarray; `both` (the default) puts them side by side with
  a ratio column. Each run starts and ends with a machine-speed calibration line, and checks first that every column gives the same
  answers. `-only PATTERN` keeps just the operations whose name matches (plain text matches anywhere in the name, a pattern with `*` or `?` is a glob, and `-only` can be repeated), `-help` prints the usage (also shown after a mistake in the command line; an unambiguous start of an option such as `-ratio` is accepted), `-md` prints markdown tables, `-verbose` adds notes on how to read the numbers (lazy `lrange`/`lreverse`, cold rows, the memory estimate), `-ratios` shows only the two ratio columns, and `-sort best1` or `-sort best8` lists each table from the biggest bitarray win to the biggest loss. `listbench_output_linux.txt` is one run of it with `-verbose` (0.5.1, this Linux container).

* `windows_0.6.0_run.txt` — the output of build, tests, sieve and a `listbench.tcl` ratios run (`-rat -sizes 1000000 -sort best1`) for 0.6.0 on one Windows machine, as the repository owner pasted it (line endings normalised).

* `typeloss_ticket_comment.md` — the follow-up comment for the core ticket (findings, the whole patch and six core-style tests, all inline). `core_lappend_typeloss.test` holds the same six tests as a file.
* `core_lappend_typeloss.patch` — a 10-line patch to Tcl trunk (tclVar.c `ListAppendInVar`, tclExecute.c `lappendListDirect`) that makes compiled `lappend` use `Tcl_ListObjReplace`, so the bitarray keeps its type inside a proc. Built on trunk of 2026-10-15 (102a512): with it `./run_tests.sh --testbug` gives `Total 288 Passed 288 Failed 0`; without it the 6 `coreTypeLoss` tests fail. Core's own list/var/execute/compile tests: 12004 total, 0 failed.
* `TODO.md` and `DESIGN_LOG.md` — the working to-do list and the log of design choices (what was decided without asking the owner, the alternatives and their cost); read both at the start of a session.
* `windows_0.7.0_run.txt` — build, tests (282, 281 passed, 1 skipped), sieve and `listbench.tcl -sort best1 -sizes 2000000 -v` for 0.7.0 on the same Windows machine (Visual Studio 2022, Tcl 9.1.1), as the repository owner pasted it (the second run, with the final `listbench.tcl`: an earlier run with the first 0.7.0 `listbench.tcl` showed 0.0 for the bitarray columns of `lsearch -exact (hit at 0, warm)`, a measuring flaw described in `RESULTS.txt`, section 18; here that row reads 0.21).
* `windows_0.8.0_run.txt` — the same for 0.8.0: build, tests (288, 281 passed, 7 skipped: 6 `--testbug`, 1 procfs), sieve and `listbench.tcl`, run by the owner on Windows.

* `windows_0.6.0_listbench.txt` — `listbench.tcl -rat -sizes 2000000 -sort best1` on the same Windows machine with the repaired same-answer check.

* `typeloss_*` — why core `lappend` / `linsert` sometimes turn a bitarray into an ordinary list: `typeloss_lstring_repro.tcl` (stock Tcl only;
  needs the `tcltest` shell), `typeloss_bitarray_repro.tcl` (the same with this extension), their `..._output.txt` files, and
  `typeloss_ticket.md`, the text of the report sent to the Tcl core.

* `CLAUDE_NOTES.md` — a briefing for an AI assistant (or a person) asked about this repository: where each kind of answer
  lives, how to trace a mutant to the tests that caught it, what was and was not checked, and the open questions.

`tcl_9.1.1.h` is the `tcl.h` of Tcl 9.1.1, unchanged, and `tcl_license.terms` is that distribution's `license.terms`, which governs it (it must stay with the copy). `tcl_decls_used.txt` holds only the declarations of the Tcl functions `bitarray.c` uses, taken from `tclDecls.h`.
