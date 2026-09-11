# Minimality proof

`Edit_Cost` counts insertions and deletions; keeps cost zero. A replacement is
one deletion plus one insertion. The public ghost procedure `Lemma_Minimal`
proves this contract for an arbitrary competing script:

```ada
Pre  => Describes (A, B, S)
        and then Describes (A, B, Alternative)
        and then Lower_Bound (A, B, W, Edit_Cost (S)),
Post => Edit_Cost (S) <= Edit_Cost (Alternative)
```

`Diff` guarantees the certificate precondition whenever it returns
`Minimal = True`. Thus the theorem applies to its returned script and **every**
valid alternative, including scripts produced by other algorithms. It does not
compare two executions of Myers or assume that Myers is optimal.

## Certificate

A path position `(x, y)` means that `x` source elements have been consumed and
`y` target elements produced. Its diagonal is `k = x - y`. At cost `r`, any path
must have `-r <= k <= r`. The table entry `W(r, k)` is an upper bound on the
source coordinate of such a path, after any number of matching keeps.

For every row below the claimed cost `D`, `Lower_Bound` checks:

- The origin is covered in row zero.
- Entries cover the clipped upper bounds from predecessor insertion/deletion
  edges. Predecessor coordinates may be earlier than their frontier endpoint.
- Every nonempty frontier lies inside the input grid and is closed under keeps:
  it ends at an input boundary or at unequal next symbols.
- The target `(A'Length, B'Length)` is excluded.

An entry need not itself describe a reachable point. An overestimate is safe:
excluding the target even from the overestimate still excludes all real paths.

## Induction over an arbitrary script

`Lemma_Lower_Bound` maintains the script's consumed and produced positions,
its exact prefix cost, and this invariant:

```ada
if Cost < D then X <= W (Cost, X - Y)
```

A keep preserves the row and diagonal. If the path were already at its frontier,
the required equal next symbols would contradict frontier closure; therefore
the keep remains behind the frontier. An insertion or deletion moves to the
next row and adjacent diagonal, whose predecessor bound covers that step.

At the end, `Describes` places the path at the target. A cost below `D` would
contradict the target-exclusion condition. Hence every competing script costs
at least `D`. Instantiating `D` with the returned script's cost proves minimality.
The recursive ghost `Prefix_Cost` connects the induction counter to executable
`Edit_Cost`.

## Producing the certificate

The original bounded Myers trace omits some paths near input boundaries. For
example, after greedily keeping a one-symbol input, deleting that symbol is no
longer possible at the frontier endpoint, although deleting it before the keep
is a legal path. The lower-bound proof must still cover that earlier edit.

After traceback, `Complete_Certificate` augments these cells using clipped
predecessor bounds and extends matching runs where needed. Existing closed
cells already covering their bounds are retained. The existing workspace is
reused, and the resulting certificate is checked before `Minimal` can become
true. Validation gates only that claim: a script the candidate check already
accepted is returned either way, and the whole-sequence fallback is reserved
for a search that produced no acceptable candidate. Both retain the proved
roundtrip property.

Certificate generation is proved free of runtime errors and terminating; its
success for every within-budget optimum is **not** a proved postcondition.
Soundness of accepted certificates and the minimality theorem are proved.
Exhaustive and seeded tests require successful certification whenever the
independent optimum fits the budget, and enumerate competing scripts for small
inputs. Malformed-certificate tests exercise rejection.

The edit-graph formulation follows [Myers' 1986 paper](https://publications.mpi-cbg.de/Myers_1986_6330.pdf).
The checked-certificate construction and SPARK induction above are this
implementation's proof structure.
