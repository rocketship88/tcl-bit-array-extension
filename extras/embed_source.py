#!/usr/bin/env python3
"""Embed bitarray.c in bitarray_stepper.html, so the page can show the code for each step
(a browser page opened from a file cannot read other files).

    python3 extras/embed_source.py          copy ../bitarray.c into the page
    python3 extras/embed_source.py --check  exit 1 if the page holds a different bitarray.c, or if it names a
                                            bitarray.c function that no longer exists
    python3 extras/embed_source.py --check --source FILE   the same, against another copy of bitarray.c

Run it again whenever bitarray.c changes. The page also has a "Load another bitarray.c" button
for looking at a modified copy without changing the file.
"""
import os, re, sys

here = os.path.dirname(os.path.abspath(__file__))
src_path = os.path.join(here, '..', 'bitarray.c')
if '--source' in sys.argv:
    src_path = sys.argv[sys.argv.index('--source') + 1]
html_path = os.path.join(here, 'bitarray_stepper.html')
OPEN, CLOSE = '<script type="text/plain" id="csrc">', '</script>'

src = open(src_path, encoding='utf-8', newline='').read().replace('\r\n', '\n')
if '</script' in src.lower():
    sys.exit('bitarray.c contains "</script"; cannot embed it')
html = open(html_path, encoding='utf-8', newline='').read()
m = re.search(re.escape(OPEN) + r'(.*?)' + re.escape(CLOSE), html, re.S)
if not m:
    sys.exit('marker not found in ' + html_path)
body = '\n' + src
if '--check' in sys.argv:
    bad = 0
    if m.group(1) != body:
        print('bitarray_stepper.html holds a DIFFERENT bitarray.c: run python3 extras/embed_source.py')
        bad = 1
    # Every bitarray.c function the page's steps and hook table name must still exist in the source.
    page = html[:m.start(1)] + html[m.end(1):]
    names = set()
    for seg in re.findall(r"src: '[^']*?bitarray\.c:\s*([^;']*)", page):
        names.update(x.strip().split()[0] for x in re.split(r'[,/]', seg) if x.strip())
    names.update(re.findall(r"\['\w+','\w+','(BA\w+)'", page))               # the hook table
    names.update(re.findall(r"F\('h', '([A-Z][A-Za-z0-9_]+)", page))            # call-history entries from bitarray.c
    have = set(re.findall(r'^([A-Za-z_]\w*)\(', src, re.M)) | {'bitarrayType', 'BitArr'}
    skip = {'S_NEW'}
    missing = sorted(n for n in names if n not in have and n not in skip and not n.isupper() and not n.startswith('Tcl'))
    if missing:
        print('the page names functions that are not in bitarray.c any more: ' + ', '.join(missing))
        print('  update the steps in bitarray_stepper.html (search for the name), then run this check again')
        bad = 1
    if not bad:
        print('bitarray_stepper.html holds the current bitarray.c and every function it names exists (%d names checked)' % len(names))
    sys.exit(bad)
html = html[:m.start(1)] + body + html[m.end(1):]
open(html_path, 'w', encoding='utf-8', newline='').write(html)
print('embedded %d lines of bitarray.c' % src.count('\n'))
