import { useEffect, useState } from "react";
import { useKeyboard } from "@opentui/react";
import { theme } from "../theme.js";
import { HelpHint } from "../components/HelpHint.js";
import { Loading } from "../components/Loading.js";
import type { ScreenProps } from "../screen-types.js";
import { opengrok, OpenGrokHttpError } from "../../client/opengrok-client.js";

/**
 * 项目列表 screen：
 *  - 启动时调 listProjects + listIndexedProjects
 *  - 用 useState 缓存两份列表
 *  - 上下键选中项目，回车跳到 SearchScreen 并预填 project 过滤
 *
 * 注意：本 Screen 只展示「读」结果，不做任何写操作。
 */
export function ProjectsScreen(props: ScreenProps) {
  const [projects, setProjects] = useState<string[]>([]);
  const [indexed, setIndexed] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState(0);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        setLoading(true);
        const [all, idx] = await Promise.all([
          opengrok.listProjects(),
          opengrok.listIndexedProjects().catch(() => []),
        ]);
        if (cancelled) return;
        setProjects(all.map((p) => p.name));
        setIndexed(new Set(idx.map((p) => p.name)));
        setError(null);
      } catch (err) {
        if (cancelled) return;
        setError(
          err instanceof OpenGrokHttpError
            ? `HTTP ${err.status}: ${err.message}`
            : (err as Error).message,
        );
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useKeyboard((key) => {
    if (loading) return;
    if (key.name === "up" || key.name === "k") {
      setSelected((s) => Math.max(0, s - 1));
    } else if (key.name === "down" || key.name === "j") {
      setSelected((s) => Math.min(projects.length - 1, s + 1));
    } else if (key.name === "return" || key.name === "enter") {
      // 回车：跳到搜索 screen（不做「写操作」之外的副作用）
      props.navigate("search");
    } else if (key.name === "r") {
      // r：刷新
      setLoading(true);
      opengrok
        .listProjects()
        .then((all) => setProjects(all.map((p) => p.name)))
        .catch((err) => setError((err as Error).message))
        .finally(() => setLoading(false));
    }
  });

  return (
    <box style={{ flexDirection: "column", flexGrow: 1 }}>
      <HelpHint
        hints={[
          { key: "↑/↓", label: "选择" },
          { key: "Enter", label: "进搜索" },
          { key: "r", label: "刷新" },
        ]}
      />

      <box style={{ flexDirection: "column", paddingLeft: 1, paddingRight: 1 }}>
        <text>
          <span fg={theme.accent}>项目列表（共 {projects.length} 个）</span>
        </text>
      </box>

      {loading ? (
        <Loading message="拉取项目列表…" />
      ) : error ? (
        <box style={{ paddingLeft: 1 }}>
          <text>
            <span fg={theme.danger}>✗ 错误：{error}</span>
          </text>
          <text>
            <span fg={theme.textMuted}>
              检查 OPENGROK_BASE_URL 与 OPENGROK_TOKEN 是否正确
            </span>
          </text>
        </box>
      ) : (
        <scrollbox style={{ rootOptions: { flexGrow: 1 }, paddingLeft: 1, paddingRight: 1 }}>
          {projects.map((name, i) => {
            const isSel = i === selected;
            const isIndexed = indexed.has(name);
            return (
              <box style={{ flexDirection: "row" }}>
                <text>
                  <span fg={isSel ? theme.accent : theme.textMuted}>
                    {isSel ? "▶ " : "  "}
                  </span>
                  <span fg={isSel ? theme.text : theme.textDim}>{name}</span>
                  <span fg={theme.textMuted}>  </span>
                  <span fg={isIndexed ? theme.success : theme.textMuted}>
                    {isIndexed ? "● indexed" : "○ stale"}
                  </span>
                </text>
              </box>
            );
          })}
        </scrollbox>
      )}
    </box>
  );
}
