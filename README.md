# spark-diff

A SPARK sequence diff and exact apply library, with an ordinary Ada CLI for
line-oriented unified diffs. The library proves the roundtrip postcondition:

```ada
Apply (S (1 .. Last), A) = B
```

Here `S` and `Last` are the outputs of `Diff (A, B, ...)`. The theorem covers
both successful bounded Myers searches and the whole-sequence replacement used
when the distance budget is exhausted. There is no patch executable.

## Build and use

Requires a matching GNAT/GNATprove toolchain with Ada 2022 support and GPRbuild.
The library has no third-party dependencies. Build the CLI and tests with:

```sh
make
bin/spark-diff old.adb new.adb
bin/spark-diff -U 5 --label a/file.adb --label b/file.adb old.adb new.adb
bin/spark-diff --max-distance 512 old.txt new.txt
bin/spark-diff -q old.txt new.txt
```

Unified output is the default; `-u` is also accepted. `-U N`, `-UN`, and
`--unified=N` set context, `--label TEXT` supplies each header label in order,
`--` ends options, and one input may be `-` for stdin. See `--help` for bounds.
Exit status is **0 identical, 1 different, 2 trouble**. Unknown options are
errors. This is a text-file comparator; NUL bytes are rejected. It does not
implement recursive comparison or whitespace ignoring.

Lines retain their LF bytes; CR, UTF-8, other non-NUL bytes, and an unterminated
final line are preserved exactly. Missing final newlines are represented by
standard unified-diff markers. Tabs and newlines in paths require safe explicit
header labels. Inputs are opened only for reading. The distinct executable name
avoids replacing the system `diff` on PATH.

## Library API

Import `spark_diff.gpr` and `with Spark_Diffs`. A sequence contains natural-number
symbols: assign equal IDs **if and only if the underlying elements are equal**.
The same API can compare interned lines, tokens, or byte values. The CLI interns
complete line bytes in a dictionary, checking string equality even when hashes
collide. The dictionary is ordinary Ada and outside the proof boundary.

```ada
A : constant Sequence := [10, 20, 30];
B : constant Sequence := [10, 40, 30];
S : Script (1 .. A'Length + B'Length);
W : Workspace (0 .. 8, -8 .. 8);
Last : Natural;
Minimal : Boolean;
-- ...
Diff (A, B, W, S, Last, Minimal);
pragma Assert (Apply (S (1 .. Last), A) = B);
```

All arrays use a lower bound of one, including empty arrays. The workspace has
rows `0 .. Budget` and columns `-Budget .. Budget`. Input lengths are at most
`Max_Length`; the output script buffer has exactly `A'Length + B'Length` slots.
Only `S (1 .. Last)` is the script. Workspace contents are scratch output and
need no initialization. No I/O, access types, or explicit heap allocation occur
in the library. `Apply` returns an array whose result storage is managed by the
Ada caller/runtime; the CLI allocates large search buffers on the heap.

Each `Keep`, `Delete`, or `Insert` includes the consumed source/output counts
before that edit and an expected or inserted symbol. Scripts carry insertion
values, so `Apply` needs no reference to the target sequence. Before applying an
external or modified script, call `Valid (A, S)` and reject `False`.
`Apply` requires this predicate; it does not parse unified text. Validation
requires complete ordered consumption, exact expected source symbols, and
contiguous output. A different source is acceptable only when all expected
symbols still match. There is no fuzzy matching or partial application.

Myers searches increasing insertion/deletion distance with an `O(Budget²)`
trace and worst-case `O((|A| + |B|) * (Budget + 1) + Budget²)` work. The CLI's
default budget is 256 (about 0.5 MiB of trace storage). Every candidate script
is checked by `Describes` before acceptance. Exhaustion or a rejected candidate
produces all deletions followed by all insertions, with the same proved
roundtrip. `Minimal` reports acceptance of the Myers candidate; shortest-edit
optimality is tested against an independent dynamic-programming oracle, **not
formally proved**. A fallback may produce a large diff.

## Verification

```sh
make flow
make prove
make test
make test-contracts
```

`src/` is the complete proof boundary. GNATprove checks runtime safety,
initialization, dependencies, termination, and functional contracts. `Valid`
defines legal complete scripts. `Describes` relates each emitted symbol to the
target. Executable `Apply` proves that its result satisfies that relation; the
ghost `Unique` lemma proves that two results described by the same script are
equal. `Diff` uses this lemma to prove the actual `Apply` roundtrip postcondition.
There are no assumed lemmas, imported axioms, suppressed proof checks, or
unproved bodies in the library.

The line interner, file I/O, option handling, and unified renderer in `cli/` are
outside SPARK. Tests cover their byte fidelity by applying generated diffs with
both GNU `patch --fuzz=0` and `git apply` in temporary directories. Core tests
exhaust short sequences and all relevant budgets, compare against an independent
minimum-edit oracle, replay scripts independently, and reject malformed scripts.
See [validation/README.md](validation/README.md) for recorded results and versions.
