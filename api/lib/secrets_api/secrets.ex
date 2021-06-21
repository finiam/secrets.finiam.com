defmodule SecretsApi.Secrets do
  @moduledoc """
  This module contains basic operations to safely
  store and retrieve secrets.
  """

  alias SecretsApi.Analytics
  alias SecretsApi.Redix

  require Logger

  @spec store_secret(any, boolean) :: {:error, :redis_error} | {:ok, binary}
  def store_secret(secret, has_passphrase \\ false) do
    room_id = generate_room_id()
    payload = Jason.encode!(%{secret: secret, has_passphrase: has_passphrase})

    case Redix.command(["SET", room_id, payload, "EX", "3600", "NX"]) do
      {:ok, _} ->
        Analytics.increment_secrets_counter()
        {:ok, room_id}

      {:error, error} ->
        Logger.error(error)
        {:error, :redis_error}
    end
  end

  @spec secret_exists(any) ::
          {:error, :not_found | :redis_error}
          | {:ok}
  def secret_exists(room_id) do
    case Redix.command(["EXISTS", room_id]) do
      {:ok, 1} ->
        {:ok}

      {:ok, _} ->
        {:error, :not_found}

      {:error, error} ->
        Logger.error(error)
        {:error, :redis_error}
    end
  end

  @retrieve_lua_script """
    local secret = redis.call('get', KEYS[1])
    redis.call('del', KEYS[1])

    return secret
  """

  @spec retrieve_and_delete_secret(any) :: {:error, :not_found | :redis_error} | {:ok, any}
  def retrieve_and_delete_secret(room_id) do
    case Redix.command(["EVAL", @retrieve_lua_script, 1, room_id]) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, payload} ->
        {:ok, Jason.decode!(payload)}

      {:error, error} ->
        Logger.error(error)
        {:error, :redis_error}
    end
  end

  @spec delete_secret(any) :: {:ok} | {:error, :not_found | :redis_error}
  def delete_secret(room_id) do
    case Redix.command(["DEL", room_id]) do
      {:ok, 0} ->
        {:error, :not_found}

      {:ok, _} ->
        {:ok}

      {:error, error} ->
        Logger.error(error)
        {:error, :redis_error}
    end
  end

  defp generate_room_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode64(case: :lower)
    |> Base.url_encode64(case: :lower, padding: true)
  end
end
