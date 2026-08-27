defmodule Playstead.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query
  alias Playstead.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  # D-06: remember-me is on by default with a ~60-day window, backed by
  # this DB-backed token — revocation (deleting the row) actually
  # invalidates the session on its next request.
  @session_validity_in_days 60

  # Default validity for the generic hashed-token contexts that survive
  # the D-02 email-flow removal (currently only `:password_reset`, minted
  # out-of-band by plan 01-03's release command — see `build_hashed_token/2`
  # and `verify_hashed_token_query/3`). Deliberately short since a leaked
  # reset link should not stay live long.
  @hashed_token_default_validity_in_hours 1

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime
    # D-06: a coarse, safe browser/OS label derived from User-Agent at
    # session-creation time (T-01-19 — never the raw user-agent string).
    # `nil` when the client string isn't recognizable; the Sessions list
    # then renders the generic "Browser session" label.
    field :client_label, :string
    belongs_to :user, Playstead.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.

  The reason why we store session tokens in the database, even
  though Phoenix already provides a session cookie, is because
  Phoenix's default session cookies are not persisted, they are
  simply signed and potentially encrypted. This means they are
  valid indefinitely, unless you change the signing/encryption
  salt.

  Therefore, storing them allows individual user
  sessions to be expired. The token system can also be extended
  to store additional data, such as the device used for logging in.
  You could then use this information to display all valid sessions
  and devices in the UI and allow users to explicitly expire any
  session they deem invalid.
  """
  def build_session_token(user, client_label \\ nil) do
    token = :crypto.strong_rand_bytes(@rand_size)
    dt = user.authenticated_at || DateTime.utc_now(:second)

    {token,
     %UserToken{
       token: token,
       context: "session",
       user_id: user.id,
       authenticated_at: dt,
       client_label: client_label
     }}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any, along with the token's creation time.

  The token is valid if it matches the value in the database and it has
  not expired (after @session_validity_in_days).
  """
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: {%{user | authenticated_at: token.authenticated_at}, token.inserted_at}

    {:ok, query}
  end

  @doc """
  Builds a single-use, hashed, out-of-band token for a context that has no
  email delivery — currently only `:password_reset` (D-05a, minted by plan
  01-03's Mix-release command and printed to stdout, never emailed).

  The non-hashed token is returned to the caller to embed in a URL; only its
  hash is stored. The original token cannot be reconstructed from the
  database, so read-only DB access cannot be used to forge one.
  """
  def build_hashed_token(user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed_token,
       context: context,
       user_id: user.id
     }}
  end

  @doc """
  Checks if a generic hashed token (see `build_hashed_token/2`) is valid and
  returns its underlying lookup query.

  The query returns the `UserToken` found by the token, if any. The token is
  valid if it matches its hashed counterpart in the database and has not
  expired (`validity_in_hours` after issuance).
  """
  def verify_hashed_token_query(
        token,
        context,
        validity_in_hours \\ @hashed_token_default_validity_in_hours
      ) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            where: token.inserted_at > ago(^validity_in_hours, "hour")

        {:ok, query}

      :error ->
        :error
    end
  end

  defp by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end
end
