defmodule Playstead.Metadata.MediaDecodeWorker do
  @moduledoc "Bounded adapter to the isolated media decoder. The sidecar owns the shared two-slot admission limit."
  alias Playstead.Metadata.MediaDecoder

  def decode(bytes, mime, opts \\ []) do
    MediaDecoder.decode(bytes, mime, opts)
  end
end
