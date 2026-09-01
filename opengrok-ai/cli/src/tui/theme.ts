/**
 * TUI 主题：所有颜色与样式常量集中在这里，避免散落在各个 Screen。
 *
 * 配色参考 Tokyo Night（暗色优先），但保持中性偏冷以便在大多数终端里可读。
 */

export const theme = {
  // 基础语义色
  bg: "#1a1b26",
  surface: "#16161e",
  surfaceFocus: "#292e42",
  border: "#2f334d",
  borderStrong: "#3b4261",

  // 文本
  text: "#c0caf5",
  textDim: "#a9b1d6",
  textMuted: "#565f89",

  // 强调
  accent: "#7aa2f7",
  accentStrong: "#bb9af7",
  success: "#9ece6a",
  warning: "#e0af68",
  danger: "#f7768e",
  info: "#7dcfff",

  // 行号
  lineNo: "#3b4261",
  lineNoCurrent: "#7aa2f7",
} as const;

export const screenTitle = {
  fg: theme.text,
  attributes: 1 << 0, // bold
} as const;
