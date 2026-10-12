// IPC contract tests for @swiftcode/sdk (Docs/Intro-to-SDK.md §19.1, §19.3).
//
// Loads the real compiled dist/index.js and exercises the real
// createStdioConnection over a loopback PassThrough pair: nothing about
// the unit under test is mocked. The "host" side is a scripted fake host
// writing raw NDJSON frames — the tests verify the package's real wire
// behavior against scripted host frames.
//
// Run: `npm run build && npm test` (npm test = `node --test tests/`).
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { PassThrough } from "node:stream";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const distUrl = pathToFileURL(
  path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist", "index.js"),
).href;
const { createStdioConnection, SDKError, SDK_PROTOCOL_VERSION } = await import(distUrl);

/** NDJSON line reader over a stream: returns a fn resolving the next raw line. */
function lineReader(stream) {
  let buffer = "";
  const lines = [];
  const waiters = [];
  function drain() {
    while (lines.length > 0 && waiters.length > 0) {
      waiters.shift()(lines.shift());
    }
  }
  stream.on("data", (chunk) => {
    buffer += chunk.toString("utf8");
    let index;
    while ((index = buffer.indexOf("\n")) !== -1) {
      lines.push(buffer.slice(0, index));
      buffer = buffer.slice(index + 1);
    }
    drain();
  });
  return () =>
    new Promise((resolve) => {
      waiters.push(resolve);
      drain();
    });
}

/**
 * Loopback IPC pair. `connection` is the real SDK connection under test;
 * the test plays the scripted host: it reads the extension's frames from
 * `nextRequestLine` and writes raw frames back via `hostWrite`.
 */
function makeLoopback() {
  const hostToExt = new PassThrough(); // host→extension ("stdin")
  const extToHost = new PassThrough(); // extension→host ("stdout")
  const connection = createStdioConnection(hostToExt, extToHost);
  const nextRequestLine = lineReader(extToHost);
  return {
    connection,
    nextRequestLine,
    /** Raw chunk to the extension, no newline added. */
    hostWriteRaw(chunk) {
      hostToExt.write(chunk);
    },
    /** One complete NDJSON frame to the extension. */
    hostWriteFrame(frame) {
      hostToExt.write(`${JSON.stringify(frame)}\n`);
    },
    /** Scripted ok:true response. */
    hostRespondOk(requestId, payload) {
      hostToExt.write(
        `${JSON.stringify({ protocolVersion: 1, type: "response", requestId, ok: true, payload })}\n`,
      );
    },
  };
}

/** Silences the SDK's stderr diagnostics for one synchronous-ish span. */
function swallowStderr() {
  const original = process.stderr.write.bind(process.stderr);
  process.stderr.write = () => true;
  return () => {
    process.stderr.write = original;
  };
}

describe("ipc", () => {
  it("NDJSON framing round-trip over the real connection", async () => {
    const { connection, nextRequestLine, hostWriteRaw } = makeLoopback();
    const pending = connection.request("echo", { a: 1 }, "r-1");

    const wire = JSON.parse(await nextRequestLine());
    assert.equal(wire.protocolVersion, SDK_PROTOCOL_VERSION);
    assert.equal(wire.protocolVersion, 1);
    assert.equal(wire.type, "request");
    assert.equal(wire.requestId, "r-1");
    assert.equal(wire.method, "echo");
    assert.deepEqual(wire.payload, { a: 1 });

    // Deliver the response split across two chunks: framing must reassemble.
    const response = JSON.stringify({
      protocolVersion: 1,
      type: "response",
      requestId: "r-1",
      ok: true,
      payload: { a: 1, b: 2 },
    });
    hostWriteRaw(`${response.slice(0, 40)}`);
    hostWriteRaw(`${response.slice(40)}\n`);

    assert.deepEqual(await pending, { a: 1, b: 2 });
    connection.close();
  });

  it("10 concurrent requests correlate to the right responses", async () => {
    const { connection, nextRequestLine, hostRespondOk } = makeLoopback();
    const count = 10;
    const ids = Array.from({ length: count }, (_, i) => `req-${i}`);
    const pending = ids.map((requestId, i) => connection.request("work", { index: i }, requestId));

    // Read all 10 request frames first…
    const frames = [];
    for (let i = 0; i < count; i++) frames.push(JSON.parse(await nextRequestLine()));
    assert.deepEqual(
      frames.map((f) => f.requestId).sort(),
      ids.slice().sort(),
    );
    // …then answer in REVERSE order: correlation must be by requestId,
    // not by arrival order.
    for (let i = count - 1; i >= 0; i--) {
      hostRespondOk(ids[i], { index: i, echoed: frames[i].payload.index });
    }

    const results = await Promise.all(pending);
    for (let i = 0; i < count; i++) {
      assert.deepEqual(results[i], { index: i, echoed: i });
    }
    connection.close();
  });

  it("ok:false response throws SDKError carrying code/message/correlationId", async () => {
    const { connection, nextRequestLine, hostWriteFrame } = makeLoopback();
    const pending = connection.request("denied", {}, "r-denied");
    await nextRequestLine(); // consume the request frame
    hostWriteFrame({
      protocolVersion: 1,
      type: "response",
      requestId: "r-denied",
      ok: false,
      error: { code: "PERMISSION_DENIED", message: "Not granted.", correlationId: "corr-123" },
    });
    await assert.rejects(pending, (error) => {
      assert.ok(error instanceof SDKError, `expected SDKError, got ${error?.constructor?.name}`);
      assert.equal(error.name, "SDKError");
      assert.equal(error.code, "PERMISSION_DENIED");
      assert.equal(error.message, "Not granted.");
      assert.equal(error.correlationId, "corr-123");
      return true;
    });
    connection.close();
  });

  it("response with protocolVersion 2 rejects with IPC_PROTOCOL_MISMATCH", async () => {
    const { connection, nextRequestLine, hostWriteFrame } = makeLoopback();
    const pending = connection.request("m", {}, "r-v2");
    await nextRequestLine();
    hostWriteFrame({
      protocolVersion: 2,
      type: "response",
      requestId: "r-v2",
      ok: true,
      payload: {},
    });
    await assert.rejects(pending, (error) => {
      assert.ok(error instanceof SDKError);
      assert.equal(error.code, "IPC_PROTOCOL_MISMATCH");
      assert.match(error.message, /version 2/);
      return true;
    });
    connection.close();
  });

  it("malformed JSON frame is ignored and the connection survives", async () => {
    const restore = swallowStderr();
    try {
      const { connection, nextRequestLine, hostWriteRaw, hostRespondOk } = makeLoopback();
      const pending = connection.request("ping", {}, "r-ping");
      await nextRequestLine();
      hostWriteRaw("this is not json at all\n");
      hostWriteRaw('{"type":"response","requestId":"no-such-request","ok":true,"payload":{}}\n');
      hostWriteRaw("\n"); // blank line: ignored, never a frame
      hostRespondOk("r-ping", { pong: true });
      assert.deepEqual(await pending, { pong: true });
      connection.close();
    } finally {
      restore();
    }
  });

  it("event frame with protocolVersion != 1 is ignored (mirrors Swift SDKIPCDispatcher)", async () => {
    const restore = swallowStderr();
    try {
      const { connection, hostWriteRaw } = makeLoopback();
      const seen = [];
      connection.onEvent((event) => seen.push(event.name));
      // v2 event must NOT reach listeners; v1 event must.
      hostWriteRaw('{"protocolVersion":2,"type":"event","requestId":"v2","event":"commands.execute","payload":{}}\n');
      hostWriteRaw('{"protocolVersion":1,"type":"event","requestId":"v1","event":"shutdown","payload":{}}\n');
      await new Promise((resolve) => setImmediate(resolve));
      assert.deepEqual(seen, ["shutdown"]);
      connection.close();
    } finally {
      restore();
    }
  });

  it('sendEvent emits a well-formed type:"event" envelope with protocolVersion 1', async () => {
    const { connection, nextRequestLine } = makeLoopback();
    connection.sendEvent("lifecycle.activated", { extensionId: "demo.ext" });
    const wire = JSON.parse(await nextRequestLine());
    assert.equal(wire.protocolVersion, 1);
    assert.equal(wire.type, "event");
    assert.equal(wire.event, "lifecycle.activated");
    assert.deepEqual(wire.payload, { extensionId: "demo.ext" });
    assert.equal(typeof wire.requestId, "string");
    assert.ok(wire.requestId.length > 0);
    connection.close();
  });

  it("close() rejects pending requests instead of hanging", async () => {
    const { connection } = makeLoopback();
    assert.equal(connection.closed, false);
    const pending = connection.request("never-answered", {});
    // Attach the rejection assertion BEFORE closing: nothing may hang.
    const assertion = assert.rejects(pending, (error) => {
      assert.ok(error instanceof SDKError);
      assert.equal(error.code, "IPC_CLOSED");
      return true;
    });
    connection.close();
    assert.equal(connection.closed, true);
    await assertion;
  });
});
