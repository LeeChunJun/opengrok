import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { OpenGrokHttpError, opengrok } from "../client/opengrok-client.js";
import { logger } from "../logger.js";
import { config } from "../config.js";

/** 把任意数据序列化成 MCP 文本内容块。 */
export function textResult(payload: unknown) {
  const text =
    typeof payload === "string" ? payload : JSON.stringify(payload, null, 2);
  return { content: [{ type: "text" as const, text }] };
}

/**
 * 把 handler 里抛出的异常转成 MCP 文本错误响应。
 *
 * 原则：handler 永远不要让异常冒泡到传输层（会断连），统一用 catch
 * 包成可读的文本结果。
 */
export function errorResult(err: unknown) {
  if (err instanceof OpenGrokHttpError) {
    logger.warn(
      { status: err.status, body: err.body },
      "OpenGrok returned an error",
    );
    return textResult({
      error: true,
      status: err.status,
      message: err.message,
      body: err.body,
    });
  }
  logger.error({ err: (err as Error).message }, "tool handler crashed");
  return textResult({ error: true, message: (err as Error).message });
}

export function canWrite(): boolean {
  return config.writeToolsEnabled;
}

/** 写工具统一附加的破坏性注解，让 MCP 客户端渲染前给用户弹确认框。 */
const destructiveAnnotations = {
  destructiveHint: true,
  idempotentHint: false,
  openWorldHint: false,
  readOnlyHint: false,
} as const;

/**
 * 注册一个只读工具。本质上是 server.tool() 的薄封装，
 * 主要是为了让调用点的代码读起来更一致。
 */
export function registerReadTool<S extends z.ZodRawShape>(
  server: McpServer,
  name: string,
  description: string,
  schemaShape: S,
  handler: (
    args: z.infer<z.ZodObject<S>>,
  ) => Promise<ReturnType<typeof textResult>>,
) {
  // SDK 的 tool() 重载在泛型 helper 里很难精确满足，
  // 这里用 any 透传，handler 内部依然保留强类型。
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (server.tool as any)(name, description, schemaShape, handler);
}

/**
 * 注册一个写工具。
 * 仅当 config.writeToolsEnabled === true 时才会真正注册，
 * 描述里会自动加上「破坏性操作」的醒目提示。
 */
export function registerWriteTool<S extends z.ZodRawShape>(
  server: McpServer,
  name: string,
  description: string,
  schemaShape: S,
  handler: (
    args: z.infer<z.ZodObject<S>>,
  ) => Promise<ReturnType<typeof textResult>>,
) {
  if (!canWrite()) return;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (server.tool as any)(
    name,
    `【写工具·危险】${description}（需要将 ENABLE_WRITE_TOOLS 设为 true 才可用）`,
    schemaShape,
    destructiveAnnotations,
    handler,
  );
}

/** registerWriteTool 的无参版本。 */
export function registerWriteToolNoArgs(
  server: McpServer,
  name: string,
  description: string,
  handler: () => Promise<ReturnType<typeof textResult>>,
) {
  if (!canWrite()) return;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (server.tool as any)(
    name,
    `【写工具·危险】${description}（需要将 ENABLE_WRITE_TOOLS 设为 true 才可用）`,
    {},
    destructiveAnnotations,
    handler,
  );
}

export { z, opengrok, logger };
