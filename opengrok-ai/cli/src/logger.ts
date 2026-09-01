import pino from "pino";
import { config } from "./config.js";

/**
 * 全局 pino 日志器，强制只写 stderr。
 *
 * TUI 模式下 stdout 被 OpenTUI 占用，任何 stdout 写入都会污染终端界面。
 * headless 模式下 stdout 是 JSON / 文本输出，同样不能被日志污染。
 */
export const logger = pino(
  {
    level: config.logLevel,
    timestamp: pino.stdTimeFunctions.isoTime,
  },
  pino.destination({ dest: 2, sync: false }), // 2 === stderr
);

export type Logger = typeof logger;
