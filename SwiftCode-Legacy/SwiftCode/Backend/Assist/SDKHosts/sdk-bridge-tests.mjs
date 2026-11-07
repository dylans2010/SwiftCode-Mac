import assert from "node:assert";
import {
  toolStateFromSDK,
  toolTimeToISO,
  redactToolText,
  parseModelID,
  extractJSONToolRequest,
} from "./opencode-bridge.mjs";
import {
  stableStringify,
  jsonSchemaToZod,
  toolInputSchema,
  buildHostTools,
  isPrivateIp,
  assertPublicUrl,
} from "./openrouter-bridge.mjs";

assert.equal(toolStateFromSDK({ status: "pending", input: {}, raw: "" }), "pending");
assert.equal(toolStateFromSDK({ status: "running", input: {}, time: { start: 1 } }), "running");
assert.equal(toolStateFromSDK({ status: "completed", input: {}, output: "ok", title: "t", metadata: {}, time: { start: 1, end: 2 } }), "completed");
assert.equal(toolStateFromSDK({ status: "error", input: {}, error: "boom", time: { start: 1, end: 2 } }), "failed");
assert.equal(toolStateFromSDK("completed"), "completed");
assert.equal(toolStateFromSDK({ status: "bogus" }), "failed");
assert.equal(toolStateFromSDK(null), "failed");

assert.equal(toolTimeToISO(1_700_000_000_000), new Date(1_700_000_000_000).toISOString());
assert.equal(toolTimeToISO(1_700_000_000), new Date(1_700_000_000_000).toISOString());
assert.equal(toolTimeToISO(0), "");
assert.equal(toolTimeToISO("not-a-number"), "");

assert.equal(redactToolText("Authorization: Bearer abc.def.ghi"), "Authorization: Bearer [redacted]");
assert.ok(redactToolText('{"password": "hunter2"}').includes("[redacted]"));
assert.ok(!redactToolText('{"password": "hunter2"}').includes("hunter2"));
assert.ok(redactToolText("api_key=sk-live-123").includes("[redacted]"));
assert.equal(redactToolText("plain text, no secrets"), "plain text, no secrets");

assert.deepEqual(parseModelID("opencode:anthropic/claude-sonnet-4-5"),
  { providerID: "anthropic", modelID: "claude-sonnet-4-5" });
assert.deepEqual(parseModelID("opencode:openrouter/moonshotai/kimi-k2"),
  { providerID: "openrouter", modelID: "moonshotai/kimi-k2" });
assert.throws(() => parseModelID("anthropic/claude-sonnet-4-5"), /expected "opencode:/);
assert.throws(() => parseModelID("opencode:anthropic"), /missing "\/"/);
assert.throws(() => parseModelID("opencode:anthropic/claude sonnet"), /whitespace/);

assert.deepEqual(
  extractJSONToolRequest('{"finalResponse": "Hello, world."}'),
  { finalResponse: "Hello, world." });
assert.deepEqual(
  extractJSONToolRequest('{"toolId": "read_file", "input": {"path": "/tmp/x"}}'),
  { toolId: "read_file", input: { path: "/tmp/x" } });
assert.equal(extractJSONToolRequest("just prose, no JSON"), null);

assert.equal(stableStringify({ b: 1, a: { d: 4, c: 3 } }), '{"a":{"c":3,"d":4},"b":1}');

{
  const schema = toolInputSchema({
    type: "object",
    properties: { url: { type: "string" } },
    required: ["url"],
  });
  assert.deepEqual(schema.parse({ url: "https://example.com" }), { url: "https://example.com" });
  assert.throws(() => schema.parse({}));
  const bare = toolInputSchema({ type: "string" });
  assert.deepEqual(bare.parse({ anything: 1 }), { anything: 1 });
  const converted = jsonSchemaToZod({ type: "object", properties: { n: { type: "number" } }, required: [] });
  assert.deepEqual(converted.parse({ n: 2 }), { n: 2 });
}

assert.deepEqual(buildHostTools().map((t) => t.modelName), ["fetch_url", "current_datetime"]);

assert.equal(isPrivateIp("127.0.0.1"), true);
assert.equal(isPrivateIp("10.1.2.3"), true);
assert.equal(isPrivateIp("172.16.0.9"), true);
assert.equal(isPrivateIp("192.168.1.1"), true);
assert.equal(isPrivateIp("169.254.1.1"), true);
assert.equal(isPrivateIp("8.8.8.8"), false);
assert.equal(isPrivateIp("::1"), true);
assert.equal(isPrivateIp("::ffff:127.0.0.1"), true);
assert.equal(isPrivateIp("::ffff:8.8.8.8"), false);
assert.equal(isPrivateIp("fc00::1"), true);

await assert.rejects(() => assertPublicUrl("http://localhost/x"), /localhost/);
await assert.rejects(() => assertPublicUrl("http://127.0.0.1/x"), /private IP/);
await assert.rejects(() => assertPublicUrl("http://[::ffff:10.0.0.5]/x"), /private IP/);
await assert.rejects(() => assertPublicUrl("ftp://example.com/x"), /only http\/https/);
await assert.rejects(() => assertPublicUrl("not a url"), /not a valid URL/);
assert.equal((await assertPublicUrl("https://example.com/")).hostname, "example.com");

console.log("sdk-bridge-tests: all assertions passed");
