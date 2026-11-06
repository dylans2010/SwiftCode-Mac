import type { SwiftCodeContext } from "@swiftcode/sdk";

/**
 * "inspect-repository" command.
 *
 * Fetches the live repository status and diff from the host's source-control service,
 * logs a summary, and returns the combined object unchanged.
 */
export function createInspectRepositoryCommand(context: SwiftCodeContext) {
  return {
    id: "inspect-repository",
    title: "Inspect Repository",
    execute: async () => {
      const status = await context.sourceControl.getStatus();
      const diff = await context.sourceControl.getDiff();
      context.log.info("Repository status and diff retrieved", {
        isRepository: status.isRepository,
        diffFiles: diff.files.length,
      });
      return { status, diff };
    },
  };
}
