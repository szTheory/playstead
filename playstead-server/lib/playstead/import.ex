defmodule Playstead.Import do
  @moduledoc """
  The import pipeline context: turns one uploaded/read source file into
  a `Playstead.Import.SourceFile` row, a `Playstead.Blobs.Blob` (when
  new), a minimal `Playstead.Catalogue.AssetSet`/`AssetMember`, and a
  `Playstead.Import.Receipt` — all in one transaction (`import_single/3`,
  task 2). Recognition and the reimport path are filled in by tasks 2
  and 3.
  """
end
