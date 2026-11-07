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
}));

const outPath = path.join(packageDir, "snippets.json");
await writeFile(outPath, JSON.stringify(manifest, null, 2) + "\n", "utf8");

const written = JSON.parse(await readFile(outPath, "utf8"));
if (JSON.stringify(written) !== JSON.stringify(manifest)) {
  throw new Error("snippets.json round-trip mismatch");
}
console.log(`wrote ${outPath} (${manifest.length} snippets)`);
