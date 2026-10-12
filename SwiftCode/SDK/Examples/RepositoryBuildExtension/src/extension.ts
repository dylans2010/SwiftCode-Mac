import type { SwiftCodeContext } from "@swiftcode/sdk";
import { createInspectRepositoryCommand } from "./commands/inspect-repository.js";
import { createRunBuildCommand } from "./commands/run-build.js";

/**
 * Live command registrations owned by this activation. Every registration is
 * disposed when the extension deactivates, and also unwound if activation
 * fails partway through, so a partially-initialized extension never leaves
 * commands behind.
 */
const registrations: Array<{ dispose(): void }> = [];

export async function activate(context: SwiftCodeContext): Promise<void> {
  try {
    registrations.push(context.commands.register(createInspectRepositoryCommand(context)));
    registrations.push(context.commands.register(createRunBuildCommand(context)));
  } catch (error) {
    for (const registration of registrations.splice(0)) {
      registration.dispose();
    }
    throw error;
  }
}

export async function deactivate(): Promise<void> {
  for (const registration of registrations.splice(0)) {
    registration.dispose();
  }
}
