import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  z,
  opengrok,
  textResult,
  errorResult,
  registerReadTool,
} from "./_helpers.js";

/**
 * 对应接口：/groups*
 *   GET  /groups
 *   GET  /groups/{group}/pattern
 *   GET  /groups/{group}/allprojects
 *   POST /groups/{group}/match
 */
export function registerGroupTools(server: McpServer) {
  registerReadTool(
    server,
    "list_groups",
    "列出所有项目分组。",
    {},
    async () => {
      try {
        return textResult(await opengrok.get("/groups"));
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "get_group_pattern",
    "返回定义该分组的路径匹配规则。",
    { group: z.string() },
    async ({ group }) => {
      try {
        return textResult(
          await opengrok.get(`/groups/${encodeURIComponent(group)}/pattern`),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "get_group_projects",
    "返回归属于该分组的所有项目。",
    { group: z.string() },
    async ({ group }) => {
      try {
        return textResult(
          await opengrok.get(`/groups/${encodeURIComponent(group)}/allprojects`),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "match_project_to_group",
    "判断某个项目名是否匹配某个分组的规则。",
    {
      group: z.string(),
      project: z.string().describe("待测试的项目名（请求体）。"),
    },
    async ({ group, project }) => {
      try {
        return textResult(
          await opengrok.post(`/groups/${encodeURIComponent(group)}/match`, project),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );
}
