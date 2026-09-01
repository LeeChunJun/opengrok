import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { logger } from "../logger.js";
import { config } from "../config.js";

import { registerSearchTools } from "./search.js";
import { registerFileTools } from "./file.js";
import { registerListTools } from "./list.js";
import { registerHistoryTools } from "./history.js";
import { registerAnnotationTools } from "./annotate.js";
import { registerSuggestTools } from "./suggest.js";
import { registerProjectTools } from "./projects.js";
import { registerGroupTools } from "./groups.js";
import { registerConfigurationTools } from "./configuration.js";
import { registerSystemTools } from "./system.js";
import { registerRepositoryTools } from "./repositories.js";
import { registerMessageTools } from "./messages.js";
import { registerStatusTools } from "./status.js";
import { registerRebuildTools } from "./rebuild.js";

/**
 * 把所有 MCP 工具注册到给定 server 上。
 *
 * 读工具始终注册；写工具受 ENABLE_WRITE_TOOLS 环境变量控制。
 */
export function registerAllTools(server: McpServer) {
  logger.info(
    {
      baseUrl: config.baseUrl,
      writeToolsEnabled: config.writeToolsEnabled,
      auth: config.auth.enabled ? "bearer" : "none",
    },
    "registering MCP tools",
  );

  registerSearchTools(server);
  registerFileTools(server);
  registerListTools(server);
  registerHistoryTools(server);
  registerAnnotationTools(server);
  registerSuggestTools(server);
  registerProjectTools(server);
  registerGroupTools(server);
  registerConfigurationTools(server);
  registerSystemTools(server);
  registerRepositoryTools(server);
  registerMessageTools(server);
  registerStatusTools(server);
  registerRebuildTools(server);
}
