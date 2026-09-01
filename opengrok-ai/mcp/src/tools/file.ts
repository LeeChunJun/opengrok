import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  z,
  opengrok,
  textResult,
  errorResult,
  registerReadTool,
} from "./_helpers.js";

/**
 * 对应接口：/file/* （content / defs / genre）
 */
export function registerFileTools(server: McpServer) {
  registerReadTool(
    server,
    "get_file_content",
    "读取指定路径文件的纯文本内容。",
    { path: z.string().describe("相对于仓库根的文件路径。") },
    async ({ path }) => {
      try {
        return textResult(await opengrok.get("/file/content", { path }));
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "get_file_definitions",
    "列出指定文件里的符号定义（函数、类等）。",
    { path: z.string().describe("相对于仓库根的文件路径。") },
    async ({ path }) => {
      try {
        return textResult(await opengrok.get("/file/defs", { path }));
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "get_file_genre",
    "返回文件被识别的 MIME / genre（text/plain），可作为是否值得读取内容的预判。",
    { path: z.string().describe("相对于仓库根的文件路径。") },
    async ({ path }) => {
      try {
        return textResult(await opengrok.get("/file/genre", { path }));
      } catch (err) {
        return errorResult(err);
      }
    },
  );
}
