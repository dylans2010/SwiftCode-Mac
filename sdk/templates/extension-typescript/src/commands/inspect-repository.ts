import type { SwiftCodeContext } from "@swiftcode/sdk";

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
