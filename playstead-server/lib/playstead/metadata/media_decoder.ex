defmodule Playstead.Metadata.MediaDecoder do
  @moduledoc """
  Client for the restricted Linux image decoder. The only wire is a
  private Unix stream socket; there is deliberately no in-BEAM decoder.
  """

  @max_input 20 * 1024 * 1024
  @max_output 16 * 1024 * 1024
  @timeout 11_000

  @spec decode(binary(), String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def decode(bytes, mime, opts \\ [])

  def decode(bytes, mime, opts) when is_binary(bytes) and is_binary(mime) do
    socket = Keyword.get(opts, :socket, Application.get_env(:playstead, :media_decoder_socket))

    cond do
      byte_size(bytes) > @max_input ->
        {:error, :image_too_large}

      mime not in ["image/png", "image/jpeg"] ->
        {:error, :unsupported_image_type}

      not (is_binary(socket) or
               match?({:mac_ci_tcp, port} when is_integer(port) and port in 1..65_535, socket)) ->
        {:error, :decoder_unavailable}

      true ->
        request(socket, bytes, mime)
    end
  end

  def decode(_bytes, _mime, _opts), do: {:error, :invalid_image}

  defp request(path, bytes, mime) do
    with {:ok, socket} <- connect(path),
         :ok <-
           :gen_tcp.send(socket, [
             <<byte_size(bytes)::unsigned-big-32>>,
             <<byte_size(mime)>>,
             mime,
             bytes
           ]),
         result <- response(socket),
         :ok <- :gen_tcp.close(socket) do
      result
    else
      {:error, :timeout} -> {:error, :decoder_timeout}
      {:error, _reason} -> {:error, :decoder_unavailable}
      _ -> {:error, :decoder_unavailable}
    end
  end

  defp connect({:mac_ci_tcp, port}) do
    :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, {:packet, 0}, {:active, false}], 1_000)
  end

  defp connect(path) when is_binary(path) do
    case :gen_tcp.connect(
           {:local, String.to_charlist(path)},
           0,
           [:local, :binary, {:packet, 0}, {:active, false}],
           1_000
         ) do
      {:ok, socket} -> {:ok, socket}
      {:error, _} -> {:error, :decoder_unavailable}
    end
  end

  defp response(socket) do
    case :gen_tcp.recv(socket, 2, @timeout) do
      {:ok, "OK"} ->
        with {:ok, <<size::unsigned-big-32>>} <- :gen_tcp.recv(socket, 4, @timeout),
             true <- size > 0 and size <= @max_output,
             {:ok, png} <- :gen_tcp.recv(socket, size, @timeout),
             true <-
               byte_size(png) == size and
                 String.starts_with?(png, <<137, 80, 78, 71, 13, 10, 26, 10>>) do
          {:ok, png}
        else
          {:error, :timeout} -> {:error, :decoder_timeout}
          _ -> {:error, :invalid_image}
        end

      {:ok, "ER"} ->
        with {:ok, <<code_size>>} <- :gen_tcp.recv(socket, 1, 100),
             true <- code_size <= 32,
             {:ok, code} <- :gen_tcp.recv(socket, code_size, 100) do
          case code do
            "busy" -> {:error, :decoder_busy}
            "timeout" -> {:error, :decoder_timeout}
            "input_size" -> {:error, :image_too_large}
            _ -> {:error, :invalid_image}
          end
        else
          _ -> {:error, :invalid_image}
        end

      {:error, :timeout} ->
        {:error, :decoder_timeout}

      _ ->
        {:error, :invalid_image}
    end
  end
end
