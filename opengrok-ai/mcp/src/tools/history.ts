import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  z,
  opengrok,
  textResult,
  errorResult,
  registerReadTool,
} from "./_helpers.js";

/**
 * 对应接口：GET /history?path=&withFiles=&max=&start=
 */
export function registerHistoryTools(server: McpServer) {
  registerReadTool(
    server,
    "get_file_history",
    "读取指定文件的 SCM 历史（修订号与提交信息）。",
    {
      path: z.string().describe("相对于仓库根的文件路径。"),
      withFiles: z.boolean().default(false)
        .describe("是否同时返回每次提交改动的文件列表。"),
      max: z.number().int().min(1).max(10000).default(1000)
        .describe("最多返回多少条修订记录。"),
      start: z.number().int().min(0).default(0)
        .describe("分页偏移。"),
    },
    async ({ path, withFiles, max, start }) => {
      try {
        return textResult(
          await opengrok.get("/history", { path, withFiles, max, start }),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );
}
