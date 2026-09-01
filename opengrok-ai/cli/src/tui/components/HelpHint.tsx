import { theme } from "../theme.js";

export interface HelpHintProps {
  hints: { key: string; label: string }[];
}

/**
 * 顶部第二行的快捷键提示（紧贴 StatusBar 下方）。
 * 用灰色文字，避免抢主区域视觉焦点。
 */
export function HelpHint({ hints }: HelpHintProps) {
  return (
    <box
      style={{
        flexDirection: "row",
        paddingLeft: 1,
        paddingRight: 1,
        height: 1,
      }}
    >
      <text>
        {hints.map((h, i) => (
          <span fg={theme.textMuted}>
            {i > 0 ? " · " : ""}
            <span fg={theme.accent}>{h.key}</span>
            <span fg={theme.textMuted}> {h.label}</span>
          </span>
        ))}
      </text>
    </box>
  );
}
