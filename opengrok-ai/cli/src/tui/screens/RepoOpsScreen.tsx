import { useEffect, useState } from "react";
import { useKeyboard } from "@opentui/react";
import { theme } from "../theme.js";
import { HelpHint } from "../components/HelpHint.js";
import { Loading } from "../components/Loading.js";
import type { ScreenProps } from "../screen-types.js";
import { opengrok, OpenGrokHttpError } from "../../client/opengrok-client.js";

/**
 * 运维 screen：
 *  - 显示 OpenGrok 版本、索引时间、ping 状态
 *  - 提供「rebuild suggester」「add message」「reload auth」三个动作
 *  - 写操作通过 opengrok.post/put 直接调用 REST，
 *    后续若要让 MCP 一致，可改用「与 opengrok-mcp 同样的 URL+method」
 *
 * 注意：本 Screen 不依赖 ENABLE_WRITE_TOOLS（CLI 直接 REST 调），
 * 受 OpenGrok 服务端权限控制。失败时把 HTTP 状态码显示给用户。
 */
type Op = "none" | "version" | "ping" | "rebuild" | "add-msg" | "reload-auth";

export function RepoOpsScreen(_props: ScreenProps) {
  const [version, setVersion] = useState<string>("");
  const [ping, setPing] = useState<boolean | null>(null);
  const [busy, setBusy] = useState<Op>("none");
  const [result, setResult] = useState<string>("");
  const [isErr, setIsErr] = useState(false);

  async function refresh() {
    try {
      setBusy("version");
      const v = await opengrok.getVersion();
      setVersion(v.replace(/\n$/, ""));
    } catch (err) {
      setResult((err as Error).message);
      setIsErr(true);
    } finally {
      setBusy("none");
    }
    try {
      setBusy("ping");
      const ok = await opengrok.ping();
      setPing(ok);
    } catch {
      setPing(false);
    } finally {
      setBusy("none");
    }
  }

  useEffect(() => {
    refresh();
  }, []);

  useKeyboard((key) => {
    if (busy !== "none") return;
    if (key.name === "r") {
      refresh();
    } else if (key.name === "x") {
      runOp("rebuild", () => opengrok.put("/suggest/rebuild"));
    } else if (key.name === "a") {
      const text = `cli-broadcast ${new Date().toISOString()}`;
      runOp("add-msg", () =>
        opengrok.post("/messages", {
          tag: "cli-info",
          text,
          createdAt: new Date().toISOString(),
        }),
      );
    } else if (key.name === "l") {
      runOp("reload-auth", () =>
        opengrok.post("/configuration/authorization/reload"),
      );
    }
  });

  async function runOp(op: Op, fn: () => Promise<unknown>) {
    try {
      setBusy(op);
      setResult("");
      setIsErr(false);
      const r = await fn();
      setResult(JSON.stringify(r, null, 2));
    } catch (err) {
      setIsErr(true);
      setResult(
        err instanceof OpenGrokHttpError
          ? `HTTP ${err.status}: ${JSON.stringify(err.body)}`
          : (err as Error).message,
      );
    } finally {
      setBusy("none");
    }
  }

  return (
    <box style={{ flexDirection: "column", flexGrow: 1 }}>
      <HelpHint
        hints={[
          { key: "r", label: "刷新状态" },
          { key: "x", label: "rebuild suggester" },
          { key: "a", label: "广播消息" },
          { key: "l", label: "reload auth" },
        ]}
      />

      <box style={{ paddingLeft: 1 }}>
        <text>
          <span fg={theme.accent}>运维面板</span>
          <span fg={theme.textMuted}>（写操作直接调 REST，受服务端权限控制）</span>
        </text>
      </box>

      <box style={{ paddingLeft: 1, flexDirection: "column" }}>
        <text>
          <span fg={theme.textMuted}>版本 </span>
          <span fg={theme.text}>{version || "（未获取）"}</span>
        </text>
        <text>
          <span fg={theme.textMuted}>Ping  </span>
          <span fg={ping == null ? theme.textMuted : ping ? theme.success : theme.danger}>
            {ping == null ? "（未获取）" : ping ? "● ok" : "✗ fail"}
          </span>
        </text>
      </box>

      {busy !== "none" ? (
        <Loading message={`执行 ${busy}…`} />
      ) : null}

      {result ? (
        <scrollbox style={{ rootOptions: { flexGrow: 1 }, paddingLeft: 1, paddingRight: 1 }}>
          <text>
            <span fg={isErr ? theme.danger : theme.success}>
              {isErr ? "✗ 失败：" : "✓ 成功："}
            </span>
            <span fg={theme.text}>{result}</span>
          </text>
        </scrollbox>
      ) : (
        <box style={{ paddingLeft: 1 }}>
          <text>
            <span fg={theme.textMuted}>
              提示：r 刷新、x 重建索引、a 广播消息、l 重载 auth。失败会显示 HTTP 状态码。
            </span>
          </text>
        </box>
      )}
    </box>
  );
}
