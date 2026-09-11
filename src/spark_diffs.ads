--  Pure, allocation-free sequence diff. Symbols are caller-defined identities:
--  equal symbols must denote exactly equal elements (e.g. complete line bytes).
package Spark_Diffs with SPARK_Mode, Pure is
   Max_Length : constant := Natural'Last / 4;
   subtype Count is Natural range 0 .. Max_Length;
   subtype Symbol is Natural;
   type Sequence is array (Positive range <>) of Symbol;
   type Edit_Kind is (Keep, Delete, Insert);
   type Edit is record
      Kind   : Edit_Kind := Keep;
      Source : Count := 0; -- elements consumed before this edit
      Target : Count := 0; -- elements produced before this edit
      Value  : Symbol := 0; -- expected old value or inserted value
   end record;
   type Script is array (Positive range <>) of Edit;
   function Source_After (E : Edit) return Natural is
     (E.Source + (if E.Kind = Insert then 0 else 1));
   function Target_After (E : Edit) return Natural is
     (E.Target + (if E.Kind = Delete then 0 else 1));
   function Output_Length (S : Script) return Natural is
     (if S'Length = 0 then 0 else Target_After (S (S'Last)));

   --  Complete, ordered consumption, exact expected source values, and
   --  contiguous output. No fuzzy matching or partial application.
   function Valid (A : Sequence; S : Script) return Boolean is
     (A'First = 1 and then A'Length <= Max_Length
      and then S'First = 1 and then S'Length <= 2 * Max_Length
      and then (if S'Length = 0 then A'Length = 0 else
        S (1).Source = 0 and then S (1).Target = 0
        and then Source_After (S (S'Last)) = A'Length)
      and then (for all I in S'Range =>
        S (I).Source <= A'Length
        and then (if S (I).Kind /= Insert then
          S (I).Source < A'Length
          and then S (I).Value = A (S (I).Source + 1))
        and then Target_After (S (I)) <= Output_Length (S)
        and then (if S (I).Kind /= Delete then S (I).Target < Max_Length)
        and then (if I < S'Last then
          Source_After (S (I)) = S (I + 1).Source
          and then Target_After (S (I)) = S (I + 1).Target)));

   function Describes (A, B : Sequence; S : Script) return Boolean is
     (Valid (A, S) and then B'First = 1
      and then B'Length = Output_Length (S)
      and then (for all I in S'Range =>
        S (I).Target <= B'Length
        and then (if S (I).Kind /= Delete then
          S (I).Target < B'Length
          and then S (I).Value = B (S (I).Target + 1))));

   function Apply (S : Script; A : Sequence) return Sequence
     with Global => null, Pre => Valid (A, S),
     Post => Apply'Result'First = 1
       and then Describes (A, Apply'Result, S);

   --  Caller-owned Myers trace. Bound memory by choosing the distance budget.
   --  Rows are 0 .. Budget, columns -Budget .. Budget. A small budget is valid:
   --  exhaustion gives a complete replacement, never an incomplete script.
   type Workspace is array (Natural range <>, Integer range <>) of Integer;
   function Prefix_Cost (S : Script; N : Natural) return Natural
     with Ghost, Global => null,
     Pre => S'First = 1 and then S'Length <= 2 * Max_Length and then N <= S'Length,
     Post => Prefix_Cost'Result <= N,
     Subprogram_Variant => (Decreases => N);
   function Edit_Cost (S : Script) return Natural
     with Global => null,
     Pre => S'First = 1 and then S'Length <= 2 * Max_Length,
     Post => Edit_Cost'Result = Prefix_Cost (S, S'Length)
       and then Edit_Cost'Result <= S'Length;

   function Workspace_Shape (W : Workspace) return Boolean is
     (W'First (1) = 0 and then W'Last (1) in 0 .. Max_Length
      and then W'First (2) = -W'Last (1) and then W'Last (2) = W'Last (1));
   function Frontier_Values (A : Sequence; W : Workspace) return Boolean is
     (for all R in W'Range (1) =>
        (for all K in W'Range (2) => W (R, K) in -1 .. A'Length));

   --  Upper bounds for one deletion/insertion from a predecessor frontier.
   --  Clipping also accounts for paths that edit before the end of a snake.
   function Delete_Bound (N : Count; V : Integer) return Integer is
     (if V < 0 or else N = 0 then -1 else Integer'Min (V + 1, N))
     with Pre => V in -1 .. N;
   function Insert_Bound (M : Count; K, V : Integer) return Integer is
     (if V < 0 or else M = 0 then -1 else Integer'Min (V, M + K))
     with Pre => K in -Max_Length .. Max_Length and then V in -1 .. Max_Length;

   function Closed (A, B : Sequence; K, V : Integer) return Boolean is
     (V = -1 or else
        (V in 0 .. A'Length and then V - K in 0 .. B'Length
         and then (if V < A'Length and then V - K < B'Length then
           A (V + 1) /= B (V - K + 1))))
     with Pre => A'First = 1 and then B'First = 1
       and then A'Length <= Max_Length and then B'Length <= Max_Length
       and then K in -Max_Length .. Max_Length and then V in -1 .. Max_Length;

   function Certificate_Cell
     (A, B : Sequence; W : Workspace; R : Natural; K : Integer) return Boolean is
     (Closed (A, B, K, W (R, K))
      and then (if K = A'Length - B'Length then W (R, K) < A'Length)
      and then (if R = 0 then W (R, K) >= 0 else
        (if K > -R and then Delete_Bound (A'Length, W (R - 1, K - 1))
            in Integer'Max (0, K) .. Integer'Min (A'Length, B'Length + K)
         then W (R, K) >= Delete_Bound (A'Length, W (R - 1, K - 1)))
        and then
        (if K < R and then Insert_Bound (B'Length, K, W (R - 1, K + 1))
            in Integer'Max (0, K) .. Integer'Min (A'Length, B'Length + K)
         then W (R, K) >= Insert_Bound (B'Length, K, W (R - 1, K + 1)))))
     with Pre => A'First = 1 and then B'First = 1
       and then A'Length <= Max_Length and then B'Length <= Max_Length
       and then Workspace_Shape (W) and then R <= W'Last (1)
       and then K in -R .. R and then Frontier_Values (A, W);

   --  A checked upper frontier for all paths costing less than D, with the
   --  target excluded. This certificate need not describe reachable paths.
   function Lower_Bound (A, B : Sequence; W : Workspace; D : Natural)
     return Boolean is
     (A'First = 1 and then B'First = 1
      and then A'Length <= Max_Length and then B'Length <= Max_Length
      and then Workspace_Shape (W) and then D <= W'Last (1)
      and then Frontier_Values (A, W)
      and then (for all R in 0 .. Integer (D) - 1 =>
        (for all K in -R .. R => Certificate_Cell (A, B, W, R, K))));

   --  Universal minimality theorem: Alternative is any complete script for
   --  the same inputs, not a second run of this algorithm.
   procedure Lemma_Minimal
     (A, B : Sequence; S, Alternative : Script; W : Workspace)
     with Ghost, Global => null, Always_Terminates,
     Pre => Describes (A, B, S) and then Describes (A, B, Alternative)
       and then Lower_Bound (A, B, W, Edit_Cost (S)),
     Post => Edit_Cost (S) <= Edit_Cost (Alternative);

   procedure Diff
     (A, B : Sequence; Work : out Workspace;
      S : out Script; Last : out Natural; Minimal : out Boolean)
     with Global => null, Always_Terminates,
     Pre => A'First = 1 and then B'First = 1
       and then A'Length <= Max_Length and then B'Length <= Max_Length
       and then S'First = 1 and then S'Length = A'Length + B'Length
       and then Work'First (1) = 0 and then Work'Last (1) in 0 .. Max_Length
       and then Work'First (2) = -Work'Last (1)
       and then Work'Last (2) = Work'Last (1),
     Post => Last <= S'Length
       and then Describes (A, B, S (1 .. Last))
       and then Apply (S (1 .. Last), A) = B
       and then (if Minimal then Lower_Bound (A, B, Work, Edit_Cost (S (1 .. Last))));
   --  Minimal certifies a shortest script via Lemma_Minimal. Work retains
   --  the lower-bound certificate after traceback.
end Spark_Diffs;
