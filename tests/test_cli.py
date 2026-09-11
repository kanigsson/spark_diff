#!/usr/bin/env python3
"""Exercise the CLI and apply its output with independent system tools in temp dirs."""
import os
from pathlib import Path
import random
import shutil
import subprocess
import tempfile

BIN = str(Path(os.environ.get('DIFF_BIN', 'bin/spark-diff')).resolve())
checks = 0

def check(value, message):
    global checks
    checks += 1
    assert value, message

def run(args, **kw):
    return subprocess.run([BIN, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kw)

for tool in ('patch', 'git'):
    if not shutil.which(tool):
        raise SystemExit(f'required test tool missing: {tool}')

with tempfile.TemporaryDirectory(prefix='spark-diff-test-') as tmp:
    root = Path(tmp)
    old, new = root / 'old file', root / 'new file'

    def compare(a, b, options=(), apply=True):
        old.write_bytes(a)
        new.write_bytes(b)
        p = run([*options, str(old), str(new)])
        check(p.returncode == int(a != b), (a, b, options, p.stderr))
        check(not p.stderr, p.stderr)
        check(bool(p.stdout) == (a != b), p.stdout)
        check(old.read_bytes() == a and new.read_bytes() == b, 'CLI changed an input')
        if a != b and apply:
            target = root / 'target'
            target.write_bytes(a)
            q = subprocess.run(['patch', '--batch', '--fuzz=0', str(target)], input=p.stdout,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            check(q.returncode == 0 and target.read_bytes() == b, (p.stdout, q.stdout, q.stderr))
            # Explicit relative labels make the same patch consumable by git apply.
            q = run([*options, '--label', 'a/target', '--label', 'b/target', str(old), str(new)])
            target.write_bytes(a)
            g = subprocess.run(['git', 'apply', '--no-index', '--unidiff-zero', '-'], cwd=root,
                               input=q.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            check(g.returncode == 0 and target.read_bytes() == b, (q.stdout, g.stderr))
        return p

    samples = [b'', b'\n', b'x', b'x\n', b'x\r\n', b'a\nb', b'a\nb\n',
               b'\xff\n', 'α\nβ'.encode(), b' \t\r\n\n', b'---\n+++\n@@\n']
    for a in samples:
        for b in samples:
            for context in (0, 1, 3):
                compare(a, b, ['-U', str(context)])
    rng = random.Random(20260911)
    for i in range(200):
        a = [rng.choice([b'a\n', b'b\n', b'c\n', b'\n']) for _ in range(rng.randrange(50))]
        b = a.copy()
        for _ in range(rng.randrange(15)):
            pos = rng.randrange(len(b) + 1)
            b[pos:pos + rng.randrange(4)] = [rng.choice([b'a\n', b'd\n', b'\n'])
                                             for _ in range(rng.randrange(4))]
        compare(b''.join(a), b''.join(b), ['-U', str(rng.randrange(6))])
    compare(b'a\nb\nc\n', b'x\ny\nz\n', ['--max-distance', '0'])
    compare(b'a' * 150000 + b'\nlast', b'a' * 150000 + b'\nlast\n')
    # Distant changes form distinct hunks; touching context merges.
    a = b''.join(f'{i}\n'.encode() for i in range(40))
    p = compare(a, a.replace(b'2\n', b'two\n'), ['-U1'])
    check(p.stdout.count(b'@@ -') == 4, p.stdout)
    old.write_bytes(b'old\n')
    new.write_bytes(b'new\n')
    p = run(['-', str(new)], input=b'old\n')
    check(p.returncode == 1 and b'-old\n+new\n' in p.stdout, p)
    p = run(['-q', str(old), str(new)])
    check(p.returncode == 1 and p.stdout.startswith(b'Files '), p)
    p = run(['--help'])
    check(p.returncode == 0 and b'Exit: 0' in p.stdout, p)
    p = run(['--unified=0', '--label', 'OLD', '--label', 'NEW', str(old), str(new)])
    check(p.returncode == 1 and p.stdout.startswith(b'--- OLD\t\n+++ NEW\t\n'), p)
    dash = root / '-name'
    dash.write_bytes(b'old\n')
    p = run(['--', '-name', 'new file'], cwd=root)
    check(p.returncode == 1, p)
    for args in [[], ['-r'], ['--patch'], ['-w'], ['--max-distance'], ['-U'],
                 ['-U', '-1'], ['--unified='], ['--max-distance', '4097'],
                 ['-U', '9999999999999999999999'], ['-', '-'],
                 [str(old), str(new), str(old)], [str(old), str(root / 'missing')],
                 [str(root), str(new)],
                 ['--label', 'bad\nlabel', str(old), str(new)],
                 ['--label', ''], ['--label', 'a', '--label', 'b', '--label', 'c']]:
        p = run(args)
        check(p.returncode == 2 and p.stderr.startswith(b'spark-diff:'), (args, p))
        check(not p.stdout, (args, p.stdout))
    for name in ['"quote', 'back\\slash', 'white space', 'ümlaut']:
        target = root / name
        old.write_bytes(b'old\n')
        new.write_bytes(b'new\n')
        p = run(['--label', 'a/' + name, '--label', 'b/' + name, str(old), str(new)])
        for command in (['patch', '--batch', '--fuzz=0', '-p1'],
                        ['git', 'apply', '--no-index', '-']):
            target.write_bytes(b'old\n')
            q = subprocess.run(command, input=p.stdout, cwd=root, capture_output=True)
            check(q.returncode == 0 and target.read_bytes() == b'new\n', (name, p.stdout, q))
    old.write_bytes(b'a\0b')
    p = run([str(old), str(new)])
    check(p.returncode == 2 and b'NUL' in p.stderr and not p.stdout, p)
print(f'PASS: {checks} CLI checks (GNU patch and git apply roundtrips)')
