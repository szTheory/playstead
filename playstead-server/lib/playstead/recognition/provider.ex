defmodule Playstead.Recognition.Provider do
  @moduledoc """
  The recognition provider behaviour (D-16, D-18). A provider declares
  its own name and version and recognizes a file from the facts
  already known about it — digests, size, original name, and the
  format evidence `Playstead.Formats.identify/2` produced — returning
  a status, a confidence level, and an evidence map.

  `Playstead.Recognition.HeaderEvidence` is the built-in implementation
  that needs no reference data at all; a later plan's DAT-pack provider
  is a drop-in implementation of this same behaviour rather than a
  rewrite of the pipeline.
  """

  @typedoc "The frozen confidence vocabulary (D-18)."
  @type confidence :: :exact | :header | :filename | :user

  @typedoc "One recognition result."
  @type result :: %{
          status: atom(),
          confidence: confidence() | nil,
          reference_name: String.t() | nil,
          evidence: map()
        }

  @doc "The provider's stable name, stored on every evidence row it writes."
  @callback name() :: String.t()

  @doc "The provider's version, so evidence rows record which release produced them."
  @callback version() :: String.t()

  @doc """
  Recognizes one file. `facts` carries whatever the caller already
  knows (digests, size, original name, and provider-specific
  pre-computed signals such as alias/variant candidates); `format_evidence`
  is the `{system_id, tier, evidence}` tuple `Playstead.Formats.identify/2`
  produced, or `nil` when format bytes were unavailable.
  """
  @callback recognize(facts :: map(), format_evidence :: {atom(), atom(), map()} | nil) ::
              result()
end
