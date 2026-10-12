/**
 * disable.mjs — disable an installed SwiftCode extension (spec §3.1).
 * Flips the enabled flag in .sdk-install.json; see _set-enabled.mjs.
 */
import { makeSetEnabledCommand } from "./_set-enabled.mjs";

const command = makeSetEnabledCommand(false);
export const definition = command.definition;
export const run = command.run;
