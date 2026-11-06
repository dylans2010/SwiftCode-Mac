import type { SwiftCodeContext } from "@swiftcode/sdk";

/**
 * "run-build" command.
 *
 * Starts a host-managed build and streams its output events to the extension
 * log, then awaits the final build result.
 *
 * Convention: an empty `target` string asks the host to resolve the default
 * scheme/build target of the currently open SwiftCode project. The extension
 * deliberately never hardcodes a target name that might not exist in the
 * user's project — if the host cannot resolve a default, `run()` rejects
 * with a typed build error and the rejection propagates to the caller.
 */
export function createRunBuildCommand(context: SwiftCodeContext) {
  return {
    id: "run-build",
    title: "Build Current Project",
    execute: async () => {
      const handle = await context.build.run({ target: "" });
      // BuildOutputEvent.text (spec §12.4's illustrative `message` became `text`
      // in the finalized @swiftcode/sdk contract, mirroring the host's
      // SDKBuildOutputEvent.text). No output is fabricated or dropped: every
      // streamed event is logged, and stream consumption does not affect wait().
      for await (const event of handle.output) {
        context.log.info(event.text);
      }
      return await handle.wait();
    },
  };
}
