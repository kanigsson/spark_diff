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

   function Prefix_Cost (S : Script; N : Natural) return Natural is
     (if N = 0 then 0 else Prefix_Cost (S, N - 1)
      + (if S (N).Kind = Keep then 0 else 1));

   function Edit_Cost (S : Script) return Natural is
      Cost : Natural := 0;
   begin
      for I in S'Range loop
         pragma Loop_Invariant (Cost = Prefix_Cost (S, I - 1));
         if S (I).Kind /= Keep then
            Cost := Cost + 1;
         end if;
      end loop;
      return Cost;
   end Edit_Cost;

   procedure Certificate_Facts
     (A, B : Sequence; W : Workspace; D : Natural)
     with Ghost, Global => null, Always_Terminates,
     Pre => Lower_Bound (A, B, W, D),
     Post => A'First = 1 and then B'First = 1
       and then A'Length <= Max_Length and then B'Length <= Max_Length
       and then Workspace_Shape (W) and then D <= W'Last (1)
       and then Frontier_Values (A, W)
   is
      pragma Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Certificate_Cell);
   begin
      null;
   end Certificate_Facts;

   procedure Get_Cell
     (A, B : Sequence; W : Workspace; D, R : Natural; K : Integer)
     with Ghost, Global => null, Always_Terminates,
     Pre => Lower_Bound (A, B, W, D) and then R < D and then K in -R .. R,
     Post => Certificate_Cell (A, B, W, R, K)
   is
      pragma Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Certificate_Cell);
   begin
      null;
   end Get_Cell;

   procedure Lemma_Lower_Bound
     (A, B : Sequence; S : Script; W : Workspace; D : Natural)
     with Ghost, Global => null, Always_Terminates,
     Pre => Describes (A, B, S) and then Lower_Bound (A, B, W, D),
     Post => D <= Edit_Cost (S)
   is
      pragma Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Lower_Bound);
      X, Y, Cost : Natural := 0;
      K : Integer := 0;
   begin
      Certificate_Facts (A, B, W, D);
      if D > 0 then
         Get_Cell (A, B, W, D, 0, 0);
      end if;
      for I in S'Range loop
         pragma Loop_Invariant (X = S (I).Source and then Y = S (I).Target);
         pragma Loop_Invariant (X <= A'Length and then Y <= B'Length);
         pragma Loop_Invariant (Cost = Prefix_Cost (S, I - 1));
         pragma Loop_Invariant (K = X - Y and then K in -Cost .. Cost);
         pragma Loop_Invariant (if Cost < D then X <= W (Cost, K));
         if Cost < D then
            Get_Cell (A, B, W, D, Cost, K);
         end if;
         if S (I).Kind = Keep then
            if Cost < D then
               pragma Assert (Closed (A, B, K, W (Cost, K)));
               pragma Assert (X < W (Cost, K));
            end if;
            X := X + 1;
            Y := Y + 1;
         elsif S (I).Kind = Delete then
            if Cost + 1 < D then
               pragma Assert (X + 1 <= Delete_Bound (A'Length, W (Cost, K)));
               Get_Cell (A, B, W, D, Cost + 1, K + 1);
               pragma Assert (Delete_Bound (A'Length, W (Cost, K)) in
                 Integer'Max (0, K + 1) .. Integer'Min (A'Length, B'Length + K + 1));
               pragma Assert (X + 1 <= W (Cost + 1, K + 1));
            end if;
            X := X + 1;
            K := K + 1;
            Cost := Cost + 1;
         else
            if Cost + 1 < D then
               pragma Assert (X <= Insert_Bound (B'Length, K - 1, W (Cost, K)));
               Get_Cell (A, B, W, D, Cost + 1, K - 1);
               pragma Assert (Insert_Bound (B'Length, K - 1, W (Cost, K)) in
                 Integer'Max (0, K - 1) .. Integer'Min (A'Length, B'Length + K - 1));
               pragma Assert (X <= W (Cost + 1, K - 1));
            end if;
            Y := Y + 1;
            K := K - 1;
            Cost := Cost + 1;
         end if;
      end loop;
      pragma Assert (X = A'Length and then Y = B'Length);
      if Cost < D then
         Get_Cell (A, B, W, D, Cost, K);
      end if;
      pragma Assert (Cost >= D);
   end Lemma_Lower_Bound;

   procedure Lemma_Minimal
     (A, B : Sequence; S, Alternative : Script; W : Workspace)
   is
      pragma Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Lower_Bound);
   begin
      Lemma_Lower_Bound (A, B, Alternative, W, Edit_Cost (S));
   end Lemma_Minimal;

   procedure Complete_Certificate
     (A, B : Sequence; W : in out Workspace; D : Natural)
     with Global => null, Always_Terminates,
     Pre => A'First = 1 and then B'First = 1
       and then A'Length <= Max_Length and then B'Length <= Max_Length
       and then Workspace_Shape (W) and then D <= W'Last (1)
       and then Frontier_Values (A, W),
     Post => Frontier_Values (A, W)
   is
      X, Y, Candidate : Integer;
   begin
      for R in 0 .. Integer (D) - 1 loop
         pragma Loop_Invariant (Frontier_Values (A, W));
         for K in -R .. R loop
            pragma Loop_Invariant (Frontier_Values (A, W));
            X := (if R = 0 then 0 else -1);
            if R > 0 then
               if K > -R then
                  Candidate := Delete_Bound (A'Length, W (R - 1, K - 1));
                  if Candidate in Integer'Max (0, K) .. Integer'Min (A'Length, B'Length + K) then
                     X := Candidate;
                  end if;
               end if;
               if K < R then
                  Candidate := Insert_Bound (B'Length, K, W (R - 1, K + 1));
                  if Candidate in Integer'Max (0, K) .. Integer'Min (A'Length, B'Length + K) then
                     X := Integer'Max (X, Candidate);
                  end if;
               end if;
            end if;
            --  Most original Myers cells already satisfy the bound. Only
            --  clipped boundary paths need additional snake traversal.
            if W (R, K) < X or else not Closed (A, B, K, W (R, K)) then
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
                  W (R, K) := X;
               else
                  W (R, K) := -1;
               end if;
            end if;
         end loop;
      end loop;
   end Complete_Certificate;

   procedure Diff
     (A, B : Sequence; Work : out Workspace;
      S : out Script; Last : out Natural; Minimal : out Boolean)
   is
      pragma Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Lower_Bound);
      Budget : constant Natural := Work'Last (1);
      Found : Boolean := False;
      Distance : Natural := 0;
      X, Y, Previous_X, Previous_Y, Previous_K : Integer;
      K : Integer;
      Used : Natural := 0;
      Usable : Boolean;

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
      --  Certification gates the Minimal claim only. A reconstructed script
      --  that validates is kept even when no certificate is obtained; the
      --  fallback is reserved for a search that produced nothing usable.
      Usable := Found and then Describes (A, B, S (1 .. Used));
      if Usable and then Edit_Cost (S (1 .. Used)) <= Budget then
         Complete_Certificate (A, B, Work, Edit_Cost (S (1 .. Used)));
         Minimal := Lower_Bound (A, B, Work, Edit_Cost (S (1 .. Used)));
      end if;
      if not Usable then
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
