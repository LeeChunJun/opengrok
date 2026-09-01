import { useEffect, useState } from "react";
import { useKeyboard } from "@opentui/react";
import { theme } from "../theme.js";
import { HelpHint } from "../components/HelpHint.js";
import { Loading } from "../components/Loading.js";
import type { ScreenProps } from "../screen-types.js";
import { opengrok, OpenGrokHttpError } from "../../client/opengrok-client.js";

/**
 * 文件阅读 screen：
 *  - 通过 currentPath 拿到当前打开的文件
 *  - 用 <scrollbox> 渲染文件内容，左侧行号
 *  - 大文件截断保护：最多渲染 5000 行
 */
export function FileScreen(props: ScreenProps) {
  const [content, setContent] = useState<string>("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!props.currentPath) return;
    let cancelled = false;
    (async () => {
      try {
        setLoading(true);
        setError(null);
        const text = await opengrok.getFileContent(props.currentPath!);
        if (!cancelled) setContent(text);
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
    if (key.name === "d" && props.currentPath) {
      props.setCurrentPath(props.currentPath);
      props.navigate("definitions");
    } else if (key.name === "b" && props.currentPath) {
      props.setCurrentPath(props.currentPath);
      props.navigate("blame");
    } else if (key.name === "h" && props.currentPath) {
      props.setCurrentPath(props.currentPath);
      props.navigate("history");
    }
  });

  const lines = content.split(/\r?\n/);
  const truncated = lines.length > 5000;
  const visible = truncated ? lines.slice(0, 5000) : lines;

  return (
    <box style={{ flexDirection: "column", flexGrow: 1 }}>
      <HelpHint
        hints={[
          { key: "↑/↓", label: "滚动" },
          { key: "d", label: "符号" },
          { key: "b", label: "Blame" },
          { key: "h", label: "历史" },
        ]}
      />

      <box style={{ paddingLeft: 1, paddingRight: 1 }}>
        <text>
          <span fg={theme.accent}>文件 </span>
          <span fg={theme.text}>
            {props.currentPath ?? "(未选择 — 先到搜索 screen 选一条结果)"}
          </span>
        </text>
      </box>

      {loading ? (
        <Loading message={`读取 ${props.currentPath}…`} />
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
              请到「2 搜索」输入关键词，回车跳回这里阅读文件
            </span>
          </text>
        </box>
      ) : (
        <>
          <box style={{ paddingLeft: 1 }}>
            <text>
              <span fg={theme.textMuted}>
                共 {lines.length} 行{truncated ? "（已截断到 5000 行）" : ""}
              </span>
            </text>
          </box>
          <scrollbox
            style={{
              rootOptions: { flexGrow: 1 },
              paddingLeft: 1,
              paddingRight: 1,
            }}
          >
            {visible.map((line, i) => (
              <box style={{ flexDirection: "row" }}>
                <text>
                  <span fg={theme.lineNo}>{`${(i + 1).toString().padStart(4, " ")}  `}</span>
                  <span fg={theme.text}>{line || " "}</span>
                </text>
              </box>
            ))}
            {truncated ? (
              <text>
                <span fg={theme.warning}>
                  ⚠ 已截断。请用 headless 模式：opengrok-cli get-file {props.currentPath} &gt; out.txt
                </span>
              </text>
            ) : null}
          </scrollbox>
        </>
      )}
    </box>
  );
}
