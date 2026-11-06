import type { SwiftCodeContext } from "@swiftcode/sdk";

/**
 * "inspect-project" command.
 *
 * Requests the current project metadata from the host.
 */
export function createInspectProjectCommand(context: SwiftCodeContext) {
  return {
    id: "inspect-project",
    title: "Inspect Project Metadata",
    execute: async () => {
      try {
        const projectInfo = await context.project.getCurrent();
        context.log.info("Project metadata requested", {
          hasProject: projectInfo !== null,
        });
        return projectInfo;
      } catch (error) {
        context.log.warn("Project metadata request failed or unhandled by host", {
          error: String(error),
        });
        return null;
      }
    },
  };
}
