# extras

Development material; none of it is needed to build or use the extension.

* `mutate5.py` — mutation testing. Applies 95 deliberate bugs to `bitarray.c` one at a time, rebuilds, runs the test suite and
  reports each as CAUGHT or MISSED. The environment variables it needs are listed at the top of the file. It takes 10–30
  minutes. The first four rounds' logs are kept for history; `mutation_round5.txt` is the final run
  (81 caught, 14 missed, reasons in `../RESULTS.txt`) and `mutation_round5_first_run.txt` is the run before the memory-growth
  test was added (79 caught, 16 missed).
* `mutation_round1.txt` … `mutation_round4.txt` — logs from the 0.1 and 0.2 versions of the code. They were produced by an
  earlier script (`mutate.py`, not included: `mutate5.py` contains all of its mutants, updated to the current code).
