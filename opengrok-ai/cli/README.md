# opengrok-cli

OpenGrok 的**交互式终端客户端**（TUI），底层直接调 OpenGrok REST API，
不依赖 opengrok-mcp。配套使用场景：

- 在终端里**交互式**搜索 / 阅读代码 / 看 blame
- 在 CI 或脚本里以 **headless 子命令** 形式调用
- 替代浏览器打开 OpenGrok Web UI 的轻量场景

技术上基于 [OpenTUI](https://opentui.com)（Zig + React 19），
需要 Bun 1.3+ 运行时。

---

## 与 opengrok-mcp 的关系

| | opengrok-mcp | opengrok-cli |
|---|---|---|
| 启动形态 | stdio / SSE / HTTP 子进程 | 终端 TUI 或 headless 命令 |
| 给谁用 | LLM / MCP 客户端 | 人 |
| HTTP 客户端 | axios | axios（**独立一份**，不复用） |
| 写工具开关 | `ENABLE_WRITE_TOOLS` | 由 OpenGrok 服务端权限控制 |
| Skill 指引 | `opengrok-ai/skills/` | 本 README |

**为什么 CLI 不复用 mcp 的客户端代码**：

- CLI 启动时不一定有 opengrok-mcp 进程；
- CLI 的 `search` / `blame` 等方法需要在响应字段不统一时做归一化，
  这是 GUI 专属逻辑；
- 两边独立演进更不容易牵一发动全身。

如果你希望两边共享 client，可以参考 `opengrok-ai/mcp/src/client/opengrok-client.ts`
与 `opengrok-ai/cli/src/client/opengrok-client.ts` 的差异，
自行抽出一个 `opengrok-ai/client/` 公共包。

---

## 环境要求

- [Bun](https://bun.com) **1.3.0+**
- 一个可访问的 OpenGrok 实例（默认 `http://localhost:8081`）

## 安装

```bash
cd opengrok-ai/cli
bun install
cp .env.example .env       # 按需修改
```

## 配置

环境变量与 opengrok-mcp **完全一致**（见 `.env.example`）：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `OPENGROK_BASE_URL` | `http://localhost:8081/api/v1` | OpenGrok REST 根地址 |
| `OPENGROK_AUTH_TYPE` | `none` | `bearer` 启用 Bearer Token 鉴权 |
| `OPENGROK_TOKEN` | _(空)_ | Bearer 令牌；`OPENGROK_AUTH_TYPE=bearer` 时必填 |
| `OPENGROK_PING_ON_START` | `true` | 启动前先 ping 一次，失败立即退出 |
| `OPENGROK_DEFAULT_MAX_RESULTS` | `50` | 搜索单次默认返回条数 |
| `LOG_LEVEL` | `info` | pino 日志级别（写 stderr） |

## 两种启动方式

### 1. TUI 模式（默认 / 交互式）

直接执行：

```bash
bun run src/index.tsx
# 或
bun run dev
```

第一次进入会显示「1 项目」画面，状态条显示 `auth: ...` 和连接状态。

### 2. Headless 模式（脚本化）

```bash
bun run src/index.tsx --headless <command> [...]
```

可用子命令：

| 命令 | 用途 |
|---|---|
| `ping` | 健康检查（输出 `pong`） |
| `version` | 服务端版本 |
| `list-projects` | 列出所有项目 |
| `list-indexed` | 列出已索引项目 |
| `search <query>` | 跨项目搜索 |
| `get-file <path>` | 读取文件原始内容到 stdout |
| `blame <path>` | 按行输出 blame |
| `history <path>` | 文件 SCM 历史 |

通用选项：
- `--json`：以 JSON 输出而不是人类可读文本
- `--help` / `-h`：打印帮助

#### Headless 示例

```bash
# 健康检查
bun run src/index.tsx --headless ping

# 跨项目搜 `OrderService` 的定义
bun run src/index.tsx --headless search OrderService --type def --json

# 限定项目
bun run src/index.tsx --headless search "TODO" --project opengrok-web --project opengrok-indexer

# 读文件
bun run src/index.tsx --headless get-file opengrok-web/src/main/java/.../Foo.java

# Blame
bun run src/index.tsx --headless blame opengrok-web/.../Foo.java --rev HEAD

# 历史
bun run src/index.tsx --headless history opengrok-web/.../Foo.java --with-files --max 20

# 管道 + jq
bun run src/index.tsx --headless search "OrderService" --type def --json | jq '.hits[].path'
```

也可以用 npm scripts 简写：

```bash
bun run search OrderService --type def
bun run get-file opengrok-web/.../Foo.java
bun run blame opengrok-web/.../Foo.java
```

## TUI 画面与快捷键

顶部状态条常驻：

```
[ 1 项目 ][ 2 搜索 ][ 3 阅读 ]...    auth: bearer token=dev-…-123 · ● connected
```

底部状态条显示当前打开的文件路径。

### 8 个画面

| 编号 | 画面 | 作用 | 关键快捷键 |
|:---:|---|---|---|
| 1 | **项目** | 列出所有项目 + 标出 indexed/stale | `↑/↓` 选择、`Enter` 进搜索、`r` 刷新 |
| 2 | **搜索** | 跨项目搜索（full/def/symbol/path/hist） | `Tab` 切类型、自动搜索、回车看文件 |
| 3 | **阅读** | 读文件内容，带行号 | `d` 符号表、`b` blame、`h` 历史 |
| 4 | **符号** | 列出文件内符号定义 | `↑/↓` 选择、`Enter` 跳到行 |
| 5 | **Blame** | 按行展示 commit / author / date | `f` 看文件、`h` 历史 |
| 6 | **历史** | 文件 SCM 修订列表 | `i` 切「改动文件」、`f` 看文件 |
| 7 | **运维** | rebuild / 广播 / reload auth | `r` 刷新、`x` rebuild、`a` 广播、`l` reload |
| ? | **帮助** | 列出全部快捷键 | — |

### 全局键

- `1`-`7`：切换对应画面
- `?`：进帮助画面
- `q` / `Ctrl-C`：退出
- `↑/↓` 或 `j/k`：列表选择 / 滚动
- `Enter`：选中 / 跳转

### 搜索结果内快捷跳转

- `Enter`：阅读当前选中文件（跳到画面 3）
- `d`：查看选中文件的符号定义（跳到画面 4）
- `b`：查看选中文件的 blame（跳到画面 5）

## 颜色与样式

主题：Tokyo Night 暗色变体，集中定义在 `src/tui/theme.ts`。

```typescript
{
  bg: '#1a1b26',
  surface: '#16161e',
  border: '#2f334d',
  text: '#c0caf5',
  textDim: '#a9b1d6',
  accent: '#7aa2f7',
  success: '#9ece6a',
  warning: '#e0af68',
  danger: '#f7768e',
}
```

需要换主题直接改 `theme.ts` 即可。

## 故障排查

| 现象 | 可能原因 | 解决 |
|---|---|---|
| `✗ 无法连接 OpenGrok` | URL / Token 错、网络不通 | 改 `.env` 后重启 |
| TUI 启动后只看到 `○ offline` | `OPENGROK_PING_ON_START=false` 或 token 失效 | 设 `OPENGROK_PING_ON_START=true` 或换 token |
| `bun` 命令找不到 | 未装 Bun | `curl -fsSL https://bun.sh/install \| bash` |
| 中文显示成方块 | 终端字体不支持 | 换支持 CJK 的字体（如 Cica、Nerd Fonts） |
| 文件超大被截断 | `>5000 行` 触发保护 | 用 headless `get-file` 导出完整文件 |
| rebuild / 广播返回 401 / 403 | OpenGrok 服务端无权限 | 联系 OpenGrok 管理员 |

## 开发

```bash
bun run dev              # TUI 开发
bun run dev:headless     # headless 测试
bun run typecheck        # tsc --noEmit
```

代码组织：

```
cli/
├── src/
│   ├── index.tsx                 # 入口（argv 路由）
│   ├── config.ts                 # 环境变量
│   ├── logger.ts                 # pino → stderr
│   ├── client/
│   │   └── opengrok-client.ts    # axios + Bearer + 业务便捷方法
│   ├── headless/
│   │   └── commands.ts           # 7 个子命令实现
│   └── tui/
│       ├── App.tsx               # 根组件 + 屏幕路由
│       ├── theme.ts              # 颜色常量
│       ├── screen-types.ts       # 屏幕标识 + 共享 props
│       ├── components/
│       │   ├── StatusBar.tsx     # 顶部状态条
│       │   ├── HelpHint.tsx      # 快捷键提示
│       │   └── Loading.tsx       # 加载态
│       └── screens/              # 8 个画面
│           ├── ProjectsScreen.tsx
│           ├── SearchScreen.tsx
│           ├── FileScreen.tsx
│           ├── DefinitionsScreen.tsx
│           ├── BlameScreen.tsx
│           ├── HistoryScreen.tsx
│           ├── RepoOpsScreen.tsx
│           └── HelpScreen.tsx
```

## License

MIT
