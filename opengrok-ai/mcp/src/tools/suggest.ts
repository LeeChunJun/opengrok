import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  z,
  opengrok,
  textResult,
  errorResult,
  registerReadTool,
} from "./_helpers.js";

/**
 * 对应接口：/suggest 的读端点
 *   GET /suggest
 *   GET /suggest/popularity/{project}
 *   GET /suggest/config
 */
export function registerSuggestTools(server: McpServer) {
  registerReadTool(
    server,
    "get_suggestions",
    "对半输入的标识符做 token 自动补全。",
    {
      projects: z.array(z.string()).optional(),
      field: z.string().default("full"),
      caret: z.number().int().min(0),
      full: z.string().optional(),
      defs: z.string().optional(),
      refs: z.string().optional(),
      path: z.string().optional(),
      hist: z.string().optional(),
      type: z.string().optional(),
    },
    async (a) => {
      try {
        const params: Record<string, unknown> = { field: a.field, caret: a.caret };
        if (a.projects?.length) params["projects[]"] = a.projects;
        if (a.full) params.full = a.full;
        if (a.defs) params.defs = a.defs;
        if (a.refs) params.refs = a.refs;
        if (a.path) params.path = a.path;
        if (a.hist) params.hist = a.hist;
        if (a.type) params.type = a.type;
        return textResult(await opengrok.get("/suggest", params));
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "get_popularity",
    "分页获取指定项目的搜索词热度数据。",
    {
      project: z.string(),
      field: z.enum(["full", "defs", "refs", "path"]).default("full"),
      page: z.number().int().min(0).default(0),
      pageSize: z.number().int().min(1).max(10000).default(100),
      all: z.boolean().default(false).describe("是否合并所有页一次性返回。"),
    },
    async ({ project, field, page, pageSize, all }) => {
      try {
        return textResult(
          await opengrok.get(`/suggest/popularity/${encodeURIComponent(project)}`, {
            field, page, pageSize, all,
          }),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "get_suggester_config",
    "读取 suggester 子系统的运行时配置。",
    {},
    async () => {
      try {
        return textResult(await opengrok.get("/suggest/config"));
      } catch (err) {
        return errorResult(err);
      }
    },
  );
}
