with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
with Spark_Diffs;

--  Ordinary Ada adapter: byte framing, exact interning, and unified rendering.
package Diff_Text is
   package Lines is new Ada.Containers.Vectors
     (Positive, Ada.Strings.Unbounded.Unbounded_String,
      Ada.Strings.Unbounded."=");
   package Id_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, Spark_Diffs.Symbol, Ada.Strings.Hash, "=");
   type Dictionary is record
      Ids : Id_Maps.Map;
      Values : Lines.Vector;
   end record;
   type Sequence_Access is access Spark_Diffs.Sequence;
   procedure Read
     (Path : String; Symbols : in out Dictionary; Result : out Sequence_Access);
   procedure Unified
     (S : Spark_Diffs.Script; Symbols : Dictionary;
      Old_Label, New_Label : String; Context : Natural);
end Diff_Text;
