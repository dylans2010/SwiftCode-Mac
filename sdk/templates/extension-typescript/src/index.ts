import type { SwiftCodeExtension } from "@swiftcode/sdk";
import { activate, deactivate } from "./extension.js";

const extension: SwiftCodeExtension = {
  id: "__EXTENSION_ID__",
  activate,
  deactivate,
};

export default extension;
