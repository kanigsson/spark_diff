# Validation — 2026-09-11

All commands completed with exit status 0 for the sources recorded in
[source-sha256.txt](source-sha256.txt).

| Command | Result | Evidence |
|---|---|---|
| `make flow` | All 45 flow checks proved | [flow.log](flow.log) |
| `make prove` | All 545 checks proved, including roundtrip and minimality | [prove.log](prove.log) |
| `make test` | 119,734 core cases / 2,448,265 checks; 3,363 CLI checks | [test.log](test.log) |
| `make test-contracts` | Same tests passed with library runtime contracts enabled | [test-contracts.log](test-contracts.log) |

The proof invocation was:

```sh
gnatprove -P spark_diff.gpr --level=2 --timeout=20 --prover=cvc5,z3 --counterexamples=off -j4
```

The project enables `--warnings=error` and `--checks-as-errors=on`. There are no
remaining proof warnings or unproved checks. This proves exact symbol-sequence
reconstruction and certificate-backed minimality. It does not prove that every
within-budget optimum is certified, nor line interning or unified-text rendering.

Core tests exhaust all pairs of ternary sequences of length 0 through 4 and
every budget from zero through the sum of the lengths. They also run 1,000
seeded random pairs up to length 64 at full and restricted budgets, symbol
boundary cases, and malformed-script rejection. The minimum edit count comes
from an independent dynamic-programming oracle. The tests require Myers to
succeed exactly when that count fits the budget, so an implementation that
always falls back does not pass. For every pair of ternary sequences of length
zero through two, a second test enumerates all complete competing scripts and
invokes the minimality lemma; ghost calls execute in the contracts build.
Certificate mutations cover missing origins, open matching runs, premature
target reachability, insufficient workspace, and invalid integer bounds.

CLI tests replay generated output with GNU `patch --fuzz=0` and `git apply`
in temporary directories. Cases include empty inputs, insertions, deletions,
repetition, separated and adjacent hunks, zero context, CRLF, UTF-8 and non-UTF-8
bytes, missing final newlines, long lines crossing read-buffer boundaries,
stdin, fallback, quoted filenames, bad options, unreadable inputs, and NUL
rejection. Input files are checked for unintended modifications.

The verified toolchain uses GNAT Pro 27.0w (20260909-153), GPRbuild Pro 27.0w
(20260909), the local GNATprove development build identifying itself as `0.0w`,
Why3 1.8.2+git, cvc5 1.3.2, and Z3 4.15.4. Exact executable paths, hashes, and
version output are in [toolchain.txt](toolchain.txt).

## Certification overhead

[benchmark_cli.py](../tests/benchmark_cli.py) compares complete CLI runs against
the initial commit `3b942c9`. Five interleaved runs per workload, after warmup,
produced identical output bytes. Medians in milliseconds were:

| Input | Baseline | With certification |
|---|---:|---:|
| 20,000 unique lines, 10 replacements | 16.59 | 16.33 |
| 20,000 repeated lines, 100 deletions | 9.94 | 9.91 |
| 400 distinct lines per side, fallback | 3.39 | 3.37 |

These short end-to-end timings include process startup and input handling;
the variation does not establish a speed improvement or a general overhead
bound. Raw samples are in [minimality-timing.json](minimality-timing.json).
Reproduce with separately built baseline and candidate executables:

```sh
python3 tests/benchmark_cli.py /path/to/baseline/spark-diff bin/spark-diff
```
