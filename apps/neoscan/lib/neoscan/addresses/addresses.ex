defmodule Neoscan.Addresses do
  @moduledoc false
  @moduledoc """
  The boundary for the Addresses system.
  """

  import Ecto.Query, warn: false
  alias Neoscan.Repo

  alias Neoscan.Addresses.Address
  alias Neoscan.Transactions.Vout
  alias Neoscan.Transactions

  @doc """
  Returns the list of addresses.

  ## Examples

      iex> list_addresses()
      [%Address{}, ...]

  """
  def list_addresses do
    Repo.all(Address)
  end

  @doc """
  Gets a single address.

  Raises `Ecto.NoResultsError` if the Address does not exist.

  ## Examples

      iex> get_address!(123)
      %Address{}

      iex> get_address!(456)
      ** (Ecto.NoResultsError)

  """
  def get_address!(id), do: Repo.get!(Address, id)

  @doc """
  Gets a single address by its hash and send it as a map

  ## Examples

      iex> get_address_by_hash_for_view(123)
      %{}

      iex> get_address_by_hash_for_view(456)
      nil

  """
  def get_address_by_hash_for_view(hash) do
   vout_query = from v in Vout,
     select: %{
       asset: v.asset,
       address_hash: v.address_hash,
       value: v.value
     }
   query = from e in Address,
     where: e.address == ^hash,
     preload: [vouts: ^vout_query],
     select: e

   Repo.all(query)
   |> List.first
  end


  @doc """
  Gets a single address by its hash and send it as a map

  ## Examples

      iex> get_address_by_hash(123)
      %{}

      iex> get_address_by_hash(456)
      nil

  """
  def get_address_by_hash(hash) do

   query = from e in Address,
     where: e.address == ^hash,
     select: e

   Repo.all(query)
   |> List.first
  end

  @doc """
  Creates a address.

  ## Examples

      iex> create_address(%{field: value})
      %Address{}

      iex> create_address(%{field: bad_value})
      no_return

  """
  def create_address(attrs \\ %{}) do
    %Address{}
    |> Address.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Updates a address.

  ## Examples

      iex> update_address(address, %{field: new_value})
      %Address{}

      iex> update_address(address, %{field: bad_value})
      no_return

  """
  def update_address(%Address{} = address, attrs) do
    address
    |> Address.changeset(attrs)
    |> Repo.update!()
  end

  @doc """
  Deletes a Address.

  ## Examples

      iex> delete_address(address)
      {:ok, %Address{}}

      iex> delete_address(address)
      {:error, %Ecto.Changeset{}}

  """
  def delete_address(%Address{} = address) do
    Repo.delete!(address)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking address changes.

  ## Examples

      iex> change_address(address)
      %Ecto.Changeset{source: %Address{}}

  """
  def change_address(%Address{} = address) do
    Address.changeset(address, %{})
  end

  @doc """
  Check if address exist in database

  ## Examples

      iex> check_if_exist(existing_address})
      true

      iex> check_if_exist(new_address})
      false

  """
  def check_if_exist(address) do
    query = from e in Address,
      where: e.address == ^address,
      select: e.addres

    case Repo.all(query) |> List.first do
      nil ->
        false
      :string ->
        true
    end
  end

  @doc """
  Populates tuples {address_hash, vins} with {%Adddress{}, vins}

  ## Examples

      iex> populate_groups(groups})
      [{%Address{}, _},...]


  """
  def populate_groups(groups) do
    lookups = groups
      |> Stream.map(fn {address, _ } -> address end)
      |> Enum.to_list

    query =  from e in Address,
     where: fragment("CAST(? AS text)", e.address) in ^lookups,
     select: e

    address_list = Repo.all(query)

    Stream.map(groups, fn {address, vins} -> {Enum.find(address_list, fn %{:address => ad} -> ad == address end), vins} end)
    |> Enum.to_list
  end


  @doc """
  Creates or add an address with a certain address string

  ## Examples

      iex> create_or_get(existing_address})
      %Address{}

      iex> create_or_get(new_address})
      %Address{}

  """
  def insert_vouts_in_address(%{:txid => txid} = transaction, vouts) do
    %{"address" => address } = List.first(vouts)
    attrs = %{:balance => address.balance , :tx_ids => address.tx_ids}
    |> add_vouts(vouts, transaction)
    |> add_tx_id(txid)
    update_address(address, attrs)
  end

  def insert_vins_in_address(address, vins, txid) do
    attrs = %{:balance => address.balance, :tx_ids => address.tx_ids}
    |> add_vins(vins)
    |> add_tx_id(txid)
    update_address(address, attrs)
  end

  def add_vins(attrs, [h | t]) do
    add_vin(attrs, h)
    |> add_vins(t)
  end
  def add_vins(attrs, []), do: attrs

  def add_vouts(attrs, [h | t], transaction) do
    Transactions.create_vout(transaction, h)
    |> add_vout(attrs)
    |> add_vouts(t, transaction)
  end
  def add_vouts(attrs, [], _transaction), do: attrs

  def insert_claim_in_addresses(transactions, vouts) do
    lookups = Stream.map(vouts, &"#{&1["address"]}")
      |> Stream.uniq
      |> Enum.to_list

    query =  from e in Address,
     where: fragment("CAST(? AS text)", e.address) in ^lookups,
     select: e

    address_list = Repo.all(query)

    Stream.each(vouts, fn %{"address" => hash, "value" => value, "asset" => asset} ->
      insert_claim_in_address(Enum.find(address_list, fn %{:address => address} -> address == hash end) , transactions, value, asset, hash)
    end)
    |> Enum.to_list
  end

  def insert_claim_in_address(address, transactions, value, asset, address_hash) do
    cond do
      address == nil ->
        attrs = %{:address => address_hash, :claimed => nil}
        |> add_claim(transactions, value, asset)

        create_address(attrs)

      true ->
        attrs = %{:claimed => address.claimed}
        |> add_claim(transactions, value, asset)

        update_address(address, attrs)
    end
  end

  def add_vout(%{:value => value} = vout, %{:balance => balance} = address) do
    cond do
      balance == nil ->
        Map.put(address, :balance, [%{"asset" => vout.asset, "amount" => value}])
      balance != nil ->
        case Enum.find_index(balance, fn %{"asset" => asset} -> asset == vout.asset end) do
          nil ->
            new_balance = Enum.concat(balance, [%{"asset" => vout.asset, "amount" => value}])
            Map.put(address, :balance, new_balance)
          index ->
            new_balance = List.update_at(balance, index, fn %{"asset" => asset, "amount" => amount} -> %{"asset" => asset, "amount" => (amount + value)} end)
            Map.put(address, :balance, new_balance)
        end
    end
  end

  def add_vin(%{:balance => balance} = attrs, vin) do
      index = Enum.find_index(balance, fn %{"asset" => asset} -> asset == vin.asset end)
      new_balance = List.update_at(balance, index, fn %{"asset" => asset, "amount" => amount} -> %{"asset" => asset, "amount" => (amount - vin.value)} end)
      Map.put(attrs, :balance, new_balance)
  end

  def add_tx_id(address, txid) do
    cond do
      address.tx_ids == nil ->
        Map.put(address, :tx_ids, [%{ "txid" => txid, "balance" => address.balance}])

      address.tx_ids != nil ->
        case Enum.any?(address.tx_ids, fn %{"txid" => tx } -> tx == txid end) do
          true ->
            index = Enum.find_index(address.tx_ids, fn %{"txid" => tx} -> tx == txid end )
            new = List.update_at(address.tx_ids, index, fn %{ "txid" => tx} -> %{ "txid" => tx , "balance" => address.balance} end)
            Map.put(address, :tx_ids, new)
          false ->
            new = List.wrap(%{ "txid" => txid, "balance" => address.balance})
            Map.put(address, :tx_ids, Enum.concat(address.tx_ids, new))
        end
    end
  end

  def add_claim(address, transactions, amount, asset) do
    cond do
      address.claimed == nil ->
        Map.put(address, :claimed, [%{ "txids" => transactions, "amount" => amount, "asset" => asset}])

      address.claimed != nil ->
        case Enum.member?(address.claimed, %{ "txids" => transactions}) do
          true ->
            address
          false ->
            new = List.wrap(%{ "txids" => transactions, "amount" => amount, "asset" => asset})
            Map.put(address, :claimed, Enum.concat(address.claimed, new))
        end
    end
  end

end
