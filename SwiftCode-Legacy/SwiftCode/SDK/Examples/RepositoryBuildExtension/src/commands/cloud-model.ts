import type { SwiftCodeContext } from "@swiftcode/sdk";

/**
 * "cloud-model" command.
 *
 * Demonstrates calling the SwiftCode Cloud Model service for text generation.
 */
export function createCloudModelCommand(context: SwiftCodeContext) {
  return {
    id: "cloud-model",
    title: "Complete with Cloud Model",
    execute: async () => {
      const response = await context.cloudModel.complete({
        prompt: "Summarize the architecture of a SwiftCode extension.",
        systemPrompt: "You are a helpful coding assistant.",
      });
      context.log.info("Cloud model completion received", {
        responseLength: response.length,
      });
      return { response };
    },
  };
}
