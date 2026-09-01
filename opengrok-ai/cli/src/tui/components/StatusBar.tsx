import type { ReactNode } from "react";
import { theme } from "../theme.js";

export interface StatusBarProps {
  /** 当前 screen 名（顶部 tab 高亮） */
  currentScreen: string;
  /** screen 列表，用于 tab 渲染 */
  screens: { id: string; label: string }[];
  /** 鉴权摘要（none / bearer token=xxx…） */
  auth: string;
  /** 是否已连上 OpenGrok */
  connected: boolean;
  /** 自定义右侧状态 */
  right?: ReactNode;
}

/**
 * 顶部状态条：screen tabs + 鉴权摘要 + 连接状态。
 * 每个 screen 都会渲染一份，给用户全局上下文。
 */
export function StatusBar(props: StatusBarProps) {
  return (
    <box
      style={{
        flexDirection: "row",
        paddingLeft: 1,
        paddingRight: 1,
        backgroundColor: theme.surface,
        height: 1,
      }}
    >
      <text>
        {props.screens.map((s, i) => {
          const active = s.id === props.currentScreen;
          const label = i === 0 ? ` ${s.label} ` : ` ${s.label} `;
          return (
            <span fg={active ? theme.bg : theme.textDim}>
              <span bg={active ? theme.accent : theme.surface}>
                <span fg={active ? theme.bg : theme.textDim}>{label}</span>
              </span>
            </span>
          );
        })}
      </text>
      <text style={{ flexGrow: 1 }}> </text>
      <text>
        <span fg={theme.textMuted}>auth: </span>
        <span fg={props.auth === "none" ? theme.warning : theme.success}>
          {props.auth}
        </span>
        <span fg={theme.textMuted}> · </span>
        <span fg={props.connected ? theme.success : theme.danger}>
          {props.connected ? "● connected" : "○ offline"}
        </span>
      </text>
      {props.right}
    </box>
  );
}
