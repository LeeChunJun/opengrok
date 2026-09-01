/**
 * TUI Screen 的标识与共享 props。
 *
 * 每个 Screen 都是一个普通 React 函数组件，接收 ScreenProps，
 * 通过 props.navigate 跳转到其他 Screen。
 */

export type ScreenId =
  | "projects"
  | "search"
  | "file"
  | "blame"
  | "history"
  | "definitions"
  | "repo-ops"
  | "help";

export const SCREENS: { id: ScreenId; label: string }[] = [
  { id: "projects", label: "1 项目" },
  { id: "search", label: "2 搜索" },
  { id: "file", label: "3 阅读" },
  { id: "definitions", label: "4 符号" },
  { id: "blame", label: "5 Blame" },
  { id: "history", label: "6 历史" },
  { id: "repo-ops", label: "7 运维" },
  { id: "help", label: "? 帮助" },
];

export interface ScreenProps {
  /** 跳转到另一个 screen（App.tsx 注册的全局 keymap 也会调它） */
  navigate(id: ScreenId): void;
  /** 当前 OpenGrok 是否已探活 */
  connected: boolean;
  /** 最近一次打开的文件路径（用于 file/blame/history 之间共享上下文） */
  currentPath?: string;
  /** 写入该路径（供 file/blame/history 写入） */
  setCurrentPath(path: string): void;
}
