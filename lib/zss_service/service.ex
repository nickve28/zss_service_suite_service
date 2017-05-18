defmodule ZssService.Service do
  use GenServer
  alias ZssService.{Heartbeat, Message, Receiver}
  require Logger

  @moduledoc """
  The worker for ZSS. Started via ServiceSupervisor.
  """

  @defaults %{
    broker: "tcp://127.0.0.1:7776",
    heartbeat: 1000
  }
  @not_found "404"

  @doc """
  Starts an instance with the given config. Defaults will be applied.

  Args:

  - config: A map containg sid (required), broker, and heartbeat\n
  """
  def start_link(%{sid: sid} = config) when is_binary(sid) do
    full_config = Map.merge(@defaults, config)

    GenServer.start_link(__MODULE__, full_config)
  end

  def init(%{sid: sid, broker: broker} = config) do
    {:ok, ctx} = :czmq.start_link

    :czmq.zctx_set_linger(ctx, 0)
    socket = :czmq.zsocket_new(ctx, :dealer)
    #remove any message after closing
    identity = get_identity(sid) |> String.to_charlist
    Logger.debug("Assuming identity #{identity}")
    :ok = :czmq.zsocket_set_identity(socket, identity)
    :ok = :czmq.zsocket_connect(socket, broker)

    #Initiate heartbeats
    config = Map.put(config, :identity, identity)
    {:ok, %{config: config, socket: socket, handlers: %{}}}
  end

  @doc """
  Register a verb to this worker. It will respond to the given verb and pass the payload and message
  """
  def add_verb(pid, {verb, module, fun}) do
    Logger.debug("Register verb #{verb} targetted to module #{module}")
    GenServer.call(pid, {:add_verb, {verb, module, fun}})
  end

  @doc """
  Starts the worker. Causes heartbeats to be run and registers itself to the broker
  """
  def run(pid) do
    GenServer.call(pid, :run)
  end

  def handle_call({:add_verb, {verb, module, fun}}, _from, %{handlers: handlers} = state) do
    handlerFn = fn payload, message ->
      apply(module, fun, [payload, message])
    end

    handlers = Map.put(handlers, String.upcase(verb), handlerFn)

    {:reply, :ok, %{state | handlers: handlers}}
  end

  def handle_call(:run, _from, %{config: %{sid: sid, identity: identity} = config, socket: socket} = state) do
    register_msg = Message.new "SMI", "UP"
    register_msg = %Message{register_msg | payload: sid, identity: identity}
    :ok = send_request(socket, register_msg)

    #Run in background and let the Task Supervisor handle supervision for us.
    #Todo, create proper master supervisor outside of this process and link properly
    {:ok, supervisor} = Task.Supervisor.start_link()
    Task.Supervisor.start_child(supervisor, Heartbeat, :start, [socket, config])
    Task.Supervisor.start_child(supervisor, Receiver, :start, [socket, self()])

    {:reply, :ok, state}
  end

  def handle_info({:message, msg}, %{handlers: handlers, socket: socket} = state) do
    handle_msg(msg, socket, handlers)

    {:noreply, state}
  end

  @doc """
  Handles heartbeat REP
  """
  defp handle_msg(%Message{address: %{verb: "HEARTBEAT"}}, _, _) do
    :ok
  end

  @doc """
  Handles UP REP
  """
  defp handle_msg(%Message{address: %{verb: "UP"}}, _, _) do
    :ok
  end

  @doc """
  Handles REQ messages intended to run a registered verb.
  """
  defp handle_msg(%Message{address: %{verb: verb}, type: "REQ"} = msg, socket, handlers) do
    Logger.info("Received message #{msg.identity} routed to #{msg.address.verb}")

    handler_fn = Map.get(handlers, verb)

    case handler_fn do
      handler_fn when is_function(handler_fn) -> #is a function handler
        %{headers: headers, payload: payload} = msg
        {:ok, {result, %{status: status}}} = handler_fn.(payload, headers)
        reply = %Message{msg |
          payload: result,
          status: status,
          type: "REP"
        }
        send_reply(socket, reply)
      _ -> #no matching handler found. Default to 404
        reply = %Message{msg |
          status: @not_found,
          type: "REP"
        }
        send_reply(socket, reply)
    end
  end

  defp handle_msg(_, _, _), do: :ok #match all in case, TODO: log

  defp send_reply(socket, message) do
    Logger.info "Sending reply with id #{message.rid} with code #{message.status} to #{message.identity}"
    :czmq.zsocket_send_all(socket, message |> Message.to_frames)
  end

  #TODO DRY
  defp send_request(socket, message) do
    Logger.info "Sending #{message.identity} with id #{message.rid} to #{message.address.sid}:#{message.address.sversion}##{message.address.verb}"
    :czmq.zsocket_send_all(socket, message |> Message.to_frames)
  end

  @doc """
  Constructs the identity frame for routing
  """
  defp get_identity(sid) do
    "#{sid}##{UUID.uuid1()}"
  end

  @doc """
  Cleans up open resources
  """
  def terminate(_reason, %{socket: socket}) do
    :czmq.zsocket_destroy(socket)
    :normal
  end
end