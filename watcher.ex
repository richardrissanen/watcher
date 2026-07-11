Mix.install([
  {:req, "~> 0.5"},
  {:floki, "~> 0.36"}
])

defmodule PageMonitor do
  @default_selector "body"
  @default_state_file "last_hash.txt"

  def run do
    with {:ok, config} <- load_config(),
         {:ok, content} <- fetch_content(config),
         hash <- hash(content),
         result <- compare(hash, config.state_file),
         :ok <- persist(hash, config.state_file) do
      handle_result(result, content)
    else
      {:error, reason} ->
        IO.puts("Error: #{reason}")
        System.halt(1)
    end
  end

  defp load_config do
    with {:ok, url} <- env("URL") do
      {:ok,
       %{
         url: url,
         selector: System.get_env("SELECTOR", @default_selector),
         state_file: System.get_env("STATE_FILE", @default_state_file)
       }}
    end
  end

  defp env(name) do
    case System.get_env(name) do
      nil -> {:error, "#{name} is not set"}
      value -> {:ok, value}
    end
  end

  defp fetch_content(%{url: url, selector: selector}) do
    body =
      Req.get!(url).body

    body
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Floki.text(separator: " ", deep: true)
    |> normalize()
    |> validate_content()
  end

  defp normalize(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp validate_content(""), do: {:error, "selector matched no text"}
  defp validate_content(text), do: {:ok, text}

  defp hash(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  defp compare(hash, state_file) do
    case File.read(state_file) do
      {:ok, ^hash} ->
        :unchanged

      {:ok, _old_hash} ->
        :changed

      {:error, :enoent} ->
        :initial

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist(hash, state_file) do
    File.write(state_file, hash)
  end

  defp handle_result(:initial, _) do
    IO.puts("Initial state stored.")
  end

  defp handle_result(:unchanged, _) do
    IO.puts("No changes detected.")
  end

  defp handle_result(:changed, content) do
    IO.puts("Content changed!\n")
    IO.puts(content)
    System.halt(2)
  end
end

PageMonitor.run()