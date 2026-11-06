# swiftcode CLI — Command Module Contract

Every command is a single ES module at `commands/<name>.mjs`, auto-discovered
by `swiftcode.mjs`. Any `*.mjs` file in this directory is loaded as a command
**except** files whose name starts with `_` — those are shared helpers
(e.g. `_shared.mjs`) and are skipped by discovery. No registration step
exists — dropping a conforming module here adds the command.

## Module shape

```js
import { UsageError } from "../errors.mjs";

export const definition = {
  name: "validate",                       // command name (must match file name)
  description: "Validate an extension package",   // one line, shown in --help
  usage: "swiftcode validate [dir] [--json]",     // full usage text
};

export async function run(args, ctx) {
  // args: parsed { _: [...], json: bool, ... }  (see Argument parsing)
  // ctx:  { log(msg), error(msg) }
  if (args._.length > 1) throw new UsageError("too many arguments");
  ctx.log("validating…");
  return { code: 0, data: { valid: true } };
}
```

### `definition`

- `name` — string, the command as typed on the command line. Must equal the
  file's base name (`validate.mjs` → `"validate"`). The dispatcher keys
  commands by this value.
- `description` — one line, shown by `swiftcode --help`.
- `usage` — multi-line usage text, shown by `swiftcode <command> --help` and
  after a `UsageError`.

### `run(args, ctx)`

- `args` — **always** the parsed object `{ _: string[], json: boolean,
  ...flags }` produced by the dispatcher's parser (see Argument parsing).
  It is never a raw argv array; write `run` against the object shape only.
  `json` is always passed through (never stripped). `--help`/`-h` after the
  command name is intercepted by the dispatcher and never reaches `run`.
- `ctx` — `{ log(msg), error(msg) }`.
  - `ctx.log` writes to stdout in human mode; in `--json` mode it is
    **suppressed** (writes nothing) so stdout stays parseable JSON.
  - `ctx.error` writes to stderr in both modes.
  - In `--json` mode, return structured results via `data` (see below);
    do not print machine-readable content yourself.

### Return value

`run` may return:

| Return                      | Meaning                                                        |
| --------------------------- | -------------------------------------------------------------- |
| `undefined` / `null`        | success, exit 0                                                |
| `number`                    | exit code (only `0`, `1`, `2` are meaningful; others map to `1`)|
| `{ code, data }`            | exit code plus structured result                               |

In `--json` mode the dispatcher serializes the outcome:

- success: `{"ok":true,"command":"<name>","data":<data|null>}`
- failure: `{"ok":false,"command":"<name>","error":{"code":"USAGE"|"OPERATIONAL","message":"…"}}`

In human mode the dispatcher prints nothing on success beyond what the
command wrote via `ctx.log`; a returned non-zero code with no thrown error
produces no extra output, so prefer throwing an `Error` with a clear message
over silently returning `1`.

### Errors and exit codes

- `throw new UsageError("…")` (import from `../errors.mjs`) → **exit 2**.
  The dispatcher prints the message and the command's `usage`. Use for
  missing/invalid arguments and malformed input.
- `throw new Error("…")` → **exit 1**. Use for operational failures
  (validation failed, build failed, file missing, subprocess failed).
- Never `process.exit()` inside a command module; always return or throw.
- Never print "installed", "running", "success", or any terminal-state claim
  until the underlying operation actually confirmed it (spec §13.2).

## Argument parsing

The dispatcher parses with a minimal hand-rolled parser (`parseArgs`, exported
from `../swiftcode.mjs`); there are no runtime dependencies.

- `--flag value` → `args.flag === "value"` (the next token is consumed as the
  value only if it does **not** start with `-`; otherwise the flag is boolean)
- `--flag=value` → `args.flag === "value"`
- `--bool` → `args.bool === true`
- `-h` → `args.help === true` (the only short flag; intercepted by the
  dispatcher, which prints `definition.usage`)
- `--` → everything after is positional, even tokens starting with `-`
- bare tokens → appended to `args._` in order

All values are strings or `true`. Parse numbers/booleans yourself and throw
`UsageError` on invalid values.

## Rules for command authors

1. Real implementations only — no dead stubs, no fake success.
2. Honor `--json`: keep stdout clean; machine data goes in returned `data`.
3. Human-readable errors on stderr via `ctx.error` or thrown `Error`s.
4. Keep the CLI thin: invoke documented host operations; do not duplicate
   host authorization logic (spec §5.1).
5. No silent network downloads and no secret values in output (spec §13.2).
6. If a feature genuinely cannot be done yet, fail with an honest message and
   exit 1 — do not ship a stub that pretends to work.

## Discovery and load failures

`swiftcode.mjs` imports each command module in isolation. A module that fails
to load (syntax error, bad import, missing `definition`/`run`) does **not**
crash the CLI: it appears in `swiftcode --help` as
`(failed to load: <reason>)`, and dispatching it exits 1 with the load error.
Fix the module; the dispatcher needs no changes. Files starting with `_`
are shared helpers and are never treated as commands.

## Adding a command

1. Create `commands/<name>.mjs` exporting `definition` and `run`.
2. Run `node swiftcode.mjs <name> --help` and the command's happy path,
   failure path, bad-args path (exit 2), and `--json` path (parseable).
3. Document the command in `../README.md`.
4. Record the work in `../agent_notes.md`.
