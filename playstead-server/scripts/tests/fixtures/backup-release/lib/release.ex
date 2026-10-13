defmodule Playstead.Release do
  # Only expose the arguments delivered by the actual OTP release launcher.
  # This fixture cannot access the application, database, or backup storage.
  def backup(args), do: Enum.each(args, &IO.puts("<#{&1}>"))
end
