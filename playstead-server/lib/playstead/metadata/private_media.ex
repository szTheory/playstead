defmodule Playstead.Metadata.PrivateMedia.Item do
  @moduledoc "Private, owner-scoped source media and optional safe derivative."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "metadata_media" do
    field :user_id, :id
    belongs_to :asset_set, Playstead.Catalogue.AssetSet
    field :original_sha256, :string
    field :original_size_bytes, :integer
    field :original_mime, :string
    field :derived_sha256, :string
    field :derived_size_bytes, :integer
    field :provenance, :map, default: %{}
    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :user_id,
      :asset_set_id,
      :original_sha256,
      :original_size_bytes,
      :original_mime,
      :derived_sha256,
      :derived_size_bytes,
      :provenance
    ])
    |> validate_required([
      :user_id,
      :asset_set_id,
      :original_sha256,
      :original_size_bytes,
      :original_mime
    ])
    |> validate_number(:original_size_bytes,
      greater_than: 0,
      less_than_or_equal_to: 20 * 1024 * 1024
    )
    |> validate_inclusion(:original_mime, ["text/plain", "image/png", "image/jpeg"])
    |> foreign_key_constraint(:asset_set_id)
    |> check_constraint(:original_size_bytes, name: :metadata_media_original_size_positive)
    |> check_constraint(:derived_sha256, name: :metadata_media_derived_pair)
    |> check_constraint(:original_mime, name: :metadata_media_kind_valid)
  end
end

defmodule Playstead.Metadata.PrivateMedia do
  @moduledoc "Stores private metadata source bytes and image derivatives outside game/save identity."
  import Ecto.Query, warn: false
  alias Playstead.{Blobs, Repo}
  alias Playstead.Catalogue.AssetSet
  alias Playstead.Metadata.PrivateMedia.Item

  @image_max 20 * 1024 * 1024
  @text_max 65_536
  @max_items 10

  def create(user_id, asset_set_id, bytes, mime, opts \\ [])

  def create(user_id, asset_set_id, bytes, mime, opts)
      when is_integer(user_id) and is_binary(asset_set_id) and is_binary(bytes) do
    with {:ok, uuid} <- Ecto.UUID.cast(asset_set_id),
         :ok <- validate(bytes, mime),
         :ok <-
           validate_provenance(
             Keyword.get(opts, :provenance, %{source: "user_upload", validated: true})
           ),
         :ok <- owned_asset_set(user_id, uuid),
         {:ok, derived} <- decode_if_image(bytes, mime, opts) do
      Repo.transaction(fn ->
        asset_set =
          Repo.one(
            from a in AssetSet, where: a.id == ^uuid and a.user_id == ^user_id, lock: "FOR UPDATE"
          )

        if is_nil(asset_set), do: Repo.rollback(:not_found)

        count =
          Repo.aggregate(
            from(i in Item, where: i.user_id == ^user_id and i.asset_set_id == ^uuid),
            :count
          )

        if count >= @max_items, do: Repo.rollback(:media_limit_reached)

        # Validate the complete manifest before publishing immutable CAS bytes.
        # The asset-set row lock stays held through admission, writes and insert,
        # so concurrent uploads cannot both pass the ten-item limit.
        original_sha256 = sha256(bytes)
        derivative_sha256 = if derived, do: sha256(derived), else: nil

        attrs = %{
          user_id: user_id,
          asset_set_id: uuid,
          original_sha256: original_sha256,
          original_size_bytes: byte_size(bytes),
          original_mime: mime,
          derived_sha256: derivative_sha256,
          derived_size_bytes: if(derived, do: byte_size(derived), else: nil),
          provenance: Keyword.get(opts, :provenance, %{source: "user_upload", validated: true})
        }

        changeset = Item.changeset(%Item{}, attrs)

        unless changeset.valid?, do: Repo.rollback(changeset)

        case Repo.insert(changeset) do
          {:ok, item} ->
            # Do the fallible manifest insert before CAS publication. The
            # row is still inside this transaction and rolls back if either
            # object cannot be stored, while a rejected insert cannot strand
            # newly published canonical bytes.
            original =
              case put(bytes) do
                {:ok, blob} -> blob
                {:error, reason} -> Repo.rollback(reason)
              end

            derivative =
              case put_derived(derived) do
                {:ok, blob} -> blob
                {:error, reason} -> Repo.rollback(reason)
              end

            unless original.sha256 == original_sha256 and
                     (is_nil(derivative) or derivative.sha256 == derivative_sha256) do
              Repo.rollback(:blob_digest_mismatch)
            end

            item

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
      |> case do
        {:ok, item} -> {:ok, item}
        {:error, reason} -> {:error, reason}
      end
    else
      :error -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def create(_, _, _, _, _), do: {:error, :invalid_media}

  def list(user_id, asset_set_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(asset_set_id),
         true <- Repo.exists?(from a in AssetSet, where: a.id == ^uuid and a.user_id == ^user_id) do
      {:ok,
       Repo.all(
         from i in Item,
           where: i.user_id == ^user_id and i.asset_set_id == ^uuid,
           order_by: [asc: i.inserted_at]
       )}
    else
      _ -> {:error, :not_found}
    end
  end

  def fetch_original(user_id, asset_set_id, media_id),
    do: fetch(user_id, asset_set_id, media_id, :original_sha256)

  def fetch_derived(user_id, asset_set_id, media_id),
    do: fetch(user_id, asset_set_id, media_id, :derived_sha256)

  def remove_derived(user_id, asset_set_id, media_id) do
    with {:ok, set_id} <- Ecto.UUID.cast(asset_set_id),
         {:ok, id} <- Ecto.UUID.cast(media_id),
         %Item{} = item <-
           Repo.one(
             from i in Item,
               where: i.id == ^id and i.asset_set_id == ^set_id and i.user_id == ^user_id
           ) do
      item
      |> Item.changeset(%{derived_sha256: nil, derived_size_bytes: nil})
      |> Repo.update()
    else
      _ -> {:error, :not_found}
    end
  end

  defp fetch(user_id, asset_set_id, media_id, field) do
    with {:ok, set_id} <- Ecto.UUID.cast(asset_set_id),
         {:ok, id} <- Ecto.UUID.cast(media_id),
         %Item{} = item <-
           Repo.one(
             from i in Item,
               where: i.id == ^id and i.asset_set_id == ^set_id and i.user_id == ^user_id
           ),
         sha when is_binary(sha) <- Map.get(item, field),
         {:ok, stream} <- Blobs.stream(sha) do
      {:ok, Enum.to_list(stream) |> IO.iodata_to_binary()}
    else
      _ -> {:error, :not_found}
    end
  end

  defp validate(bytes, "text/plain") when byte_size(bytes) in 1..@text_max do
    if String.valid?(bytes), do: :ok, else: {:error, :invalid_media}
  end

  defp validate(bytes, mime)
       when mime in ["image/png", "image/jpeg"] and byte_size(bytes) in 1..@image_max, do: :ok

  defp validate(_, _), do: {:error, :invalid_media}

  defp validate_provenance(provenance) when is_map(provenance) do
    case Jason.encode(provenance) do
      {:ok, encoded} when byte_size(encoded) <= 16_384 -> :ok
      _ -> {:error, :invalid_provenance}
    end
  end

  defp validate_provenance(_), do: {:error, :invalid_provenance}

  defp owned_asset_set(user_id, uuid) do
    if Repo.exists?(from a in AssetSet, where: a.id == ^uuid and a.user_id == ^user_id),
      do: :ok,
      else: {:error, :not_found}
  end

  defp decode_if_image(_bytes, "text/plain", _opts), do: {:ok, nil}

  defp decode_if_image(bytes, mime, opts) do
    decoder = Keyword.get(opts, :decoder, Playstead.Metadata.MediaDecodeWorker)
    decoder.decode(bytes, mime, opts)
  end

  defp put(bytes) do
    case Blobs.put_stream([bytes], byte_size(bytes)) do
      {:ok, _, meta} -> {:ok, meta}
      {:error, reason} -> {:error, reason}
    end
  end

  defp put_derived(nil), do: {:ok, nil}
  defp put_derived(bytes), do: put(bytes)

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
