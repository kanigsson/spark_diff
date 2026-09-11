with Spark_Diffs;
with Ada.Text_IO;
with Ada.Numerics.Discrete_Random;

procedure Test_Diff is
   use Spark_Diffs;
   Checks, Cases : Natural := 0;
   procedure Check (Condition : Boolean) is
   begin
      Checks := Checks + 1;
      if not Condition then
         raise Program_Error with "check" & Checks'Image & " failed";
      end if;
   end Check;

   --  Independent dynamic-programming oracle, not Myers' recurrence.
   function Optimal (A, B : Sequence) return Natural is
      type Table is array (Natural range <>, Natural range <>) of Natural;
      T : Table (0 .. A'Length, 0 .. B'Length);
   begin
      for I in 0 .. A'Length loop
         T (I, 0) := I;
      end loop;
      for J in 0 .. B'Length loop
         T (0, J) := J;
      end loop;
      for I in A'Range loop
         for J in B'Range loop
            T (I, J) := (if A (I) = B (J) then T (I - 1, J - 1)
                         else 1 + Natural'Min (T (I - 1, J), T (I, J - 1)));
         end loop;
      end loop;
      return T (A'Length, B'Length);
   end Optimal;

   procedure Test (A, B : Sequence; Budget : Natural) is
      W : Workspace (0 .. Budget, -Budget .. Budget);
      S : Script (1 .. A'Length + B'Length);
      Last : Natural;
      Minimal : Boolean;
      Expected : constant Natural := Optimal (A, B);
      X, Y, Cost : Natural := 0;
   begin
      Cases := Cases + 1;
      Diff (A, B, W, S, Last, Minimal);
      Check (Valid (A, S (1 .. Last)));
      Check (Apply (S (1 .. Last), A) = B);
      Check (Minimal = (Expected <= Budget));
      if Minimal then
         Check (Lower_Bound (A, B, W, Edit_Cost (S (1 .. Last))));
      end if;
      --  Sequential replay without the production validator or Apply.
      for E of S (1 .. Last) loop
         Check (E.Source = X and E.Target = Y);
         case E.Kind is
            when Keep =>
               X := X + 1;
               Y := Y + 1;
               Check (A (X) = B (Y) and E.Value = A (X));
            when Delete =>
               X := X + 1;
               Cost := Cost + 1;
               Check (E.Value = A (X));
            when Insert =>
               Y := Y + 1;
               Cost := Cost + 1;
               Check (E.Value = B (Y));
         end case;
      end loop;
      Check (X = A'Length and Y = B'Length);
      Check (Cost = (if Minimal then Expected else A'Length + B'Length));
      if Last > 0 then
         S (1).Source := 1;
         Check (not Valid (A, S (1 .. Last)));
      end if;
   end Test;

   function Decode (Length, Code : Natural) return Sequence is
      S : Sequence (1 .. Length);
      N : Natural := Code;
   begin
      for E of S loop
         E := N mod 3;
         N := N / 3;
      end loop;
      return S;
   end Decode;

   procedure All_Alternatives (A, B : Sequence) is
      Budget : constant Natural := A'Length + B'Length;
      W : Workspace (0 .. Budget, -Budget .. Budget);
      Best, Other : Script (1 .. Budget);
      Last : Natural;
      Minimal : Boolean;
      procedure Visit (X, Y, Used : Natural) is
      begin
         if X = A'Length and Y = B'Length then
            Check (Describes (A, B, Other (1 .. Used)));
            Lemma_Minimal (A, B, Best (1 .. Last), Other (1 .. Used), W);
            Check (Edit_Cost (Best (1 .. Last)) <= Edit_Cost (Other (1 .. Used)));
            return;
         end if;
         if X < A'Length and then Y < B'Length and then A (X + 1) = B (Y + 1) then
            Other (Used + 1) := (Keep, X, Y, A (X + 1));
            Visit (X + 1, Y + 1, Used + 1);
         end if;
         if X < A'Length then
            Other (Used + 1) := (Delete, X, Y, A (X + 1));
            Visit (X + 1, Y, Used + 1);
         end if;
         if Y < B'Length then
            Other (Used + 1) := (Insert, X, Y, B (Y + 1));
            Visit (X, Y + 1, Used + 1);
         end if;
      end Visit;
   begin
      Diff (A, B, W, Best, Last, Minimal);
      Check (Minimal);
      Visit (0, 0, 0);
   end All_Alternatives;

   subtype Draw is Natural range 0 .. 1000;
   package Randoms is new Ada.Numerics.Discrete_Random (Draw);
   Gen : Randoms.Generator;
begin
   for N in 0 .. 4 loop
      for M in 0 .. 4 loop
         for AC in 0 .. 3 ** N - 1 loop
            for BC in 0 .. 3 ** M - 1 loop
               for Budget in 0 .. N + M loop
                  Test (Decode (N, AC), Decode (M, BC), Budget);
               end loop;
            end loop;
         end loop;
      end loop;
   end loop;
   for N in 0 .. 2 loop
      for M in 0 .. 2 loop
         for AC in 0 .. 3 ** N - 1 loop
            for BC in 0 .. 3 ** M - 1 loop
               All_Alternatives (Decode (N, AC), Decode (M, BC));
            end loop;
         end loop;
      end loop;
   end loop;
   declare
      A : constant Sequence := [1];
      B : constant Sequence := [2];
      W : Workspace (0 .. 2, -2 .. 2);
      S : Script (1 .. 2);
      Last : Natural;
      Minimal : Boolean;
   begin
      Diff (A, B, W, S, Last, Minimal);
      Check (Minimal and Lower_Bound (A, B, W, 2));
      Check (not Lower_Bound (A, A, W, 1)); -- matching snake is not closed
      Check (not Lower_Bound (A, B, W, 3)); -- certificate too small
      W (0, 0) := -1;
      Check (not Lower_Bound (A, B, W, 2)); -- missing origin
      W (0, 0) := 1;
      Check (not Lower_Bound (A, B, W, 2)); -- target reached too early
      W (0, 0) := Integer'Last;
      Check (not Lower_Bound (A, B, W, 2)); -- malformed bound, no overflow
   end;
   Randoms.Reset (Gen, 20260911);
   for Iteration in 1 .. 1000 loop
      declare
         A : Sequence (1 .. Randoms.Random (Gen) mod 65);
         B : Sequence (1 .. Randoms.Random (Gen) mod 65);
      begin
         for E of A loop
            E := Randoms.Random (Gen) mod 13;
         end loop;
         for E of B loop
            E := Randoms.Random (Gen) mod 13;
         end loop;
         Test (A, B, A'Length + B'Length);
         Test (A, B, Randoms.Random (Gen) mod 16);
      end;
   end loop;
   Test ([0, Natural'Last, 1], [Natural'Last, 0], 5);
   --  Malformed external scripts: incomplete source, wrong expected values,
   --  output gaps, duplicates, and noncanonical lower bounds.
   Check (not Valid ([7], Script'[]));
   Check (not Valid ([7], [(Delete, 0, 0, 8)]));
   Check (not Valid ([7], [(Keep, 0, 1, 7)]));
   Check (not Valid (Sequence'[], [(Insert, 0, 0, 7), (Insert, 0, 0, 8)]));
   Check (not Valid ([7], [(Keep, 0, 0, 7), (Insert, 1, 2, 8)]));
   Check (not Valid ([7], Script'(2 => (Keep, 0, 0, 7))));
   Check (not Valid (Sequence'(2 => 7), Script'[]));
   Check (not Valid (Sequence'[], [(Insert, 0, Max_Length, 7)]));
   Ada.Text_IO.Put_Line ("PASS:" & Cases'Image & " cases," & Checks'Image & " checks");
end Test_Diff;
