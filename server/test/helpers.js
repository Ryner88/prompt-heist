import assert from "node:assert/strict";
import { once } from "node:events";
import WebSocket from "ws";
import { createPromptHeistServer } from "../src/server.js";

export async function startTestServer(options = {}) {
  const logs = [];
  const service = createPromptHeistServer({
    logger: (event, fields) => logs.push({ event, ...fields }),
    ...options,
  });
  const address = await service.listen();
  return {
    service,
    logs,
    httpUrl: `http://127.0.0.1:${address.port}`,
    websocketUrl: `ws://127.0.0.1:${address.port}/ws`,
  };
}

export async function connectClient(url) {
  const websocket = new WebSocket(url);
  const messages = [];
  const waiters = [];
  websocket.on("message", (data) => {
    const message = JSON.parse(String(data));
    messages.push(message);
    for (const waiter of [...waiters]) {
      if (waiter.predicate(message)) {
        waiters.splice(waiters.indexOf(waiter), 1);
        clearTimeout(waiter.timer);
        waiter.resolve(message);
      }
    }
  });
  await once(websocket, "open");
  return {
    websocket,
    messages,
    send(message) {
      websocket.send(typeof message === "string" ? message : JSON.stringify(message));
    },
    next(predicate = () => true, timeoutMs = 1_000) {
      const existing = messages.find(predicate);
      if (existing) return Promise.resolve(existing);
      return new Promise((resolve, reject) => {
        const waiter = { predicate, resolve, timer: null };
        waiter.timer = setTimeout(() => {
          const index = waiters.indexOf(waiter);
          if (index >= 0) waiters.splice(index, 1);
          reject(new Error(`Timed out waiting for message; received ${JSON.stringify(messages)}`));
        }, timeoutMs);
        waiters.push(waiter);
      });
    },
    clear() {
      messages.length = 0;
    },
    async close() {
      if (websocket.readyState === WebSocket.CLOSED) return;
      websocket.close();
      await once(websocket, "close");
    },
  };
}

export function command(type, requestId, payload) {
  return { version: 1, type, request_id: requestId, payload };
}

export async function createRoom(client, name = "Ada", requestId = "create-1") {
  client.send(command("create_room", requestId, { display_name: name }));
  const result = await client.next(
    (message) => message.type === "command_result" && message.request_id === requestId,
  );
  assert.equal(result.payload.command, "create_room");
  return result;
}
