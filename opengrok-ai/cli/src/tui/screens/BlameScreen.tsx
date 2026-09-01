import { useEffect, useState } from "react";
import { useKeyboard } from "@opentui/react";
import { theme } from "../theme.js";
import { HelpHint } from "../components/HelpHint.js";
import { Loading } from "../components/Loading.js";
import type { ScreenProps } from "../screen-types.js";
import { opengrok, OpenGrokHttpError, type Annotation } from "../../client/opengrok-client.js";

/**
 * Blame screen：调用 /annotation，按行展示 commit / author / date。
 *
 * 同时加载 /file/content 做并排展示：左侧 blame，右侧代码。
 */
export function BlameScreen(props: ScreenProps) {
  const [annotations, setAnnotations] = useState<Annotation[]>([]);
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
        const [a, c] = await Promise.all([
          opengrok.annotateFile(props.currentPath!),
          opengrok.getFileContent(props.currentPath!),
        ]);
        if (!cancelled) {
          setAnnotations(a);
          setContent(c);
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
    if (key.name === "f" && props.currentPath) {
      props.setCurrentPath(props.currentPath);
      props.navigate("file");
    } else if (key.name === "h" && props.currentPath) {
      props.setCurrentPath(props.currentPath);
      props.navigate("history");
    }
  });

  const codeLines = content.split(/\r?\n/);
  const max = Math.min(annotations.length, codeLines.length, 5000);

  return (
    <box style={{ flexDirection: "column", flexGrow: 1 }}>
      <HelpHint
        hints={[
          { key: "↑/↓", label: "滚动" },
          { key: "f", label: "看文件" },
          { key: "h", label: "看历史" },
        ]}
      />

      <box style={{ paddingLeft: 1, paddingRight: 1 }}>
        <text>
          <span fg={theme.accent}>Blame </span>
          <span fg={theme.text}>
            {props.currentPath ?? "(未选择 — 先到搜索 screen 选一条结果)"}
          </span>
        </text>
      </box>

      {loading ? (
        <Loading message={`Blame ${props.currentPath}…`} />
      ) : error ? (
        <box style={{ paddingLeft: 1 }}>
          <text>
            <span fg={theme.danger}>✗ {error}</span>
          </text>
        </box>
      ) : !props.currentPath ? (
        <box style={{ paddingLeft: 1 }}>
          <text>
            <span fg={theme.textMuted}>先到「2 搜索」选一条结果，再按 b 进入 Blame</span>
          </text>
        </box>
      ) : (
        <>
          <box style={{ paddingLeft: 1 }}>
            <text>
              <span fg={theme.textMuted}>共 {annotations.length} 行 blame</span>
            </text>
          </box>
          <scrollbox
            style={{ rootOptions: { flexGrow: 1 }, paddingLeft: 1, paddingRight: 1 }}
          >
            {Array.from({ length: max }).map((_, i) => {
              const ann = annotations[i];
              const code = codeLines[i] ?? "";
              return (
                <box style={{ flexDirection: "row" }}>
                  <text>
                    <span fg={theme.accent}>
                      {(ann.revision ?? "").toString().slice(0, 8).padEnd(8, " ")}
                    </span>
                    <span fg={theme.textMuted}> </span>
                    <span fg={theme.warning}>
                      {(ann.author ?? "").toString().slice(0, 12).padEnd(12, " ")}
                    </span>
                    <span fg={theme.textMuted}> </span>
                    <span fg={theme.lineNo}>
                      {(i + 1).toString().padStart(4, " ")}
                    </span>
                    <span fg={theme.textMuted}> │ </span>
                    <span fg={theme.text}>{code || " "}</span>
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
