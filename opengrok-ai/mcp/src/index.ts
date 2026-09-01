#!/usr/bin/env node
import { parseArgs } from "node:util";
import { createMcpServer } from "./server.js";
import { startStdio } from "./transport/stdio.js";
import { startSse } from "./transport/sse.js";
import { startHttp } from "./transport/http.js";
import { fetchWadl } from "./fetch-wadl.js";
import { logger } from "./logger.js";
import { config } from "./config.js";

/**
 * 命令行入口。
 *
 * 两种模式：
 *
 * 1. 服务模式 —— 必须且只能传一个传输参数：
 *      --stdio       stdio JSON-RPC（本地 MCP 客户端默认方式）
 *      --sse         旧版 HTTP + SSE 传输
 *      --http        新版 Streamable HTTP 传输（推荐）
 *      --port <n>    HTTP 端口（默认从环境变量 / 3001 读取）
 *      --host <h>    HTTP 绑定地址（默认从环境变量 / 127.0.0.1 读取）
 *
 * 2. 诊断模式：
 *      fetch-wadl [--detail] [--full] [--save <path>]
 *      拉取 OpenGrok 的 WADL 并把 JSON 信封（可选地带上 XML 原文）输出到
 *      stdout，日志走 stderr。方便快速验证鉴权配置是否生效。
 */
async function main() {
  // 先识别诊断子命令，避免 parseArgs 因为缺少传输参数直接报错。
  const positional = process.argv.slice(2).filter((a) => !a.startsWith("-"));
  if (positional[0] === "fetch-wadl") {
    const exit = await runFetchWadl(process.argv.slice(2));
    process.exit(exit);
  }

  const { values } = parseArgs({
    options: {
      stdio: { type: "boolean", default: false },
      sse:   { type: "boolean", default: false },
      http:  { type: "boolean", default: false },
      port:  { type: "string" },
      host:  { type: "string" },
      help:  { type: "boolean", short: "h", default: false },
    },
    allowPositionals: false,
  });

  if (values.help) {
    printHelp();
    return;
  }

  const chosen = [
    values.stdio ? "stdio" : null,
    values.sse   ? "sse"   : null,
    values.http  ? "http"  : null,
  ].filter(Boolean) as string[];

  if (chosen.length === 0) {
    logger.error("未指定传输方式 —— 请使用 --stdio / --sse / --http 之一");
    printHelp();
    process.exit(2);
  }
  if (chosen.length > 1) {
    logger.error(
      { chosen },
      "--stdio / --sse / --http 必须且只能传一个",
    );
    process.exit(2);
  }

  const server = createMcpServer();
  const port = values.port ? Number(values.port) : config.http.port;
  const host = values.host ?? config.http.host;

  try {
    if (values.stdio) {
      await startStdio(server);
    } else if (values.sse) {
      await startSse(server, { port, host });
    } else if (values.http) {
      await startHttp(server, { port, host });
    }
  } catch (err) {
    logger.fatal({ err: (err as Error).message }, "transport failed to start");
    process.exit(1);
  }
}

async function runFetchWadl(argv: string[]): Promise<number> {
  // 手写一个极简参数解析器，不为单一命令多引一个依赖。
  const opts: { detail: boolean; full: boolean; save?: string } = {
    detail: false,
    full: false,
  };
  for (let i = 1; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--detail") opts.detail = true;
    else if (a === "--full") opts.full = true;
    else if (a === "--save") {
      const next = argv[i + 1];
      if (!next || next.startsWith("-")) {
        process.stderr.write("fetch-wadl: --save 后面必须跟一个文件路径\n");
        return 2;
      }
      opts.save = next;
      i++;
    } else if (a === "-h" || a === "--help") {
      process.stderr.write(
        "用法：opengrok-mcp fetch-wadl [--detail] [--full] [--save <path>]\n",
      );
      return 0;
    }
  }
  return fetchWadl(opts);
}

function printHelp() {
  const msg = `
opengrok-mcp —— OpenGrok 的 MCP 服务器

用法
  opengrok-mcp [server-options]
  opengrok-mcp fetch-wadl [--detail] [--full] [--save <path>]

服务端选项
  --stdio               用 stdio 传输（本地 MCP 客户端）。
  --sse                 用旧版 HTTP+SSE 传输。
  --http                用新版 Streamable HTTP 传输（推荐）。
  --port <n>            --sse / --http 监听的端口（默认 ${config.http.port}）。
  --host <h>            --sse / --http 绑定的地址（默认 ${config.http.host}）。
  -h, --help            打印本帮助。

诊断命令
  fetch-wadl            拉取 OpenGrok 的 WADL，并把 JSON 信封写到 stdout
                        （日志走 stderr），便于快速验证鉴权。
                        --detail 请求扩展版 WADL
                        --full  同时把 XML 原文一并输出
                        --save <path>  额外把原文写到文件

环境变量
  OPENGROK_BASE_URL     OpenGrok REST 根地址（默认 http://localhost:8081/api/v1）
  OPENGROK_AUTH_TYPE    "bearer" 或 "none"（默认 "none"）
  OPENGROK_TOKEN        Bearer 令牌；OPENGROK_AUTH_TYPE=bearer 时必填
  MCP_HTTP_PORT         HTTP 默认端口
  MCP_HTTP_HOST         HTTP 默认绑定地址
  ENABLE_WRITE_TOOLS    "true" 时注册写工具（默认 false）
  LOG_LEVEL             pino 日志级别：fatal|error|warn|info|debug|trace
  REQUEST_TIMEOUT_MS    单次请求超时（默认 30000）
`;
  process.stderr.write(msg);
}

main().catch((err) => {
  logger.fatal({ err: (err as Error).message }, "unhandled error");
  process.exit(1);
});
