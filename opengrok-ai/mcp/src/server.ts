import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { authSummary, config } from "./config.js";
import { logger } from "./logger.js";
import { registerAllTools } from "./tools/index.js";

/**
 * 创建并返回配置完毕的 MCP Server 实例。
 *
 * 该工厂与传输层无关——同一个 server 实例会被 stdio / SSE / Streamable HTTP
 * 三种传输共用。SDK 在每次请求之间保持无状态。
 */
export function createMcpServer(): McpServer {
  const server = new McpServer(
    {
      name: "opengrok-mcp",
      version: "0.1.0",
    },
    {
      capabilities: {
        tools: {},
      },
      // 给模型的轻量提示，引导它先列项目再搜索。
      instructions: [
        "本服务把 OpenGrok 的源码检索能力暴露为 MCP 工具。",
        "建议先调用 list_projects 发现可用项目，再用 search_code 查询；",
        "get_file_content 读文件、get_file_definitions 列符号，",
        "annotate_file 与 get_file_history 提供 SCM 历史。",
      ].join(" "),
    },
  );

  registerAllTools(server);

  // 启动鉴权自检：只打印脱敏摘要，不泄露 token 原文。
  logger.info(
    {
      baseUrl: config.baseUrl,
      auth: authSummary(),
      writeToolsEnabled: config.writeToolsEnabled,
    },
    "MCP server ready",
  );

  if (config.auth.type === "bearer" && !config.auth.enabled) {
    logger.warn(
      "OPENGROK_AUTH_TYPE=bearer 但 OPENGROK_TOKEN 为空——所有请求将不带鉴权头，预期会被服务端拒绝。",
    );
  }

  return server;
}
