defmodule Hyperliquid.Atomizer do
  def atomize_keys(data) when is_map(data) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      atom_key = if is_binary(key), do: String.to_atom(key), else: key
      Map.put(acc, atom_key, atomize_keys(value))
    end)
  end

  def atomize_keys(data) when is_list(data) do
    Enum.map(data, &atomize_keys/1)
  end

  def atomize_keys({key, value}) when is_binary(key) do
    atom_key = String.to_atom(key)
    {atom_key, atomize_keys(value)}
  end

  def atomize_keys({key, value}) do
    {key, atomize_keys(value)}
  end

  def atomize_keys(data), do: data
end
