import pino from "pino";
import { config } from "./config.js";

/**
 * 全局 pino 日志器，强制只写 stderr。
 *
 * 为什么必须写 stderr？因为 stdio 传输模式下，MCP 协议本身占用 stdout
 * 来传输 JSON-RPC 帧。任何往 stdout 写日志都会破坏协议流、断开连接。
 */
export const logger = pino(
  {
    level: config.logLevel,
    // 使用 ISO 时间戳，方便跨机器对齐日志时间。
    timestamp: pino.stdTimeFunctions.isoTime,
  },
  pino.destination({ dest: 2, sync: false }), // 2 === stderr
);

export type Logger = typeof logger;
