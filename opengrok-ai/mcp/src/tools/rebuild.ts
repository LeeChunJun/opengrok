import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  z,
  opengrok,
  textResult,
  errorResult,
  registerWriteTool,
} from "./_helpers.js";

/**
 * 对应接口：
 *   PUT /suggest/rebuild
 *   PUT /suggest/rebuild/{project}
 *
 * 重建 suggester 索引，属于写操作。
 */
export function registerRebuildTools(server: McpServer) {
  registerWriteTool(
    server,
    "rebuild_suggester_index",
    "重建 suggester 索引（全部项目或单个项目）。属于长时任务，返回任务 UUID 后请用 get_job_status 轮询。",
    {
      project: z
        .string()
        .optional()
        .describe("只重建指定项目；不传则重建全部。"),
    },
    async ({ project }) => {
      try {
        const url = project
          ? `/suggest/rebuild/${encodeURIComponent(project)}`
          : `/suggest/rebuild`;
        return textResult(await opengrok.put(url));
      } catch (err) {
        return errorResult(err);
      }
    },
  );
}
