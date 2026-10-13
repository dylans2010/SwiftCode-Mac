/**
 * create.mjs — scaffold a new SwiftCode extension or standalone project.
 *
 *   swiftcode create --type extension --language typescript \
 *     --id <reverse-dns> --name <name> --outDir <dir> \
 *     [--description <text>] [--version <semver>]
 *
 *   swiftcode create --type project --language typescript \
 *     --name <name> --outDir <dir> [--description <text>] [--version <semver>]
 *
 * Extension scaffolding shells out to the real generator at
 * ../create-extension.mjs (exact argv passthrough) and verifies the output
 * directory is real and non-empty before reporting success.
 *
 * Project scaffolding copies ../../templates/project-typescript with
 * placeholder substitution, using the same validation rules as the
 * extension generator (semver, npm name, non-empty outDir guard).
 *
 * Honest boundaries (exit 1, not stubs):
 *   --type project --language swift     → Swift standalone projects are
 *                                         created in SwiftCode Studio (Phase 7).
 *   --type extension --language python  → not supported in this release
 *                                         (spec §3.2 defers Python extension
 *                                         runtime support).
 */
import { spawn } from "node:child_process";
import { mkdir, readdir, readFile, writeFile, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { UsageError } from "../errors.mjs";

export const definition = {
  name: "create",
  description: "Scaffold a new SwiftCode extension or standalone project",
  usage: `swiftcode create --type extension|project --language <lang> [options]

Extension (TypeScript):
  swiftcode create --type extension --language typescript \\
      --id <reverse-dns> --name <name> --outDir <dir> \\
      [--description <text>] [--version <semver>]

Standalone project (TypeScript):
  swiftcode create --type project --language typescript \\
      --name <name> --outDir <dir> \\
      [--description <text>] [--version <semver>]

Boundaries:
  --type project --language swift    Swift standalone projects are created in
                                     SwiftCode Studio (not supported by this CLI).
  --type extension --language python Python extensions are not supported in
                                     this release (spec §3.2).`,
};

const here = path.dirname(fileURLToPath(import.meta.url));
const CREATE_EXTENSION = path.join(here, "..", "create-extension.mjs");
const PROJECT_TEMPLATE_DIR = path.join(here, "..", "..", "templates", "project-typescript");

const VERSION_PATTERN =
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-((0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$/;
const SLUG_PATTERN = /^[a-z0-9][a-z0-9._~-]*$/;

function checkVersion(version, flag) {
  if (!VERSION_PATTERN.test(version)) {
    throw new UsageError(`--version "${version}" is not valid semver`);
  }
}

/** Derive an npm-safe package slug from a human-readable project name. */
function slugify(name) {
  const slug = name
    .toLowerCase()
    .replace(/[\s_]+/g, "-")
    .replace(/[^a-z0-9._~-]/g, "")
    .replace(/^[._~-]+/, "");
  if (!SLUG_PATTERN.test(slug)) {
    throw new UsageError(
      `--name "${name}" cannot be turned into a valid npm package name`
    );
  }
  return slug;
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

async function assertCreatedDir(target) {
  if (!existsSync(target)) {
    throw new Error(`scaffolding reported success but ${target} does not exist`);
  }
  const entries = await readdir(target);
  if (entries.length === 0) {
    throw new Error(`scaffolding reported success but ${target} is empty`);
  }
  return target;
}

function runGenerator(argv, json) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [CREATE_EXTENSION, ...argv], {
      stdio: json ? ["ignore", "pipe", "pipe"] : "inherit",
    });
    let stdout = "";
    let stderr = "";
    if (json) {
      child.stdout?.on("data", (d) => (stdout += d));
      child.stderr?.on("data", (d) => (stderr += d));
    }
    child.on("error", reject);
    child.on("close", (code) => resolve({ code: code ?? 1, stdout, stderr }));
  });
}

async function createExtension(args, ctx) {
  const { id, name, outDir } = args;
  const description = args.description ?? "";
  const version = args.version ?? "0.1.0";

  if (!id) throw new UsageError("--id is required (reverse-DNS, e.g. com.example.my-ext)");
  if (!name) throw new UsageError("--name is required (human-readable extension name)");
  if (!outDir) throw new UsageError("--outDir is required (target project directory)");
  checkVersion(version, "--version");
  if (description.length > 1000) {
    throw new UsageError("--description must be at most 1000 characters");
  }
  if (!existsSync(CREATE_EXTENSION)) {
    throw new Error(`extension generator missing: ${CREATE_EXTENSION}`);
  }

  const argv = ["--id", id, "--name", name, "--outDir", outDir];
  if (args.description !== undefined) argv.push("--description", description);
  if (args.version !== undefined) argv.push("--version", version);

  const { code, stdout, stderr } = await runGenerator(argv, args.json === true);
  if (code !== 0) {
    const detail = stderr.trim() || stdout.trim();
    throw new Error(
      `extension generator failed (exit ${code})${detail ? `: ${detail}` : ""}`
    );
  }

  const target = await assertCreatedDir(path.resolve(outDir));
  ctx.log(`Extension created at ${target}`);
  return {
    code: 0,
    data: { type: "extension", language: "typescript", id, name, path: target },
  };
}

async function createProject(args, ctx) {
  const { name, outDir } = args;
  const description = args.description ?? "";
  const version = args.version ?? "0.1.0";

  if (!name) throw new UsageError("--name is required (project name)");
  if (!outDir) throw new UsageError("--outDir is required (target project directory)");
  if (name.length > 128) throw new UsageError("--name must be at most 128 characters");
  checkVersion(version, "--version");
  if (description.length > 1000) {
    throw new UsageError("--description must be at most 1000 characters");
  }
  if (!existsSync(PROJECT_TEMPLATE_DIR)) {
    throw new Error(`project template missing: ${PROJECT_TEMPLATE_DIR}`);
  }

  const slug = slugify(name);
  const target = path.resolve(outDir);
  if (existsSync(target)) {
    const entries = await readdir(target);
    if (entries.length > 0) {
      throw new Error(`--outDir ${target} already exists and is not empty`);
    }
  }

  await copyTemplate(PROJECT_TEMPLATE_DIR, target, {
    __PROJECT_NAME__: name,
    __PACKAGE_SLUG__: slug,
    __PROJECT_VERSION__: version,
    __PROJECT_DESCRIPTION__: description,
  });
  await assertCreatedDir(target);

  ctx.log(`Project created at ${target}`);
  ctx.log(`Next steps:\n  cd ${target} && npm install && npm run build && npm test`);
  return {
    code: 0,
    data: { type: "project", language: "typescript", name, package: slug, path: target },
  };
}

export async function run(args, ctx) {
  const type = args.type;
  const language = args.language ?? "typescript";

  if (!type) throw new UsageError("--type is required (extension|project)");
  if (type !== "extension" && type !== "project") {
    throw new UsageError(`--type must be "extension" or "project", got "${type}"`);
  }

  if (type === "extension") {
    if (language === "python") {
      throw new Error(
        "Python extensions are not supported in this release (spec §3.2 defers Python extension runtime support)"
      );
    }
    if (language !== "typescript") {
      throw new Error(
        `unsupported extension language "${language}": only "typescript" is supported in this release`
      );
    }
    return createExtension(args, ctx);
  }

  // type === "project"
  if (language === "swift") {
    throw new Error("Swift standalone projects are created in SwiftCode Studio");
  }
  if (language !== "typescript") {
    throw new Error(
      `unsupported project language "${language}": only "typescript" is supported in this release`
    );
  }
  return createProject(args, ctx);
}
