/**
 * Capability → scope ID list for `@swiftcode/sdk`.
 *
 * Finalized from Docs/Intro-to-SDK.md §8.1 (the fixed capability registry)
 * and §10.4 (IPC methods), matched against the Swift host contracts:
 * - `SwiftCode/SDK/Contracts/Capability/SDKCapability.swift` — the 30 fixed
 *   capability IDs (11 original kebab-case + 12 `<area>.<View>` IDs + 5
 *   `security.*` IDs + 2 Assist SDK variants `assist.ui`/`assist.headless`),
 * - `SwiftCode/SDK/Runtime/IPC/SDKIPCDispatcher.swift` — the real IPC
 *   method strings serving the API capabilities,
 * - `SwiftCode/SDK/Host/ViewOpener/SDKViewOpenerBuiltIns.swift` — the 10
 *   view IDs with registered openers.
 *
 * This file mirrors `SwiftCode/SDK/Host/ScopesIDLists.swift`. The two are
 * kept in sync by `tests/scopes-sync.test.mjs`, which parses BOTH files
 * and fails on any ID, kind, or ipcMethod drift in either direction.
 */
/**
 * `"view"`: the scope opens a host view through `ui.openView` (the view ID
 * travels in the payload's `viewId` field and is authorized at the
 * capability broker like any other capability). `"api"`: the scope is
 * served by the host's adapters over its own IPC method(s).
 */
export type ScopeKind = "view" | "api";
export interface ScopeIDEntry {
    /** Lookup key and wire capability ID. */
    readonly id: string;
    /** Short user-facing title (matches `SDKCapabilityInfo.title`). */
    readonly title: string;
    /** One-sentence plain-language description of what the scope allows. */
    readonly description: string;
    readonly kind: ScopeKind;
    /**
     * The primary IPC method serving this capability.
     * - View entries: always `"ui.openView"`; see `viewId` for the payload value.
     * - API entries: the real host method string (e.g. `"build.run"`), or
     *   `null` when the host has not wired an IPC method for the capability
     *   in this release. `null` is honest, never a placeholder: a capability
     *   whose grant exists but whose method is `null` cannot be invoked yet.
     *   A capability may span several methods (e.g. `build.execute` also
     *   covers `build.wait`/`build.cancel`); this field names the primary one.
     */
    readonly ipcMethod: string | null;
    /**
     * The fixed `SDKCapabilityID` registry value — wire-stable, matched
     * verbatim (case-sensitive) in manifests, grants, and IPC messages.
     */
    readonly capabilityId: string;
    /**
     * Present only for `kind: "view"`: the exact `viewId` payload value the
     * extension sends to `ui.openView` to open this view.
     */
    readonly viewId?: string;
}
/**
 * Every capability ID in the fixed registry (spec §8.1, registry order),
 * each paired with its scope kind and primary IPC method.
 *
 * 12 entries are views (`ui.openView` + registered openers in
 * `SDKViewOpenerBuiltIns.swift`); 20 are API capabilities served by the
 * host adapters. Entries with `ipcMethod: null` have a broker capability
 * but no wired host method in this release — `assist.invoke` is the
 * deny-by-default exception (spec §9): it is never grantable and no
 * method pattern reaches it (`SDKAssistGate`). The `assist.ui` and
 * `assist.headless` entries are entitlement-only (task B3): their
 * `assist.invoke` route is the dedicated entitled path the sibling
 * dispatcher/gate task implements, not a manifest grant.
 */
export declare const SCOPES_ID_LIST: readonly ScopeIDEntry[];
/**
 * `SCOPES_ID_LIST` keyed by `id`. Every key is a wire capability ID;
 * every value is the same entry object from the list.
 */
export declare const SCOPES_BY_ID: Readonly<Record<string, ScopeIDEntry>>;
