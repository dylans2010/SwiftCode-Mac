// Two-way sync test for the ScopesIDLists pair.
//
// Enforces that `src/ScopesIDLists.ts` (TypeScript) and
// `ycode/Sources/YcodeSDK/Host/ScopesIDLists.swift` (host) stay identical:
// the same capability IDs, the same scope kinds, and the same primary IPC
// methods. It also enforces that every `kind: "view"` entry in the list
// has a real opener registered in
// `ycode/Sources/YcodeSDK/Host/ViewOpener/SDKViewOpenerBuiltIns.swift` —
// and that every registered opener has a matching `view` entry in the list.
//
// PARSING APPROACH (documented here so the contract is explicit):
//   1. The TypeScript side comes from the compiled `dist/index.js`
//      (`SCOPES_ID_LIST`, `SCOPES_BY_ID`) — run `npm run build` first,
//      exactly like the other package tests.
//   2. The Swift side is read from disk as text and parsed with a regex
//      that matches the canonical single-line `ScopeEntry(...)` literal
//      shape used in `ScopesIDLists.swift` (fields in fixed order: id,
//      title, description, kind, ipcMethod, capabilityId, viewId —
//      `ipcMethod`/`viewId` may be omitted entirely, defaulting to nil).
//      If that shape ever changes, this test must be updated in the same
//      change — the test fails loudly rather than silently comparing
//      nothing.
//   3. Registered view IDs are collected from
//      `SDKViewOpenerBuiltIns.swift` (direct `register(viewID: "...")`
//      string-literal calls and `SDK<Area>ViewOpener.register()` sibling
//      calls, resolved by reading each sibling file's
//      `static let viewID = "..."` line). The IDs are already wire IDs,
//      so no enum-case mapping is needed; each one is still checked
//      against `SDKCapabilityID`'s raw values in
//      `ycode/Sources/YcodeExtensions/Capabilities.swift`, so a renamed
//      raw value breaks this test rather than the mapping.
//
// This test FAILS when someone adds an ID to one file and not the other —
// that is the entire point of the ScopesIDLists pair.
//
// Run: `npm run build && npm test` (npm test = `node --test "tests/*.test.mjs"`).
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const testsDir = path.dirname(fileURLToPath(import.meta.url));
// tests/ -> package/ -> sdk/ -> repo root (Wave 15: destination layout).
const repoRoot = path.resolve(testsDir, "..", "..", "..");
const swiftScopesPath = path.join(
  repoRoot,
  "ycode",
  "Sources",
  "YcodeSDK",
  "Host",
  "ScopesIDLists.swift",
);
const swiftCapabilityPath = path.join(
  repoRoot,
  "ycode",
  "Sources",
  "YcodeExtensions",
  "Capabilities.swift",
);
const swiftBuiltInsPath = path.join(
  repoRoot,
  "ycode",
  "Sources",
  "YcodeSDK",
  "Host",
  "ViewOpener",
  "SDKViewOpenerBuiltIns.swift",
);

const distUrl = pathToFileURL(
  path.join(testsDir, "..", "dist", "index.js"),
).href;
const { SCOPES_ID_LIST, SCOPES_BY_ID } = await import(distUrl);

/**
 * Parses the Swift `ScopesIDLists.all` table from disk. Returns the parsed
 * entries in file order. Asserts the table is non-empty and has no duplicate
 * IDs — a silent parse failure (zero entries) is itself a failure, so a
 * formatting change that breaks the regex cannot go unnoticed.
 *
 * Destination shape: single-line `ScopeEntry(...)` literals, fields in
 * fixed order; `ipcMethod` and `viewId` may be omitted (default nil).
 */
function parseSwiftScopeEntries() {
  const src = readFileSync(swiftScopesPath, "utf8");
  // Groups: 1 id, 2 title, 3 description, 4 kind, 5 ipcMethod raw
  // (nil | "..." | absent), 6 ipcMethod string, 7 capability case,
  // 8 viewId raw (nil | "..." | absent), 9 viewId string.
  const entryRe =
    /ScopeEntry\(\s*id:\s*"([^"]+)",\s*title:\s*"([^"]*)",\s*description:\s*"([^"]*)",\s*kind:\s*\.(\w+)(?:,\s*ipcMethod:\s*(nil|"([^"]*)"))?,\s*capabilityId:\s*\.(\w+)(?:,\s*viewId:\s*(nil|"([^"]*)"))?\s*\)/g;
  const entries = [];
  for (const m of src.matchAll(entryRe)) {
    entries.push({
      id: m[1],
      kind: m[4],
      ipcMethod: m[5] === undefined || m[5] === "nil" ? null : m[6],
      capabilityCase: m[7],
      viewId: m[8] === undefined || m[8] === "nil" ? null : m[9],
    });
  }
  assert.ok(
    entries.length > 0,
    `ScopesIDLists.swift: parsed 0 ScopeEntry blocks — the regex no longer matches the file's shape; update tests/scopes-sync.test.mjs`,
  );
  const dupes = entries
    .map((e) => e.id)
    .filter((id, i, arr) => arr.indexOf(id) !== i);
  assert.deepEqual(dupes, [], `ScopesIDLists.swift: duplicate IDs: ${dupes}`);
  return entries;
}

/**
 * Maps `SDKCapabilityID` enum case names to their wire raw values by
 * parsing `case <name> = "<raw>"` in `ycode/Sources/YcodeExtensions/
 * Capabilities.swift`. Used so the opener-registration check works with
 * wire IDs, and so a raw-value rename fails this test rather than
 * silently mismatching.
 */
function parseCapabilityCaseMap() {
  const src = readFileSync(swiftCapabilityPath, "utf8");
  const map = new Map();
  for (const m of src.matchAll(/case\s+(\w+)\s*=\s*"([^"]+)"/g)) {
    map.set(m[1], m[2]);
  }
  assert.ok(
    map.size > 0,
    "Capabilities.swift: parsed 0 capability cases — update the test",
  );
  return map;
}

/**
 * Collects the wire view IDs registered by `registerBuiltInOpeners()`:
 * direct `register(viewID: "...")` string-literal calls, plus
 * `SDK<Area>ViewOpener.register()` sibling calls (resolved by reading
 * each sibling file's `static let viewID = "..."` line).
 */
function parseRegisteredViewIDs() {
  const src = readFileSync(swiftBuiltInsPath, "utf8");
  const ids = new Set();
  for (const m of src.matchAll(/register\(viewID:\s*"([^"]+)"\)/g)) {
    ids.add(m[1]);
  }
  for (const m of src.matchAll(/await (SDK\w+ViewOpener)\.register\(\)/g)) {
    const siblingName = m[1];
    const siblingSrc = readFileSync(
      path.join(path.dirname(swiftBuiltInsPath), `${siblingName}.swift`),
      "utf8",
    );
    const viewMatch = siblingSrc.match(/static let viewID = "([^"]+)"/);
    assert.ok(
      viewMatch,
      `${siblingName}.swift: could not parse its static viewID`,
    );
    ids.add(viewMatch[1]);
  }
  assert.ok(
    ids.size > 0,
    "SDKViewOpenerBuiltIns.swift: parsed 0 registered view IDs — update the test",
  );
  return ids;
}

describe("ScopesIDLists two-way sync", () => {
  it("TypeScript list is well-formed", () => {
    assert.ok(Array.isArray(SCOPES_ID_LIST) && SCOPES_ID_LIST.length > 0);
    const ids = SCOPES_ID_LIST.map((e) => e.id);
    assert.deepEqual(
      [...new Set(ids)],
      ids,
      "ScopesIDLists.ts: duplicate IDs",
    );
    for (const entry of SCOPES_ID_LIST) {
      assert.ok(
        entry.kind === "view" || entry.kind === "api",
        `TS entry ${entry.id}: bad kind ${entry.kind}`,
      );
      assert.ok(
        entry.ipcMethod === null || typeof entry.ipcMethod === "string",
        `TS entry ${entry.id}: ipcMethod must be a string or null`,
      );
      if (entry.kind === "view") {
        assert.equal(
          entry.ipcMethod,
          "ui.openView",
          `TS view entry ${entry.id}: ipcMethod must be "ui.openView"`,
        );
        assert.equal(
          entry.viewId,
          entry.id,
          `TS view entry ${entry.id}: viewId must equal the entry id`,
        );
      } else {
        assert.equal(
          entry.viewId,
          undefined,
          `TS API entry ${entry.id}: viewId must be absent`,
        );
      }
      assert.equal(
        entry.capabilityId,
        entry.id,
        `TS entry ${entry.id}: capabilityId must equal the entry id`,
      );
    }
    // SCOPES_BY_ID is the same entries, keyed by id.
    assert.deepEqual(
      Object.keys(SCOPES_BY_ID).sort(),
      ids.sort(),
      "SCOPES_BY_ID keys must match the list IDs",
    );
    for (const id of ids) {
      assert.equal(SCOPES_BY_ID[id], SCOPES_ID_LIST.find((e) => e.id === id));
    }
  });

  it("ID sets are equal in both directions", () => {
    const tsIds = new Set(SCOPES_ID_LIST.map((e) => e.id));
    const swiftEntries = parseSwiftScopeEntries();
    const swiftIds = new Set(swiftEntries.map((e) => e.id));
    const missingInSwift = [...tsIds].filter((id) => !swiftIds.has(id));
    const missingInTs = [...swiftIds].filter((id) => !tsIds.has(id));
    assert.deepEqual(
      missingInSwift,
      [],
      `IDs in ScopesIDLists.ts but missing from ScopesIDLists.swift: ${missingInSwift}`,
    );
    assert.deepEqual(
      missingInTs,
      [],
      `IDs in ScopesIDLists.swift but missing from ScopesIDLists.ts: ${missingInTs}`,
    );
  });

  it("every entry's kind, ipcMethod, and viewId match across the pair", () => {
    const swiftById = new Map(
      parseSwiftScopeEntries().map((e) => [e.id, e]),
    );
    for (const ts of SCOPES_ID_LIST) {
      const swift = swiftById.get(ts.id);
      assert.ok(swift, `Swift table is missing entry ${ts.id}`);
      assert.equal(
        swift.kind,
        ts.kind,
        `kind drift for ${ts.id}: TS=${ts.kind} Swift=${swift.kind}`,
      );
      assert.equal(
        swift.ipcMethod,
        ts.ipcMethod,
        `ipcMethod drift for ${ts.id}: TS=${ts.ipcMethod} Swift=${swift.ipcMethod}`,
      );
      const tsViewId = ts.viewId ?? null;
      assert.equal(
        swift.viewId,
        tsViewId,
        `viewId drift for ${ts.id}: TS=${tsViewId} Swift=${swift.viewId}`,
      );
      // The typed enum case in Swift must name the same capability ID.
      const caseMap = parseCapabilityCaseMap();
      assert.ok(
        caseMap.has(swift.capabilityCase),
        `Swift entry ${ts.id}: capability case .${swift.capabilityCase} is not in SDKCapabilityID`,
      );
      assert.equal(
        caseMap.get(swift.capabilityCase),
        ts.id,
        `capability case drift for ${ts.id}: .${swift.capabilityCase} has raw value "${caseMap.get(swift.capabilityCase)}"`,
      );
    }
  });

  it("every view entry has a registered opener, and every registered opener has a view entry", () => {
    const caseMap = parseCapabilityCaseMap();
    const knownRawIds = new Set(caseMap.values());
    // The registered IDs are already wire IDs; each must be a known
    // SDKCapabilityID raw value, so a raw-value rename fails here.
    const registeredRawIds = parseRegisteredViewIDs();
    for (const id of registeredRawIds) {
      assert.ok(
        knownRawIds.has(id),
        `opener registered for unknown capability ID "${id}"`,
      );
    }
    const viewIds = new Set(
      SCOPES_ID_LIST.filter((e) => e.kind === "view").map((e) => e.id),
    );
    const unregistered = [...viewIds].filter((id) => !registeredRawIds.has(id));
    const unlisted = [...registeredRawIds].filter((id) => !viewIds.has(id));
    assert.deepEqual(
      unregistered,
      [],
      `view entries with no registered opener in SDKViewOpenerBuiltIns.swift: ${unregistered}`,
    );
    assert.deepEqual(
      unlisted,
      [],
      `registered opener IDs missing a "view" entry in ScopesIDLists.ts: ${unlisted}`,
    );
  });
});

// ---------------------------------------------------------------------------
// validate.mjs manifest vocabulary pin (Wave 16 Slice A decision)
//
// The 32-entry CAPABILITY_IDS mirror in sdk/cli/commands/validate.mjs is
// the CANONICAL vocabulary for swiftcode.json `capabilities[].id` —
// deliberately not the 34-case SDKCapabilityID enum. This block pins the
// exact three-way relationship so any drift fails loudly:
//   mirror (validate.mjs) == schema enum (32 entries)
//   mirror = 26 SDKCapabilityID raw values + the 6 `use.Security.*`
//     method scopes (which are NOT enum cases)
//   enum cases NOT in the mirror = exactly the 8 non-manifest ids:
//     assist.ui / assist.headless / assist.main (entitlement-only, never
//     grantable via a manifest) and the 5 security.* method ids (enforced
//     under the single use.Security grant, never granted separately).
// See the DECISION comment above CAPABILITY_IDS in validate.mjs.
// ---------------------------------------------------------------------------

const validateMjsPath = path.join(
  repoRoot,
  "sdk",
  "cli",
  "commands",
  "validate.mjs",
);
const manifestSchemaPath = path.join(
  repoRoot,
  "sdk",
  "Contracts",
  "Manifest",
  "swiftcode-extension-v1.schema.json",
);

function parseValidateMirror() {
  const src = readFileSync(validateMjsPath, "utf8");
  const block = src.match(/const CAPABILITY_IDS = \[([\s\S]*?)\];/);
  assert.ok(block, "validate.mjs: could not find the CAPABILITY_IDS array");
  const ids = [...block[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]);
  assert.ok(ids.length > 0, "validate.mjs: parsed 0 CAPABILITY_IDS entries");
  assert.deepEqual([...new Set(ids)], ids, "validate.mjs: duplicate CAPABILITY_IDS entries");
  return ids;
}

function parseSchemaCapabilityEnum() {
  const schema = JSON.parse(readFileSync(manifestSchemaPath, "utf8"));
  const cap = schema?.properties?.capabilities;
  assert.ok(cap, "schema: missing properties.capabilities");
  assert.equal(
    cap.maxItems,
    32,
    "schema: capabilities maxItems must be 32 (the mirror size)",
  );
  const ids = cap?.items?.properties?.id?.enum;
  assert.ok(Array.isArray(ids) && ids.length > 0, "schema: missing capabilities[].id enum");
  return ids;
}

describe("validate.mjs manifest vocabulary pin", () => {
  it("mirror equals the schema enum (same 32 entries)", () => {
    const mirror = parseValidateMirror();
    const schemaEnum = parseSchemaCapabilityEnum();
    assert.equal(mirror.length, 32, `validate.mjs mirror must have 32 entries, got ${mirror.length}`);
    assert.equal(schemaEnum.length, 32, `schema enum must have 32 entries, got ${schemaEnum.length}`);
    assert.deepEqual(
      [...mirror].sort(),
      [...schemaEnum].sort(),
      "validate.mjs CAPABILITY_IDS must match the schema capabilities[].id enum exactly",
    );
    // The manifest cap in validate.mjs must stay in step with the schema.
    const src = readFileSync(validateMjsPath, "utf8");
    assert.ok(
      /capabilities\.length > 32/.test(src),
      "validate.mjs: the capabilities length cap must be 32",
    );
  });

  it("mirror is 26 SDKCapabilityID values + the 6 use.Security.* method scopes", () => {
    const mirror = parseValidateMirror();
    const enumIds = new Set(parseCapabilityCaseMap().values());
    const inEnum = mirror.filter((id) => enumIds.has(id));
    const notInEnum = mirror.filter((id) => !enumIds.has(id));
    assert.equal(inEnum.length, 26, `mirror must contain 26 SDKCapabilityID values, got ${inEnum.length}: ${inEnum}`);
    assert.deepEqual(
      [...notInEnum].sort(),
      [
        "use.Security.audit",
        "use.Security.crypto",
        "use.Security.keychain",
        "use.Security.policy",
        "use.Security.redaction",
        "use.Security.securePrompt",
      ],
      "the 6 mirror entries outside SDKCapabilityID must be exactly the use.Security.* method scopes",
    );
  });

  it("exactly 8 enum ids are excluded, each for a documented reason", () => {
    const mirror = new Set(parseValidateMirror());
    const enumIds = new Set(parseCapabilityCaseMap().values());
    assert.equal(enumIds.size, 34, `SDKCapabilityID must have 34 cases, got ${enumIds.size}`);
    const excluded = [...enumIds].filter((id) => !mirror.has(id)).sort();
    // Entitlement-only Assist variants: never grantable via a manifest.
    const entitlementOnly = ["assist.headless", "assist.main", "assist.ui"];
    // Method scopes enforced under the single use.Security grant.
    const methodScopes = [
      "security.addValue",
      "security.deleteValue",
      "security.hasValue",
      "security.listValueIDs",
      "security.useValue",
    ];
    assert.deepEqual(
      excluded,
      [...entitlementOnly, ...methodScopes].sort(),
      "the enum ids excluded from the manifest vocabulary must be exactly the 3 entitlement-only assist.* ids + the 5 security.* method ids",
    );
    // The excluded ids stay real runtime surface: the 5 security.* ids
    // are ScopesIDLists entries and the 3 assist.* ids are enum cases
    // with registry entries — this test pins only that they are not
    // manifest-declarable, not that they do not exist.
    const tsIds = new Set(SCOPES_ID_LIST.map((e) => e.id));
    for (const id of methodScopes) {
      assert.ok(tsIds.has(id), `excluded method scope ${id} must remain a ScopesIDLists entry`);
    }
  });
});
