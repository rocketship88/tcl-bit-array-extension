#!/usr/bin/env python3
"""Embed bitarray.c in bitarray_stepper.html, so the page can show the code for each step
(a browser page opened from a file cannot read other files).  Two more files are embedded so that a double-click
on a Tcl name (Tcl_Obj, TCL_OK, Tcl_NewObj, ...) can show its definition one level deep: the whole of tcl.h
(extras/tcl_9.1.1.h) and the declarations of the Tcl functions bitarray.c uses (extras/tcl_decls_used.txt, made by
extras/make_tcl_refs.py from a Tcl source tree).

    python3 extras/embed_source.py          copy ../bitarray.c and the two Tcl files into the page
    python3 extras/embed_source.py --check  exit 1 if the page holds different copies, if it names a
                                            bitarray.c function that no longer exists, or if bitarray.c uses a
                                            Tcl name that neither tcl.h nor tcl_decls_used.txt defines
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
CLOSE = '</script>'
BLOCKS = [('csrc', src_path, 'bitarray.c'),
          ('tclh', os.path.join(here, 'tcl_9.1.1.h'), 'tcl.h'),
          ('tcld', os.path.join(here, 'tcl_decls_used.txt'), 'the Tcl declarations')]

def read(path):
    return open(path, encoding='utf-8', newline='').read().replace('\r\n', '\n')

html = open(html_path, encoding='utf-8', newline='').read()
text = {}
for bid, path, label in BLOCKS:
    text[bid] = read(path)
    if '</script' in text[bid].lower():
        sys.exit(label + ' contains "</script"; cannot embed it')

def span(bid):
    open_tag = '<script type="text/plain" id="%s">' % bid
    m = re.search(re.escape(open_tag) + r'(.*?)' + re.escape(CLOSE), html, re.S)
    if not m:
        sys.exit('marker for %s not found in %s' % (bid, html_path))
    return m

src = text['csrc']
if '--check' in sys.argv:
    bad = 0
    page = html
    for bid, path, label in BLOCKS:
        m = span(bid)
        if m.group(1) != '\n' + text[bid]:
            print('bitarray_stepper.html holds a DIFFERENT %s: run python3 extras/embed_source.py' % label)
            bad = 1
        page = page.replace(m.group(1), '')
    # Every bitarray.c function the page's steps and hook table name must still exist in the source.
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
    # Every Tcl name bitarray.c uses should be defined in tcl.h or declared in tcl_decls_used.txt, so a
    # double-click on it shows something.  (Names bitarray.c defines itself are not Tcl names.)
    mine = set(re.findall(r'^\s*#\s*define\s+(\w+)', src, re.M)) | have
    used = {n for n in re.findall(r'\b(?:Tcl|TCL|TclBN)_\w+', src) if n not in mine}
    defs = [l for l in text['tclh'].split('\n') if re.match(r'\s*(#\s*define\s|typedef\b|\}|struct\b|enum\b|union\b)', l)]
    deftext = '\n'.join(defs)
    declared = set(re.findall(r'^@@ \d+ (\w+)$', text['tcld'], re.M))
    nodef = sorted(n for n in used if n not in declared and not re.search(r'\b' + n + r'\b', deftext))
    if nodef:
        print('bitarray.c uses Tcl names with no definition in tcl.h and no declaration in tcl_decls_used.txt: ' + ', '.join(nodef))
        print('  run: python3 extras/make_tcl_refs.py --tcl-generic /path/to/tcl/generic   then embed_source.py')
        bad = 1
    if not bad:
        print('bitarray_stepper.html holds the current bitarray.c, tcl.h and the Tcl declarations; every function it names exists (%d names checked, %d Tcl names resolve)' % (len(names), len(used)))
    sys.exit(bad)
for bid, path, label in BLOCKS:
    m = span(bid)
    html = html[:m.start(1)] + '\n' + text[bid] + html[m.end(1):]
open(html_path, 'w', encoding='utf-8', newline='').write(html)
print('embedded %d lines of bitarray.c, %d of tcl.h and %d of Tcl declarations' % (src.count('\n'), text['tclh'].count('\n'), text['tcld'].count('\n')))
