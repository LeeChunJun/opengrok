import "dotenv/config";

/**
 * 统一配置中心：所有环境变量都在这里读取，业务代码不要直接访问 process.env。
 *
 * 与 opengrok-mcp 字段一致，但额外加了：
 *  - OPENGROK_PING_ON_START：CLI 启动时是否先 ping 一次探活
 *  - OPENGROK_DEFAULT_MAX_RESULTS：CLI 默认单次返回条数
 */
export type AuthType = "none" | "bearer";

export interface AppConfig {
  baseUrl: string;
  auth: {
    type: AuthType;
    token?: string;
    enabled: boolean;
  };
  pingOnStart: boolean;
  defaultMaxResults: number;
  logLevel: "fatal" | "error" | "warn" | "info" | "debug" | "trace";
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

  pingOnStart: parseBool(process.env.OPENGROK_PING_ON_START, true),
  defaultMaxResults: Number(process.env.OPENGROK_DEFAULT_MAX_RESULTS ?? 50),

  logLevel: parseLogLevel(process.env.LOG_LEVEL),
  requestTimeoutMs: Number(process.env.REQUEST_TIMEOUT_MS ?? 30000),
};

/**
 * 返回当前鉴权配置的脱敏摘要。token 只露首尾各 4 位。
 */
export function authSummary(): string {
  if (!config.auth.enabled || !config.auth.token) return "none";
  const t = config.auth.token;
  if (t.length <= 12) return `bearer token=${t}`;
  return `bearer token=${t.slice(0, 4)}…${t.slice(-4)} (len=${t.length})`;
}
