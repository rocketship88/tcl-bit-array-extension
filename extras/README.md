# extras

Development material; none of it is needed to build or use the extension.

* `mutate5.py` — mutation testing. Applies 95 deliberate bugs to `bitarray.c` one at a time, rebuilds, runs the test suite and
  reports each as CAUGHT or MISSED. The environment variables it needs are listed at the top of the file. It takes 10–30
  minutes. The first four rounds' logs are kept for history; `mutation_round5.txt` is the final run
  (81 caught, 14 missed, reasons in `../RESULTS.txt`) and `mutation_round5_first_run.txt` is the run before the memory-growth
  test was added (79 caught, 16 missed).
* `mutation_round1.txt` … `mutation_round4.txt` — logs from the 0.1 and 0.2 versions of the code. They were produced by an
  earlier script (`mutate.py`, not included: `mutate5.py` contains all of its mutants, updated to the current code).

* `mutate6.py` — the same 95 mutants (it reads the list from `mutate5.py`), but it keeps a full record and writes:
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

* `CLAUDE_REFRESHER.md` — a briefing for an AI assistant (or a person) asked about this repository: where each kind of answer
  lives, how to trace a mutant to the tests that caught it, what was and was not checked, and the open questions.
