// Generates the Studio snippet-browser manifest.
//
// `npm run build:snippets` (run automatically by `npm run build` after
// `tsc`) reads the compiled `dist/snippets.js` and writes the full
// manifest `snippets.json` at the package root: id, title, description,
// capabilityId, tags, and the runnable `code` snippet so the Studio
// Capability & Snippet Library can display, copy, and insert real executable
// code directly.
//
// The manifest is a build product: regenerate it after editing
// `src/snippets.ts` by running `npm run build` (or `npm run build:snippets`
// directly). `tests/snippets.test.mjs` fails when the checked-in manifest
// is out of sync with the compiled library.
import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";

const packageDir = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const distUrl = pathToFileURL(path.join(packageDir, "dist", "snippets.js"));
const { SNIPPETS } = await import(distUrl.href);

const manifest = SNIPPETS.map((snippet) => ({
  id: snippet.id,
  title: snippet.title,
  description: snippet.description,
  capabilityId: snippet.capabilityId,
  tags: [...snippet.tags],
  code: snippet.code,
}));

const outPath = path.join(packageDir, "snippets.json");
await writeFile(outPath, JSON.stringify(manifest, null, 2) + "\n", "utf8");

// Round-trip check: the file on disk must parse back to the same manifest.
const written = JSON.parse(await readFile(outPath, "utf8"));
if (JSON.stringify(written) !== JSON.stringify(manifest)) {
  throw new Error("snippets.json round-trip mismatch");
}
console.log(`wrote ${outPath} (${manifest.length} snippets)`);
