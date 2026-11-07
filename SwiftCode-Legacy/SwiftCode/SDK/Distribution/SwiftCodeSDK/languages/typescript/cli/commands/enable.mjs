import { makeSetEnabledCommand } from "./_set-enabled.mjs";

const command = makeSetEnabledCommand(true);
export const definition = command.definition;
export const run = command.run;
