/**
 * __PROJECT_NAME__ — SwiftCode standalone TypeScript project.
 *
 * A standalone project is user-owned code: it uses the language's ordinary
 * development workflow (npm / tsc / node) and is not subject to extension
 * sandbox restrictions (spec §14.1).
 */
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";

// createRequire keeps this working under NodeNext ESM without needing
// resolveJsonModule; the name always reflects the real package.json.
const require = createRequire(import.meta.url);
const pkg = require("../package.json") as { name?: string; version?: string };

export function greeting(): string {
  return `Hello from ${pkg.name ?? "swiftcode-project"} v${pkg.version ?? "0.0.0"}!`;
}

export function main(): void {
  console.log(greeting());
}

// Run only when executed directly (`node dist/index.js`), not when imported
// by the test suite.
if (process.argv[1] !== undefined) {
  const entryUrl = pathToFileURL(process.argv[1]).href;
  if (import.meta.url === entryUrl) {
    main();
  }
}
