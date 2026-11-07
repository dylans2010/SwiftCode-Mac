import { makeSetEnabledCommand } from "./_set-enabled.mjs";

const command = makeSetEnabledCommand(false);
export const definition = command.definition;
export const run = command.run;
