defmodule Playstead.Sync.SavePayload do
  @moduledoc """
  The frozen `save` change-journal payload (D-17), following
  `Playstead.Sync.CurationPayload`'s template (an inner `type` plus a
  frozen key set) and `Playstead.Catalogue.Payload`'s `@frozen_keys`
  discipline exactly. Lineage itself (`parent_revision_id`,
  `save_line_id`) lives in the `save_lines`/`save_revisions` tables and
  not in this payload, because `Playstead.Sync.Compaction.run/0`
  deletes journal rows at 90 days and journal-only lineage would have
  a 90-day event horizon (D-17). Naming, tags, and conversion history
  are deliberately deferred (SEED-001) and never appear here.
  """

  alias Playstead.Saves.Revision

  @frozen_keys ~w(
    type revision_id save_line_id content_key save_kind slot
    parent_revision_id blob_sha256 size_bytes origin_device_id
    device_captured_at recorded_at capture_method adapter_id
    adapter_version save_format format_confidence play_session_id
    base_sha256 base_matched device_reported_now
    device_clock_offset_ms device_monotonic_ms origin
  )a

  @doc "The frozen key set, for tests that assert no accidental additions."
  @spec frozen_keys() :: [atom()]
  def frozen_keys, do: @frozen_keys

  @doc """
  Builds the `save` journal payload for a committed revision. `save`
  (the owning `Playstead.Saves.Save` line) must be preloaded or passed
  alongside so the identity tuple's `content_key`/`save_kind`/`slot`
  can be carried -- the journal payload is the only place a resuming
  client sees the line's own identity, since the line row itself is
  never journaled under its own entity id.
  """
  @spec build(Revision.t(), Playstead.Saves.Save.t()) :: map()
  def build(%Revision{} = revision, %Playstead.Saves.Save{} = save) do
    %{
      type: "revision",
      revision_id: revision.id,
      save_line_id: revision.save_line_id,
      content_key: save.content_key,
      save_kind: save.save_kind,
      slot: save.slot,
      parent_revision_id: revision.parent_revision_id,
      blob_sha256: revision.blob_sha256,
      size_bytes: revision.size_bytes,
      origin_device_id: revision.origin_device_id,
      device_captured_at: revision.device_captured_at,
      recorded_at: revision.recorded_at,
      capture_method: revision.capture_method,
      adapter_id: revision.adapter_id,
      adapter_version: revision.adapter_version,
      save_format: revision.save_format,
      format_confidence: revision.format_confidence,
      play_session_id: revision.play_session_id,
      base_sha256: revision.base_sha256,
      base_matched: revision.base_matched,
      device_reported_now: revision.device_reported_now,
      device_clock_offset_ms: revision.device_clock_offset_ms,
      device_monotonic_ms: revision.device_monotonic_ms,
      origin: revision.origin
    }
  end
end
