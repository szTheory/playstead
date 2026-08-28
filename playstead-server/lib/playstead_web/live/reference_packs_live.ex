defmodule PlaysteadWeb.ReferencePacksLive do
  @moduledoc """
  `/reference-packs` — the console surface for supplying an
  administrator's own reference pack and reviewing its provenance
  (D-18, D-26, D-32). Follows the import console's idiom exactly: an
  upload, a confirm action that dispatches to the context, and a
  reload from the context on every outcome — never a private path.

  There is no acquisition path anywhere on this page: no button that
  retrieves a file, no search, no catalogue to look through, and no
  link to any source of packs. Sourcing reference data is the
  administrator's own responsibility; Playstead never retrieves,
  bundles, or redistributes one on its own.
  """

  use PlaysteadWeb, :live_view

  alias Playstead.Recognition
  alias Playstead.Recognition.{DatPack, DatPackImporter}
  alias PlaysteadWeb.Problem

  # A reference pack is a text document; 32 MiB comfortably covers the
  # largest real-world Logiqx/No-Intro DAT while still bounding an
  # oversized upload at the browser boundary, matching
  # `Playstead.Recognition.LogiqxHandler`'s own hard cap.
  @max_pack_bytes 33_554_432

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Reference packs",
       license_claims: DatPack.license_claims(),
       just_identified: nil
     )
     |> allow_upload(:pack,
       accept: :any,
       max_entries: 1,
       max_file_size: @max_pack_bytes,
       auto_upload: false
     )
     |> load_packs()}
  end

  defp load_packs(socket) do
    user_id = socket.assigns.current_scope.user.id
    assign(socket, packs: DatPackImporter.list_packs(user_id))
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("import", %{"pack" => pack_params}, socket) do
    user_id = socket.assigns.current_scope.user.id

    results =
      consume_uploaded_entries(socket, :pack, fn %{path: path}, _entry ->
        {:ok, DatPackImporter.import_pack(user_id, path, provenance(pack_params))}
      end)

    case results do
      [{:ok, %DatPack{}}] ->
        %{identified: identified} = Recognition.reidentify(user_id)

        {:noreply,
         socket
         |> assign(:just_identified, identified)
         |> load_packs()}

      [{:error, reason}] ->
        {:noreply,
         socket
         |> assign(:just_identified, nil)
         |> put_flash(:error, refusal_message(reason))}

      [] ->
        {:noreply, put_flash(socket, :error, "Choose a reference pack file first.")}
    end
  end

  @impl true
  def handle_event("remove", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Enum.find(socket.assigns.packs, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, generic_error_flash())}

      pack ->
        case DatPackImporter.remove_pack(pack, user_id) do
          {:ok, _removed} -> {:noreply, load_packs(socket)}
          {:error, _reason} -> {:noreply, put_flash(socket, :error, generic_error_flash())}
        end
    end
  end

  defp provenance(params) do
    %{
      source: blank_to_nil(params["source"]),
      upstream_version: blank_to_nil(params["upstream_version"]),
      license_claim: params["license_claim"] || "unstated",
      license_note: blank_to_nil(params["license_note"]),
      transform_version: "1"
    }
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp refusal_message(:too_large),
    do: "This file is larger than Playstead will read as a reference pack. Nothing was stored."

  defp refusal_message(:dtd_or_entity_declared),
    do:
      "This file declares a document type or entity, which Playstead refuses to process for safety. Nothing was stored."

  defp refusal_message(:entry_cap_exceeded),
    do: "This file has more entries than Playstead will read at once. Nothing was stored."

  defp refusal_message(:malformed),
    do: "This file doesn't look like a valid reference pack. Nothing was stored."

  defp refusal_message(_other),
    do: "This file could not be read as a reference pack. Nothing was stored."

  defp generic_error_flash do
    "Something went wrong on the server. Your data is safe — nothing was changed. " <>
      "Correlation ID: #{Problem.generate_correlation_id()}"
  end

  defp sha_prefix(sha256) when is_binary(sha256), do: String.slice(sha256, 0, 12)
  defp sha_prefix(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0F172A] px-8 py-12 font-sans">
      <Layouts.flash_group flash={@flash} />
      <div class="mx-auto max-w-3xl space-y-8">
        <div>
          <h1 class="text-display font-semibold text-[#F1F5F9]">Reference packs</h1>
          <p class="mt-1 text-sm text-[#94A3B8]">
            Supply your own reference pack to identify games already in your library. Playstead
            never retrieves or bundles one on its own — supplying it is entirely up to you.
          </p>
        </div>

        <section id="import-pack-section" class="rounded-lg border border-[#334155] bg-[#1E293B] p-6">
          <form id="reference-pack-form" phx-change="validate" phx-submit="import">
            <label
              for={@uploads.pack.ref}
              class="flex h-11 w-fit cursor-pointer items-center justify-center rounded-md border border-[#334155] bg-[#1E293B] px-4 text-base font-semibold text-[#F1F5F9] hover:border-[#94A3B8]"
            >
              Choose a reference pack file
            </label>
            <.live_file_input upload={@uploads.pack} class="sr-only" />

            <div
              :for={err <- upload_errors(@uploads.pack)}
              id="pack-upload-error"
              class="mt-4 text-sm text-[#EF4444]"
            >
              {err}
            </div>

            <div :for={entry <- @uploads.pack.entries} class="mt-4">
              <p id={"pack-entry-#{entry.ref}"} class="text-sm text-[#F1F5F9]">{entry.client_name}</p>
            </div>

            <div class="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div>
                <label for="pack_source" class="text-sm font-semibold text-[#94A3B8]">
                  Where this pack came from
                </label>
                <input
                  type="text"
                  id="pack_source"
                  name="pack[source]"
                  class="mt-1 w-full rounded-md border border-[#334155] bg-[#0F172A] p-2 text-sm text-[#F1F5F9]"
                />
              </div>

              <div>
                <label for="pack_upstream_version" class="text-sm font-semibold text-[#94A3B8]">
                  Upstream version
                </label>
                <input
                  type="text"
                  id="pack_upstream_version"
                  name="pack[upstream_version]"
                  class="mt-1 w-full rounded-md border border-[#334155] bg-[#0F172A] p-2 text-sm text-[#F1F5F9]"
                />
              </div>

              <div>
                <label for="pack_license_claim" class="text-sm font-semibold text-[#94A3B8]">
                  Licence claim
                </label>
                <select
                  id="pack_license_claim"
                  name="pack[license_claim]"
                  class="mt-1 w-full rounded-md border border-[#334155] bg-[#0F172A] p-2 text-sm text-[#F1F5F9]"
                >
                  <option :for={claim <- @license_claims} value={claim}>{claim}</option>
                </select>
              </div>

              <div>
                <label for="pack_license_note" class="text-sm font-semibold text-[#94A3B8]">
                  Licence note
                </label>
                <input
                  type="text"
                  id="pack_license_note"
                  name="pack[license_note]"
                  class="mt-1 w-full rounded-md border border-[#334155] bg-[#0F172A] p-2 text-sm text-[#F1F5F9]"
                />
              </div>
            </div>

            <button
              type="submit"
              id="import-pack-submit"
              class="mt-6 h-11 rounded-md bg-[#38BDF8] px-4 text-base font-semibold text-[#0F172A]"
            >
              Import pack
            </button>
          </form>

          <p
            :if={@just_identified}
            id="pack-identified-count"
            class="mt-4 text-sm text-[#94A3B8]"
          >
            {@just_identified} item{if @just_identified != 1, do: "s"} in your library {if @just_identified ==
                                                                                             1,
                                                                                           do: "was",
                                                                                           else:
                                                                                             "were"} newly identified.
          </p>
        </section>

        <section id="installed-packs">
          <h2 class="text-heading font-semibold text-[#F1F5F9]">Installed packs</h2>

          <div
            :if={@packs == []}
            id="packs-empty"
            class="mt-4 rounded-lg border border-[#334155] bg-[#1E293B] p-6"
          >
            <p class="text-base text-[#F1F5F9]">No reference packs installed yet</p>
          </div>

          <div :if={@packs != []} id="pack-list" class="mt-4 space-y-3">
            <div
              :for={pack <- @packs}
              id={"pack-#{pack.id}"}
              class="rounded-lg border border-[#334155] bg-[#1E293B] p-4"
            >
              <p class="text-base font-semibold text-[#F1F5F9]">
                {pack.source || "Unspecified source"}
              </p>
              <p class="mt-1 text-sm text-[#94A3B8]">
                Retrieved {pack.retrieved_at} · Version {pack.upstream_version || "unspecified"} ·
                Hash {sha_prefix(pack.file_sha256)} · {pack.entry_count} entries
              </p>
              <p class="mt-1 text-sm text-[#94A3B8]">
                Licence claim: {pack.license_claim}
                <span :if={pack.license_note}>— {pack.license_note}</span>
              </p>

              <button
                type="button"
                id={"remove-pack-#{pack.id}"}
                phx-click="remove"
                phx-value-id={pack.id}
                data-confirm="Remove this reference pack? Recognition evidence it already produced stays in your library."
                class="mt-2 text-sm text-[#94A3B8] hover:text-[#F1F5F9]"
              >
                Remove
              </button>
            </div>
          </div>
        </section>
      </div>
    </div>
    """
  end
end
