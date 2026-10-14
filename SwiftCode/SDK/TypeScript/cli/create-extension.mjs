#!/usr/bin/env node
/**
 * create-extension.mjs — generate a real, compilable SwiftCode TypeScript
 * extension project from the template in ../templates/extension-typescript.
 *
 * Usage:
 *   node create-extension.mjs --id com.example.my-ext --name "My Ext" \
 *     --outDir ./MyExt [--description "..."] [--version 0.1.0] [--sdk-path <path>]
 *
 * --sdk-path defaults to the real SDK package dir ../package (resolved
 * relative to this script); the generated package.json depends on it via a
 * file: URL, so npm install resolves @swiftcode/sdk from local source.
 */
import { copyFile, mkdir, readdir, readFile, stat, symlink, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const TEMPLATE_DIR = path.join(here, "..", "templates", "extension-typescript");
const SCHEMA_SOURCE = path.join(
  here,
  "..",
  "..",
  "Contracts",
  "Manifest",
  "swiftcode-extension-v1.schema.json"
);
const DEFAULT_SDK_DIR = path.join(here, "..", "package");

const ID_PATTERN = /^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$/;
const VERSION_PATTERN =
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-((0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$/;
const SLUG_PATTERN = /^[a-z0-9][a-z0-9._~-]*$/;

function fail(message) {
  process.stderr.write(`create-extension: error: ${message}\n`);
  process.exit(1);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) fail(`unexpected argument: ${token}`);
    const key = token.slice(2);
    const value = argv[i + 1];
    if (value === undefined || value.startsWith("--")) fail(`missing value for ${token}`);
    args[key] = value;
    i += 1;
  }
  return args;
}

async function copyTemplate(dir, destDir, substitutions) {
  await mkdir(destDir, { recursive: true });
  for (const entry of await readdir(dir)) {
    const src = path.join(dir, entry);
    const dest = path.join(destDir, entry);
    if ((await stat(src)).isDirectory()) {
      await copyTemplate(src, dest, substitutions);
    } else {
      let text = await readFile(src, "utf8");
      for (const [placeholder, value] of Object.entries(substitutions)) {
        text = text.split(placeholder).join(value);
      }
      await writeFile(dest, text);
    }
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const { id, name, outDir } = args;
  const description = args.description ?? "";
  const version = args["version"] ?? "0.1.0";
  const sdkPath = args["sdk-path"] ?? DEFAULT_SDK_DIR;

  if (!id) fail("--id is required (reverse-DNS, e.g. com.example.my-ext)");
  if (!ID_PATTERN.test(id)) {
    fail(`--id "${id}" is not a valid reverse-DNS identifier (letters, digits, hyphens, at least one dot)`);
  }
  if (!name) fail("--name is required (human-readable extension name)");
  if (name.length > 128) fail("--name must be at most 128 characters");
  if (!VERSION_PATTERN.test(version)) fail(`--version "${version}" is not valid semver`);
  if (!outDir) fail("--outDir is required (target project directory)");

  if (description.length > 1000) fail("--description must be at most 1000 characters");

  // id-slug: last DNS label of the id, lowercased, used as the npm package name.
  const idSlug = id.split(".").pop().toLowerCase();
  if (!SLUG_PATTERN.test(idSlug)) fail(`derived package name "${idSlug}" is not a valid npm name`);

  const sdkDir = path.resolve(sdkPath);
  if (!existsSync(path.join(sdkDir, "package.json"))) {
    fail(`SDK package not found at ${sdkDir} (no package.json) — pass --sdk-path <dir>`);
  }
  const sdkPackage = JSON.parse(await readFile(path.join(sdkDir, "package.json"), "utf8"));
  if (sdkPackage.name !== "@swiftcode/sdk") {
    fail(`package at ${sdkDir} is "${sdkPackage.name}", not "@swiftcode/sdk"`);
  }
  const sdkFileUrl = pathToFileURL(sdkDir).href;

  if (!existsSync(TEMPLATE_DIR)) fail(`template directory missing: ${TEMPLATE_DIR}`);
  if (!existsSync(SCHEMA_SOURCE)) fail(`manifest schema missing: ${SCHEMA_SOURCE}`);

  const target = path.resolve(outDir);
  if (existsSync(target)) {
    const entries = await readdir(target);
    if (entries.length > 0) fail(`--outDir ${target} already exists and is not empty`);
  }

  const substitutions = {
    __EXTENSION_ID__: id,
    __EXTENSION_NAME__: name,
    __EXTENSION_VERSION__: version,
    __EXTENSION_DESCRIPTION__: description,
    __ID_SLUG__: idSlug,
    __SDK_FILE_URL__: sdkFileUrl,
  };
  await copyTemplate(TEMPLATE_DIR, target, substitutions);

  // The $schema pointer in swiftcode.json is "./schemas/...": ship the real
  // schema with every generated project so the pointer is live.
  await mkdir(path.join(target, "schemas"), { recursive: true });
  await copyFile(SCHEMA_SOURCE, path.join(target, "schemas", "swiftcode-extension-v1.schema.json"));

  // Pre-seed node_modules from the local @swiftcode/sdk package when available
  // so generated projects can build and typecheck immediately, including offline.
  const sdkNodeModules = path.join(sdkDir, "node_modules");
  if (existsSync(sdkNodeModules)) {
    const targetNodeModules = path.join(target, "node_modules");
    const targetScopeDir = path.join(targetNodeModules, "@swiftcode");
    await mkdir(targetScopeDir, { recursive: true });
    const sdkLinkPath = path.join(targetScopeDir, "sdk");
    if (!existsSync(sdkLinkPath)) {
      await symlink(sdkDir, sdkLinkPath);
    }
    for (const entry of await readdir(sdkNodeModules)) {
      if (entry.startsWith(".package-lock")) continue;
      const srcEntry = path.join(sdkNodeModules, entry);
      const destEntry = path.join(targetNodeModules, entry);
      if (!existsSync(destEntry)) {
        await symlink(srcEntry, destEntry);
      }
    }
  }

  process.stdout.write(`Created SwiftCode extension "${name}" (${id}) in ${target}\n`);
  process.stdout.write(`  SDK: @swiftcode/sdk ${sdkPackage.version ?? "?"} via ${sdkFileUrl}\n`);
  process.stdout.write(`Next steps:\n`);
  process.stdout.write(`  cd ${target} && npm install && npm run build && npm test\n`);
}

main().catch((error) => fail(error.message ?? String(error)));
