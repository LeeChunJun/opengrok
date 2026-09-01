import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse } from "axios";
import { config } from "../config.js";
import { logger } from "../logger.js";

/**
 * OpenGrok REST 客户端（CLI 自包含版本，与 opengrok-mcp 的同名模块一致）。
 *
 * 与 mcp 客户端的区别：
 *  - 默认 maxResults 取 config.defaultMaxResults 而不是写死 25；
 *  - 增加面向人类阅读的 search/list/getFile 包装方法，
 *    TUI 各 Screen 都通过这一层拿数据；
 *  - 保留 OpenGrokHttpError，供各 Screen 把异常转成 UI 提示。
 *
 * 注意：这里不复用 mcp 的实现，是为了把 cli/ 完全独立出来，
 * 后续两边各自演进不会互相牵制。
 */
export class OpenGrokClient {
  private readonly http: AxiosInstance;

  constructor(baseUrl: string = config.baseUrl) {
    const headers: Record<string, string> = {
      Accept: "application/json, text/plain, */*",
    };
    if (config.auth.enabled && config.auth.token) {
      headers["Authorization"] = `Bearer ${config.auth.token}`;
    }

    this.http = axios.create({
      baseURL: baseUrl,
      timeout: config.requestTimeoutMs,
      headers,
      // 不在 axios 这一层抛 4xx/5xx，由调用方按 response 状态自行判断。
      validateStatus: () => true,
      maxContentLength: 50 * 1024 * 1024,
    });
  }

  // ============== 底层 HTTP ==============

  async get<T = unknown>(
    path: string,
    params?: Record<string, unknown>,
  ): Promise<T> {
    return this.request<T>({ method: "GET", url: path, params });
  }

  async post<T = unknown>(
    path: string,
    body?: unknown,
    params?: Record<string, unknown>,
  ): Promise<T> {
    return this.request<T>({ method: "POST", url: path, data: body, params });
  }

  async put<T = unknown>(
    path: string,
    body?: unknown,
    params?: Record<string, unknown>,
  ): Promise<T> {
    return this.request<T>({ method: "PUT", url: path, data: body, params });
  }

  async delete<T = unknown>(
    path: string,
    params?: Record<string, unknown>,
    body?: unknown,
  ): Promise<T> {
    return this.request<T>({ method: "DELETE", url: path, params, data: body });
  }

  private async request<T>(cfg: AxiosRequestConfig): Promise<T> {
    const started = Date.now();
    try {
      const res: AxiosResponse<T> = await this.http.request<T>(cfg);
      const ms = Date.now() - started;
      logger.debug(
        { method: cfg.method, url: cfg.url, status: res.status, ms },
        "opengrok request",
      );
      if (res.status >= 400) {
        throw new OpenGrokHttpError(
          `OpenGrok ${cfg.method} ${cfg.url} -> ${res.status}`,
          res.status,
          res.data,
        );
      }
      return res.data;
    } catch (err) {
      if (err instanceof OpenGrokHttpError) throw err;
      const ms = Date.now() - started;
      logger.error(
        { err: (err as Error).message, method: cfg.method, url: cfg.url, ms },
        "opengrok request failed",
      );
      throw err;
    }
  }

  // ============== 业务便捷方法（面向 TUI / headless） ==============

  async ping(): Promise<boolean> {
    try {
      await this.get("/system/ping");
      return true;
    } catch {
      return false;
    }
  }

  async getVersion(): Promise<string> {
    return this.get<string>("/system/version");
  }

  async listProjects(): Promise<Project[]> {
    const data = await this.get<Project[]>("/projects");
    return Array.isArray(data) ? data : [];
  }

  async listIndexedProjects(): Promise<Project[]> {
    const data = await this.get<Project[]>("/projects/indexed");
    return Array.isArray(data) ? data : [];
  }

  async search(opts: SearchOptions): Promise<SearchResult> {
    const params: Record<string, unknown> = {
      [opts.type]: opts.query,
      start: opts.start ?? 0,
      sort: opts.sort ?? "relevancy",
      maxresults: opts.maxresults ?? config.defaultMaxResults,
    };
    if (opts.projects?.length) params.projects = opts.projects.join(",");
    if (opts.maxhitsperfile) params.maxhitsperfile = opts.maxhitsperfile;
    if (opts.path) params.path = opts.path;

    // OpenGrok /search 返回结构各家差异较大，我们只取结果数组。
    const data = (await this.get("/search", params)) as unknown;
    return normaliseSearchResult(data);
  }

  async getFileContent(path: string): Promise<string> {
    return this.get<string>("/file/content", { path });
  }

  async getFileDefinitions(path: string): Promise<Definition[]> {
    const data = await this.get<Definition[] | { definitions: Definition[] }>(
      "/file/defs",
      { path },
    );
    if (Array.isArray(data)) return data;
    if (data && Array.isArray((data as { definitions: Definition[] }).definitions)) {
      return (data as { definitions: Definition[] }).definitions;
    }
    return [];
  }

  async annotateFile(path: string, revision?: string): Promise<Annotation[]> {
    const data = await this.get<Annotation[] | { annotations: Annotation[] }>(
      "/annotation",
      { path, revision },
    );
    if (Array.isArray(data)) return data;
    if (data && Array.isArray((data as { annotations: Annotation[] }).annotations)) {
      return (data as { annotations: Annotation[] }).annotations;
    }
    return [];
  }

  async getFileHistory(
    path: string,
    opts: { withFiles?: boolean; max?: number; start?: number } = {},
  ): Promise<HistoryEntry[]> {
    const data = await this.get<HistoryEntry[] | { revisions: HistoryEntry[] }>(
      "/history",
      { path, withFiles: opts.withFiles ?? false, max: opts.max ?? 100, start: opts.start ?? 0 },
    );
    if (Array.isArray(data)) return data;
    if (data && Array.isArray((data as { revisions: HistoryEntry[] }).revisions)) {
      return (data as { revisions: HistoryEntry[] }).revisions;
    }
    return [];
  }
}

// ============== 类型定义（与 OpenGrok REST 响应一致） ==============

export interface Project {
  name: string;
  /** 部分 OpenGrok 版本会带 indexed/tags 等字段，这里宽松处理。 */
  [k: string]: unknown;
}

export interface SearchOptions {
  query: string;
  type: "full" | "def" | "symbol" | "path" | "hist";
  projects?: string[];
  start?: number;
  maxresults?: number;
  maxhitsperfile?: number;
  path?: string;
  sort?: "relevancy" | "date" | "path";
}

export interface SearchHit {
  path: string;
  line?: number;
  /** OpenGrok 不同版本字段名差异：line / lineno / lineNumber */
  [k: string]: unknown;
}

export interface SearchResult {
  hits: SearchHit[];
  /** 不同 OpenGrok 版本字段：total / count / numHits */
  total?: number;
  elapsed?: number;
  more: boolean;
  raw: unknown;
}

export interface Definition {
  /** 符号名（OpenGrok 有时叫 symbol、有时叫 name） */
  name?: string;
  symbol?: string;
  line?: number;
  kind?: string;
  [k: string]: unknown;
}

export interface Annotation {
  line: number;
  revision: string;
  author: string;
  date: string;
  message: string;
  [k: string]: unknown;
}

export interface HistoryEntry {
  revision: string;
  author: string;
  date: string;
  message: string;
  files?: string[];
  [k: string]: unknown;
}

// ============== 工具函数 ==============

function normaliseSearchResult(data: unknown): SearchResult {
  // OpenGrok 不同版本字段名差异很大，这里尽量宽松解析。
  if (data == null) return { hits: [], more: false, raw: data };
  if (Array.isArray(data)) {
    return { hits: data as SearchHit[], more: false, raw: data };
  }
  if (typeof data !== "object") {
    return { hits: [], more: false, raw: data };
  }
  const obj = data as Record<string, unknown>;
  const hits =
    (Array.isArray(obj["hits"]) && (obj["hits"] as SearchHit[])) ||
    (Array.isArray(obj["results"]) && (obj["results"] as SearchHit[])) ||
    (Array.isArray(obj["documents"]) &&
      ((obj["documents"] as Array<{ path: string }>).map((d) => ({
        path: d.path,
      })))) ||
    [];
  const total =
    (typeof obj["total"] === "number" && (obj["total"] as number)) ||
    (typeof obj["count"] === "number" && (obj["count"] as number)) ||
    (typeof obj["numHits"] === "number" && (obj["numHits"] as number)) ||
    undefined;
  const elapsed =
    (typeof obj["elapsed"] === "number" && (obj["elapsed"] as number)) ||
    undefined;
  const more =
    typeof obj["more"] === "boolean"
      ? (obj["more"] as boolean)
      : total != null
        ? total > hits.length
        : false;
  return { hits, total, elapsed, more, raw: data };
}

export class OpenGrokHttpError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly body: unknown,
  ) {
    super(message);
    this.name = "OpenGrokHttpError";
  }
}

/** 默认共享实例。 */
export const opengrok = new OpenGrokClient();
