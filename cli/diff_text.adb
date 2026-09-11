with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;
with Ada.Strings.Fixed;

package body Diff_Text is
   use Ada.Strings.Unbounded;
   use Spark_Diffs;

   procedure Read
     (Path : String; Symbols : in out Dictionary; Result : out Sequence_Access)
   is
      package IO renames Ada.Streams.Stream_IO;
      package Id_Vectors is new Ada.Containers.Vectors (Positive, Symbol);
      Items : Id_Vectors.Vector;
      Pending : Unbounded_String;
      File : IO.File_Type;

      procedure Emit is
         Key : constant String := To_String (Pending);
         Position : constant Id_Maps.Cursor := Symbols.Ids.Find (Key);
         Id : Symbol;
      begin
         if Id_Maps.Has_Element (Position) then
            Id := Id_Maps.Element (Position);
         else
            if Natural (Symbols.Values.Length) = Natural'Last then
               raise Constraint_Error with "too many distinct lines";
            end if;
            Symbols.Values.Append (Pending);
            Id := Symbols.Values.Last_Index;
            Symbols.Ids.Insert (Key, Id);
         end if;
         if Natural (Items.Length) = Max_Length then
            raise Constraint_Error with "too many lines";
         end if;
         Items.Append (Id);
         Pending := Null_Unbounded_String;
      end Emit;

      procedure Read_Stream (Input : access Ada.Streams.Root_Stream_Type'Class) is
         use Ada.Streams;
         Block : Stream_Element_Array (1 .. 64 * 1024);
         Last : Stream_Element_Offset;
         Bytes : String (1 .. Block'Length);
         Start : Positive;
      begin
         loop
            Input.Read (Block, Last);
            exit when Last < Block'First;
            Start := 1;
            for I in 1 .. Natural (Last) loop
               Bytes (I) := Character'Val (Block (Stream_Element_Offset (I)));
               if Bytes (I) = ASCII.NUL then
                  raise Constraint_Error with "NUL byte in input; only text files are supported";
               end if;
               if Bytes (I) = ASCII.LF then
                  Append (Pending, Bytes (Start .. I));
                  Emit;
                  Start := I + 1;
               end if;
            end loop;
            Append (Pending, Bytes (Start .. Natural (Last)));
         end loop;
         if Length (Pending) /= 0 then
            Emit;
         end if;
      end Read_Stream;
   begin
      if Path = "-" then
         Read_Stream (Ada.Text_IO.Text_Streams.Stream (Ada.Text_IO.Standard_Input));
      else
         IO.Open (File, IO.In_File, Path);
         Read_Stream (IO.Stream (File));
         IO.Close (File);
      end if;
      Result := new Sequence (1 .. Natural (Items.Length));
      for I in Result'Range loop
         Result (I) := Items (I);
      end loop;
   exception
      when others =>
         if IO.Is_Open (File) then
            IO.Close (File);
         end if;
         raise;
   end Read;

   procedure Unified
     (S : Script; Symbols : Dictionary;
      Old_Label, New_Label : String; Context : Natural)
   is
      use Ada.Text_IO;
      function Number (N : Natural) return String is
        (Ada.Strings.Fixed.Trim (N'Image, Ada.Strings.Both));
      function Span (Before, Size : Natural) return String is
        (Number (Before + (if Size = 0 then 0 else 1)) & "," & Number (Size));
      function Header_Name (Label : String) return String is
         Quoted : Unbounded_String := To_Unbounded_String ("""");
      begin
         if not (for some C of Label => C = '"' or else C = '\') then
            return Label;
         end if;
         for C of Label loop
            if C = '"' or else C = '\' then
               Append (Quoted, '\');
            end if;
            Append (Quoted, C);
         end loop;
         return To_String (Quoted) & '"';
      end Header_Name;

      procedure Line (E : Edit) is
         Bytes : constant String := To_String (Symbols.Values (E.Value));
         Prefix : constant Character :=
           (case E.Kind is when Keep => ' ', when Delete => '-', when Insert => '+');
      begin
         Put (Prefix);
         Put (Bytes);
         if Bytes'Length = 0 or else Bytes (Bytes'Last) /= ASCII.LF then
            New_Line;
            Put_Line ("\ No newline at end of file");
         end if;
      end Line;
      Cursor : Positive := 1;
      First, Last, Scan : Natural;
      Old_Size, New_Size : Natural;
      Headers : Boolean := False;
   begin
      while Cursor <= S'Last loop
         if S (Cursor).Kind = Keep then
            Cursor := Cursor + 1;
         else
            if not Headers then
               -- A tab separates filenames from the (omitted) timestamp,
               -- allowing spaces in ordinary paths to be parsed by patch.
               Put_Line ("--- " & Header_Name (Old_Label) & ASCII.HT);
               Put_Line ("+++ " & Header_Name (New_Label) & ASCII.HT);
               Headers := True;
            end if;
            First := Natural'Max (1, Cursor - Natural'Min (Context, Cursor - 1));
            Last := Natural'Min (S'Last, Cursor + Context);
            Scan := Cursor + 1;
            while Scan <= S'Last and then Scan <= Last + Context + 1 loop
               if S (Scan).Kind /= Keep then
                  Last := Natural'Min (S'Last, Scan + Context);
               end if;
               Scan := Scan + 1;
            end loop;
            Old_Size := Source_After (S (Last)) - S (First).Source;
            New_Size := Target_After (S (Last)) - S (First).Target;
            Put_Line ("@@ -" & Span (S (First).Source, Old_Size)
                      & " +" & Span (S (First).Target, New_Size) & " @@");
            for I in First .. Last loop
               Line (S (I));
            end loop;
            Cursor := Last + 1;
         end if;
      end loop;
   end Unified;
end Diff_Text;
