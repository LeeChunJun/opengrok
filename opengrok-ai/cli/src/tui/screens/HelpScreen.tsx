import { theme } from "../theme.js";
import { SCREENS, type ScreenProps } from "../screen-types.js";

/**
 * 帮助 screen：列出所有 screen 与全局快捷键。
 */
export function HelpScreen(_props: ScreenProps) {
  return (
    <box style={{ flexDirection: "column", flexGrow: 1, paddingLeft: 1, paddingRight: 1 }}>
      <box>
        <text>
          <span fg={theme.accent}>快捷键与画面列表</span>
        </text>
      </box>

      <box style={{ flexDirection: "column", marginTop: 1 }}>
        <text>
          <span fg={theme.warning}>画面切换（数字键）：</span>
        </text>
        {SCREENS.map((s) => (
          <text>
            <span fg={theme.textMuted}>  </span>
            <span fg={theme.accent}>{(s.label.match(/^\d+/) ?? [""])[0]}</span>
            <span fg={theme.textMuted}>  → </span>
            <span fg={theme.text}>{s.label.replace(/^\d+\s*/, "")}</span>
          </text>
        ))}
      </box>

      <box style={{ flexDirection: "column", marginTop: 1 }}>
        <text>
          <span fg={theme.warning}>通用键：</span>
        </text>
        <text>
          <span fg={theme.accent}>? </span>
          <span fg={theme.text}>本帮助</span>
        </text>
        <text>
          <span fg={theme.accent}>1-7 </span>
          <span fg={theme.text}>切换画面</span>
        </text>
        <text>
          <span fg={theme.accent}>↑/↓ / j/k </span>
          <span fg={theme.text}>列表选择 / 滚动</span>
        </text>
        <text>
          <span fg={theme.accent}>Enter </span>
          <span fg={theme.text}>选中 / 跳转</span>
        </text>
        <text>
          <span fg={theme.accent}>Ctrl-C / q </span>
          <span fg={theme.text}>退出</span>
        </text>
      </box>

      <box style={{ flexDirection: "column", marginTop: 1 }}>
        <text>
          <span fg={theme.warning}>搜索结果内快捷跳转：</span>
        </text>
        <text>
          <span fg={theme.accent}>Enter </span>
          <span fg={theme.text}>阅读文件</span>
        </text>
        <text>
          <span fg={theme.accent}>d </span>
          <span fg={theme.text}>查看符号表</span>
        </text>
        <text>
          <span fg={theme.accent}>b </span>
          <span fg={theme.text}>查看 Blame</span>
        </text>
      </box>

      <box style={{ flexDirection: "column", marginTop: 1 }}>
        <text>
          <span fg={theme.warning}>Headless 模式（脚本化）：</span>
        </text>
        <text>
          <span fg={theme.textDim}>  bun run src/index.tsx --headless ping</span>
        </text>
        <text>
          <span fg={theme.textDim}>  bun run src/index.tsx --headless search OrderService --type def</span>
        </text>
        <text>
          <span fg={theme.textDim}>  bun run src/index.tsx --headless get-file path/to/Foo.java</span>
        </text>
        <text>
          <span fg={theme.textDim}>  bun run src/index.tsx --headless blame path/to/Foo.java</span>
        </text>
        <text>
          <span fg={theme.textDim}>  bun run src/index.tsx --headless history path/to/Foo.java</span>
        </text>
      </box>
    </box>
  );
}
