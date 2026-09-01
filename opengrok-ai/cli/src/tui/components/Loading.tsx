import { theme } from "../theme.js";

export interface LoadingProps {
  message?: string;
}

/**
 * 加载态：简单的旋转字符动画 + 文案。
 */
export function Loading({ message = "加载中…" }: LoadingProps) {
  return (
    <box style={{ paddingLeft: 1 }}>
      <text>
        <span fg={theme.accent}>⏳</span>
        <span fg={theme.textDim}> {message}</span>
      </text>
    </box>
  );
}
