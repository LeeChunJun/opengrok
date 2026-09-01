/**
 * headless 子命令实现：每个子命令都把结果以「人类可读文本」输出到 stdout，
 * 错误以非 0 退出码报告，便于 shell 脚本拼接。
 *
 * 设计原则：
 *  - stdout 仅放最终结果，日志走 stderr；
 *  - 默认尽量用相对简短的输出，加 --json 切到 JSON；
 *  - 错误统一走 OpenGrokHttpError 分支打印可读消息。
 */

import { opengrok, OpenGrokHttpError } from "../client/opengrok-client.js";
import { logger } from "../logger.js";

export interface CommandContext {
  args: string[];
  /** 把结果以 JSON 输出而非人类可读文本 */
  json: boolean;
  /** 是否显示详细日志（始终写 stderr，与此无关） */
  verbose: boolean;
}

export interface CommandResult {
  /** 进程退出码：0 = 成功 */
  exitCode: number;
}

const USAGE = `用法：
  opengrok-cli --headless <command> [options]

子命令：
  list-projects              列出所有项目
  list-indexed               列出已索引的项目
  ping                       检查 OpenGrok 是否可达
  version                    读取服务端版本
  search <query>             跨项目搜索
    --type <full|def|symbol|path|hist>   默认 full
    --project <name>        可重复，限定项目
    --max <n>               默认 50
    --path <glob>           限定路径
  get-file <path>            读取文件内容（按 stdout 输出纯文本）
  blame <path> [--rev <r>]   按行输出 blame
  history <path>             输出文件 SCM 历史
    --max <n>               默认 30
    --with-files            同时列出改动的文件

通用选项：
  --json                     以 JSON 形式输出
  --help, -h                 打印本帮助
`;

export function printUsage() {
  process.stdout.write(USAGE);
}

/** 把任意数据按人类可读文本打到 stdout。 */
function dump(payload: unknown, ctx: CommandContext) {
  if (ctx.json) {
    process.stdout.write(JSON.stringify(payload, null, 2) + "\n");
    return;
  }
  if (typeof payload === "string") {
    process.stdout.write(payload);
    if (!payload.endsWith("\n")) process.stdout.write("\n");
    return;
  }
  if (Array.isArray(payload)) {
    for (const item of payload) {
      process.stdout.write(formatItem(item) + "\n");
    }
    return;
  }
  process.stdout.write(JSON.stringify(payload, null, 2) + "\n");
}

function formatItem(item: unknown): string {
  if (item == null) return String(item);
  if (typeof item === "string") return item;
  if (typeof item === "object") {
    const obj = item as Record<string, unknown>;
    if ("path" in obj && typeof obj["path"] === "string") {
      const line = obj["line"] ?? obj["lineno"] ?? "";
      return line ? `${obj["path"]}:${line}` : obj["path"];
    }
    return JSON.stringify(item);
  }
  return String(item);
}

function failExit(err: unknown): number {
  if (err instanceof OpenGrokHttpError) {
    process.stderr.write(
      `OpenGrok HTTP ${err.status}: ${(err.body as { message?: string })?.message ?? err.message}\n`,
    );
    return err.status >= 500 ? 2 : 1;
  }
  process.stderr.write(`错误：${(err as Error).message}\n`);
  return 1;
}

// ============== 各子命令 ==============

export async function cmdPing(ctx: CommandContext): Promise<CommandResult> {
  const ok = await opengrok.ping();
  if (ctx.json) {
    process.stdout.write(JSON.stringify({ ok }) + "\n");
  } else {
    process.stdout.write(ok ? "pong\n" : "OpenGrok 不可达\n");
  }
  return { exitCode: ok ? 0 : 2 };
}

export async function cmdVersion(_ctx: CommandContext): Promise<CommandResult> {
  try {
    const v = await opengrok.getVersion();
    process.stdout.write(v.replace(/\n$/, "") + "\n");
    return { exitCode: 0 };
  } catch (err) {
    return { exitCode: failExit(err) };
  }
}

export async function cmdListProjects(ctx: CommandContext): Promise<CommandResult> {
  try {
    const projects = await opengrok.listProjects();
    if (ctx.json) {
      process.stdout.write(JSON.stringify(projects, null, 2) + "\n");
    } else {
      process.stdout.write(`共 ${projects.length} 个项目：\n`);
      for (const p of projects) {
        process.stdout.write(`  - ${p.name}\n`);
      }
    }
    return { exitCode: 0 };
  } catch (err) {
    return { exitCode: failExit(err) };
  }
}

export async function cmdListIndexed(ctx: CommandContext): Promise<CommandResult> {
  try {
    const projects = await opengrok.listIndexedProjects();
    dump(projects.map((p) => p.name), ctx);
    return { exitCode: 0 };
  } catch (err) {
    return { exitCode: failExit(err) };
  }
}

export async function cmdSearch(
  args: string[],
  ctx: CommandContext,
): Promise<CommandResult> {
  if (args.length === 0 || args[0] === "-h" || args[0] === "--help") {
    process.stderr.write("search 需要一个查询词，例如：opengrok-cli search OrderService\n");
    return { exitCode: 2 };
  }

  const query = args[0];
  const projects: string[] = [];
  let type: "full" | "def" | "symbol" | "path" | "hist" = "full";
  let max = 50;
  let path: string | undefined;

  for (let i = 1; i < args.length; i++) {
    const a = args[i];
    if (a === "--type") type = args[++i] as typeof type;
    else if (a === "--project") projects.push(args[++i]);
    else if (a === "--max") max = Number(args[++i]);
    else if (a === "--path") path = args[++i];
  }

  try {
    const result = await opengrok.search({
      query,
      type,
      projects,
      maxresults: max,
      path,
    });
    if (ctx.json) {
      process.stdout.write(JSON.stringify(result, null, 2) + "\n");
      return { exitCode: 0 };
    }
    process.stdout.write(
      `搜索 [${type}] "${query}"${path ? ` (path=${path})` : ""}${
        projects.length ? ` projects=${projects.join(",")}` : ""
      }：\n`,
    );
    if (result.hits.length === 0) {
      process.stdout.write("  （无结果）\n");
    } else {
      for (const h of result.hits) {
        process.stdout.write("  " + formatItem(h) + "\n");
      }
    }
    if (result.total != null) {
      process.stdout.write(
        `\n共 ${result.total} 条（已显示 ${result.hits.length} 条）${
          result.more ? "，还有更多" : ""
        }\n`,
      );
    }
    if (result.elapsed != null) {
      process.stdout.write(`耗时 ${result.elapsed}ms\n`);
    }
    return { exitCode: 0 };
  } catch (err) {
    return { exitCode: failExit(err) };
  }
}

export async function cmdGetFile(
  args: string[],
  ctx: CommandContext,
): Promise<CommandResult> {
  const path = args[0];
  if (!path) {
    process.stderr.write("get-file 需要一个文件路径\n");
    return { exitCode: 2 };
  }
  try {
    const text = await opengrok.getFileContent(path);
    // 文件内容永远按原始文本输出到 stdout，--json 仅影响元信息
    if (ctx.json) {
      process.stdout.write(JSON.stringify({ path, content: text }, null, 2) + "\n");
    } else {
      process.stdout.write(text);
    }
    return { exitCode: 0 };
  } catch (err) {
    return { exitCode: failExit(err) };
  }
}

export async function cmdBlame(
  args: string[],
  ctx: CommandContext,
): Promise<CommandResult> {
  const path = args[0];
  let revision: string | undefined;
  for (let i = 1; i < args.length; i++) {
    if (args[i] === "--rev") revision = args[++i];
  }
  if (!path) {
    process.stderr.write("blame 需要一个文件路径\n");
    return { exitCode: 2 };
  }
  try {
    const lines = await opengrok.annotateFile(path, revision);
    if (ctx.json) {
      process.stdout.write(JSON.stringify(lines, null, 2) + "\n");
      return { exitCode: 0 };
    }
    process.stdout.write(`Blame: ${path}${revision ? ` @ ${revision}` : ""}\n\n`);
    for (const a of lines) {
      const rev = (a.revision ?? "").toString().slice(0, 8);
      const author = (a.author ?? "").toString().slice(0, 16).padEnd(16, " ");
      const date = (a.date ?? "").toString().slice(0, 19);
      process.stdout.write(
        `${rev} ${author} ${date}  L${(a.line ?? 0).toString().padStart(4, " ")}\n`,
      );
    }
    return { exitCode: 0 };
  } catch (err) {
    return { exitCode: failExit(err) };
  }
}

export async function cmdHistory(
  args: string[],
  ctx: CommandContext,
): Promise<CommandResult> {
  const path = args[0];
  let max = 30;
  let withFiles = false;
  for (let i = 1; i < args.length; i++) {
    if (args[i] === "--max") max = Number(args[++i]);
    else if (args[i] === "--with-files") withFiles = true;
  }
  if (!path) {
    process.stderr.write("history 需要一个文件路径\n");
    return { exitCode: 2 };
  }
  try {
    const revs = await opengrok.getFileHistory(path, { max, withFiles });
    if (ctx.json) {
      process.stdout.write(JSON.stringify(revs, null, 2) + "\n");
      return { exitCode: 0 };
    }
    process.stdout.write(`History: ${path}\n\n`);
    for (const r of revs) {
      process.stdout.write(
        `${(r.revision ?? "").toString().slice(0, 10)} ${(r.date ?? "").toString().slice(0, 19)} ${(r.author ?? "")
          .toString()
          .slice(0, 16)
          .padEnd(16, " ")} ${r.message ?? ""}\n`,
      );
      if (withFiles && r.files?.length) {
        for (const f of r.files.slice(0, 10)) {
          process.stdout.write(`    ${f}\n`);
        }
        if (r.files.length > 10) {
          process.stdout.write(`    ... 共 ${r.files.length} 个文件\n`);
        }
      }
    }
    return { exitCode: 0 };
  } catch (err) {
    return { exitCode: failExit(err) };
  }
}

/** headless 入口：根据 argv[0] 分派。 */
export async function runHeadless(argv: string[]): Promise<number> {
  const ctx: CommandContext = {
    args: argv.slice(1),
    json: argv.includes("--json"),
    verbose: argv.includes("--verbose"),
  };

  const sub = argv[0];
  switch (sub) {
    case undefined:
    case "help":
    case "--help":
    case "-h":
      printUsage();
      return 0;
    case "ping":
      return (await cmdPing(ctx)).exitCode;
    case "version":
      return (await cmdVersion(ctx)).exitCode;
    case "list-projects":
    case "projects":
    case "ls":
      return (await cmdListProjects(ctx)).exitCode;
    case "list-indexed":
      return (await cmdListIndexed(ctx)).exitCode;
    case "search":
      return (await cmdSearch(ctx.args, ctx)).exitCode;
    case "get-file":
    case "cat":
      return (await cmdGetFile(ctx.args, ctx)).exitCode;
    case "blame":
    case "annotate":
      return (await cmdBlame(ctx.args, ctx)).exitCode;
    case "history":
    case "log":
      return (await cmdHistory(ctx.args, ctx)).exitCode;
    default:
      process.stderr.write(`未知子命令：${sub}\n\n`);
      printUsage();
      return 2;
  }
}
