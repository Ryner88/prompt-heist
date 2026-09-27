import Ajv from "ajv";
import { MAX_PAYLOAD_BYTES, PROTOCOL_VERSION } from "./constants.js";
import { clientMessageSchemas } from "./schemas.js";

const ajv = new Ajv({ allErrors: true, strict: true });
const validators = Object.fromEntries(
  Object.entries(clientMessageSchemas).map(([type, schema]) => [type, ajv.compile(schema)]),
);
const REQUEST_ID_PATTERN = /^[A-Za-z0-9._:-]{1,128}$/;

export function decodeClientMessage(data, isBinary = false) {
  const size = Buffer.isBuffer(data) ? data.byteLength : Buffer.byteLength(String(data));
  if (size === 0) return failure("empty_message");
  if (size > MAX_PAYLOAD_BYTES) return failure("payload_too_large");
  if (isBinary) return failure("unsupported_message_type");

  let message;
  try {
    message = JSON.parse(String(data));
  } catch {
    return failure("malformed_message");
  }
  if (!message || typeof message !== "object" || Array.isArray(message)) {
    return failure("invalid_message");
  }
  const requestId = typeof message.request_id === "string" ? message.request_id : null;
  if (message.version !== PROTOCOL_VERSION) {
    return failure("unsupported_version", requestId);
  }
  if (typeof message.type !== "string" || !validators[message.type]) {
    return failure("unsupported_command", requestId);
  }
  if (!validators[message.type](message)) {
    return failure("invalid_message", requestId);
  }
  return { ok: true, message };
}

export function response(type, payload, requestId = null) {
  return {
    version: PROTOCOL_VERSION,
    type,
    request_id: requestId,
    payload,
  };
}

export function errorResponse(code, requestId = null) {
  return response("error", { code }, requestId);
}

export function recoverRequestId(data, isBinary = false) {
  if (isBinary) return null;
  try {
    const message = JSON.parse(String(data));
    return typeof message?.request_id === "string" && REQUEST_ID_PATTERN.test(message.request_id)
      ? message.request_id
      : null;
  } catch {
    return null;
  }
}

function failure(code, requestId = null) {
  return { ok: false, response: errorResponse(code, requestId) };
}
