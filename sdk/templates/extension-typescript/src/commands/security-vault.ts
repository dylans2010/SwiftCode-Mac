import type { SwiftCodeContext } from "@swiftcode/sdk";

/**
 * "security-vault" command.
 *
 * Lists stored secret IDs in the extension's Keychain vault under its security ID.
 */
export function createSecurityVaultCommand(context: SwiftCodeContext) {
  return {
    id: "security-vault",
    title: "Inspect Security Secret IDs",
    execute: async () => {
      const securityID = context.extension.id;
      const values = await context.security.listValueIDs(securityID);
      context.log.info("Security vault value IDs retrieved", {
        securityID,
        count: values.length,
      });
      return { securityID, values };
    },
  };
}
