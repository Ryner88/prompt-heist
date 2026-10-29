import http from "node:http";
import { randomUUID } from "node:crypto";
import { createReadStream, statSync } from "node:fs";
import { join } from "node:path";
import { WebSocket, WebSocketServer } from "ws";
import {
  MAX_PAYLOAD_BYTES,
  PROTOCOL_VERSION,
  REQUEST_CACHE_SIZE,
  WEBSOCKET_PATH,
} from "./constants.js";
import { decodeClientMessage, errorResponse, recoverRequestId, response } from "./protocol.js";
import { FixedWindowRateLimiter } from "./rate-limiter.js";
import { RoomRegistry } from "./room-registry.js";

export function createPromptHeistServer({ registry = new RoomRegistry(), logger = defaultLogger,
  sweepIntervalMs = 1_000, staticDir = process.env.STATIC_DIR ?? null } = {}) {
  const connections = new Map();
  let ready = false;
  let shuttingDown = false;
  let refreshTicks = 0;
  const expiryTimer = setInterval(() => {
    sweepExpiredSeats();
    if (++refreshTicks % 5 === 0) {
      for (const roomCode of registry.roomCodes()) {
        broadcastSnapshot(roomCode);
        broadcastMatch(roomCode);
      }
    }
  }, sweepIntervalMs);
  expiryTimer.unref();

  const httpServer = http.createServer((request, reply) => {
    if (request.method === "GET" && request.url === "/healthz") {
      const healthy = ready && !shuttingDown;
      reply.writeHead(healthy ? 200 : 503, { "content-type": "application/json" });
      reply.end(JSON.stringify({ status: healthy ? "ready" : "unavailable", protocol_version: PROTOCOL_VERSION }));
      return;
    }
    if (staticDir && (request.method === "GET" || request.method === "HEAD")) {
      const pathname = new URL(request.url ?? "/", "http://localhost").pathname;
      const asset = pathname === "/" ? "index.html" : pathname.slice(1);
      if (/^index(?:\.[A-Za-z0-9_-]+)*\.(?:html|js|wasm|pck|png|ico)$/.test(asset)) {
        const file = join(staticDir, asset);
        try {
          const info = statSync(file);
          if (info.isFile()) {
            const extension = asset.slice(asset.lastIndexOf("."));
            const mime = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
              ".wasm": "application/wasm", ".pck": "application/octet-stream",
              ".png": "image/png", ".ico": "image/x-icon" }[extension];
            reply.writeHead(200, { "content-type": mime, "content-length": info.size,
              "cache-control": "no-cache", "x-content-type-options": "nosniff" });
            if (request.method === "HEAD") reply.end();
            else createReadStream(file).pipe(reply);
            return;
          }
        } catch { /* Missing files receive the same 404 as other paths. */ }
      }
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
      retired: false,
    };
    connections.set(connectionId, context);
    logger("connection_opened", { active_connections: connections.size });

    websocket.on("message", (data, isBinary) => handleMessage(context, data, isBinary));
    websocket.on("error", () => logger("connection_error", {}));
    websocket.on("close", () => {
      if (!connections.delete(connectionId)) return;
      const removal = registry.removeConnection(connectionId);
      if (removal?.snapshot) {
        broadcastSnapshot(removal.roomCode);
        broadcastMatch(removal.roomCode);
      }
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
    // A resumed session invalidates its previous socket immediately, even if
    // that socket has messages queued before the close handshake finishes.
    if (context.retired) return;
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

    const result = dispatch(context, message);
    const bindsSeat = SEAT_COMMANDS.has(message.type);
    const direct = result.ok
      ? response(
          "command_result",
          !bindsSeat ? { command: message.type, room_code: result.roomCode } : {
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
      if (result.replacedConnectionId) {
        const replaced = connections.get(result.replacedConnectionId);
        if (replaced) {
          replaced.retired = true;
          replaced.websocket.close(1000, "session replaced");
        }
      }
      if (MATCH_COMMANDS.has(message.type)) {
        if (result.changed === false) return;
        broadcastMatch(result.roomCode);
        const match = registry.publicMatchSnapshot(result.roomCode);
        if (message.type === "start_match") logger("match_started", { players: match.seats.length, mode: match.mode });
        else if (match.phase === "finished") logger("match_finished", { winner: match.outcome.winner });
        return;
      }
      if (message.type !== "leave_room" || result.snapshot) {
        broadcastSnapshot(result.roomCode);
        broadcastMatch(result.roomCode);
      }
    }
  }

  function dispatch(context, message) {
    const { payload } = message;
    const capabilities = { sync: payload.sync === true, game: payload.game === true };
    switch (message.type) {
      case "create_room":
        if (registry.sessionForConnection(context.connectionId)) return { ok: false, code: "connection_already_joined" };
        return registry.createRoom(payload.display_name, context.connectionId, {
          reconnect: payload.reconnect === true,
          ...capabilities,
        });
      case "join_room":
        return registry.joinRoom(payload.room_code, payload.display_name, context.connectionId, {
          reconnect: payload.reconnect === true,
          ...capabilities,
        });
      case "resume_room":
        return registry.resumeRoom(payload.room_code, payload.reconnect_token, context.connectionId, capabilities);
      case "leave_room":
        return registry.leaveRoom(context.connectionId);
      case "start_match":
        return registry.startMatch(context.connectionId);
      case "ready":
        return registry.matchAction(context.connectionId, (match, playerId) => match.ready(playerId, payload.phase, payload.round));
      case "cast_vote":
        return registry.matchAction(context.connectionId, (match, playerId) =>
          match.castVote(playerId, payload.round, payload.plan_id, { sabotage: payload.sabotage === true }));
      case "use_ability":
        return registry.matchAction(context.connectionId, (match, playerId) =>
          match.useAbility(playerId, payload.round, payload.target_plan_id ?? null));
      default:
        return registry.matchAction(context.connectionId, (match, playerId) => match.accuse(playerId, payload.suspect_seat));
    }
  }

  /**
   * Sends every game-capable member the shared public view and, separately,
   * only that member's private seat view.
   */
  function broadcastMatch(roomCode) {
    const snapshot = registry.publicMatchSnapshot(roomCode);
    if (!snapshot) return;
    for (const connectionId of registry.matchConnectionIdsForRoom(roomCode)) {
      const context = connections.get(connectionId);
      if (!context) continue;
      send(context.websocket, response("match_snapshot", snapshot));
      const privateState = registry.privateMatchState(connectionId);
      if (privateState) send(context.websocket, response("match_private", privateState));
    }
  }

  function sweepExpiredSeats() {
    for (const roomCode of registry.expireReservations()) {
      broadcastSnapshot(roomCode);
      broadcastMatch(roomCode);
    }
  }

  function broadcastSnapshot(roomCode) {
    const legacy = registry.publicSnapshot(roomCode);
    if (!legacy) return;
    const revisioned = registry.publicSnapshot(roomCode, { revision: true });
    for (const connectionId of registry.connectionIdsForRoom(roomCode)) {
      const context = connections.get(connectionId);
      if (context) {
        const session = registry.sessionForConnection(connectionId);
        send(context.websocket, response("room_snapshot", session?.sync ? revisioned : legacy));
      }
    }
  }

  return { listen, close, sendPrivate, httpServer, registry };
}

// Commands whose direct result binds a seat and carries its private identity.
const SEAT_COMMANDS = new Set(["create_room", "join_room", "resume_room"]);
const MATCH_COMMANDS = new Set(["start_match", "ready", "cast_vote", "use_ability", "accuse"]);

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
