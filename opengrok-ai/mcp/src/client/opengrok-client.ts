import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse } from "axios";
import { config } from "../config.js";
import { logger } from "../logger.js";

/**
 * OpenGrok REST 调用的 axios 封装。
 *
 * 主要职责：
 *  - 当配置启用鉴权时，自动注入 `Authorization: Bearer <token>` 请求头。
 *  - 把所有 4xx/5xx 统一抛成 OpenGrokHttpError，让 MCP 工具层能把它
 *    转成模型可读的错误消息而不是直接崩掉传输层。
 *  - 透传 query / body 参数，不做任何业务解析。
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
      // 文件内容接口可能返回较大文本，适度放宽默认 JSON 体积限制。
      maxContentLength: 50 * 1024 * 1024,
    });
  }

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

/** 默认共享实例，多数调用方应直接用它。 */
export const opengrok = new OpenGrokClient();
