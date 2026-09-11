package body Spark_Diffs with SPARK_Mode is
   function Apply (S : Script; A : Sequence) return Sequence is
      R : Sequence (1 .. Output_Length (S)) := [others => 0];
      N : Natural := 0;
   begin
      for I in S'Range loop
         pragma Loop_Invariant (N = S (I).Target);
         pragma Loop_Invariant (N <= R'Length);
         pragma Loop_Invariant
           (for all J in S'First .. I - 1 =>
              S (J).Target <= N
              and then (if S (J).Kind /= Delete then
                S (J).Target < N
                and then R (S (J).Target + 1) = S (J).Value));
         --  The remaining suffix cannot decrease the output cursor.
         if S (I).Kind /= Delete then
            R (N + 1) := (if S (I).Kind = Keep then A (S (I).Source + 1)
                          else S (I).Value);
            N := N + 1;
         end if;
      end loop;
      return R;
   end Apply;

   procedure Unique (A, B, C : Sequence; S : Script)
     with Ghost, Global => null, Always_Terminates,
     Pre => Describes (A, B, S) and then Describes (A, C, S),
     Post => B = C
   is
      N : Natural := 0;
   begin
      for I in S'Range loop
         pragma Loop_Invariant (N = S (I).Target);
         pragma Loop_Invariant (N <= B'Length);
         pragma Loop_Invariant (for all J in 1 .. N => B (J) = C (J));
         if S (I).Kind /= Delete then
            N := N + 1;
         end if;
      end loop;
   end Unique;

   procedure Diff
     (A, B : Sequence; Work : out Workspace;
      S : out Script; Last : out Natural; Minimal : out Boolean)
   is
      Budget : constant Natural := Work'Last (1);
      Found : Boolean := False;
      Distance : Natural := 0;
      X, Y, Previous_X, Previous_Y, Previous_K : Integer;
      K : Integer;
      Used : Natural := 0;

      procedure Push (Kind : Edit_Kind; Src, Dst : Count; V : Symbol)
        with Pre => S'First = 1 and then Used < S'Length,
        Post => Used = Used'Old + 1
          and then S (Used) = (Kind, Src, Dst, V)
          and then (for all I in 1 .. Used'Old => S (I) = S'Old (I))
      is
      begin
         Used := Used + 1;
         S (Used) := (Kind, Src, Dst, V);
      end Push;
   begin
      S := [others => (Keep, 0, 0, 0)];
      Work := [others => [others => -1]];
      Minimal := False;
      --  Search uses only reachable coordinates; -1 denotes no path.
      for D in 0 .. Budget loop
         pragma Loop_Invariant (Distance <= Budget);
         pragma Loop_Invariant
           (for all Row in Work'Range (1) =>
              (for all Col in Work'Range (2) =>
                 Work (Row, Col) in -1 .. A'Length));
         K := -D;
         while K <= D loop
            pragma Loop_Invariant (Distance <= Budget);
            pragma Loop_Variant (Decreases => D - K);
            pragma Loop_Invariant (K in -D .. D + 2);
            pragma Loop_Invariant
              (for all Row in Work'Range (1) =>
                 (for all Col in Work'Range (2) =>
                    Work (Row, Col) in -1 .. A'Length));
            X := -1;
            if D = 0 then
               X := 0;
            else
               if K > -D and then Work (D - 1, K - 1) >= 0
                 and then Work (D - 1, K - 1) < A'Length
               then
                  X := Work (D - 1, K - 1) + 1;
               end if;
               if K < D and then Work (D - 1, K + 1) >= 0
                 and then Work (D - 1, K + 1) > X
               then
                  X := Work (D - 1, K + 1);
               end if;
            end if;
            Y := X - K;
            if X >= 0 and then Y in 0 .. B'Length then
               while X < A'Length and then Y < B'Length
                 and then A (X + 1) = B (Y + 1)
               loop
                  pragma Loop_Invariant (X in 0 .. A'Length);
                  pragma Loop_Invariant (Y in 0 .. B'Length);
                  pragma Loop_Variant (Decreases => A'Length - X);
                  X := X + 1;
                  Y := Y + 1;
               end loop;
               Work (D, K) := X;
               if X = A'Length and then Y = B'Length then
                  Found := True;
                  Distance := D;
                  exit;
               end if;
            end if;
            K := K + 2;
         end loop;
         exit when Found;
      end loop;

      if Found then
         X := A'Length;
         Y := B'Length;
         for D in reverse 0 .. Distance loop
            pragma Loop_Invariant (X in 0 .. A'Length);
            pragma Loop_Invariant (Y in 0 .. B'Length);
            pragma Loop_Invariant (Used <= S'Length);
            K := X - Y;
            Previous_X := 0;
            Previous_Y := 0;
            if D > 0 then
               --  Defensive guards keep reconstruction total even if the
               --  search changes. The final validator is the proof boundary.
               exit when K not in -D .. D;
               if K = -D or else
                 (K /= D and then Work (D - 1, K - 1) < Work (D - 1, K + 1))
               then
                  Previous_K := K + 1;
               else
                  Previous_K := K - 1;
               end if;
               Previous_X := Work (D - 1, Previous_K);
               Previous_Y := Previous_X - Previous_K;
            end if;
            exit when Previous_X not in 0 .. X or else Previous_Y not in 0 .. Y;
            while X > Previous_X and then Y > Previous_Y loop
               pragma Loop_Invariant (X in 0 .. A'Length);
               pragma Loop_Invariant (Y in 0 .. B'Length);
               pragma Loop_Invariant (Used <= S'Length);
               pragma Loop_Variant (Decreases => X);
               exit when Used = S'Length;
               X := X - 1;
               Y := Y - 1;
               Push (Keep, X, Y, A (X + 1));
            end loop;
            exit when Used = S'Length;
            if D > 0 then
               if X = Previous_X and then Y > 0 then
                  Y := Y - 1;
                  Push (Insert, X, Y, B (Y + 1));
               elsif X > 0 then
                  X := X - 1;
                  Push (Delete, X, Y, A (X + 1));
               end if;
            end if;
         end loop;
         for I in 1 .. Used / 2 loop
            declare
               T : constant Edit := S (I);
            begin
               S (I) := S (Used - I + 1);
               S (Used - I + 1) := T;
            end;
         end loop;
      end if;
      if Found and then Describes (A, B, S (1 .. Used)) then
         Minimal := True;
      else
         for I in S'Range loop
            if I <= A'Length then
               S (I) := (Delete, I - 1, 0, A (I));
            else
               S (I) := (Insert, A'Length, I - A'Length - 1, B (I - A'Length));
            end if;
            pragma Loop_Invariant
              (for all J in 1 .. I =>
                 S (J) = (if J <= A'Length then (Delete, J - 1, 0, A (J))
                          else (Insert, A'Length, J - A'Length - 1, B (J - A'Length))));
         end loop;
         Used := S'Length;
         pragma Assert (Valid (A, S (1 .. Used)));
      end if;
      pragma Assert (Describes (A, B, S (1 .. Used)));
      Last := Used;
      Unique (A, B, Apply (S (1 .. Last), A), S (1 .. Last));
   end Diff;
end Spark_Diffs;
