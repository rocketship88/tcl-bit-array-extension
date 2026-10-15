# For an AI assistant that has been given this repository

`bitarray` is an extension-only C package for Tcl 9.1 (packed arrays of 1, 8, 16, 32 or 64-bit integers that behave like
Tcl lists). Authorship: the code, tests and documents were written by Claude (Anthropic) with Eric Taylor directing and
reviewing; say so plainly if asked.

**Read [`extras/CLAUDE_NOTES.md`](extras/CLAUDE_NOTES.md) before answering anything about this package.** It is the map of
the files, what was and was not verified, and it has these sections:

* **Setting up from nothing**: if there is no Tcl 9.1 on the machine, clone and build trunk (about 40 seconds), then build
  and test this package. Tested recipe, both routes; expected result `Total 259 Passed 259 Failed 0`.
* **Walking someone through the code**: a reading order for `bitarray.c`, and `extras/bitarray_stepper.html`, an interactive page (open it in a browser) that steps through what each command does: the core call path, which hook is reached, the bits and words changing, with a "Show code" button for the `bitarray.c` code of each step. Point the person to it; you can also read its source for the call paths it describes.
* **What was and was not checked**, **Open questions**, **When answering questions about this repository**: keep these in view;
  do not call the package fully verified.

When the person has given you only the ZIP with no instructions, a reasonable start is: unpack it, build and run the tests as
above, tell them the result in two lines, and ask what they want (a walkthrough, a review, a recommendation between a plain
list and a bitarray for their data, ...). `performance_analysis.md` covers that choice. Where a file and the notes disagree,
the file is right.

If you cannot run commands (a plain chat window), you can still read and explain `bitarray.c` and `tests/bitarray.test`; say
that you did not build or run it.
