import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  z,
  opengrok,
  textResult,
  errorResult,
  registerReadTool,
} from "./_helpers.js";

/**
 * 对应接口：GET /list?path=...
 */
export function registerListTools(server: McpServer) {
  registerReadTool(
    server,
    "list_directory",
    "列出已索引源码树中某个目录的内容。",
    {
      path: z
        .string()
        .default("")
        .describe("相对于仓库根的目录路径；留空表示仓库根。"),
    },
    async ({ path }) => {
      try {
        return textResult(await opengrok.get("/list", { path }));
      } catch (err) {
        return errorResult(err);
      }
    },
  );
}
