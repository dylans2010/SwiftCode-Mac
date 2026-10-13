import type { SwiftCodeContext } from "@swiftcode/sdk";

/**
 * "open-docs" command.
 *
 * Opens the host documentation search view.
 */
export function createOpenDocsCommand(context: SwiftCodeContext) {
  return {
    id: "open-docs",
    title: "Open Documentation Browser",
    execute: async () => {
      await context.ui.openView("docs.search");
      context.log.info("Documentation browser opened.");
      return { success: true };
    },
  };
}
