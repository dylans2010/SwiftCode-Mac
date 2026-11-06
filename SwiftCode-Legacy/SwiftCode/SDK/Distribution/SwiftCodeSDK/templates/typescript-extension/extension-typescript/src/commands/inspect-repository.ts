import type { SwiftCodeContext } from "@swiftcode/sdk";

/**
 * "inspect-repository" command.
 *
 * Fetches the live repository status from the host's source-control service,
 * logs a summary, and returns the status object unchanged. No data is
 * fabricated: the caller receives exactly what the host reports.
 */
export function createInspectRepositoryCommand(context: SwiftCodeContext) {
  return {
    id: "inspect-repository",
    title: "Inspect Repository",
    execute: async () => {
      const status = await context.sourceControl.getStatus();
      context.log.info("Repository status retrieved", {
        isRepository: status.isRepository,
      });
      return status;
    },
  };
}
