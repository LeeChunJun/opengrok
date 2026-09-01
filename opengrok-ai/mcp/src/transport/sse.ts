import express, { type Request, type Response } from "express";
import { randomUUID } from "node:crypto";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import { logger } from "../logger.js";
import { config } from "../config.js";

/**
 * 旧版 HTTP+SSE 传输：
 *  - GET  /sse           客户端用它打开事件流
 *  - POST /messages?sessionId=<id>  客户端用它发送请求
 *
 * 保留它是为了兼容尚未升级到 Streamable HTTP 的老 MCP 客户端。
 * 新部署建议直接使用 transport/http.ts。
 */
export async function startSse(
  server: McpServer,
  opts: { port: number; host: string },
): Promise<void> {
  const app = express();
  app.use(express.json({ limit: "10mb" }));

  // 每个打开的 SSE 连接独享一个 sessionId 与 transport。
  const sessions = new Map<string, SSEServerTransport>();

  app.get("/sse", async (_req: Request, res: Response) => {
    const sessionId = randomUUID();
    logger.info({ sessionId }, "new SSE session");
    const transport = new SSEServerTransport(
      `/messages?sessionId=${sessionId}`,
      res,
    );
    sessions.set(sessionId, transport);

    res.on("close", () => {
      logger.info({ sessionId }, "SSE session closed");
      sessions.delete(sessionId);
    });

    await server.connect(transport);
  });

  app.post("/messages", async (req: Request, res: Response) => {
    const sessionId = String(req.query.sessionId ?? "");
    const transport = sessions.get(sessionId);
    if (!transport) {
      res.status(404).json({ error: "unknown sessionId" });
      return;
    }
    await transport.handlePostMessage(req, res, req.body);
  });

  app.get("/healthz", (_req, res) => res.json({ ok: true }));

  await new Promise<void>((resolve) => {
    app.listen(opts.port, opts.host, () => resolve());
  });
  logger.info(
    { host: opts.host, port: opts.port },
    `SSE transport listening on http://${opts.host}:${opts.port}/sse`,
  );

  const shutdown = async (signal: string) => {
    logger.info({ signal }, "shutting down SSE server");
    for (const t of sessions.values()) {
      try { await t.close(); } catch { /* 忽略关闭异常 */ }
    }
    sessions.clear();
    process.exit(0);
  };
  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("SIGTERM", () => void shutdown("SIGTERM"));

  // 保留 config 引用，方便后续日志按需读取。
  void config;
}
