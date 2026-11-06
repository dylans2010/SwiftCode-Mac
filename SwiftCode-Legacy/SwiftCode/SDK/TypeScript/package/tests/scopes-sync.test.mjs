// Two-way sync test for the ScopesIDLists pair.
//
// Enforces that `src/ScopesIDLists.ts` (TypeScript) and
// `SwiftCode/SDK/Host/ScopesIDLists.swift` (host) stay identical: the same
// capability IDs, the same scope kinds, and the same primary IPC methods.
// It also enforces that every `kind: "view"` entry in the list has a real
// opener registered in `SDKViewOpenerBuiltIns.swift` — and that every
// registered opener has a matching `view` entry in the list.
//
// PARSING APPROACH (documented here so the contract is explicit):
//   1. The TypeScript side comes from the compiled `dist/index.js`
//      (`SCOPES_ID_LIST`, `SCOPES_BY_ID`) — run `npm run build` first,
//      exactly like the other package tests.
//   2. The Swift side is read from disk as text and parsed with regexes
//      that match the canonical `ScopeEntry(...)` literal shape used in
//      `ScopesIDLists.swift` (fields in fixed order: id, title,
//      description, kind, ipcMethod, capabilityId, viewId). If that shape
//      ever changes, this test must be updated in the same change — the
//      test fails loudly rather than silently comparing nothing.
//   3. Registered view IDs are collected from
//      `SDKViewOpenerBuiltIns.swift` (direct `register(viewID: .case)`
//      calls, `(.case, "toolID")` notification-bridge tuples, and
//      `SDK<Area>ViewOpener.capabilityID` sibling references whose case is
//      read from the sibling file). Enum case names are mapped to wire IDs
//      through `SDKCapability.swift`'s `case <name> = "<raw>"` lines, so a
//      renamed raw value breaks this test rather than the mapping.
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
// tests/ -> SwiftCode/SDK/TypeScript/package/tests/, so the repo root is
// five levels up.
const repoRoot = path.resolve(testsDir, "..", "..", "..", "..", "..");
const swiftScopesPath = path.join(
  repoRoot,
  "SwiftCode",
  "SDK",
  "Host",
  "ScopesIDLists.swift",
);
const swiftCapabilityPath = path.join(
  repoRoot,
  "SwiftCode",
  "SDK",
  "Contracts",
  "Capability",
  "SDKCapability.swift",
);
const swiftBuiltInsPath = path.join(
  repoRoot,
  "SwiftCode",
  "SDK",
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
 */
function parseSwiftScopeEntries() {
  const src = readFileSync(swiftScopesPath, "utf8");
  // Canonical ScopeEntry(...) literal shape; fields in fixed order. `nil`
  // maps to null; quoted strings map to their contents.
  const entryRe =
    /ScopeEntry\(\s*\n\s*id:\s*"([^"]+)",\s*\n\s*title:\s*"([^"]*)",\s*\n\s*description:\s*"([^"]*)",\s*\n\s*kind:\s*\.(\w+),\s*\n\s*ipcMethod:\s*(nil|"([^"]*)"),\s*\n\s*capabilityId:\s*\.(\w+),\s*\n\s*viewId:\s*(nil|"([^"]*)")\s*\n?\)/g;
  const entries = [];
  for (const m of src.matchAll(entryRe)) {
    entries.push({
      id: m[1],
      kind: m[4],
      ipcMethod: m[5] === "nil" ? null : m[6],
      capabilityCase: m[7],
      viewId: m[8] === "nil" ? null : m[9],
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
 * parsing `case <name> = "<raw>"` in SDKCapability.swift. Used so the
 * opener-registration check works with wire IDs, and so a raw-value
 * rename fails this test rather than silently mismatching.
 */
function parseCapabilityCaseMap() {
  const src = readFileSync(swiftCapabilityPath, "utf8");
  const map = new Map();
  for (const m of src.matchAll(/case\s+(\w+)\s*=\s*"([^"]+)"/g)) {
    map.set(m[1], m[2]);
  }
  assert.ok(
    map.size > 0,
    "SDKCapability.swift: parsed 0 capability cases — update the test",
  );
  return map;
}

/**
 * Collects the enum case names of every view ID registered by
 * `registerBuiltInOpeners()`: direct `register(viewID: .case)` calls, the
 * `(.case, "toolID")` notification-bridge tuples, and sibling
 * `SDK<Area>ViewOpener.capabilityID` references (resolved by reading the
 * sibling file's `capabilityID = .case` line).
 */
function parseRegisteredViewCases() {
  const src = readFileSync(swiftBuiltInsPath, "utf8");
  const cases = new Set();
  for (const m of src.matchAll(/register\(viewID:\s*\.(\w+)\)/g)) {
    cases.add(m[1]);
  }
  for (const m of src.matchAll(/\(\.(\w+),\s*"[^"]+"\)/g)) {
    cases.add(m[1]);
  }
  for (const m of src.matchAll(/register\(viewID:\s*(SDK\w+ViewOpener)\.capabilityID\)/g)) {
    const siblingName = m[1];
    const siblingSrc = readFileSync(
      path.join(
        repoRoot,
        "SwiftCode",
        "SDK",
        "Host",
        "ViewOpener",
        `${siblingName}.swift`,
      ),
      "utf8",
    );
    const caseMatch = siblingSrc.match(
      /capabilityID:\s*SDKCapabilityID\s*=\s*\.(\w+)/,
    );
    assert.ok(
      caseMatch,
      `${siblingName}.swift: could not parse its capabilityID case`,
    );
    cases.add(caseMatch[1]);
  }
  assert.ok(
    cases.size > 0,
    "SDKViewOpenerBuiltIns.swift: parsed 0 registered view IDs — update the test",
  );
  return cases;
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
    const registeredRawIds = new Set(
      [...parseRegisteredViewCases()].map((caseName) => {
        assert.ok(
          caseMap.has(caseName),
          `opener registered for unknown capability case .${caseName}`,
        );
        return caseMap.get(caseName);
      }),
    );
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
