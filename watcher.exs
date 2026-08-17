Mix.install([
  {:floki, "0.38.4"},
  {:jason, "~> 1.5"}
])

defmodule MonitorPage do
  @default_selector "body"
  @default_state_file "last_hash.txt"

  def run do
    case load_pages() do
      {:ok, pages} ->
        results =
          Enum.reduce_while(pages, [], fn page, acc ->
            case monitor_page(page) do
              {:ok, result} -> {:cont, [{page, result} | acc]}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)

        case results do
          {:error, reason} ->
            IO.inspect(reason, label: "Error")
            System.halt(1)

          page_results ->
            Enum.each(page_results, fn {page, result} -> handle_result(page, result) end)

            if Enum.any?(page_results, fn {_page, result} -> result == :changed end) do
              System.halt(2)
            else
              System.halt(0)
            end
        end

      {:error, reason} ->
        IO.inspect(reason, label: "Error")
        System.halt(1)
    end
  end

  defp load_pages do
    case System.get_env("MONITOR_PAGES") do
      nil -> {:error, "MONITOR_PAGES is not set"}
      json_pages ->
        with {:ok, parsed_pages} <- Jason.decode(json_pages),
             true <- is_list(parsed_pages),
             true <- Enum.all?(parsed_pages, &is_map/1) do
          {:ok,
           Enum.map(parsed_pages, fn page ->
             %{
               name: Map.get(page, "name") || Map.get(page, :name) || Map.get(page, "url") || Map.get(page, :url),
               url: Map.get(page, "url") || Map.get(page, :url),
               selector: Map.get(page, "selector") || Map.get(page, :selector) || @default_selector,
               state_file:
                 Map.get(page, "state_file") ||
                   Map.get(page, :state_file) ||
                   default_state_file_for_url(Map.get(page, "url") || Map.get(page, :url))
             }
           end)}
        else
          _ -> {:error, "MONITOR_PAGES is not a JSON array of page objects"}
        end
    end
  end

  defp default_state_file_for_url(url) do
    url
    |> String.replace(~r/[^a-zA-Z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> @default_state_file
      slug -> ".github/monitor/#{slug}.hash"
    end
  end

  defp monitor_page(%{url: url, selector: selector, state_file: state_file}) do
    with {:ok, document} <- fetch_document(url),
         {:ok, content} <- fetch_content(document, selector),
         hash = hash(content),
         {:ok, result} <- compare(hash, state_file),
         :ok <- persist(hash, state_file) do
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
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
    :sha256
    |> :crypto.hash(content)
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

  defp handle_result(page, result) do
    payload = %{
      name: page.name,
      url: page.url,
      status: Atom.to_string(result)
    }

    case result do
      :initial -> IO.puts(:stderr, "Initial state stored for #{page.name} (#{page.url}).")
      :unchanged -> IO.puts(:stderr, "No changes detected for #{page.name}.")
      :changed -> IO.puts(:stderr, "Content changed for #{page.name} (#{page.url}).")
    end

    IO.puts(Jason.encode!(payload))
  end
end

MonitorPage.run()
