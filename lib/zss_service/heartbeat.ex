defmodule ZssService.Heartbeat do
  @moduledoc """
  This module will handle the heartbeats that have to be sent. Since this should not hinder
  The actual socket, it's extracted to a several module that will be supervised
  """

  alias ZssService.Message
  require Logger

  def start(socket, %{sid: sid, identity: identity, heartbeat: heartbeat} = config) do
    heartbeat_msg = Message.new "SMI", "HEARTBEAT"

    heartbeat_msg = %Message{heartbeat_msg | identity: identity, payload: sid}
    :ok = send_request(socket, heartbeat_msg)

    #Todo better mechanism than timers perhaps
    :timer.sleep(heartbeat)
    start(socket, config)
  end

  defp send_request(socket, message) do
    Logger.debug "Sending #{message.identity} with id #{message.rid} to #{message.address.sid}:#{message.address.sversion}##{message.address.verb}"
    :czmq.zsocket_send_all(socket, message |> Message.to_frames)
  end
end