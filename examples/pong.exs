defmodule Example.Pong do
  @moduledoc false

  def start do
    config = %{sid: "PING_ME"}
    |> ZssService.get_instance
    |> ZssService.add_verb({"get", Examples.SampleHandler, :ping_me})
    |> ZssService.add_verb({"list", Examples.SampleHandler, :ping_me_more})

    {:ok, pid} = ZssService.run config
    {:ok, pid} = ZssService.run config
    {:ok, pid} = ZssService.run config

    loop()
  end

  def loop do #Keep the script running
    loop()
  end
end

defmodule Examples.SampleHandler do
  @moduledoc false

  def ping_me(_payload, message) do
    {:ok, %{ping: "PONG"}}
  end

  def ping_me_more(_payload, message) do
    # %{headers: %{"userId" => user_id}} = message
    {:ok, [%{ping: "PONG", user_id: "1"}, %{ping: "PANG", user_id: "1"}], 202}
  end
end


Example.Pong.start
