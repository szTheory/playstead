defmodule Playstead.Metadata.ProviderMediaCache.Object do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "metadata_provider_media" do
    field :user_id, :id
    belongs_to :asset_set, Playstead.Catalogue.AssetSet
    field :provider, :string, default: "igdb"
    field :image_id, :string
    field :size, :string
    field :object_key, :string
    field :sha256, :string
    field :size_bytes, :integer
    field :pinned, :boolean, default: false
    field :legally_refetchable, :boolean, default: false
    field :cache_expires_at, :utc_datetime
    field :license_expires_at, :utc_datetime
    field :last_accessed_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(object, attrs) do
    object
    |> cast(attrs, [
      :user_id,
      :asset_set_id,
      :provider,
      :image_id,
      :size,
      :object_key,
      :sha256,
      :size_bytes,
      :pinned,
      :legally_refetchable,
      :cache_expires_at,
      :license_expires_at,
      :last_accessed_at
    ])
    |> validate_required([
      :user_id,
      :asset_set_id,
      :provider,
      :image_id,
      :size,
      :object_key,
      :sha256,
      :size_bytes,
      :pinned,
      :legally_refetchable,
      :cache_expires_at,
      :last_accessed_at
    ])
    |> validate_inclusion(:size, ["cover_small", "cover_big", "screenshot_med", "screenshot_huge"])
    |> validate_number(:size_bytes, greater_than: 0)
    |> foreign_key_constraint(:asset_set_id)
    |> unique_constraint([:user_id, :asset_set_id, :image_id, :size],
      name: :metadata_provider_media_identity_index
    )
  end
end

defmodule Playstead.Metadata.ProviderMediaCache do
  @moduledoc "Rights-gated, independently bounded cache of fixed-host IGDB image derivatives."
  import Ecto.Query, warn: false

  alias Playstead.Metadata.{Consent, MediaDecodeWorker, RequestBudget}
  alias Playstead.Metadata.ProviderMediaCache.Object
  alias Playstead.Repo

  @max_response 12 * 1_048_576
  @max_cover 8 * 1_048_576
  @max_game 32 * 1_048_576
  @max_user 1_073_741_824
  @fresh_seconds 30 * 24 * 60 * 60
  @sizes ["cover_small", "cover_big", "screenshot_med", "screenshot_huge"]
  @id_pattern ~r/\A[a-zA-Z0-9_-]{1,128}\z/

  def sizes, do: @sizes
  def max_response_bytes, do: @max_response

  def image_url(image_id, size) do
    if valid_image_id?(image_id) and size in @sizes do
      {:ok, "https://images.igdb.com/igdb/image/upload/t_#{size}/#{image_id}.jpg"}
    else
      {:error, :invalid_image_reference}
    end
  end

  def fetch(user_id, asset_set_id, image_id, size, opts \\ []) do
    with {:ok, _consent} <- Consent.authorize_image(user_id, asset_set_id),
         {:ok, url} <- image_url(image_id, size),
         {:ok, cached} <- cached_object(user_id, asset_set_id, image_id, size, opts),
         {:miss, _} <- cached do
      with {:ok, _consent} <- Consent.authorize_image(user_id, asset_set_id),
           :ok <- RequestBudget.wait_for_slot(),
           {:ok, _consent} <- Consent.authorize_image(user_id, asset_set_id),
           {:ok, %{status: 200, body: bytes, mime: mime, license_expires_at: expiry}} <-
             transport(opts).get(url, @max_response, opts),
           true <- byte_size(bytes) in 1..@max_response,
           true <- mime in ["image/jpeg", "image/png"],
           {:ok, derivative} <- decoder(opts).decode(bytes, mime, decoder_opts(opts)),
           :ok <- validate_derivative(derivative, size),
           {:ok, _consent} <- Consent.authorize_image(user_id, asset_set_id),
           :ok <- before_store(opts),
           {:ok, object} <- store(user_id, asset_set_id, image_id, size, derivative, expiry, opts) do
        {:ok, object}
      else
        false -> {:error, :image_response_too_large}
        {:ok, %{status: status}} when status in 400..499 -> {:error, :provider_image_rejected}
        {:ok, %{status: status}} when status in 500..599 -> {:error, :provider_unavailable}
        {:error, _} = error -> error
        _ -> {:error, :provider_image_unavailable}
      end
    else
      {:ok, {:hit, object}} -> touch_and_read(object, opts)
      {:error, _} = error -> error
      _ -> {:error, :provider_image_unavailable}
    end
  end

  def usage(user_id) do
    objects = Repo.all(from o in Object, where: o.user_id == ^user_id)
    used = Enum.reduce(objects, 0, &(&1.size_bytes + &2))
    reclaimable = objects |> Enum.filter(&reclaimable?/1) |> Enum.reduce(0, &(&1.size_bytes + &2))

    %{
      used_bytes: used,
      budget_bytes: @max_user,
      reclaimable_bytes: reclaimable,
      available_bytes: max(0, @max_user - used)
    }
  end

  def pin(user_id, object_id, pinned \\ true) when is_boolean(pinned) do
    with {:ok, id} <- Ecto.UUID.cast(object_id),
         %Object{} = object <-
           Repo.one(from o in Object, where: o.id == ^id and o.user_id == ^user_id) do
      object |> Ecto.Changeset.change(pinned: pinned) |> Repo.update()
    else
      _ -> {:error, :not_found}
    end
  end

  def read(user_id, asset_set_id, object_id) do
    with {:ok, _consent} <- Consent.authorize_image(user_id, asset_set_id),
         {:ok, id} <- Ecto.UUID.cast(object_id),
         %Object{} = object <-
           Repo.one(
             from o in Object,
               where: o.id == ^id and o.user_id == ^user_id and o.asset_set_id == ^asset_set_id
           ),
         true <- DateTime.compare(object.cache_expires_at, now()) == :gt,
         true <-
           is_nil(object.license_expires_at) or
             DateTime.compare(object.license_expires_at, now()) == :gt,
         {:ok, result} <- touch_and_read(object, []) do
      {:ok, result}
    else
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  @doc "Evict only old, unpinned, legally refetchable provider derivatives."
  def reclaim(user_id, requested_bytes \\ nil) do
    target =
      if is_integer(requested_bytes) and requested_bytes > 0, do: requested_bytes, else: @max_user

    candidates =
      Repo.all(
        from o in Object,
          where: o.user_id == ^user_id and o.pinned == false and o.legally_refetchable == true,
          order_by: [asc: o.last_accessed_at]
      )

    evict_until(candidates, target, 0)
  end

  def purge(user_id, asset_set_id) do
    objects =
      Repo.all(from o in Object, where: o.user_id == ^user_id and o.asset_set_id == ^asset_set_id)

    errors =
      Enum.reduce(objects, [], fn object, errors ->
        case delete_object(object) do
          :ok -> errors
          {:error, reason} -> [{object.id, reason} | errors]
        end
      end)

    case errors do
      [] -> :ok
      errors -> {:error, {:cache_delete_failed, Enum.reverse(errors)}}
    end
  end

  defp cached_object(user_id, asset_set_id, image_id, size, opts) do
    case Repo.one(
           from o in Object,
             where:
               o.user_id == ^user_id and o.asset_set_id == ^asset_set_id and
                 o.image_id == ^image_id and o.size == ^size
         ) do
      %Object{cache_expires_at: expires, license_expires_at: license} = object ->
        now = now()

        cond do
          DateTime.compare(expires, now) != :gt -> {:ok, {:miss, object}}
          not is_nil(license) and DateTime.compare(license, now) != :gt -> {:ok, {:miss, object}}
          File.regular?(object_path(object, opts)) -> {:ok, {:hit, object}}
          true -> {:ok, {:miss, object}}
        end

      nil ->
        {:ok, {:miss, nil}}
    end
  end

  defp touch_and_read(object, opts) do
    with {:ok, bytes} <- File.read(object_path(object, opts)),
         true <- byte_size(bytes) == object.size_bytes,
         true <- sha256(bytes) == object.sha256 do
      Repo.update!(Ecto.Changeset.change(object, last_accessed_at: now()))
      {:ok, Map.put(Map.from_struct(object), :bytes, bytes)}
    else
      _ -> {:error, :cache_corrupt}
    end
  end

  defp store(user_id, asset_set_id, image_id, size, bytes, license_expiry, opts) do
    case Repo.transaction(fn ->
           # Serialize usage calculation, eviction, and insert per owner across nodes.
           Repo.query!("SELECT id FROM users WHERE id = $1 FOR UPDATE", [user_id])

           case Consent.authorize_image(user_id, asset_set_id) do
             {:ok, _consent} ->
               store_locked(user_id, asset_set_id, image_id, size, bytes, license_expiry, opts)

             {:error, reason} ->
               {:error, reason}
           end
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp before_store(opts) do
    case Keyword.get(opts, :before_store) do
      callback when is_function(callback, 0) ->
        callback.()
        :ok

      _ ->
        :ok
    end
  end

  defp store_locked(user_id, asset_set_id, image_id, size, bytes, license_expiry, opts) do
    cap = if String.starts_with?(size, "cover"), do: @max_cover, else: @max_game

    if byte_size(bytes) > cap do
      {:error, :capacity_refused}
    else
      with :ok <- reclaim_for_capacity(user_id, asset_set_id, byte_size(bytes)) do
        digest = sha256(bytes)
        key = "#{user_id}/#{asset_set_id}/#{image_id}-#{size}-#{digest}.png"
        path = Path.join(cache_root(opts), key)

        previous =
          Repo.one(
            from o in Object,
              where:
                o.user_id == ^user_id and o.asset_set_id == ^asset_set_id and
                  o.image_id == ^image_id and o.size == ^size,
              lock: "FOR UPDATE"
          )

        path_existed = File.regular?(path)

        with :ok <- File.mkdir_p(Path.dirname(path)),
             :ok <- atomic_write(path, bytes) do
          attrs = %{
            user_id: user_id,
            asset_set_id: asset_set_id,
            provider: "igdb",
            image_id: image_id,
            size: size,
            object_key: key,
            sha256: digest,
            size_bytes: byte_size(bytes),
            pinned: false,
            legally_refetchable: true,
            cache_expires_at: DateTime.add(now(), @fresh_seconds, :second),
            license_expires_at: license_expiry,
            last_accessed_at: now()
          }

          case %Object{}
               |> Object.changeset(attrs)
               |> Repo.insert(
                 on_conflict:
                   {:replace,
                    [
                      :object_key,
                      :sha256,
                      :size_bytes,
                      :cache_expires_at,
                      :license_expires_at,
                      :last_accessed_at,
                      :updated_at
                    ]},
                 conflict_target: [:user_id, :asset_set_id, :image_id, :size]
               ) do
            {:ok, object} ->
              case cleanup_replaced_object(previous, object, opts) do
                :ok ->
                  {:ok, Map.put(Map.from_struct(object), :bytes, bytes)}

                {:error, reason} ->
                  restore_result = restore_previous_object(previous, object)
                  new_file_cleanup = if path_existed, do: :ok, else: remove_cache_file(path)

                  {:error,
                   {:cache_replacement_cleanup_failed, reason, restore_result, new_file_cleanup}}
              end

            {:error, changeset} ->
              cleanup_result = if path_existed, do: :ok, else: remove_cache_file(path)

              case cleanup_result do
                :ok ->
                  {:error, changeset}

                {:error, reason} ->
                  {:error, {:cache_insert_cleanup_failed, changeset, reason}}
              end
          end
        end
      end
    end
  end

  defp evict_until(_objects, requested, freed) when freed >= requested,
    do: {:ok, %{reclaimed_bytes: freed, usage: nil}}

  defp evict_until([], _requested, freed), do: {:ok, %{reclaimed_bytes: freed, usage: nil}}

  defp evict_until([object | rest], requested, freed) do
    if reclaimable?(object) do
      case delete_object(object) do
        :ok -> evict_until(rest, requested, freed + object.size_bytes)
        {:error, reason} -> {:error, {:cache_delete_failed, object.id, reason}}
      end
    else
      evict_until(rest, requested, freed)
    end
  end

  defp reclaim_for_capacity(user_id, asset_set_id, incoming) do
    user_used =
      from(o in Object, where: o.user_id == ^user_id)
      |> Repo.aggregate(:sum, :size_bytes)
      |> bytes_integer()

    game_used =
      from(o in Object, where: o.user_id == ^user_id and o.asset_set_id == ^asset_set_id)
      |> Repo.aggregate(:sum, :size_bytes)
      |> bytes_integer()

    game_needed = max(0, game_used + incoming - @max_game)

    game_candidates =
      Repo.all(
        from o in Object,
          where:
            o.user_id == ^user_id and o.asset_set_id == ^asset_set_id and o.pinned == false and
              o.legally_refetchable == true,
          order_by: [asc: o.last_accessed_at]
      )

    with {:ok, %{reclaimed_bytes: game_freed}} <-
           evict_until(game_candidates, game_needed, 0) do
      user_needed = max(0, user_used + incoming - @max_user)

      if user_needed > 0 do
        user_candidates =
          Repo.all(
            from o in Object,
              where:
                o.user_id == ^user_id and o.asset_set_id != ^asset_set_id and o.pinned == false and
                  o.legally_refetchable == true,
              order_by: [asc: o.last_accessed_at]
          )

        with {:ok, %{reclaimed_bytes: other_freed}} <-
               evict_until(user_candidates, max(0, user_needed - game_freed), 0) do
          if game_freed + other_freed >= max(game_needed, user_needed),
            do: :ok,
            else: {:error, {:capacity_refused, usage(user_id)}}
        end
      else
        if game_freed >= game_needed,
          do: :ok,
          else: {:error, {:capacity_refused, usage(user_id)}}
      end
    end
  end

  defp reclaimable?(%Object{pinned: false, legally_refetchable: true, license_expires_at: expiry}) do
    is_nil(expiry) or DateTime.compare(expiry, now()) == :gt
  end

  defp reclaimable?(_), do: false

  defp bytes_integer(nil), do: 0
  defp bytes_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp bytes_integer(value) when is_integer(value), do: value

  defp delete_object(object) do
    case remove_cache_file(object_path(object, [])) do
      :ok -> delete_object_row(object)
      {:error, reason} -> {:error, reason}
    end
  end

  defp remove_cache_file(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_object_row(object) do
    case Repo.delete(object) do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp cleanup_replaced_object(nil, _new, _opts), do: :ok

  defp cleanup_replaced_object(old, new, opts) do
    if old.object_key == new.object_key or
         Repo.exists?(from o in Object, where: o.object_key == ^old.object_key) do
      :ok
    else
      remove_cache_file(object_path(old, opts))
    end
  end

  defp restore_previous_object(nil, _new), do: :ok

  defp restore_previous_object(old, new) do
    attrs =
      old
      |> Map.from_struct()
      |> Map.take([
        :object_key,
        :sha256,
        :size_bytes,
        :cache_expires_at,
        :license_expires_at,
        :last_accessed_at,
        :updated_at
      ])

    new |> Object.changeset(attrs) |> Repo.update()
  end

  defp validate_derivative(bytes, size) when is_binary(bytes) and byte_size(bytes) > 0 do
    cap = if String.starts_with?(size, "cover"), do: @max_cover, else: @max_game

    if byte_size(bytes) <= cap and String.starts_with?(bytes, <<137, 80, 78, 71, 13, 10, 26, 10>>),
      do: :ok,
      else: {:error, :decoded_image_too_large}
  end

  defp validate_derivative(_, _), do: {:error, :invalid_image}

  defp valid_image_id?(image_id), do: is_binary(image_id) and Regex.match?(@id_pattern, image_id)

  defp transport(opts),
    do: Keyword.get(opts, :transport, Playstead.Metadata.ProviderMediaCache.ReqTransport)

  defp decoder(opts), do: Keyword.get(opts, :decoder, MediaDecodeWorker)
  defp decoder_opts(opts), do: Keyword.take(opts, [:socket, :test_pid])

  defp cache_root(opts),
    do:
      Keyword.get(
        opts,
        :cache_root,
        Application.get_env(
          :playstead,
          :metadata_provider_cache_root,
          Path.join(Playstead.Blobs.Store.LocalDisk.blob_path(), "provider-media-cache")
        )
      )

  defp object_path(object, opts), do: Path.join(cache_root(opts), object.object_key)

  defp atomic_write(path, bytes) do
    temp = path <> ".tmp-" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

    with :ok <- File.write(temp, bytes, [:binary, :exclusive]), :ok <- File.rename(temp, path) do
      :ok
    else
      {:error, reason} ->
        File.rm(temp)
        {:error, reason}
    end
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end

defmodule Playstead.Metadata.ProviderMediaCache.ReqTransport do
  @moduledoc false
  @max_response 12 * 1_048_576

  def get(url, max_bytes \\ @max_response, _opts \\ []) do
    with {:ok, uri} <- URI.new(url),
         true <-
           uri.scheme == "https" and uri.host == "images.igdb.com" and is_nil(uri.query) and
             is_nil(uri.userinfo),
         {:ok, response} <-
           Req.get(url,
             redirect: false,
             retry: false,
             receive_timeout: 8_000,
             connect_options: [timeout: 3_000],
             decode_body: false,
             into: collector(max_bytes)
           ) do
      case response do
        %Req.Response{status: 200, private: %{provider_image_too_large: true}} ->
          {:error, :image_response_too_large}

        %Req.Response{status: 200, private: %{provider_image_body: body}} ->
          mime =
            response.headers
            |> Map.get("content-type", ["application/octet-stream"])
            |> List.first()
            |> String.split(";")
            |> hd()

          {:ok, %{status: 200, body: body, mime: mime, license_expires_at: nil}}

        %Req.Response{status: 429, headers: headers} ->
          {:error, {:retry_after, retry_after(headers)}}

        %Req.Response{status: status} when status in 500..599 ->
          {:error, :provider_unavailable}

        %Req.Response{} ->
          {:error, :provider_image_rejected}
      end
    else
      false -> {:error, :invalid_image_reference}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :provider_image_unavailable}
    end
  rescue
    _ -> {:error, :provider_image_unavailable}
  end

  defp collector(max_bytes) do
    fn {:data, chunk}, {req, resp} ->
      body = Map.get(resp.private, :provider_image_body, <<>>)

      if byte_size(body) + byte_size(chunk) > min(max_bytes, @max_response) do
        {:halt, {req, put_in(resp.private[:provider_image_too_large], true)}}
      else
        {:cont, {req, put_in(resp.private[:provider_image_body], body <> chunk)}}
      end
    end
  end

  defp retry_after(headers) do
    case headers |> Map.get("retry-after", ["1"]) |> List.first() |> Integer.parse() do
      {seconds, _} -> min(3_600, max(1, seconds))
      _ -> 1
    end
  end
end
