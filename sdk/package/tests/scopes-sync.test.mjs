import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const testsDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(testsDir, "..", "..", "..");
const swiftScopesPath = path.join(
  repoRoot,
  "swiftcode",
  "Sources",
  "SwiftCodeSDK",
  "Host",
  "ScopesIDLists.swift",
);
const swiftCapabilityPath = path.join(
  repoRoot,
  "swiftcode",
  "Sources",
  "SwiftCodeExtensions",
  "Capabilities.swift",
);
const swiftBuiltInsPath = path.join(
  repoRoot,
  "swiftcode",
  "Sources",
  "SwiftCodeSDK",
  "Host",
  "ViewOpener",
  "SDKViewOpenerBuiltIns.swift",
);

const distUrl = pathToFileURL(
  path.join(testsDir, "..", "dist", "index.js"),
).href;
const { SCOPES_ID_LIST, SCOPES_BY_ID } = await import(distUrl);

function parseSwiftScopeEntries() {
  const src = readFileSync(swiftScopesPath, "utf8");
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
    const entitlementOnly = ["assist.headless", "assist.main", "assist.ui"];
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
    const tsIds = new Set(SCOPES_ID_LIST.map((e) => e.id));
    for (const id of methodScopes) {
      assert.ok(tsIds.has(id), `excluded method scope ${id} must remain a ScopesIDLists entry`);
    }
  });
});
