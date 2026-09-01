import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { logger } from "../logger.js";

/**
 * 通过 stdio 启动 MCP server（MCP 的标准传输方式）。
 *
 * stdout 仅承载 JSON-RPC 帧，绝不能写入任何日志或其它内容。
 * 本项目的 logger 已固定走 stderr，这一边就可以放心使用了。
 */
export async function startStdio(server: McpServer): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);

  logger.info("stdio transport connected");

  // 优雅退出：SDK 会自动处理在途消息。
  const shutdown = async (signal: string) => {
    logger.info({ signal }, "shutting down stdio server");
    try {
      await server.close();
    } catch (err) {
      logger.error({ err }, "error during shutdown");
    }
    process.exit(0);
  };
  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
}
