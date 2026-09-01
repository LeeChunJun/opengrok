import { useEffect, useState } from "react";
import { useKeyboard } from "@opentui/react";
import { theme } from "../theme.js";
import { HelpHint } from "../components/HelpHint.js";
import { Loading } from "../components/Loading.js";
import type { ScreenProps } from "../screen-types.js";
import {
  opengrok,
  OpenGrokHttpError,
  type SearchHit,
  type SearchResult,
} from "../../client/opengrok-client.js";

type SearchType = "full" | "def" | "symbol" | "path" | "hist";

/**
 * 搜索 screen：
 *  - 类型：full / def / symbol / path / hist（按 Tab 切换）
 *  - 输入框：直接用 opentui 的 <input>
 *  - 结果：可滚动列表，回车跳到 file screen 看该文件
 */
export function SearchScreen(_props: ScreenProps) {
  const [type, setType] = useState<SearchType>("full");
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState(0);

  useKeyboard((key) => {
    if (key.name === "tab") {
      // Tab 切换搜索类型
      const types: SearchType[] = ["full", "def", "symbol", "path", "hist"];
      const idx = types.indexOf(type);
      setType(types[(idx + 1) % types.length]);
    } else if (key.name === "up" || key.name === "k") {
      setSelected((s) => Math.max(0, s - 1));
    } else if (key.name === "down" || key.name === "j") {
      if (results) setSelected((s) => Math.min(results.hits.length - 1, s + 1));
    } else if (key.name === "return" || key.name === "enter") {
      // 进 file screen 看当前选中项的文件
      if (results && results.hits[selected]) {
        _props.setCurrentPath(results.hits[selected].path);
        _props.navigate("file");
      }
    } else if (key.name === "d") {
      // d：跳到 definitions screen（先用当前选中文件）
      if (results && results.hits[selected]) {
        _props.setCurrentPath(results.hits[selected].path);
        _props.navigate("definitions");
      }
    } else if (key.name === "b") {
      // b：跳到 blame screen
      if (results && results.hits[selected]) {
        _props.setCurrentPath(results.hits[selected].path);
        _props.navigate("blame");
      }
    }
  });

  // query 变化时自动搜索（300ms 防抖）
  useEffect(() => {
    if (!query.trim()) {
      setResults(null);
      return;
    }
    const timer = setTimeout(async () => {
      try {
        setLoading(true);
        setError(null);
        const r = await opengrok.search({ query, type });
        setResults(r);
        setSelected(0);
      } catch (err) {
        setError(
          err instanceof OpenGrokHttpError
            ? `HTTP ${err.status}: ${err.message}`
            : (err as Error).message,
        );
      } finally {
        setLoading(false);
      }
    }, 300);
    return () => clearTimeout(timer);
  }, [query, type]);

  return (
    <box style={{ flexDirection: "column", flexGrow: 1 }}>
      <HelpHint
        hints={[
          { key: "Tab", label: "切类型" },
          { key: "↑/↓", label: "选结果" },
          { key: "Enter", label: "阅读" },
          { key: "d", label: "符号" },
          { key: "b", label: "Blame" },
        ]}
      />

      <box
        style={{
          flexDirection: "row",
          paddingLeft: 1,
          paddingRight: 1,
          border: true,
          borderColor: theme.border,
        }}
      >
        <text>
          <span fg={theme.accent}>搜索 </span>
          <span fg={theme.textMuted}>[</span>
          <span fg={theme.warning}>{type}</span>
          <span fg={theme.textMuted}>]</span>
        </text>
        <input
          placeholder="输入关键词后回车…"
          onInput={setQuery}
          style={{ flexGrow: 1, focusedBackgroundColor: theme.surfaceFocus }}
        />
      </box>

      {error ? (
        <box style={{ paddingLeft: 1 }}>
          <text>
            <span fg={theme.danger}>✗ {error}</span>
          </text>
        </box>
      ) : loading ? (
        <Loading message={`搜索 [${type}] "${query}"…`} />
      ) : results ? (
        <box style={{ flexDirection: "column", paddingLeft: 1, paddingRight: 1 }}>
          <text>
            <span fg={theme.textMuted}>
              {results.total != null
                ? `共 ${results.total} 条，显示 ${results.hits.length}`
                : `显示 ${results.hits.length} 条`}
              {results.elapsed != null ? ` · ${results.elapsed}ms` : ""}
            </span>
          </text>
        </box>
      ) : null}

      <scrollbox style={{ rootOptions: { flexGrow: 1 }, paddingLeft: 1, paddingRight: 1 }}>
        {(results?.hits ?? []).map((hit: SearchHit, i: number) => (
          <HitRow hit={hit} selected={i === selected} />
        ))}
      </scrollbox>
    </box>
  );
}

function HitRow({ hit, selected }: { hit: SearchHit; selected: boolean }) {
  const path = String(hit.path ?? "(unknown)");
  const line = hit.line ?? hit.lineno ?? hit.lineNumber;
  const lineStr = line != null ? `:${line}` : "";
  return (
    <box style={{ flexDirection: "row" }}>
      <text>
        <span fg={selected ? theme.accent : theme.textMuted}>
          {selected ? "▶ " : "  "}
        </span>
        <span fg={selected ? theme.text : theme.textDim}>{path}</span>
        {lineStr ? (
          <span fg={theme.accentStrong}>{lineStr}</span>
        ) : null}
      </text>
    </box>
  );
}
