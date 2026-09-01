import "dotenv/config";

/**
 * 统一配置中心：所有环境变量都在这里读取，业务代码不要直接访问 process.env。
 *
 * 配置项会从进程环境（.env 也会被 dotenv 加载）解析，并对每个字段做
 * 必要的默认值、类型转换与范围校验。
 */
export type AuthType = "none" | "bearer";

export interface AppConfig {
  /** OpenGrok REST 根地址，例如 http://localhost:8081/api/v1 */
  baseUrl: string;

  /** Bearer Token 鉴权，对应服务端用
   *  `Authorization: Bearer <token>` 验证请求的部署形态。 */
  auth: {
    type: AuthType;
    token?: string;
    enabled: boolean;
  };

  /** HTTP 传输层绑定的网络选项。 */
  http: {
    host: string;
    port: number;
  };

  /** 写工具（破坏性）总开关；为 false 时所有写工具都不会被注册。 */
  writeToolsEnabled: boolean;

  /** pino 日志级别。 */
  logLevel: "fatal" | "error" | "warn" | "info" | "debug" | "trace";

  /** 单次 OpenGrok REST 请求的超时时间（毫秒）。 */
  requestTimeoutMs: number;
}

function parseBool(value: string | undefined, fallback: boolean): boolean {
  if (value === undefined || value === "") return fallback;
  return value.toLowerCase() === "true" || value === "1";
}

function parseLogLevel(value: string | undefined): AppConfig["logLevel"] {
  const allowed = ["fatal", "error", "warn", "info", "debug", "trace"] as const;
  const v = (value ?? "info").toLowerCase();
  return (allowed as readonly string[]).includes(v)
    ? (v as AppConfig["logLevel"])
    : "info";
}

function parseAuthType(value: string | undefined): AuthType {
  const v = (value ?? "none").toLowerCase();
  return v === "bearer" ? "bearer" : "none";
}

const token = process.env.OPENGROK_TOKEN?.trim();
const authType = parseAuthType(process.env.OPENGROK_AUTH_TYPE);

export const config: AppConfig = {
  baseUrl: (process.env.OPENGROK_BASE_URL ?? "http://localhost:8081/api/v1")
    .replace(/\/+$/, ""),

  auth: {
    type: authType,
    token: token || undefined,
    enabled: authType === "bearer" && Boolean(token),
  },

  http: {
    host: process.env.MCP_HTTP_HOST ?? "127.0.0.1",
    port: Number(process.env.MCP_HTTP_PORT ?? 3001),
  },

  writeToolsEnabled: parseBool(process.env.ENABLE_WRITE_TOOLS, false),

  logLevel: parseLogLevel(process.env.LOG_LEVEL),

  requestTimeoutMs: Number(process.env.REQUEST_TIMEOUT_MS ?? 30000),
};

/**
 * 返回当前鉴权配置的脱敏摘要字符串，可直接打到启动日志中。
 * 只展示 token 的首尾各 4 位，绝不会泄露完整密钥。
 */
export function authSummary(): string {
  if (!config.auth.enabled || !config.auth.token) return "none";
  const t = config.auth.token;
  if (t.length <= 12) return `bearer token=${t}`;
  return `bearer token=${t.slice(0, 4)}…${t.slice(-4)} (len=${t.length})`;
}
