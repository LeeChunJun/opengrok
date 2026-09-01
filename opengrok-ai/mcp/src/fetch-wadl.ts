/**
 * fetch-wadl：拉取 OpenGrok WADL 并把结果输出到 stdout 的诊断命令。
 *
 * 主要用途：
 *   - 验证鉴权头是否被正确注入；
 *   - 检查当前 OpenGrok 构建实际暴露了哪些接口；
 *   - 升级 OpenGrok 后做接口差异比对。
 *
 * 用法：
 *   node dist/index.js fetch-wadl [--detail] [--save <path>] [--full]
 *
 * 输出格式：stdout 先打一段 JSON 信封（可选地附 XML 原文），日志统一走
 * stderr，方便直接用管道做后续处理。
 */
import { writeFileSync } from "node:fs";
import { resolve } from "node:path";
import axios from "axios";
import { config, authSummary } from "./config.js";
import { logger } from "./logger.js";

export interface FetchWadlOptions {
  detail?: boolean;
  full?: boolean;
  save?: string;
}

export async function fetchWadl(opts: FetchWadlOptions = {}): Promise<number> {
  const url = `${config.baseUrl}/application.wadl${opts.detail ? "?detail=true" : ""}`;

  logger.info({ url, auth: authSummary() }, "fetching OpenGrok WADL");

  const headers: Record<string, string> = {
    Accept: "application/xml, text/xml, */*",
  };
  if (config.auth.enabled && config.auth.token) {
    headers["Authorization"] = `Bearer ${config.auth.token}`;
  }

  try {
    const res = await axios.get<string>(url, {
      headers,
      timeout: config.requestTimeoutMs,
      // WADL 是 XML，禁止 axios 自动 JSON 解析。
      transformResponse: [(d) => d],
      validateStatus: () => true,
    });

    const ok = res.status >= 200 && res.status < 300;
    const body: string = typeof res.data === "string" ? res.data : String(res.data);
    const byteSize = Buffer.byteLength(body, "utf8");

    // 简单统计 <resource> 与 <method> 元素个数，作为接口规模的粗略指标。
    const resourceCount = (body.match(/<resource\b/g) ?? []).length;
    const methodCount = (body.match(/<method\b/g) ?? []).length;

    const envelope = {
      ok,
      url,
      status: res.status,
      statusText: res.statusText,
      contentType: res.headers["content-type"] ?? null,
      bytes: byteSize,
      resourceCount,
      methodCount,
      auth: authSummary(),
      savedTo: opts.save ? resolve(opts.save) : null,
    };

    if (!ok) {
      process.stdout.write(JSON.stringify(envelope, null, 2) + "\n");
      logger.error(
        { status: res.status, statusText: res.statusText },
        "OpenGrok returned non-2xx",
      );
      return 2;
    }

    if (opts.save) {
      writeFileSync(resolve(opts.save), body, "utf8");
    }

    if (opts.full) {
      // 先打 JSON 信封，再打分隔符，再打原文。
      process.stdout.write(JSON.stringify(envelope, null, 2) + "\n");
      process.stdout.write("---WADL-BODY-START---\n");
      process.stdout.write(body);
      process.stdout.write("\n---WADL-BODY-END---\n");
    } else {
      process.stdout.write(JSON.stringify(envelope, null, 2) + "\n");
    }

    logger.info(
      { bytes: byteSize, resourceCount, methodCount },
      "WADL fetched successfully",
    );
    return 0;
  } catch (err) {
    const envelope = {
      ok: false,
      url,
      error: true,
      message: (err as Error).message,
      auth: authSummary(),
    };
    process.stdout.write(JSON.stringify(envelope, null, 2) + "\n");
    logger.error({ err: (err as Error).message }, "fetch failed");
    return 1;
  }
}
