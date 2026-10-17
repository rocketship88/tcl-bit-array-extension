#!/usr/bin/env python3
"""Write extras/tcl_decls_used.txt: the declarations of the Tcl functions that bitarray.c uses, copied from
a Tcl source tree's generic/tclDecls.h, for the code viewer of bitarray_stepper.html (double-click a Tcl name).

    python3 extras/make_tcl_refs.py --tcl-generic /path/to/tcl/generic

The viewer also embeds the whole of tcl.h (extras/tcl_9.1.1.h); tclDecls.h is too big (190 KB) to embed, so only
the declarations bitarray.c needs are kept: the EXTERN prototype of each function, or, where the function is a
macro in tclDecls.h (Tcl_GetString, Tcl_PkgProvide, ...), that #define.  Run extras/embed_source.py afterwards.
Each entry starts with a line  '@@ <line number in tclDecls.h> <name>'.
"""
import os, re, sys

here = os.path.dirname(os.path.abspath(__file__))
if '--tcl-generic' not in sys.argv:
    sys.exit(__doc__)
gen = sys.argv[sys.argv.index('--tcl-generic') + 1]
src = open(os.path.join(here, '..', 'bitarray.c'), encoding='utf-8').read()
ids = set(re.findall(r'\b[A-Za-z_]\w*\b', src))
L = open(os.path.join(gen, 'tclDecls.h'), encoding='utf-8').read().replace('\r\n', '\n').split('\n')
want = {}                                   # name -> (line, [lines])
i = 0
while i < len(L):
    if L[i].startswith('EXTERN'):
        j = i
        while j < len(L) and not L[j].rstrip().endswith(';'):
            j += 1
        text = ' '.join(L[i:j + 1])
        # the function name is the identifier just before the first '('
        m = re.search(r'(\w+)\s*\(', re.sub(r'^EXTERN\s+', '', text))
        if m and m.group(1) in ids:
            want.setdefault(m.group(1), (i + 1, L[i:j + 1]))
        i = j + 1
        continue
    m = re.match(r'#define\s+(\w+)\(', L[i])         # a function-like macro in the redirect section
    if m and m.group(1) in ids:
        j = i
        while L[j].rstrip().endswith('\\'):
            j += 1
        want.setdefault('#' + m.group(1), (i + 1, L[i:j + 1]))
    i += 1
out = []
for name in sorted(ids):
    e = want.get(name) or want.get('#' + name)
    if e:
        out.append('@@ %d %s' % (e[0], name))
        out.extend(l.rstrip() for l in e[1])
open(os.path.join(here, 'tcl_decls_used.txt'), 'w', encoding='utf-8', newline='').write('\n'.join(out) + '\n')
print('wrote tcl_decls_used.txt: %d declarations' % sum(1 for l in out if l.startswith('@@ ')))
