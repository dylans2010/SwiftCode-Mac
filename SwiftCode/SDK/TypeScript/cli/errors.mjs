/**
 * errors.mjs — shared error types for swiftcode CLI command modules.
 *
 * Throwing a UsageError from a command's run() signals a usage error:
 * the dispatcher prints the command's usage text and exits with code 2.
 * Any other thrown Error is an operational failure: exit code 1.
 */

export class UsageError extends Error {
  constructor(message) {
    super(message);
    this.name = "UsageError";
  }
}
