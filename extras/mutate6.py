#!/usr/bin/env python3
"""Mutation testing with a full record.  Same mutants as mutate5.py (it reads its MUT list), but for each one it keeps:
   id, description, automatic class, line range in bitarray.c, original and mutated text, build result, the NAMES of
   every test that failed (or the test that was running when the run crashed), and the time taken.
It writes   mutants.json        everything, machine readable
            bitarray.mutants    bitarray.c with each mutant applied, and a comment at the right giving its id, kind, result
                                and the tests that failed.  For a side-by-side compare with bitarray.c: every line keeps its
                                place; a comment too wide for the column goes on its own line below
            bitarray.mutants.stacked   the same, but where several mutants touch the same lines every version is written
                                one under the other instead of being mentioned in a comment
            mutation_summary.txt  per-mutant table, per-test kill counts, tests that caught nothing

usage (from anywhere; the three variables are the same ones mutate5.py needs):
    BITARRAY_INCLUDE=/opt/tcl9.1/include BITARRAY_STUBLIB=/opt/tcl9.1/lib/libtclstub.a \\
    BITARRAY_TCLSH=/opt/tcl9.1/bin/tclsh9.1  python3 extras/mutate6.py [--jobs N] [--out DIR] [--col N] [M01 W17 ...]
    (also BITARRAY_INCLUDE2, CC, LD_LIBRARY_PATH as for mutate5.py; BITARRAY_ROOT only if this script is not in extras/)
The mutants themselves are the list in mutate5.py, which this script reads.  Takes 20-40 minutes on two cores (--jobs 2);
an interrupted run resumes where it stopped (mutants.partial.jsonl), delete that file to start over.
--regen rebuilds bitarray.mutants / the summary from an existing mutants.json without running anything.
"""
import subprocess, os, shutil, sys, re, tempfile, json, time, argparse
from concurrent.futures import ThreadPoolExecutor

ap = argparse.ArgumentParser()
ap.add_argument('--jobs', type=int, default=2)
ap.add_argument('--out', default=None, help='where to write the results (default: the folder this script is in)')
ap.add_argument('--regen', action='store_true')
ap.add_argument('--col', default='auto', help="column for the comments: a number, or 'auto' (the width that 90%% of the mutated lines fit in, 60..100)")
ap.add_argument('--mutlist', default=None, help='file defining MUT (default: mutate5.py next to ROOT/extras)')
ap.add_argument('only', nargs='*')
A = ap.parse_args()

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get('BITARRAY_ROOT', os.path.dirname(HERE))      # the folder holding bitarray.c and tests/
SRC = open(os.path.join(ROOT, 'bitarray.c')).read()
TESTFILE = os.path.join(ROOT, 'tests', 'bitarray.test')
OUT = os.path.abspath(A.out or HERE)
os.makedirs(OUT, exist_ok=True)

# ---- the mutant list: reuse mutate5.py's literal ----
ml = A.mutlist or os.path.join(ROOT, 'extras', 'mutate5.py')
code = open(ml).read()
a = code.index('MUT = ['); b = code.index('\n]\n', a) + 3
ns = {}; exec(code[a:b], ns); MUT = ns['MUT']

# ---- automatic classification ----
TOK = re.compile(r'\s*("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|0[xX][0-9a-fA-F]+|\d+|[A-Za-z_]\w*|<<=|>>=|<<|>>|<=|>=|==|!=|&&|\|\||->|[-+*/%&|^~!<>=?:;,(){}\[\].])')
def toks(s): return TOK.findall(s)
def classify(old, new):
    o, n = toks(old), toks(new)
    if not new.strip():
        return 'deleted:statement'
    if len(n) < len(o) and all(t in o for t in n):
        return 'deleted:clause'
    ol_, nl_ = [x.strip() for x in old.split('\n') if x.strip()], [x.strip() for x in new.split('\n') if x.strip()]
    if len(nl_) > len(ol_) and all(x in nl_ for x in ol_):
        return 'added:code'                      # every old line is still there, plus whole new lines
    if new.find(old.strip()) >= 0 and old.strip() and re.search(r'[;{]', new.replace(old.strip(), '', 1)):
        return 'added:code'                      # the old text is all still there, plus a new statement or branch
    if len(n) > len(o) and not [t for t in o if t not in n]:
        return 'changed:+tokens'                 # the old text with something appended, e.g. "- 1"
    if len(o) == len(n):
        d = [(x, y) for x, y in zip(o, n) if x != y]
        if len(d) == 1:
            x, y = d[0]
            if re.fullmatch(r'0[xX][0-9a-fA-F]+|\d+', x) and re.fullmatch(r'0[xX][0-9a-fA-F]+|\d+', y): return 'changed:constant'
            if re.fullmatch(r'[A-Za-z_]\w*', x) and re.fullmatch(r'[A-Za-z_]\w*', y): return 'changed:name/variable'
            if re.fullmatch(r'[^\w\s]+', x) and re.fullmatch(r'[^\w\s]+', y): return 'changed:operator'
            return 'changed:token'
        return 'changed:%d tokens' % len(d)
    return 'changed:expression'

def lines_of(src, old):
    i = src.index(old); j = i + len(old)
    return src.count('\n', 0, i) + 1, src.count('\n', 0, j) + 1 - (1 if old.endswith('\n') else 0)

# ---- running ----
CC = os.environ.get('CC', 'cc')
def run_one(item):
    name, old, new = item
    mid = name.split()[0]
    rec = dict(id=mid, name=name, old=old, new=new, cls=classify(old, new))
    if SRC.count(old) != 1:
        rec.update(result='BADPATTERN', tests=[], line1=0, line2=0); return rec
    rec['line1'], rec['line2'] = lines_of(SRC, old)
    d = tempfile.mkdtemp(prefix='bitarray_mut_')
    t0 = time.time()
    try:
        open(d + '/bitarray.c', 'w').write(SRC.replace(old, new))
        INC = [os.environ['BITARRAY_INCLUDE']] + ([os.environ['BITARRAY_INCLUDE2']] if 'BITARRAY_INCLUDE2' in os.environ else [])
        cmd = [CC, '-O2', '-fPIC', '-shared', '-DUSE_TCL_STUBS'] + ['-I' + i for i in INC] + [d + '/bitarray.c', os.environ['BITARRAY_STUBLIB'], '-o', d + '/libbitarray.so']
        c = subprocess.run(cmd, capture_output=True, text=True)
        if c.returncode:
            rec.update(result='NOCOMPILE', tests=[], detail=c.stderr[-300:]); return rec
        env = dict(os.environ, BITARRAY_LIB=d + '/libbitarray.so')
        try:
            r = subprocess.run([os.environ['BITARRAY_TCLSH'], TESTFILE, '-verbose', 'body start'], cwd=d, env=env,
                               capture_output=True, text=True, timeout=300)
        except subprocess.TimeoutExpired as e:
            out = (e.stdout or b'')
            out = out.decode('utf-8', 'replace') if isinstance(out, bytes) else out
            starts = re.findall(r'^---- (\S+) start$', out, re.M)
            rec.update(result='CAUGHT', how='timeout', tests=[], running=starts[-1] if starts else None); return rec
        out = r.stdout
        failed = []
        for t in re.findall(r'^==== (\S+) FAILED$', out, re.M):
            if t not in failed: failed.append(t)
        starts = re.findall(r'^---- (\S+) start$', out, re.M)
        m = re.search(r'Total\s+(\d+)\s+Passed\s+(\d+).*Failed\s+(\d+)', out)
        rec['total'] = int(m.group(1)) if m else None
        if r.returncode != 0 and not m:
            rec.update(result='CAUGHT', how='crash rc=%d' % r.returncode, tests=failed, running=starts[-1] if starts else None)
        elif m and int(m.group(3)) > 0:
            rec.update(result='CAUGHT', how='%d tests fail' % int(m.group(3)), tests=failed)
        elif r.returncode != 0:
            rec.update(result='CAUGHT', how='rc=%d' % r.returncode, tests=failed)
        else:
            rec.update(result='MISSED', how='', tests=[])
        return rec
    finally:
        rec['secs'] = round(time.time() - t0, 1)
        shutil.rmtree(d, ignore_errors=True)

jpath = os.path.join(OUT, 'mutants.json')
if A.regen:
    RECS = json.load(open(jpath))
    for r_ in RECS: r_['cls'] = classify(r_['old'], r_['new'])
    json.dump(RECS, open(jpath, 'w'), indent=1)
else:
    from concurrent.futures import as_completed
    part = os.path.join(OUT, 'mutants.partial.jsonl')      # one line per finished mutant, so an interrupted run can resume
    done = {}
    if os.path.exists(part):
        for ln in open(part):
            try: r_ = json.loads(ln); done[r_['id']] = r_
            except ValueError: pass
    items = [m for m in MUT if (not A.only or m[0].split()[0] in A.only) and m[0].split()[0] not in done]
    print('already done: %d, to run: %d' % (len(done), len(items)), flush=True)
    with ThreadPoolExecutor(A.jobs) as ex, open(part, 'a') as pf:
        futs = [ex.submit(run_one, it) for it in items]
        for f in as_completed(futs):
            rec = f.result(); done[rec['id']] = rec
            pf.write(json.dumps(rec) + '\n'); pf.flush()
            print(rec['id'], rec['result'], rec.get('how', ''), flush=True)
    RECS = [done[m[0].split()[0]] for m in MUT if m[0].split()[0] in done]
    json.dump(RECS, open(jpath, 'w'), indent=1)

# ---- bitarray.mutants ----
def result_text(r):
    if r['result'] == 'MISSED': return 'MISSED by all %s tests' % (r.get('total') or '')
    if r['result'] != 'CAUGHT': return r['result']
    how = r.get('how', '')
    if how.startswith('crash') or how == 'timeout':
        s = 'CAUGHT (%s' % how
        if r.get('running'): s += ' while running %s' % r['running']
        s += ')'
        if r['tests']: s += ' + failed: ' + ' '.join(r['tests'])
        return s
    return 'CAUGHT by %d: %s' % (len(r['tests']), ' '.join(r['tests']))

def esc(s):
    return s.replace('*/', '*\\').replace('/*', '\\*').replace('\n', '\\n').replace('\t', ' ')

def splice(src, old, new):
    """Return (start offset, end offset, old block, new block) for whole lines; the new block has exactly as many
    lines as the old one: surplus lines are folded onto one line inside the changed region, a shortfall is padded
    with blank lines at the end of the changed region."""
    i = src.index(old); j = i + len(old)
    ls = src.rfind('\n', 0, i) + 1
    le = src.find('\n', j)
    if le < 0: le = len(src)
    old_block = src[ls:le]
    new_block = src[ls:i] + new + src[j:le]
    ol, nl = old_block.split('\n'), new_block.split('\n')
    p = 0
    while p < min(len(ol), len(nl)) and ol[p] == nl[p]: p += 1
    s_ = 0
    while s_ < min(len(ol), len(nl)) - p and ol[len(ol) - 1 - s_] == nl[len(nl) - 1 - s_]: s_ += 1
    mo, mn = ol[p:len(ol) - s_], nl[p:len(nl) - s_]
    if len(mn) > len(mo):
        if not mo:                                   # pure insertion: hang it on the line before
            fold = ' '.join(x.strip() for x in mn)
            if p > 0: nl = nl[:p - 1] + [nl[p - 1] + ' ' + fold] + nl[p + len(mn):]
            else:     nl = [fold] + nl[len(mn):]
        else:
            keep = len(mo) - 1
            fold = ' '.join(x.strip() for x in mn[keep:])
            mn = mn[:keep] + [fold]
            nl = nl[:p] + mn + nl[len(nl) - s_:] if s_ else nl[:p] + mn
    elif len(mn) < len(mo):
        mn = mn + [''] * (len(mo) - len(mn))
        nl = nl[:p] + mn + nl[len(nl) - s_:] if s_ else nl[:p] + mn
    return ls, le, old_block, '\n'.join(nl)

good = sorted([r for r in RECS if r['result'] not in ('BADPATTERN',) and r.get('line1')], key=lambda r: (r['line1'], r['id']))
taken = []     # accepted mutants (non-overlapping line ranges); the rest become "also" notes
also = {}
for r in good:
    hit = next((t for t in taken if not (r['line2'] < t['line1'] or r['line1'] > t['line2'])), None)
    if hit is None: taken.append(r)
    else: also.setdefault(hit['id'], []).append(r)

lines = SRC.split('\n')
out_lines = list(lines)
notes = {}     # line index -> comment text
for r in taken:
    ls, le, ob, nbk = splice(SRC, r['old'], r['new'])
    first = SRC.count('\n', 0, ls)                      # 0-based index of first line of block
    ol, nl = ob.split('\n'), nbk.split('\n')
    assert len(ol) == len(nl), (r['id'], len(ol), len(nl))
    changed = [k for k in range(len(ol)) if ol[k] != nl[k]]
    for k in range(len(ol)): out_lines[first + k] = nl[k]
    head = '%s %s | %s | %s | %s' % (r['id'], r['cls'], result_text(r), r['name'].split(' ', 1)[1], 'line %d' % r['line1'] + ('-%d' % r['line2'] if r['line2'] != r['line1'] else ''))
    for al in also.get(r['id'], []):
        head += ' || ALSO %s %s | %s | %s => %s' % (al['id'], al['cls'], result_text(al), al['name'].split(' ', 1)[1], al['new'].strip())
    for n_, k in enumerate(changed):
        notes[first + k] = head if n_ == 0 else '%s (cont.)' % r['id']
    if not changed:
        notes[first] = head + ' [no visible change?]'

def disp(s): return len(s.expandtabs(8))

def pick_col(widths):
    if A.col != 'auto': return int(A.col)
    w = sorted(widths)
    return max(60, min(100, (w[int(len(w) * 0.9) - 1] if w else 60) + 3))

def render(pairs, col):
    """pairs = [(code line, comment or None)].  A comment goes to the right of its line at column COL; if the code is
    too wide for that, the comment goes on a line of its own just below, at the same column."""
    out = []
    for t, c in pairs:
        if not c: out.append(t); continue
        if disp(t) + 3 > col:
            out.append(t); out.append(' ' * col + '/* ' + esc(c) + ' */')
        else:
            out.append(t + ' ' * (col - disp(t)) + '/* ' + esc(c) + ' */')
    return '\n'.join(out)

COL = pick_col([disp(out_lines[k]) for k in notes])
open(os.path.join(OUT, 'bitarray.mutants'), 'w').write(render([(out_lines[k], notes.get(k)) for k in range(len(out_lines))], COL))
print('comment column', COL, '; mutated lines too wide for it (comment placed on the next line):', sum(1 for k in notes if disp(out_lines[k]) + 3 > COL))

# ---- bitarray.mutants.stacked: where mutants share lines, every version is written one under the other ----
groups = []
for r in good:
    ls_, le_, ob_, nb_ = splice(SRC, r['old'], r['new'])
    f0 = SRC.count('\n', 0, ls_); f1 = f0 + ob_.count('\n')
    r['_f0'], r['_f1'], r['_nl'] = f0, f1, nb_.split('\n')
    if groups and f0 <= groups[-1]['end']:
        groups[-1]['m'].append(r); groups[-1]['end'] = max(groups[-1]['end'], f1)
    else:
        groups.append(dict(start=f0, end=f1, m=[r]))
st = []          # (text, comment or None)
pos = 0
for g in groups:
    for k in range(pos, g['start']): st.append((lines[k], None))
    for r in g['m']:
        blk = list(lines[g['start']:g['end'] + 1])
        for k, t in enumerate(r['_nl']): blk[r['_f0'] - g['start'] + k] = t
        head = '%s %s | %s | %s | line %d' % (r['id'], r['cls'], result_text(r), r['name'].split(' ', 1)[1], r['line1']) + ('-%d' % r['line2'] if r['line2'] != r['line1'] else '')
        if len(g['m']) > 1: head += ' | version %d of %d on these lines' % (g['m'].index(r) + 1, len(g['m']))
        n_ = 0
        for k, t in enumerate(blk):
            if t != lines[g['start'] + k]:
                st.append((t, head if n_ == 0 else '%s (cont.)' % r['id'])); n_ += 1
            elif len(g['m']) > 1:
                st.append((t, None))      # unchanged line inside a stacked version: repeat it so each version reads whole
            else:
                st.append((t, None))
    pos = g['end'] + 1
for k in range(pos, len(lines)): st.append((lines[k], None))
open(os.path.join(OUT, 'bitarray.mutants.stacked'), 'w').write(render(st, COL))

# ---- summary ----
S = []
S.append('%-5s %-8s %-22s %-5s %-9s %s' % ('id', 'result', 'class', 'lines', 'tests', 'description'))
S.append('-' * 100)
for r in sorted(RECS, key=lambda r: r['id']):
    S.append('%-5s %-8s %-22s %-5s %-9s %s' % (r['id'], r['result'], r['cls'], r.get('line1', ''), ('%d' % len(r['tests'])) if r['result'] == 'CAUGHT' else '-', r['name'].split(' ', 1)[1]))
kills = {}
for r in RECS:
    for t in r.get('tests', []): kills.setdefault(t, []).append(r['id'])
alltests = []
tf = open(TESTFILE).read()
alltests = re.findall(r'^test\s+(\S+)', tf, re.M)
S.append('')
S.append('Tests by number of mutants they failed on (only mutants that ran to completion are counted; crashes list the test running at the time separately)')
for t in sorted(alltests, key=lambda t: -len(kills.get(t, []))):
    S.append('  %-14s %3d' % (t, len(kills.get(t, []))))
S.append('')
S.append('Tests that failed on no mutant: ' + ' '.join(t for t in alltests if t not in kills))
crash = [(r['id'], r.get('running')) for r in RECS if r.get('how', '').startswith('crash')]
S.append('Mutants that crashed the run (test running at the time): ' + ', '.join('%s:%s' % c for c in crash))
S.append('')
c = {}
for r in RECS: c[(r['cls'].split(':')[0], r['result'])] = c.get((r['cls'].split(':')[0], r['result']), 0) + 1
for k in sorted(c): S.append('  %-10s %-8s %d' % (k[0], k[1], c[k]))
open(os.path.join(OUT, 'mutation_summary.txt'), 'w').write('\n'.join(S) + '\n')
print('wrote', OUT)
