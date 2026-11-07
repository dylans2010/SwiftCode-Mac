import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const pkg = require("../package.json") as { name?: string; version?: string };

export function greeting(): string {
  return `Hello from ${pkg.name ?? "swiftcode-project"} v${pkg.version ?? "0.0.0"}!`;
}

export function main(): void {
  console.log(greeting());
}

if (process.argv[1] !== undefined) {
  const entryUrl = pathToFileURL(process.argv[1]).href;
  if (import.meta.url === entryUrl) {
    main();
  }
}
