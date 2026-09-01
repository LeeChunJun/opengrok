import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  z,
  opengrok,
  textResult,
  errorResult,
  registerReadTool,
} from "./_helpers.js";

/**
 * 对应接口：GET /annotation?path=&revision=
 */
export function registerAnnotationTools(server: McpServer) {
  registerReadTool(
    server,
    "annotate_file",
    "对文件做 SCM blame，输出每一行的提交信息；revision 留空时为 HEAD。",
    {
      path: z.string().describe("相对于仓库根的文件路径。"),
      revision: z.string().optional()
        .describe("SCM 修订号；不填则默认 HEAD。"),
    },
    async ({ path, revision }) => {
      try {
        return textResult(
          await opengrok.get("/annotation", { path, revision }),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );
}
