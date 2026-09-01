import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  z,
  opengrok,
  textResult,
  errorResult,
  registerReadTool,
  registerWriteTool,
  registerWriteToolNoArgs,
} from "./_helpers.js";

/**
 * 对应接口：/configuration*
 *   GET  /configuration
 *   GET  /configuration/{field}
 *   PUT  /configuration
 *   PUT  /configuration/{field}
 *   POST /configuration/authorization/reload
 */
export function registerConfigurationTools(server: McpServer) {
  // ---- 只读 ----

  registerReadTool(
    server,
    "get_configuration",
    "读取完整 OpenGrok 配置（XML 格式）。",
    {},
    async () => {
      try {
        return textResult(await opengrok.get("/configuration"));
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "get_configuration_field",
    "读取配置的某一个字段。",
    { field: z.string() },
    async ({ field }) => {
      try {
        return textResult(
          await opengrok.get(`/configuration/${encodeURIComponent(field)}`),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  // ---- 写（受开关控制）----

  registerWriteTool(
    server,
    "set_configuration",
    "整体替换 OpenGrok 配置（请求体为 XML）。使用需谨慎。",
    {
      body: z.string().describe("完整 XML 配置体。"),
      reindex: z.boolean().default(false)
        .describe("应用配置后是否立即触发重建索引。"),
    },
    async ({ body, reindex }) => {
      try {
        return textResult(
          await opengrok.put("/configuration", body, { reindex }),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerWriteTool(
    server,
    "set_configuration_field",
    "修改配置的某一个字段。",
    {
      field: z.string(),
      value: z.string().describe("字段的新值（请求体）。"),
    },
    async ({ field, value }) => {
      try {
        return textResult(
          await opengrok.put(
            `/configuration/${encodeURIComponent(field)}`,
            value,
          ),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerWriteToolNoArgs(
    server,
    "reload_authorization",
    "从磁盘重新加载授权插件的配置。",
    async () => {
      try {
        return textResult(
          await opengrok.post("/configuration/authorization/reload"),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );
}
