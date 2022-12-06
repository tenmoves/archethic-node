defmodule ArchethicWeb.GraphQLSchema.BeaconChainSummary do
  @moduledoc false

  use Absinthe.Schema.Notation
  alias Archethic.BeaconChain.SummaryAggregate

  @desc """
  [Beacon Chain Summary] represents the beacon chain aggregate for a certain date
  """

  @default_limit 10

  object :beacon_chain_summary do
    field(:version, :integer)
    field(:summary_time, :string)
    field(:availability_adding_time, list_of(:integer))
    field(:p2p_availabilities, :p2p_availabilities)

    field(:transaction_summaries, list_of(:transaction_summary)) do
      arg(:paging_offset, :non_neg_integer)
      arg(:limit, :pos_integer)

      resolve(fn args,
                 %{
                   source: %SummaryAggregate{
                     transaction_summaries: transaction_summaries
                   }
                 } ->
        limit = Map.get(args, :limit, @default_limit)
        paging_offset = Map.get(args, :paging_offset, 0)

        result =
          transaction_summaries
          |> Enum.split(paging_offset)
          |> then(fn {_, offset_tx_summaries} -> offset_tx_summaries end)
          |> Enum.take(limit)

        {:ok, result}
      end)
    end
  end

  @desc """
  [Transaction Summary] Represents transaction header or extract to summarize it
  """
  object :transaction_summary do
    field(:timestamp, :timestamp)
    field(:address, :address)
    field(:movements_addresses, list_of(:address))
    field(:type, :string)
    field(:fee, :integer)
  end

  scalar :p2p_availabilities do
    serialize(fn p2p_availabilities ->
      p2p_availabilities
      |> Map.to_list()
      |> Enum.map(fn {
                       <<subset>>,
                       %{
                         end_of_node_synchronizations: end_of_node_synchronizations,
                         node_average_availabilities: node_average_availabilities,
                         node_availabilities: node_availabilities
                       }
                     } ->
        {
          subset,
          %{
            end_of_node_synchronizations: end_of_node_synchronizations,
            node_average_availabilities: node_average_availabilities,
            node_availabilities: transform_node_availabilities(node_availabilities)
          }
        }
      end)
      |> Enum.into(%{})
    end)
  end

  defp transform_node_availabilities(bitstring, acc \\ [])

  defp transform_node_availabilities(<<1::size(1), rest::bitstring>>, acc),
    do: transform_node_availabilities(<<rest::bitstring>>, [1 | acc])

  defp transform_node_availabilities(<<0::size(1), rest::bitstring>>, acc),
    do: transform_node_availabilities(<<rest::bitstring>>, [0 | acc])

  defp transform_node_availabilities(<<>>, acc), do: acc
end
