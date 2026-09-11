with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Diff_Text;
with Spark_Diffs;

procedure Spark_Diff_Cli is
   use Ada.Command_Line;
   use Ada.Strings.Unbounded;
   use Spark_Diffs;
   Paths : array (1 .. 2) of Unbounded_String;
   Labels : array (1 .. 2) of Unbounded_String;
   Path_Count, Label_Count : Natural := 0;
   Context : Natural := 3;
   Budget : Natural := 256;
   Brief, Options_Done : Boolean := False;
   Arg : Positive := 1;

   procedure Help is
      use Ada.Text_IO;
   begin
      Put_Line ("Usage: spark-diff [OPTIONS] OLD NEW");
      Put_Line ("Compare text files by exact line bytes; '-' reads stdin once.");
      Put_Line ("  -u, --unified       unified output (the default)");
      Put_Line ("  -U N, --unified=N   context lines (0..1000000; default 3)");
      Put_Line ("  -q, --brief         report only whether files differ");
      Put_Line ("  --label TEXT        old/new header label, repeated at most twice");
      Put_Line ("  --max-distance N    Myers budget (0..4096; default 256)");
      Put_Line ("  --help              show this help");
      Put_Line ("  --                  end options");
      Put_Line ("Exit: 0 identical, 1 different, 2 trouble. NUL input is rejected.");
      Put_Line ("Budget exhaustion emits a whole-file replacement. No patch command.");
   end Help;

   function Next return String is
   begin
      if Arg = Argument_Count then
         raise Constraint_Error with "missing value for " & Argument (Arg);
      end if;
      Arg := Arg + 1;
      return Argument (Arg);
   end Next;

   function Number (Value : String; Limit : Natural) return Natural is
      N : Natural := 0;
   begin
      if Value'Length = 0 then
         raise Constraint_Error with "empty numeric option";
      end if;
      for C of Value loop
         if C not in '0' .. '9' or else N > Limit / 10 then
            raise Constraint_Error with "invalid numeric option: " & Value;
         end if;
         N := N * 10 + Character'Pos (C) - Character'Pos ('0');
         if N > Limit then
            raise Constraint_Error with "numeric option exceeds limit: " & Value;
         end if;
      end loop;
      return N;
   end Number;

   procedure Check_Label (Value : String) is
   begin
      for C of Value loop
         if C = ASCII.HT or else C = ASCII.LF or else C = ASCII.CR
           or else C = ASCII.NUL
         then
            raise Constraint_Error with "header labels cannot contain tabs, newlines, or NUL";
         end if;
      end loop;
      if Value'Length = 0 then
         raise Constraint_Error with "header labels cannot be empty";
      end if;
   end Check_Label;

begin
   while Arg <= Argument_Count loop
      declare
         A : constant String := Argument (Arg);
      begin
         if not Options_Done and then A = "--" then
            Options_Done := True;
         elsif not Options_Done and then A = "--help" then
            Help;
            return;
         elsif not Options_Done and then (A = "-u" or else A = "--unified") then
            null;
         elsif not Options_Done and then (A = "-q" or else A = "--brief") then
            Brief := True;
         elsif not Options_Done and then A = "-U" then
            Context := Number (Next, 1_000_000);
         elsif not Options_Done and then A'Length > 2 and then A (1 .. 2) = "-U" then
            Context := Number (A (3 .. A'Last), 1_000_000);
         elsif not Options_Done and then A'Length >= 10
           and then A (1 .. 10) = "--unified="
         then
            Context := Number (A (11 .. A'Last), 1_000_000);
         elsif not Options_Done and then A = "--max-distance" then
            Budget := Number (Next, 4096);
         elsif not Options_Done and then A = "--label" then
            if Label_Count = 2 then
               raise Constraint_Error with "--label may occur at most twice";
            end if;
            Label_Count := Label_Count + 1;
            Labels (Label_Count) := To_Unbounded_String (Next);
         elsif not Options_Done and then A'Length > 1 and then A (1) = '-' then
            raise Constraint_Error with "unknown option: " & A & "; see --help";
         else
            if Path_Count = 2 then
               raise Constraint_Error with "expected exactly two input paths; see --help";
            end if;
            Path_Count := Path_Count + 1;
            Paths (Path_Count) := To_Unbounded_String (A);
         end if;
      end;
      Arg := Arg + 1;
   end loop;
   if Path_Count /= 2 then
      raise Constraint_Error with "expected exactly two input paths; see --help";
   end if;
   if Paths (1) = "-" and then Paths (2) = "-" then
      raise Constraint_Error with "stdin may be used only once";
   end if;
   for I in 1 .. 2 loop
      if I > Label_Count then
         Labels (I) := Paths (I);
      end if;
      Check_Label (To_String (Labels (I)));
   end loop;
   declare
      Symbols : Diff_Text.Dictionary;
      A, B : Diff_Text.Sequence_Access;
      type Script_Access is access Script;
      type Work_Access is access Workspace;
      S : Script_Access;
      Work : Work_Access;
      Last : Natural;
      Minimal : Boolean;
   begin
      Diff_Text.Read (To_String (Paths (1)), Symbols, A);
      Diff_Text.Read (To_String (Paths (2)), Symbols, B);
      if A.all = B.all then
         return;
      end if;
      if Brief then
         Ada.Text_IO.Put_Line
           ("Files " & To_String (Paths (1)) & " and " & To_String (Paths (2)) & " differ");
      else
         Budget := Natural'Min (Budget, A'Length + B'Length);
         S := new Script (1 .. A'Length + B'Length);
         Work := new Workspace (0 .. Budget, -Budget .. Budget);
         Diff (A.all, B.all, Work.all, S.all, Last, Minimal);
         Diff_Text.Unified (S (1 .. Last), Symbols,
                            To_String (Labels (1)), To_String (Labels (2)), Context);
      end if;
      Set_Exit_Status (1);
   end;
exception
   when E : others =>
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
                           "spark-diff: " & Ada.Exceptions.Exception_Message (E));
      Set_Exit_Status (2);
end Spark_Diff_Cli;
