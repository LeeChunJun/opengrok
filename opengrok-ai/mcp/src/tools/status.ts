import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  z,
  opengrok,
  textResult,
  errorResult,
  registerReadTool,
  registerWriteTool,
} from "./_helpers.js";

/**
 * 对应接口：/status/{uuid}
 *
 * 用于轮询/取消长时任务（如重建索引）。
 */
export function registerStatusTools(server: McpServer) {
  registerReadTool(
    server,
    "get_job_status",
    "通过 UUID 轮询一个长时任务的当前状态。",
    { uuid: z.string() },
    async ({ uuid }) => {
      try {
        return textResult(
          await opengrok.get(`/status/${encodeURIComponent(uuid)}`),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerWriteTool(
    server,
    "delete_job_status",
    "通过 UUID 取消并清理一个长时任务的状态条目。",
    { uuid: z.string() },
    async ({ uuid }) => {
      try {
        return textResult(
          await opengrok.delete(`/status/${encodeURIComponent(uuid)}`),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );
}
