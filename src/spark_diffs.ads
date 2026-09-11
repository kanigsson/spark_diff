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
       and then Apply (S (1 .. Last), A) = B;
   --  Minimal means the bounded Myers search completed and its script passed
   --  validation. Shortest-edit optimality is tested, not a proved contract.
end Spark_Diffs;
