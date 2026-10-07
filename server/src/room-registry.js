import { createHash, randomBytes, randomUUID } from "node:crypto";
import {
  MAX_CODE_GENERATION_ATTEMPTS,
  MAX_NAME_LENGTH,
  MAX_PLAYERS_PER_ROOM,
  MIN_NAME_LENGTH,
  ROOM_CODE_ALPHABET,
  ROOM_CODE_LENGTH,
} from "./constants.js";

const RECONNECT_TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

export class RoomRegistry {
  #rooms = new Map();
  #sessions = new Map();
  #retiredConnections = new Set();
  #tokens = new Map();
  #codeGenerator;
  #idGenerator;
  #tokenGenerator;
  #clock;
  #graceMs;

  constructor({ codeGenerator = generateRoomCode, idGenerator = randomUUID,
    tokenGenerator = generateReconnectToken, clock = () => performance.now(), graceMs = 30_000 } = {}) {
    this.#codeGenerator = codeGenerator;
    this.#idGenerator = idGenerator;
    this.#tokenGenerator = tokenGenerator;
    this.#clock = clock;
    this.#graceMs = graceMs;
  }

  createRoom(displayName, connectionId, { reconnect = false } = {}) {
    this.expireReservations();
    if (this.#retiredConnections.has(connectionId) || this.#sessions.has(connectionId)) {
      return failure("connection_already_joined");
    }
    const normalized = normalizeName(displayName);
    const nameError = validateName(normalized);
    if (nameError) return failure(nameError);

    let roomCode = null;
    for (let attempt = 0; attempt < MAX_CODE_GENERATION_ATTEMPTS; attempt += 1) {
      const candidate = String(this.#codeGenerator()).trim().toUpperCase();
      if (isValidRoomCode(candidate) && !this.#rooms.has(candidate)) {
        roomCode = candidate;
        break;
      }
    }
    if (!roomCode) return failure("room_code_unavailable");

    const player = this.#makePlayer(normalized, connectionId, roomCode, reconnect);
    const token = reconnect ? this.#issueToken(player) : null;
    if (reconnect && !token) return failure("reconnect_token_unavailable");
    this.#rooms.set(roomCode, { roomCode, players: [player] });
    this.#sessions.set(connectionId, player);
    return success(roomCode, player, this.publicSnapshot(roomCode), token);
  }

  joinRoom(roomCode, displayName, connectionId, { reconnect = false } = {}) {
    this.expireReservations();
    if (this.#retiredConnections.has(connectionId) || this.#sessions.has(connectionId)) {
      return failure("connection_already_joined");
    }
    const code = String(roomCode).trim().toUpperCase();
    const room = this.#rooms.get(code);
    if (!isValidRoomCode(code) || !room) return failure("unknown_room");

    const normalized = normalizeName(displayName);
    const nameError = validateName(normalized);
    if (nameError) return failure(nameError);
    if (room.players.length >= MAX_PLAYERS_PER_ROOM) return failure("room_full");
    const key = comparableName(normalized);
    if (room.players.some((player) => comparableName(player.displayName) === key)) {
      return failure("duplicate_name");
    }

    const player = this.#makePlayer(normalized, connectionId, code, reconnect);
    const token = reconnect ? this.#issueToken(player) : null;
    if (reconnect && !token) return failure("reconnect_token_unavailable");
    room.players.push(player);
    this.#sessions.set(connectionId, player);
    return success(code, player, this.publicSnapshot(code), token);
  }

  removeConnection(connectionId) {
    this.#retiredConnections.delete(connectionId);
    const session = this.#sessions.get(connectionId);
    if (!session) return null;
    this.#sessions.delete(connectionId);
    if (session.connectionId !== connectionId) return null;
    const room = this.#rooms.get(session.roomCode);
    if (!room) return null;
    if (session.reconnectable) {
      session.connectionId = null;
      session.expiresAt = this.#clock() + this.#graceMs;
      return { roomCode: session.roomCode, snapshot: this.publicSnapshot(session.roomCode) };
    }
    return this.#dropPlayer(session);
  }

  resumeRoom(roomCode, token, connectionId) {
    this.expireReservations();
    if (this.#retiredConnections.has(connectionId) || this.#sessions.has(connectionId)) {
      return failure("connection_already_joined");
    }
    const code = String(roomCode).trim().toUpperCase();
    const digest = tokenDigest(token);
    const player = this.#tokens.get(digest);
    if (!isValidRoomCode(code) || !player || player.roomCode !== code) {
      return failure("invalid_reconnect");
    }
    const nextToken = this.#issueToken(player);
    if (!nextToken) return failure("reconnect_token_unavailable");
    const replacedConnectionId = player.connectionId;
    if (replacedConnectionId) {
      this.#sessions.delete(replacedConnectionId);
      this.#retiredConnections.add(replacedConnectionId);
    }
    this.#tokens.delete(digest);
    player.connectionId = connectionId;
    player.expiresAt = null;
    player.sessionId = this.#idGenerator();
    this.#sessions.set(connectionId, player);
    return { ...success(code, player, this.publicSnapshot(code), nextToken), replacedConnectionId };
  }

  leaveRoom(connectionId) {
    const player = this.#sessions.get(connectionId);
    if (!player || player.connectionId !== connectionId) return failure("not_in_room");
    this.#sessions.delete(connectionId);
    const removal = this.#dropPlayer(player);
    return { ok: true, roomCode: player.roomCode, snapshot: removal.snapshot };
  }

  expireReservations() {
    const changed = new Set();
    const now = this.#clock();
    for (const room of this.#rooms.values()) {
      for (const player of [...room.players]) {
        if (player.expiresAt !== null && now >= player.expiresAt) {
          this.#dropPlayer(player);
          changed.add(room.roomCode);
        }
      }
    }
    return [...changed];
  }

  publicSnapshot(roomCode) {
    const room = this.#rooms.get(roomCode);
    if (!room) return null;
    return {
      room_code: room.roomCode,
      player_names: room.players.map((player) => player.displayName),
      player_count: room.players.length,
      max_players: MAX_PLAYERS_PER_ROOM,
    };
  }

  connectionIdsForRoom(roomCode) {
    return (this.#rooms.get(roomCode)?.players ?? []).map((player) => player.connectionId).filter(Boolean);
  }

  sessionForConnection(connectionId) {
    return this.#sessions.get(connectionId) ?? null;
  }

  roomCount() {
    return this.#rooms.size;
  }

  #makePlayer(displayName, connectionId, roomCode, reconnectable) {
    const player = {
      playerId: this.#idGenerator(),
      sessionId: this.#idGenerator(),
      displayName,
      connectionId,
      roomCode,
      reconnectable,
      expiresAt: null,
    };
    return player;
  }

  #issueToken(player) {
    for (let attempt = 0; attempt < 8; attempt += 1) {
      const token = this.#tokenGenerator();
      if (typeof token !== "string" || !RECONNECT_TOKEN_PATTERN.test(token)) continue;
      const digest = tokenDigest(token);
      if (!this.#tokens.has(digest)) {
        this.#tokens.set(digest, player);
        player.tokenDigest = digest;
        return token;
      }
    }
    return null;
  }

  #dropPlayer(player) {
    if (player.tokenDigest) this.#tokens.delete(player.tokenDigest);
    const room = this.#rooms.get(player.roomCode);
    if (!room) return { roomCode: player.roomCode, snapshot: null };
    room.players = room.players.filter((member) => member !== player);
    if (room.players.length === 0) this.#rooms.delete(player.roomCode);
    return { roomCode: player.roomCode, snapshot: this.publicSnapshot(player.roomCode) };
  }
}

export function generateReconnectToken() {
  return randomBytes(32).toString("base64url");
}

function tokenDigest(token) {
  return createHash("sha256").update(String(token)).digest("hex");
}

export function normalizeName(value) {
  return typeof value === "string" ? value.trim().normalize("NFKC") : "";
}

export function comparableName(value) {
  return normalizeName(value).toLocaleLowerCase("en-US");
}

export function validateName(value) {
  const length = [...value].length;
  return length < MIN_NAME_LENGTH || length > MAX_NAME_LENGTH ? "invalid_name" : null;
}

export function isValidRoomCode(value) {
  return (
    value.length === ROOM_CODE_LENGTH &&
    [...value].every((character) => ROOM_CODE_ALPHABET.includes(character))
  );
}

export function generateRoomCode() {
  const accepted = [];
  const uniformLimit = 256 - (256 % ROOM_CODE_ALPHABET.length);
  while (accepted.length < ROOM_CODE_LENGTH) {
    for (const byte of randomBytes(ROOM_CODE_LENGTH)) {
      if (byte < uniformLimit) accepted.push(byte);
      if (accepted.length === ROOM_CODE_LENGTH) break;
    }
  }
  return accepted.map((byte) => ROOM_CODE_ALPHABET[byte % ROOM_CODE_ALPHABET.length]).join("");
}

function success(roomCode, player, snapshot, token = null) {
  return {
    ok: true,
    roomCode,
    playerId: player.playerId,
    sessionId: player.sessionId,
    ...(token ? { reconnectToken: token } : {}),
    snapshot,
  };
}

function failure(code) {
  return { ok: false, code };
}
