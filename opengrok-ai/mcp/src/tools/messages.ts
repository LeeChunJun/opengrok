import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  z,
  opengrok,
  textResult,
  errorResult,
  registerReadTool,
  registerWriteTool,
} from "./_helpers.js";

/**
 * 对应接口：/messages
 *   GET    /messages?tag=...
 *   POST   /messages
 *   DELETE /messages?tag=...   body 为纯文本 tag
 */
export function registerMessageTools(server: McpServer) {
  registerReadTool(
    server,
    "get_messages",
    "读取系统消息，可按 tag 过滤。",
    { tag: z.string().optional() },
    async ({ tag }) => {
      try {
        return textResult(
          await opengrok.get("/messages", tag ? { tag } : undefined),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerWriteTool(
    server,
    "add_message",
    "新增一条系统消息。请求体为 JSON 对象。",
    {
      message: z
        .record(z.string(), z.unknown())
        .describe("描述消息内容的 JSON 对象。"),
    },
    async ({ message }) => {
      try {
        return textResult(await opengrok.post("/messages", message));
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerWriteTool(
    server,
    "remove_messages_with_tag",
    "删除所有带指定 tag 的消息。请求体为纯文本 tag。",
    { tag: z.string().describe("待删除消息的 tag。") },
    async ({ tag }) => {
      try {
        return textResult(await opengrok.delete("/messages", { tag }, tag));
      } catch (err) {
        return errorResult(err);
      }
    },
  );
}
