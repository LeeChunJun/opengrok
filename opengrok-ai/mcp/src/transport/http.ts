import express, { type Request, type Response } from "express";
import { randomUUID } from "node:crypto";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { logger } from "../logger.js";

/**
 * Streamable HTTP 传输（MCP 协议 2025-03-26+ 推荐形态）。
 *
 * 单个端点 `/mcp` 同时支持：
 *   - 普通 HTTP POST 响应（非流式调用）
 *   - SSE 流式响应（长任务、流式输出）
 *   - 通过 `Mcp-Session-Id` 头复用既有会话
 */
export async function startHttp(
  server: McpServer,
  opts: { port: number; host: string },
): Promise<void> {
  const app = express();
  app.use(express.json({ limit: "10mb" }));

  // 每个会话独享一个 transport 实例。
  const transports = new Map<string, StreamableHTTPServerTransport>();

  const handle = async (req: Request, res: Response) => {
    const sessionId = req.headers["mcp-session-id"] as string | undefined;

    if (sessionId && transports.has(sessionId)) {
      // 已有会话：复用 transport。
      const t = transports.get(sessionId)!;
      await t.handleRequest(req, res, req.body);
      return;
    }

    // 新会话：仅 POST 且不带 session id 时开启。
    if (!sessionId && req.method === "POST") {
      const t = new StreamableHTTPServerTransport({
        sessionIdGenerator: () => randomUUID(),
        onsessioninitialized: (id) => {
          logger.info({ sessionId: id }, "streamable-HTTP session opened");
          transports.set(id, t);
        },
      });
      t.onclose = () => {
        const id = t.sessionId;
        if (id) {
          logger.info({ sessionId: id }, "streamable-HTTP session closed");
          transports.delete(id);
        }
      };
      await server.connect(t);
      await t.handleRequest(req, res, req.body);
      return;
    }

    res.status(400).json({
      error:
        "Bad request: 请提供已存在的 Mcp-Session-Id，或不带它直接 POST 以开启新会话。",
    });
  };

  app.all("/mcp", handle);
  app.get("/healthz", (_req, res) => res.json({ ok: true }));

  await new Promise<void>((resolve) => {
    app.listen(opts.port, opts.host, () => resolve());
  });
  logger.info(
    { host: opts.host, port: opts.port },
    `Streamable HTTP transport listening on http://${opts.host}:${opts.port}/mcp`,
  );

  const shutdown = async (signal: string) => {
    logger.info({ signal }, "shutting down streamable-HTTP server");
    for (const t of transports.values()) {
      try { await t.close(); } catch { /* 忽略关闭异常 */ }
    }
    transports.clear();
    process.exit(0);
  };
  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
}
