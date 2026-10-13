/**
 * Preset TypeScript snippet library for `@swiftcode/sdk`.
 *
 * Every snippet is real, working TypeScript against the actual SDK API
 * (`SwiftCodeContext` from `./types.js`): paste a snippet's `code` into an
 * extension and run it. No invented methods — every call below maps to a
 * method on `SwiftCodeContext` that `createContext` implements and the
 * Swift host's `SDKIPCDispatcher` routes.
 *
 * Each snippet declares the exact capability wire ID (`capabilityId`,
 * from `SwiftCode/SDK/Contracts/Capability/SDKCapability.swift`) that the
 * extension manifest must request for the snippet to work. Seven registry
 * capabilities have no TypeScript context API yet (workspace.read,
 * workspace.write, source-control.write, task.execute, network.request,
 * credentials.use, and the deny-by-default assist.invoke), so they have no
 * snippet here rather than a fake one.
 *
 * The light manifest (`id`, `title`, `description`, `capabilityId`, `tags`
 * — no code) is generated into `snippets.json` at the package root by
 * `npm run build:snippets` (see `scripts/build-snippets.mjs`) for the
 * Studio snippet browser.
 */
/** One preset, runnable snippet against the real `@swiftcode/sdk` API. */
export interface Snippet {
    /** Stable kebab-case identifier, unique within the library. */
    readonly id: string;
    /** Short human-readable title shown in the snippet browser. */
    readonly title: string;
    /** One or two sentences describing what the snippet does. */
    readonly description: string;
    /**
     * Exact capability wire ID the extension manifest must request
     * (case-sensitive, from `SDKCapabilityID`).
     */
    readonly capabilityId: string;
    /** Search keywords for the snippet browser. */
    readonly tags: readonly string[];
    /**
     * Self-contained TypeScript: imports `SwiftCodeContext` from
     * `@swiftcode/sdk` and exports an async `runExample(context)` function.
     */
    readonly code: string;
}
export declare const SNIPPETS: readonly Snippet[];
/**
 * Case-insensitive search across id, title, description, tags, and code.
 * A blank query returns every snippet.
 */
export declare function searchSnippets(query: string): Snippet[];
/** Returns the snippet with the given id, or `undefined` when unknown. */
export declare function getSnippet(id: string): Snippet | undefined;
