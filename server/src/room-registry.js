import { randomBytes, randomUUID } from "node:crypto";
import {
  MAX_CODE_GENERATION_ATTEMPTS,
  MAX_NAME_LENGTH,
  MAX_PLAYERS_PER_ROOM,
  MIN_NAME_LENGTH,
  ROOM_CODE_ALPHABET,
  ROOM_CODE_LENGTH,
} from "./constants.js";

export class RoomRegistry {
  #rooms = new Map();
  #sessions = new Map();
  #codeGenerator;
  #idGenerator;

  constructor({ codeGenerator = generateRoomCode, idGenerator = randomUUID } = {}) {
    this.#codeGenerator = codeGenerator;
    this.#idGenerator = idGenerator;
  }

  createRoom(displayName, connectionId) {
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

    const player = this.#makePlayer(normalized, connectionId, roomCode);
    this.#rooms.set(roomCode, { roomCode, players: [player] });
    this.#sessions.set(connectionId, player);
    return success(roomCode, player, this.publicSnapshot(roomCode));
  }

  joinRoom(roomCode, displayName, connectionId) {
    const code = String(roomCode).trim().toUpperCase();
    const room = this.#rooms.get(code);
    if (!isValidRoomCode(code) || !room) return failure("unknown_room");
    if (this.#sessions.has(connectionId)) return failure("connection_already_joined");

    const normalized = normalizeName(displayName);
    const nameError = validateName(normalized);
    if (nameError) return failure(nameError);
    if (room.players.length >= MAX_PLAYERS_PER_ROOM) return failure("room_full");
    const key = comparableName(normalized);
    if (room.players.some((player) => comparableName(player.displayName) === key)) {
      return failure("duplicate_name");
    }

    const player = this.#makePlayer(normalized, connectionId, code);
    room.players.push(player);
    this.#sessions.set(connectionId, player);
    return success(code, player, this.publicSnapshot(code));
  }

  removeConnection(connectionId) {
    const session = this.#sessions.get(connectionId);
    if (!session) return null;
    this.#sessions.delete(connectionId);
    const room = this.#rooms.get(session.roomCode);
    if (!room) return null;
    room.players = room.players.filter((player) => player.connectionId !== connectionId);
    if (room.players.length === 0) {
      this.#rooms.delete(session.roomCode);
      return { roomCode: session.roomCode, snapshot: null };
    }
    return { roomCode: session.roomCode, snapshot: this.publicSnapshot(session.roomCode) };
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
    return (this.#rooms.get(roomCode)?.players ?? []).map((player) => player.connectionId);
  }

  sessionForConnection(connectionId) {
    return this.#sessions.get(connectionId) ?? null;
  }

  roomCount() {
    return this.#rooms.size;
  }

  #makePlayer(displayName, connectionId, roomCode) {
    return {
      playerId: this.#idGenerator(),
      sessionId: this.#idGenerator(),
      displayName,
      connectionId,
      roomCode,
    };
  }
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
  const bytes = randomBytes(ROOM_CODE_LENGTH);
  return [...bytes].map((byte) => ROOM_CODE_ALPHABET[byte % ROOM_CODE_ALPHABET.length]).join("");
}

function success(roomCode, player, snapshot) {
  return {
    ok: true,
    roomCode,
    playerId: player.playerId,
    sessionId: player.sessionId,
    snapshot,
  };
}

function failure(code) {
  return { ok: false, code };
}
