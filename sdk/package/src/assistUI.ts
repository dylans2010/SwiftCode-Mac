import { SDKError, type HostConnection } from "./ipc.js";
import { SDKAssistAccessError, type AssistUIAPI } from "./types.js";

export const ASSIST_VIEW_ID = "assist.main";

function mapAssistDenial(error: unknown): never {
  if (error instanceof SDKError && error.code === "ASSIST_DENIED") {
    throw new SDKAssistAccessError(error.correlationId);
  }
  throw error;
}

export function createAssistUIAPI(connection: HostConnection): AssistUIAPI {
  return {
    async openAssistView(): Promise<void> {
      try {
        await connection.request<unknown>("ui.openView", { viewId: ASSIST_VIEW_ID });
      } catch (error) {
        mapAssistDenial(error);
      }
    },
  };
}
