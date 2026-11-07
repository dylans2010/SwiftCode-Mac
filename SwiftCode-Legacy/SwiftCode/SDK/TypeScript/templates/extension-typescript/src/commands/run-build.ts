import type { SwiftCodeContext } from "@swiftcode/sdk";

export function createRunBuildCommand(context: SwiftCodeContext) {
  return {
    id: "run-build",
    title: "Build Current Project",
    execute: async () => {
      const handle = await context.build.run({ target: "" });
      for await (const event of handle.output) {
        context.log.info(event.text);
      }
      return await handle.wait();
    },
  };
}
