import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  z,
  opengrok,
  textResult,
  errorResult,
  registerReadTool,
} from "./_helpers.js";

/**
 * 对应接口：/repositories/property/{field}?repository=...
 */
export function registerRepositoryTools(server: McpServer) {
  registerReadTool(
    server,
    "get_repository_property",
    "读取某个仓库的某一个属性。",
    {
      field: z.string().describe("属性字段名。"),
      repository: z.string().describe("仓库名。"),
    },
    async ({ field, repository }) => {
      try {
        return textResult(
          await opengrok.get(
            `/repositories/property/${encodeURIComponent(field)}`,
            { repository },
          ),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );
}
