import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  z,
  opengrok,
  textResult,
  errorResult,
  registerReadTool,
  registerWriteToolNoArgs,
} from "./_helpers.js";

/**
 * 对应接口：/system*
 *   GET  /system/ping
 *   GET  /system/version
 *   GET  /system/indextime
 *   POST /system/pathdesc
 *   PUT  /system/includes/reload
 */
export function registerSystemTools(server: McpServer) {
  registerReadTool(
    server,
    "ping",
    "健康检查：OpenGrok 可达时返回 200。",
    {},
    async () => {
      try {
        return textResult(await opengrok.get("/system/ping"));
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "get_system_version",
    "读取 OpenGrok 服务端版本号（text/plain）。",
    {},
    async () => {
      try {
        return textResult(await opengrok.get("/system/version"));
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "get_index_time",
    "读取最后一次构建索引的时间。",
    {},
    async () => {
      try {
        return textResult(await opengrok.get("/system/indextime"));
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "load_path_descriptions",
    "批量上传「路径 → 描述」映射，便于给文件打标签。",
    {
      entries: z
        .array(
          z.object({
            path: z.string(),
            description: z.string(),
          }),
        )
        .describe("{path, description} 对象数组。"),
    },
    async ({ entries }) => {
      try {
        return textResult(await opengrok.post("/system/pathdesc", entries));
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerWriteToolNoArgs(
    server,
    "reload_includes",
    "重新加载 OpenGrok 使用的 include 文件定义。",
    async () => {
      try {
        return textResult(await opengrok.put("/system/includes/reload"));
      } catch (err) {
        return errorResult(err);
      }
    },
  );
}
