import { useEffect, useState } from "react";
import { useKeyboard, useRenderer } from "@opentui/react";
import { theme } from "./theme.js";
import { StatusBar } from "./components/StatusBar.js";
import { ProjectsScreen } from "./screens/ProjectsScreen.js";
import { SearchScreen } from "./screens/SearchScreen.js";
import { FileScreen } from "./screens/FileScreen.js";
import { BlameScreen } from "./screens/BlameScreen.js";
import { HistoryScreen } from "./screens/HistoryScreen.js";
import { DefinitionsScreen } from "./screens/DefinitionsScreen.js";
import { RepoOpsScreen } from "./screens/RepoOpsScreen.js";
import { HelpScreen } from "./screens/HelpScreen.js";
import { SCREENS, type ScreenId } from "./screen-types.js";
import { authSummary } from "../config.js";
import { opengrok } from "../client/opengrok-client.js";

/**
 * TUI 根组件。
 * - 维护 currentScreen / currentPath 全局状态；
 * - 注册全局数字键 1-7、?、q、Ctrl-C 切换 screen；
 * - 启动时 ping 一次以更新 StatusBar 的连接状态。
 */
export function App() {
  const renderer = useRenderer();
  const [currentScreen, setCurrentScreen] = useState<ScreenId>("projects");
  const [currentPath, setCurrentPath] = useState<string>("");
  const [connected, setConnected] = useState(false);

  // 启动时 ping 一次以决定 StatusBar 颜色
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const ok = await opengrok.ping();
      if (!cancelled) setConnected(ok);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // 全局 keymap：数字键切屏，? 进帮助，q 退出
  useKeyboard((key) => {
    if (key.name === "q") {
      renderer?.destroy();
      process.exit(0);
      return;
    }
    if (key.name === "?" || (key.shift && key.name === "/")) {
      setCurrentScreen("help");
      return;
    }
    // 数字键 1-7 切屏
    if (typeof key.name === "string" && /^[1-7]$/.test(key.name)) {
      const map: Record<string, ScreenId> = {
        "1": "projects",
        "2": "search",
        "3": "file",
        "4": "definitions",
        "5": "blame",
        "6": "history",
        "7": "repo-ops",
      };
      const id = map[key.name];
      if (id) setCurrentScreen(id);
    }
  });

  return (
    <box
      style={{
        flexDirection: "column",
        flexGrow: 1,
        backgroundColor: theme.bg,
      }}
    >
      <StatusBar
        currentScreen={currentScreen}
        screens={SCREENS}
        auth={authSummary()}
        connected={connected}
      />

      <box style={{ flexGrow: 1, flexDirection: "column" }}>
        {renderScreen(currentScreen, {
          navigate: setCurrentScreen,
          connected,
          currentPath,
          setCurrentPath,
        })}
      </box>

      <box
        style={{
          flexDirection: "row",
          height: 1,
          paddingLeft: 1,
          backgroundColor: theme.surface,
        }}
      >
        <text>
          <span fg={theme.textMuted}>
            1-7 切换 · ? 帮助 · q 退出 · 当前路径：
          </span>
          <span fg={theme.accent}>{currentPath || "(未选择)"}</span>
        </text>
      </box>
    </box>
  );
}

function renderScreen(id: ScreenId, props: Parameters<typeof ProjectsScreen>[0]) {
  switch (id) {
    case "projects":
      return <ProjectsScreen {...props} />;
    case "search":
      return <SearchScreen {...props} />;
    case "file":
      return <FileScreen {...props} />;
    case "definitions":
      return <DefinitionsScreen {...props} />;
    case "blame":
      return <BlameScreen {...props} />;
    case "history":
      return <HistoryScreen {...props} />;
    case "repo-ops":
      return <RepoOpsScreen {...props} />;
    case "help":
      return <HelpScreen {...props} />;
    default:
      return null;
  }
}
