import {
  MAX_NAME_LENGTH,
  MIN_NAME_LENGTH,
  PROTOCOL_VERSION,
  ROOM_CODE_ALPHABET,
  ROOM_CODE_LENGTH,
} from "./constants.js";

const requestId = {
  type: "string",
  minLength: 1,
  maxLength: 128,
  pattern: "^[A-Za-z0-9._:-]+$",
};

const displayName = {
  type: "string",
  minLength: MIN_NAME_LENGTH,
  maxLength: MAX_NAME_LENGTH + 2,
};

const roomCode = {
  type: "string",
  minLength: ROOM_CODE_LENGTH,
  maxLength: ROOM_CODE_LENGTH + 2,
  pattern: `^[${ROOM_CODE_ALPHABET.toLowerCase()}${ROOM_CODE_ALPHABET} ]+$`,
};

const reconnectToken = {
  type: "string",
  pattern: "^[A-Za-z0-9_-]{43}$",
};

const envelope = (type, payload) => ({
  $id: `prompt-heist/v${PROTOCOL_VERSION}/${type}`,
  type: "object",
  additionalProperties: false,
  required: ["version", "type", "request_id", "payload"],
  properties: {
    version: { const: PROTOCOL_VERSION },
    type: { const: type },
    request_id: requestId,
    payload,
  },
});

export const clientMessageSchemas = {
  create_room: envelope("create_room", {
    type: "object",
    additionalProperties: false,
    required: ["display_name"],
    properties: { display_name: displayName, reconnect: { const: true } },
  }),
  join_room: envelope("join_room", {
    type: "object",
    additionalProperties: false,
    required: ["room_code", "display_name"],
    properties: {
      room_code: roomCode,
      display_name: displayName,
      reconnect: { const: true },
    },
  }),
  resume_room: envelope("resume_room", {
    type: "object",
    additionalProperties: false,
    required: ["room_code", "reconnect_token"],
    properties: { room_code: roomCode, reconnect_token: reconnectToken },
  }),
  leave_room: envelope("leave_room", {
    type: "object",
    additionalProperties: false,
    required: [],
    properties: {},
  }),
};
