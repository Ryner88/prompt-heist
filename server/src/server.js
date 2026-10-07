import http from "node:http";
import { randomUUID } from "node:crypto";
import { WebSocket, WebSocketServer } from "ws";
import {
  MAX_PAYLOAD_BYTES,
  REQUEST_CACHE_SIZE,
  WEBSOCKET_PATH,
} from "./constants.js";
import { decodeClientMessage, errorResponse, recoverRequestId, response } from "./protocol.js";
import { FixedWindowRateLimiter } from "./rate-limiter.js";
import { RoomRegistry } from "./room-registry.js";

export function createPromptHeistServer({ registry = new RoomRegistry(), logger = defaultLogger } = {}) {
  const connections = new Map();
  let ready = false;
  let shuttingDown = false;
  const expiryTimer = setInterval(sweepExpiredSeats, 1_000);
  expiryTimer.unref();

  const httpServer = http.createServer((request, reply) => {
    if (request.method === "GET" && request.url === "/healthz") {
      const healthy = ready && !shuttingDown;
      reply.writeHead(healthy ? 200 : 503, { "content-type": "application/json" });
      reply.end(JSON.stringify({ status: healthy ? "ready" : "unavailable", protocol_version: 1 }));
      return;
    }
    reply.writeHead(404, { "content-type": "application/json" });
    reply.end(JSON.stringify({ error: "not_found" }));
  });

  const websocketServer = new WebSocketServer({ noServer: true, maxPayload: MAX_PAYLOAD_BYTES });

  httpServer.on("upgrade", (request, socket, head) => {
    const path = new URL(request.url ?? "/", "http://localhost").pathname;
    if (shuttingDown || path !== WEBSOCKET_PATH) {
      socket.write("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n");
      socket.destroy();
      return;
    }
    websocketServer.handleUpgrade(request, socket, head, (websocket) => {
      websocketServer.emit("connection", websocket);
    });
  });

  websocketServer.on("connection", (websocket) => {
    const connectionId = randomUUID();
    const context = {
      connectionId,
      websocket,
      limiter: new FixedWindowRateLimiter(),
      requestCache: new Map(),
    };
    connections.set(connectionId, context);
    logger("connection_opened", { active_connections: connections.size });

    websocket.on("message", (data, isBinary) => handleMessage(context, data, isBinary));
    websocket.on("error", () => logger("connection_error", {}));
    websocket.on("close", () => {
      if (!connections.delete(connectionId)) return;
      const removal = registry.removeConnection(connectionId);
      if (removal?.snapshot) broadcastSnapshot(removal.roomCode);
      logger("connection_closed", { active_connections: connections.size });
    });
  });

  async function listen({ port = 0, host = "127.0.0.1" } = {}) {
    await new Promise((resolve, reject) => {
      httpServer.once("error", reject);
      httpServer.listen(port, host, resolve);
    });
    ready = true;
    logger("server_ready", { port: httpServer.address().port });
    return httpServer.address();
  }

  async function close() {
    if (shuttingDown) return;
    shuttingDown = true;
    ready = false;
    clearInterval(expiryTimer);
    for (const context of connections.values()) {
      send(context.websocket, response("server_shutdown", { reason: "service_restart" }));
      context.websocket.close(1012, "service restart");
    }
    await Promise.all([
      new Promise((resolve) => websocketServer.close(resolve)),
      new Promise((resolve) => httpServer.close(resolve)),
    ]);
    logger("server_stopped", {});
  }

  function sendPrivate(connectionId, payload, requestId = null) {
    const context = connections.get(connectionId);
    if (!context || !registry.sessionForConnection(connectionId)) return false;
    return send(context.websocket, response("private_message", payload, requestId));
  }

  function handleMessage(context, data, isBinary) {
    sweepExpiredSeats();
    if (!context.limiter.consume()) {
      send(context.websocket, errorResponse("rate_limited", recoverRequestId(data, isBinary)));
      return;
    }
    const decoded = decodeClientMessage(data, isBinary);
    if (!decoded.ok) {
      send(context.websocket, decoded.response);
      return;
    }

    const { message } = decoded;
    const cached = context.requestCache.get(message.request_id);
    if (cached) {
      send(context.websocket, cached);
      return;
    }

    let result;
    if (message.type === "create_room") {
      if (registry.sessionForConnection(context.connectionId)) {
        result = { ok: false, code: "connection_already_joined" };
      } else {
        result = registry.createRoom(message.payload.display_name, context.connectionId, {
          reconnect: message.payload.reconnect === true,
        });
      }
    } else if (message.type === "join_room") {
      result = registry.joinRoom(
        message.payload.room_code,
        message.payload.display_name,
        context.connectionId,
        { reconnect: message.payload.reconnect === true },
      );
    } else if (message.type === "resume_room") {
      result = registry.resumeRoom(
        message.payload.room_code,
        message.payload.reconnect_token,
        context.connectionId,
      );
    } else {
      result = registry.leaveRoom(context.connectionId);
    }

    const direct = result.ok
      ? response(
          "command_result",
          message.type === "leave_room" ? { command: "leave_room", room_code: result.roomCode } : {
            command: message.type,
            room_code: result.roomCode,
            player_id: result.playerId,
            session_id: result.sessionId,
            ...(result.reconnectToken ? { reconnect_token: result.reconnectToken } : {}),
          },
          message.request_id,
        )
      : errorResponse(result.code, message.request_id);
    cacheResponse(context, message.request_id, direct);
    send(context.websocket, direct);
    if (result.ok) {
      if (result.replacedConnectionId) connections.get(result.replacedConnectionId)?.websocket.close(1000, "session replaced");
      if (message.type !== "leave_room" || result.snapshot) broadcastSnapshot(result.roomCode);
    }
  }

  function sweepExpiredSeats() {
    for (const roomCode of registry.expireReservations()) broadcastSnapshot(roomCode);
  }

  function broadcastSnapshot(roomCode) {
    const snapshot = registry.publicSnapshot(roomCode);
    if (!snapshot) return;
    const message = response("room_snapshot", snapshot);
    for (const connectionId of registry.connectionIdsForRoom(roomCode)) {
      const context = connections.get(connectionId);
      if (context) send(context.websocket, message);
    }
  }

  return { listen, close, sendPrivate, httpServer, registry };
}

function cacheResponse(context, requestId, message) {
  context.requestCache.set(requestId, message);
  if (context.requestCache.size > REQUEST_CACHE_SIZE) {
    context.requestCache.delete(context.requestCache.keys().next().value);
  }
}

function send(websocket, message) {
  if (websocket.readyState !== WebSocket.OPEN) return false;
  websocket.send(JSON.stringify(message));
  return true;
}

function defaultLogger(event, fields) {
  console.log(JSON.stringify({ level: "info", event, ...fields }));
}
