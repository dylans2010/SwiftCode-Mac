import type { SwiftCodeContext } from "@swiftcode/sdk";
import { createInspectRepositoryCommand } from "./commands/inspect-repository.js";
import { createRunBuildCommand } from "./commands/run-build.js";
import { createInspectProjectCommand } from "./commands/inspect-project.js";
import { createTerminalCommand } from "./commands/terminal-command.js";
import { createCloudModelCommand } from "./commands/cloud-model.js";
import { createSecurityVaultCommand } from "./commands/security-vault.js";
import { createOpenDocsCommand } from "./commands/open-docs.js";

/**
 * Live command registrations owned by this activation.
 */
const registrations: Array<{ dispose(): void }> = [];

export async function activate(context: SwiftCodeContext): Promise<void> {
  try {
    registrations.push(context.commands.register(createInspectRepositoryCommand(context)));
    registrations.push(context.commands.register(createRunBuildCommand(context)));
    registrations.push(context.commands.register(createInspectProjectCommand(context)));
    registrations.push(context.commands.register(createTerminalCommand(context)));
    registrations.push(context.commands.register(createCloudModelCommand(context)));
    registrations.push(context.commands.register(createSecurityVaultCommand(context)));
    registrations.push(context.commands.register(createOpenDocsCommand(context)));
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
