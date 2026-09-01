import { useEffect, useState } from "react";
import { useKeyboard } from "@opentui/react";
import { theme } from "../theme.js";
import { HelpHint } from "../components/HelpHint.js";
import { Loading } from "../components/Loading.js";
import type { ScreenProps } from "../screen-types.js";
import { opengrok, OpenGrokHttpError, type Definition } from "../../client/opengrok-client.js";

/**
 * Definitions screen：列出文件的符号定义（函数 / 类 / 变量）。
 * 按 Enter 跳到 file screen 并高亮该行（暂用 setCurrentPath）。
 */
export function DefinitionsScreen(props: ScreenProps) {
  const [defs, setDefs] = useState<Definition[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState(0);

  useEffect(() => {
    if (!props.currentPath) return;
    let cancelled = false;
    (async () => {
      try {
        setLoading(true);
        setError(null);
        const data = await opengrok.getFileDefinitions(props.currentPath!);
        if (!cancelled) {
          setDefs(data);
          setSelected(0);
        }
      } catch (err) {
        if (!cancelled) {
          setError(
            err instanceof OpenGrokHttpError
              ? `HTTP ${err.status}: ${err.message}`
              : (err as Error).message,
          );
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [props.currentPath]);

  useKeyboard((key) => {
    if (key.name === "up" || key.name === "k") {
      setSelected((s) => Math.max(0, s - 1));
    } else if (key.name === "down" || key.name === "j") {
      setSelected((s) => Math.min(defs.length - 1, s + 1));
    } else if (key.name === "return" || key.name === "enter") {
      props.navigate("file");
    } else if (key.name === "f") {
      props.navigate("file");
    }
  });

  return (
    <box style={{ flexDirection: "column", flexGrow: 1 }}>
      <HelpHint
        hints={[
          { key: "↑/↓", label: "选择" },
          { key: "Enter / f", label: "跳文件" },
        ]}
      />

      <box style={{ paddingLeft: 1 }}>
        <text>
          <span fg={theme.accent}>符号 </span>
          <span fg={theme.text}>
            {props.currentPath ?? "(未选择 — 先到搜索 screen 选一条结果)"}
          </span>
        </text>
      </box>

      {loading ? (
        <Loading message={`解析 ${props.currentPath}…`} />
      ) : error ? (
        <box style={{ paddingLeft: 1 }}>
          <text>
            <span fg={theme.danger}>✗ {error}</span>
          </text>
        </box>
      ) : !props.currentPath ? (
        <box style={{ paddingLeft: 1 }}>
          <text>
            <span fg={theme.textMuted}>
              先到「2 搜索」选一条结果，再按 d 进入符号表
            </span>
          </text>
        </box>
      ) : (
        <>
          <box style={{ paddingLeft: 1 }}>
            <text>
              <span fg={theme.textMuted}>共 {defs.length} 个符号</span>
            </text>
          </box>
          <scrollbox style={{ rootOptions: { flexGrow: 1 }, paddingLeft: 1, paddingRight: 1 }}>
            {defs.map((d, i) => {
              const name = String(d.name ?? d.symbol ?? "(?)");
              const kind = String(d.kind ?? "").padEnd(10, " ");
              const line = d.line ?? 0;
              const isSel = i === selected;
              return (
                <box style={{ flexDirection: "row" }}>
                  <text>
                    <span fg={isSel ? theme.accent : theme.textMuted}>
                      {isSel ? "▶ " : "  "}
                    </span>
                    <span fg={theme.warning}>{kind}</span>
                    <span fg={isSel ? theme.text : theme.textDim}>{name}</span>
                    <span fg={theme.textMuted}>  </span>
                    <span fg={theme.accentStrong}>L{line}</span>
                  </text>
                </box>
              );
            })}
          </scrollbox>
        </>
      )}
    </box>
  );
}
