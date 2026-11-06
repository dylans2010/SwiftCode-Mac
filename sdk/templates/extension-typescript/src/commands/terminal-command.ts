import type { SwiftCodeContext } from "@swiftcode/sdk";

/**
 * "terminal-command" command.
 *
 * Executes a sandboxed terminal command through the host's sandboxed terminal service.
 */
export function createTerminalCommand(context: SwiftCodeContext) {
  return {
    id: "terminal-command",
    title: "Run Sandboxed Terminal Command",
    execute: async () => {
      const result = await context.terminalSandbox.run({
        command: "git",
        args: ["--version"],
      });
      context.log.info("Terminal sandbox command completed", {
        exitCode: result.exitCode,
        stdout: result.stdout.trim(),
      });
      return result;
    },
  };
}
