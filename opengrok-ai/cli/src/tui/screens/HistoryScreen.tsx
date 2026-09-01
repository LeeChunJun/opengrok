import { useEffect, useState } from "react";
import { useKeyboard } from "@opentui/react";
import { theme } from "../theme.js";
import { HelpHint } from "../components/HelpHint.js";
import { Loading } from "../components/Loading.js";
import type { ScreenProps } from "../screen-types.js";
import { opengrok, OpenGrokHttpError, type HistoryEntry } from "../../client/opengrok-client.js";

/**
 * History screen：列出文件的 SCM 历史修订。
 * 用 i 键切换 withFiles 显示改动的文件列表。
 */
export function HistoryScreen(props: ScreenProps) {
  const [entries, setEntries] = useState<HistoryEntry[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [withFiles, setWithFiles] = useState(true);

  useEffect(() => {
    if (!props.currentPath) return;
    let cancelled = false;
    (async () => {
      try {
        setLoading(true);
        setError(null);
        const data = await opengrok.getFileHistory(props.currentPath!, {
          withFiles,
          max: 100,
        });
        if (!cancelled) setEntries(data);
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
  }, [props.currentPath, withFiles]);

  useKeyboard((key) => {
    if (key.name === "i") setWithFiles((v) => !v);
    else if (key.name === "f" && props.currentPath) {
      props.navigate("file");
    }
  });

  return (
    <box style={{ flexDirection: "column", flexGrow: 1 }}>
      <HelpHint
        hints={[
          { key: "i", label: withFiles ? "隐藏改文件" : "显示改文件" },
          { key: "f", label: "看文件" },
        ]}
      />

      <box style={{ paddingLeft: 1 }}>
        <text>
          <span fg={theme.accent}>History </span>
          <span fg={theme.text}>
            {props.currentPath ?? "(未选择 — 先到搜索 screen 选一条结果)"}
          </span>
        </text>
      </box>

      {loading ? (
        <Loading message={`History ${props.currentPath}…`} />
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
        <scrollbox style={{ rootOptions: { flexGrow: 1 }, paddingLeft: 1, paddingRight: 1 }}>
          {entries.map((e) => (
            <box style={{ flexDirection: "column", marginBottom: 1 }}>
              <text>
                <span fg={theme.accent}>
                  {(e.revision ?? "").toString().slice(0, 10).padEnd(10, " ")}
                </span>
                <span fg={theme.textMuted}> </span>
                <span fg={theme.text}>
                  {(e.date ?? "").toString().slice(0, 19)}
                </span>
                <span fg={theme.textMuted}> · </span>
                <span fg={theme.warning}>
                  {(e.author ?? "").toString().slice(0, 16)}
                </span>
              </text>
              <text>
                <span fg={theme.textDim}>{"  "}{e.message ?? ""}</span>
              </text>
              {withFiles && e.files?.length ? (
                <box style={{ paddingLeft: 4 }}>
                  <text>
                    <span fg={theme.textMuted}>
                      改动文件 ({e.files.length})：
                    </span>
                  </text>
                  {e.files.slice(0, 10).map((f) => (
                    <text>
                      <span fg={theme.textMuted}>  · </span>
                      <span fg={theme.text}>{f}</span>
                    </text>
                  ))}
                  {e.files.length > 10 ? (
                    <text>
                      <span fg={theme.textMuted}>  · 还有 {e.files.length - 10} 个…</span>
                    </text>
                  ) : null}
                </box>
              ) : null}
            </box>
          ))}
        </scrollbox>
      )}
    </box>
  );
}
