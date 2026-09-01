import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  z,
  opengrok,
  textResult,
  errorResult,
  registerReadTool,
} from "./_helpers.js";

/**
 * 对应接口：GET /search
 *
 * WADL 查询参数：
 *   full / def / symbol / path / hist / type
 *   projects, maxresults, start（默认 0）, sort（默认 relevancy）
 *   maxhitsperfile（默认 0，OpenAPI 未列出但 WADL 中可见）
 */
export function registerSearchTools(server: McpServer) {
  registerReadTool(
    server,
    "search_code",
    [
      "在 OpenGrok 索引中搜索源代码。",
      "根据查询语义，把 query 放到对应的字段（full/def/symbol/path/hist）里。",
      "支持分页、排序、按文件命中数限制。",
    ].join(""),
    {
      query: z.string().describe("搜索关键词。"),
      type: z
        .enum(["full", "def", "symbol", "path", "hist"])
        .default("full")
        .describe("query 要落到哪个字段上。"),

      projects: z
        .array(z.string())
        .optional()
        .describe("限定到指定项目集合。"),

      maxresults: z.number().int().min(1).max(1000).default(25)
        .describe("返回结果的最大条数。"),
      start: z.number().int().min(0).default(0)
        .describe("分页偏移。"),
      sort: z.enum(["relevancy", "date", "path"]).default("relevancy"),

      // OpenAPI 没列但 WADL 里有，保留给高级用户。
      maxhitsperfile: z.number().int().min(0).default(0)
        .describe("单个文件最多返回的命中数；0 表示不限制。"),
    },
    async (args) => {
      try {
        const params: Record<string, unknown> = {
          [args.type]: args.query,
          start: args.start,
          sort: args.sort,
          maxresults: args.maxresults,
          maxhitsperfile: args.maxhitsperfile,
        };
        if (args.projects?.length) params.projects = args.projects.join(",");
        return textResult(await opengrok.get("/search", params));
      } catch (err) {
        return errorResult(err);
      }
    },
  );
}
