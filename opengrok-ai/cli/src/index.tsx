#!/usr/bin/env bun
/**
 * CLI 入口：根据 argv 分派到 headless 子命令或 TUI。
 *
 * 默认进入 TUI 模式；
 * 带 --headless 时按子命令运行，结果输出到 stdout。
 *
 * 用法：
 *   bun run src/index.tsx                         # 进 TUI
 *   bun run src/index.tsx --headless ping          # headless 子命令
 *   bun run src/index.tsx --headless search <q>    # 搜索
 *   bun run src/index.tsx --headless get-file <p>  # 读文件
 *   bun run src/index.tsx --headless blame <p>     # blame
 *   bun run src/index.tsx --headless history <p>   # history
 *   bun run src/index.tsx --help                   # 打印帮助
 */

import { createCliRenderer } from "@opentui/core";
import { createRoot } from "@opentui/react";
import { App } from "./tui/App.js";
import { runHeadless, printUsage } from "./headless/commands.js";
import { config } from "./config.js";
import { opengrok } from "./client/opengrok-client.js";
import { logger } from "./logger.js";

async function main() {
  const argv = process.argv.slice(2);

  // 帮助
  if (argv.length === 0 && process.stdout.isTTY) {
    // 没有参数且是 TTY：进 TUI
    await launchTui();
    return;
  }
  if (argv.includes("--help") || argv.includes("-h")) {
    printUsage();
    process.exit(0);
  }

  // 启动探活（headless 模式默认也探活，避免 401/网络错误时不告知）
  if (config.pingOnStart) {
    const ok = await opengrok.ping();
    if (!ok) {
      process.stderr.write(
        `✗ 无法连接 OpenGrok：${config.baseUrl}\n` +
          `  检查 OPENGROK_BASE_URL 与 OPENGROK_TOKEN 是否正确\n`,
      );
      process.exit(2);
    }
  }

  if (argv[0] === "--headless") {
    const code = await runHeadless(argv.slice(1));
    process.exit(code);
  }

  // 默认进 TUI
  await launchTui();
}

async function launchTui() {
  // OpenTUI 必须运行在 TTY 环境
  if (!process.stdout.isTTY) {
    process.stderr.write(
      "✗ TUI 模式必须在 TTY 中运行。\n" +
        "  在脚本/CI 中请加 --headless 子命令，例如：\n" +
        "  bun run src/index.tsx --headless search <query>\n",
    );
    process.exit(2);
  }

  // 启动前先 ping，避免 TUI 启动后才发现鉴权失败
  if (config.pingOnStart) {
    const ok = await opengrok.ping();
    if (!ok) {
      process.stderr.write(
        `⚠ OpenGrok 未响应（${config.baseUrl}），仍可进入 TUI 查看错误\n`,
      );
      logger.warn({ baseUrl: config.baseUrl }, "ping failed on TUI start");
    } else {
      logger.info({ baseUrl: config.baseUrl, auth: config.auth.enabled ? "bearer" : "none" }, "TUI ready");
    }
  }

  const renderer = await createCliRenderer();
  createRoot(renderer).render(<App />);
}

main().catch((err) => {
  process.stderr.write(`✗ 启动失败：${(err as Error).message}\n`);
  logger.fatal({ err: (err as Error).message }, "CLI failed to start");
  process.exit(1);
});
