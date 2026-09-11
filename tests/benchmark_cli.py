#!/usr/bin/env python3
"""Compare CLI wall time and output bytes against a supplied baseline binary."""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('baseline', type=Path)
parser.add_argument('candidate', type=Path)
parser.add_argument('--runs', type=int, default=5)
args = parser.parse_args()
if args.runs < 1:
    parser.error('--runs must be positive')
binaries = [str(args.baseline.resolve()), str(args.candidate.resolve())]
unique = [f'line {i}\n'.encode() for i in range(20_000)]
changed = unique.copy()
for i in range(10):
    changed[1000 + i * 1800] = f'changed {i}\n'.encode()
workloads = [
    ('20000 unique lines, 10 replacements', b''.join(unique), b''.join(changed)),
    ('20000 repeated lines, 100 deletions', b'x\n' * 20_000, b'x\n' * 19_900),
    ('400 distinct lines per side, fallback',
     b''.join(f'old {i}\n'.encode() for i in range(400)),
     b''.join(f'new {i}\n'.encode() for i in range(400))),
]
results = []
with tempfile.TemporaryDirectory(prefix='spark-diff-timing-') as tmp:
    root = Path(tmp)
    for name, old, new in workloads:
        (root / 'old').write_bytes(old)
        (root / 'new').write_bytes(new)
        samples = [[], []]
        output = None
        # Warm both binaries; then alternate order across measurement rounds.
        for round_no in range(-1, args.runs):
            order = (0, 1) if round_no % 2 == 0 else (1, 0)
            for index in order:
                start = time.perf_counter()
                p = subprocess.run([binaries[index], '--label', 'a/input', '--label', 'b/input',
                                    str(root / 'old'), str(root / 'new')], capture_output=True)
                elapsed = time.perf_counter() - start
                assert p.returncode == 1 and not p.stderr, p
                if output is None:
                    output = p.stdout
                assert output == p.stdout, f'output changed: {name}'
                if round_no >= 0:
                    samples[index].append(elapsed * 1000)
        results.append({'case': name, 'output_bytes': len(output),
                        'baseline_ms': samples[0], 'candidate_ms': samples[1],
                        'baseline_median_ms': statistics.median(samples[0]),
                        'candidate_median_ms': statistics.median(samples[1])})
print(json.dumps({'runs': args.runs, 'binaries': binaries, 'cases': results}, indent=2))
