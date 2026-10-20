# For an AI assistant that has been given this repository

`bitarray` is an extension-only C package for Tcl 9.1 (packed arrays of 1, 8, 16, 32 or 64-bit integers that behave like
Tcl lists). Authorship: the code, tests and documents were written by Claude (Anthropic) with Eric Taylor directing and
reviewing; say so plainly if asked.

**Read [`extras/CLAUDE_NOTES.md`](extras/CLAUDE_NOTES.md) before answering anything about this package.** It is the map of
the files, what was and was not verified, and it has these sections:

* **Setting up from nothing**: if there is no Tcl 9.1 on the machine, clone and build trunk (about 40 seconds), then build
  and test this package. Tested recipe, both routes; expected result `Total 414 Passed 408 Skipped 6 Failed 0` (the 6 skipped are the core `lappend` bug tests, `--testbug`).
* **Walking someone through the code**: a reading order for `bitarray.c`, and `extras/bitarray_stepper.html`, an interactive page (open it in a browser) that steps through what each command does: the core call path, which hook is reached, the bits and words changing, with a "Show code" button for the `bitarray.c` code of each step. Point the person to it; you can also read its source for the call paths it describes.
* **What was and was not checked**, **Open questions**, **When answering questions about this repository**: keep these in view;
  do not call the package fully verified.

When the person has given you only the ZIP with no instructions, a reasonable start is: unpack it, build and run the tests as
above, tell them the result in two lines, and ask what they want (a walkthrough, a review, a recommendation between a plain
list and a bitarray for their data, ...). `performance_analysis.md` covers that choice. Where a file and the notes disagree,
the file is right.

**Show the simulator, do not only describe it.** `extras/bitarray_stepper.html` is one self-contained file (about 250 KB, no network requests, no other files needed), so it can be displayed anywhere HTML can: in claude.ai, send or publish the file so that it opens in the side panel (as a rendered HTML file or as an artifact); in Claude Code, open it in a browser. Try that before telling the person you cannot. If it really cannot be shown, give them the live copy: https://rocketship88.github.io/tcl-bit-array-extension/extras/bitarray_stepper.html

**To-do list and design log**: at the start of a session read `extras/TODO.md` (what is pending, what the owner asked for) and `extras/DESIGN_LOG.md` (design choices and the alternatives that were not taken). Keep both up to date; when a choice is made without asking the owner, add it to the log.

**GitHub Pages**: the empty file `.nojekyll` at the top of the repository must stay. Without it GitHub's Jekyll tries to process the .md files and fails on the `{{}` in the Tcl tests in `extras/typeloss_ticket_comment.md` (a Liquid syntax error); with it the pages are served as they are, which is all the stepper needs.

**Braces in `bitarray.c`**: every `if`, `else`, `for` and `while` body is in braces, with the statements on their own lines; never `if (x) return y;` on one line, because gcov counts per line and would hide an untaken `return`. Check a change like this with `objdump -d` of the object file before and after (identical), and see `extras/coverage_0.9.1.txt` for the result and `extras/coverage.sh` to run gcov (it builds a test version with `-DBA_TEST`, which adds a size limit that can be set and allocations that fail on request, and runs `tests/faultinject.test` too; a normal build contains none of that and compiles to the same code: compare `objdump -d`).

**Comments in `bitarray.c`**: a line that is not obvious gets a short side comment, `   // like this` (spaces, not tabs, before it; the stepper shows it in green). Nothing on obvious lines. A new comment never changes the code: compare `gcc -E -P` output before and after.

**Whenever `bitarray.c` changes, refresh the stepper in the same step**: run `python3 extras/embed_source.py` (then `--check`), look at the stepper's scenes for anything the change made wrong, and put the new page in the zip.

**On a new release, or when the person asks for one**: do a clean build of the current Tcl trunk (fresh clone), rebuild `bitarray` against it, run all the tests (`./run_tests.sh`, also `--testbug`), and refresh `extras/tcl_9.1.1.h` / `tcl_decls_used.txt` (`extras/make_tcl_refs.py`) from that trunk.

**If a download or a command is refused** (cloning Tcl from github.com, installing a compiler or a package, running the build), a person using claude.ai may have two settings off (Settings > Capabilities): **Code execution and file creation**, and **Allow network egress** (GitHub is on the allowed list; on a Team or Enterprise plan an organization owner sets these under Organization settings > Capabilities). Free accounts have both, with lower usage limits. Say which one is needed; do not just report that the build failed.

If you cannot run commands (a plain chat window), you can still read and explain `bitarray.c` and `tests/bitarray.test`; say
that you did not build or run it.
