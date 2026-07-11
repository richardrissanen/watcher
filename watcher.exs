Mix.install([
  {:floki, "0.38.4"}
])

defmodule MonitorPage do
  @default_selector "body"
  @default_state_file "last_hash.txt"

  def run do
    with {:ok, url} <- get_env("URL"),
         {:ok, selector} <- get_env("SELECTOR", @default_selector),
         {:ok, state_file} <- get_env("STATE_FILE", @default_state_file),
         {:ok, document} <- fetch_document(url),
         {:ok, content} <- fetch_content(document, selector),
         hash = hash(content),
         {:ok, result} <- compare(hash, state_file),
         :ok <- persist(hash, state_file) do
      handle_result(result, content)
    else
      {:error, reason} ->
        IO.inspect(reason, label: "Error")
        System.halt(1)
    end
  end

  defp get_env(var, default \\ nil) do
    case System.get_env(var, default) do
      nil -> {:error, "#{var} is not set"}
      value -> {:ok, value}
    end
  end

  defp fetch_document(url) do
    case System.cmd("node", ["render.js"], env: [{"URL", url}]) do
      {html, 0} ->
        Floki.parse_document(html)

      {error, exit_code} ->
        {:error, "renderer failed (#{exit_code}): #{error}"}
    end
  end

  defp fetch_content(document, selector) do
    document
    |> Floki.find(selector)
    |> Floki.text(sep: " ", deep: true)
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> validate_content()
  end

  defp validate_content(""), do: {:error, "selector matched no text"}
  defp validate_content(text), do: {:ok, text}

  defp hash(content) do
    content
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end

  defp compare(hash, state_file) do
    case File.read(state_file) do
      {:ok, stored_hash} ->
        case String.trim(stored_hash) do
          ^hash -> {:ok, :unchanged}
          _ -> {:ok, :changed}
        end

      {:error, :enoent} ->
        {:ok, :initial}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist(hash, state_file) do
    state_file
    |> Path.dirname()
    |> File.mkdir_p!()

    temp_file = "#{state_file}.tmp"

    with :ok <- File.write(temp_file, hash),
         :ok <- File.rename(temp_file, state_file) do
      :ok
    end
  end

  defp handle_result(:initial, _), do: IO.puts("Initial state stored.")
  defp handle_result(:unchanged, _), do: IO.puts("No changes detected.")

  defp handle_result(:changed, content) do
    IO.puts("Content changed!\n")
    IO.puts(content)
    System.halt(2)
  end
end

MonitorPage.run()
