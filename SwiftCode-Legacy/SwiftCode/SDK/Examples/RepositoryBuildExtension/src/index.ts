import type { SwiftCodeExtension } from "@swiftcode/sdk";
import { activate, deactivate } from "./extension.js";

const extension: SwiftCodeExtension = {
  id: "com.example.repository-build-extension",
  activate,
  deactivate,
};

export default extension;
