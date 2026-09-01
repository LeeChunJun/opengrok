# opengrok-mcp

OpenGrok 的 MCP（Model Context Protocol）服务器 —— 把
[OpenGrok REST API](../opengrok-web/docs/api/application.wadl.xml)
封装成 MCP 工具，让任何兼容 MCP 的客户端（Claude Desktop、Cursor、
Continue、MCP Inspector、自定义 agent）都能搜索和检视已索引的源代码。

* **一个二进制，三种传输**：`stdio`（本地）、`SSE`（旧版 HTTP+SSE）、
  `Streamable HTTP`（MCP 2025-03-26+ 推荐形态）。
* **30 个工具**，覆盖 WADL 中的全部接口：搜索、文件读取、历史、blame、
  自动补全、项目 CRUD、配置管理，等等。
* **写工具总闸门** —— 破坏性操作默认全部关闭，需要时用
  `ENABLE_WRITE_TOOLS=true` 显式开启。
* **Bearer Token 鉴权**，与
  `curl -H "Authorization: Bearer <token>"` 的调用方式完全一致。
* **pino 日志走 stderr**，绝不污染 stdio 上的 JSON-RPC 流。

---

## 环境要求

* Node.js **>= 22**
* 一个可访问的 OpenGrok 服务（HTTP 或 HTTPS）

## 安装

```bash
cd opengrok-ai/mcp
npm install
cp .env.example .env       # 然后按需修改
npm run build
```

## 配置

编辑 `.env`（也可以直接 export 环境变量），完整字段见
[`.env.example`](.env.example)：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `OPENGROK_BASE_URL` | `http://localhost:8081/api/v1` | OpenGrok REST 根地址 |
| `OPENGROK_AUTH_TYPE` | `none` | `bearer` 启用 `Authorization: Bearer` |
| `OPENGROK_TOKEN` | _(空)_ | Bearer 令牌，`OPENGROK_AUTH_TYPE=bearer` 时必填 |
| `ENABLE_WRITE_TOOLS` | `false` | `true` 时注册破坏性写工具 |
| `MCP_HTTP_HOST` | `127.0.0.1` | HTTP 传输的绑定地址 |
| `MCP_HTTP_PORT` | `3001` | HTTP 传输的绑定端口 |
| `LOG_LEVEL` | `info` | pino 日志级别 |
| `REQUEST_TIMEOUT_MS` | `30000` | OpenGrok 请求超时（毫秒） |

### 鉴权说明

服务复刻了你拉 WADL 时所用的
`curl -H "Authorization: Bearer <token>"` 调用方式。启用方式：

```bash
OPENGROK_AUTH_TYPE=bearer
OPENGROK_TOKEN=dev-token-123
```

启动时会在 **stderr** 打印一行脱敏摘要（例如
`bearer token=dev-…-123 (len=13)`），完整 token 永远不会被记录。

如果想在不启动 MCP 客户端的前提下验证鉴权是否生效：

```bash
node dist/index.js fetch-wadl           # stdout 输出 JSON 信封
node dist/index.js fetch-wadl --full    # 同时输出 XML 原文
node dist/index.js fetch-wadl --save application.wadl.xml
```

## 启动方式

**必须**且**只能**指定以下三种传输标志之一：

### 1. stdio（Claude Desktop / Cursor 等本地客户端）

```bash
npm run dev               # tsx watch + stdio
# 或者先 build 再跑：
npm run start             # node dist/index.js --stdio
```

### 2. Streamable HTTP（远程 agent 推荐）

```bash
npm run dev:http          # tsx watch + HTTP，默认 3002 端口
# 或者：
npm run start:http -- --port 3002
```

端点说明：

| 路径 | 用途 |
|---|---|
| `POST/GET /mcp` | MCP JSON-RPC + SSE 流式响应 |
| `GET  /healthz` | 健康检查 |

### 3. SSE（旧版 MCP 客户端兼容）

```bash
npm run dev:sse           # tsx watch + SSE，默认 3001 端口
```

端点说明：

| 路径 | 用途 |
|---|---|
| `GET  /sse` | 客户端打开事件流 |
| `POST /messages?sessionId=<id>` | 客户端向服务端发消息 |
| `GET  /healthz` | 健康检查 |

## 工具清单（30 个）

### 始终可用（只读）

| 工具名 | 对应接口 |
|---|---|
| `search_code` | `GET /search` |
| `get_file_content` | `GET /file/content` |
| `get_file_definitions` | `GET /file/defs` |
| `get_file_genre` | `GET /file/genre` |
| `list_directory` | `GET /list` |
| `get_file_history` | `GET /history` |
| `annotate_file` | `GET /annotation` |
| `get_suggestions` | `GET /suggest` |
| `get_popularity` | `GET /suggest/popularity/{project}` |
| `get_suggester_config` | `GET /suggest/config` |
| `list_projects` | `GET /projects` |
| `list_indexed_projects` | `GET /projects/indexed` |
| `get_project_property` | `GET /projects/{p}/property/{field}` |
| `get_project_index_files` | `GET /projects/{p}/files` |
| `get_project_repositories` | `GET /projects/{p}/repositories` |
| `get_project_repository_type` | `GET /projects/{p}/repositories/type` |
| `list_groups` | `GET /groups` |
| `get_group_pattern` | `GET /groups/{g}/pattern` |
| `get_group_projects` | `GET /groups/{g}/allprojects` |
| `match_project_to_group` | `POST /groups/{g}/match` |
| `get_configuration` | `GET /configuration` |
| `get_configuration_field` | `GET /configuration/{field}` |
| `ping` | `GET /system/ping` |
| `get_system_version` | `GET /system/version` |
| `get_index_time` | `GET /system/indextime` |
| `load_path_descriptions` | `POST /system/pathdesc` |
| `get_repository_property` | `GET /repositories/property/{field}` |
| `get_messages` | `GET /messages` |
| `get_job_status` | `GET /status/{uuid}` |

### 仅当 `ENABLE_WRITE_TOOLS=true` 时启用（破坏性）

| 工具名 | 对应接口 |
|---|---|
| `add_project` | `POST /projects` |
| `delete_project` | `DELETE /projects/{p}` |
| `set_project_property` | `PUT /projects/{p}/property/{field}` |
| `delete_project_data` | `DELETE /projects/{p}/data` |
| `delete_project_annotation_cache` | `DELETE /projects/{p}/annotationcache` |
| `delete_project_history_cache` | `DELETE /projects/{p}/historycache` |
| `mark_project_indexed` | `PUT /projects/{p}/indexed` |
| `set_configuration` | `PUT /configuration` |
| `set_configuration_field` | `PUT /configuration/{field}` |
| `reload_authorization` | `POST /configuration/authorization/reload` |
| `reload_includes` | `PUT /system/includes/reload` |
| `add_message` | `POST /messages` |
| `remove_messages_with_tag` | `DELETE /messages` |
| `delete_job_status` | `DELETE /status/{uuid}` |
| `rebuild_suggester_index` | `PUT /suggest/rebuild[/project]` |

所有写工具都会附加 MCP `annotations.destructiveHint = true`，
兼容的客户端会在调用前弹出确认对话框。

---

## 用 MCP Inspector 调试

[MCP Inspector](https://github.com/modelcontextprotocol/inspector)
是调试 MCP 服务器最方便的工具。

```bash
npm run inspect       # 构建 + 拉起 Inspector，对接 stdio
# 或开发期实时刷新：
npm run inspect:dev
```

Inspector 会打开一个 Web UI（默认 `http://localhost:5173`），
可以在里面浏览工具、调用工具、检查 JSON-RPC 流量。

---

## 接入 Claude Desktop

服务器走 **stdio** 传输，Claude Desktop 会把它作为子进程拉起并通过
stdin/stdout 通信。

### 第 1 步 —— 找到配置文件

| 操作系统 | 路径 |
|---|---|
| Windows | `%APPDATA%\Claude\claude_desktop_config.json` |
| macOS | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Linux | `~/.config/Claude/claude_desktop_config.json` |

Windows 下的完整路径形如：

```
C:\Users\<你的用户名>\AppData\Roaming\Claude\claude_desktop_config.json
```

如果文件不存在，直接新建一个。

### 第 2 步 —— 写入服务条目

```json
{
  "mcpServers": {
    "opengrok": {
      "command": "node",
      "args": [
        "D:/AppsData/deploy/opengrok/opengrok-ai/mcp/dist/index.js",
        "--stdio"
      ],
      "env": {
        "OPENGROK_BASE_URL": "http://localhost:8081/api/v1",
        "OPENGROK_AUTH_TYPE": "bearer",
        "OPENGROK_TOKEN": "dev-token-123",
        "ENABLE_WRITE_TOOLS": "false",
        "LOG_LEVEL": "info"
      }
    }
  }
}
```

几点注意：

* **路径用正斜杠**，即使在 Windows 上。Claude Desktop 启动子进程时
  两种斜杠都能处理，但正斜杠能避免 JSON 字符串里的转义麻烦。
* **不要让 Claude Desktop 去跑 `tsx`** —— Claude 自带的 Node 加上
  子进程生命周期，让它直接启动已经构建好的 `dist/index.js` 最稳。
  记得先 `npm run build`。
* 临时启用写工具：把 `ENABLE_WRITE_TOOLS` 改成 `"true"`，然后重启
  Claude Desktop。

### 第 3 步 —— 重启 Claude Desktop

彻底退出（Windows 右下角托盘右键 → 退出；macOS ⌘Q）后重新打开。
聊天输入框下方应该出现一个标着 **opengrok** 的小锤子图标，鼠标悬停
可以看到工具总数。

### 第 4 步 —— 烟雾测试

在任意 Claude 对话里问：

> 列出所有 OpenGrok 项目。

调用成功时，回复里会出现 `Used: list_projects`，并返回项目列表的
JSON。如果只看到 `Authorization: 401`，请检查 `OPENGROK_TOKEN`
然后重启 Claude。

### 查看服务端日志

Claude Desktop 会捕获子进程的 stderr，写到自己的日志文件里：

| 操作系统 | 路径 |
|---|---|
| Windows | `%APPDATA%\Claude\logs\mcp.log` |
| macOS | `~/Library/Logs/Claude/mcp.log` |

启动 Claude 前可以 `tail -f` 这个文件，看到启动横幅
（`auth: bearer token=dev-…-123 (len=13)`）就说明配置生效了。

### 排错速查表

| 现象 | 可能原因 | 解决 |
|---|---|---|
| 没有锤子图标 | `command` / `args` 路径有误 | 先在终端里跑同样的命令确认能起 |
| `ENOENT` on `node` | Claude Desktop 的 `PATH` 里没 Node | 用绝对路径，例如 `"C:\\Program Files\\nodejs\\node.exe"` |
| 每次调用都 401 | token 环境变量没传给子进程 | 确保 `env` 写在 server 配置块**内部**，不是顶层 |
| 连接成功但工具列表为空 | `ENABLE_WRITE_TOOLS=false` 过滤掉了写工具 | 这是预期行为 |
| 服务立刻崩溃 | Node 版本不对 | 必须 Node >= 22 |

---

## 接入 Cursor

`Settings → Features → Model Context Protocol → Add new global MCP server`，
粘贴下面这段：

```json
{
  "mcpServers": {
    "opengrok": {
      "command": "node",
      "args": [
        "D:\\AppsData\\deploy\\opengrok\\opengrok-ai\\mcp\\dist\\index.js",
        "--stdio"
      ],
      "env": {
        "OPENGROK_BASE_URL": "http://localhost:8081/api/v1",
        "OPENGROK_AUTH_TYPE": "bearer",
        "OPENGROK_TOKEN": "dev-token-123",
        "ENABLE_WRITE_TOOLS": "false"
      }
    }
  }
}
```

> Cursor 文档与 Claude Desktop 略有差别，参考
> [cursor.com/docs/model-context-protocol](https://cursor.com/docs/model-context-protocol)。

---

## 接入 Continue（VS Code / JetBrains）

`~/.continue/config.json` 中的 `experimental.mcpServers`：

```json
{
  "experimental": {
    "mcpServers": [
      {
        "name": "opengrok",
        "command": "node",
        "args": [
          "D:/AppsData/deploy/opengrok/opengrok-ai/mcp/dist/index.js",
          "--stdio"
        ],
        "env": {
          "OPENGROK_BASE_URL": "http://localhost:8081/api/v1",
          "OPENGROK_AUTH_TYPE": "bearer",
          "OPENGROK_TOKEN": "dev-token-123",
          "ENABLE_WRITE_TOOLS": "false"
        }
      }
    ]
  }
}
```

---

## 接入远程 agent（Streamable HTTP）

当 MCP 客户端和 OpenGrok 不在同一台机器上时（无头 agent 或
共享部署），用 **Streamable HTTP** 传输：

```bash
# 在服务端机器上：
npm run start:http -- --host 0.0.0.0 --port 3002
```

然后把 MCP 客户端指向 `http://<host>:3002/mcp`。MCP server 自己
会负责给 OpenGrok 加 Bearer 请求头，客户端这边**不需要**再传任何
鉴权头。

生产环境建议在 `3002` 前面挂一层反向代理（nginx / Caddy /
Cloudflare）来加 TLS，服务本身只走明文 HTTP。

---

## 一键接入 Claude Desktop（Windows）

如果你懒得手写 JSON，可以跑仓库里自带的 PowerShell 脚本：

```powershell
.\scripts\install-claude.ps1 -Token dev-token-123
# 或
npm run install:claude -- -Token dev-token-123
# 移除：
.\scripts\install-claude.ps1 -Uninstall
```

脚本会读 `OPENGROK_BASE_URL`（默认 `http://localhost:8081/api/v1`），
把你给的 token 写进 `%APPDATA%\Claude\claude_desktop_config.json`，
同时保留已有的其它 MCP 服务条目。写完后**记得重启 Claude Desktop**。

---

## 开发

```bash
npm run typecheck      # tsc --noEmit
npm run dev            # tsx watch + stdio
npm run dev:http       # tsx watch + HTTP，默认 3002 端口
npm run dev:sse        # tsx watch + SSE，默认 3001 端口
npm run build          # 编译到 dist/
npm run clean          # 删除 dist/
npm run install:claude # 在 Windows 上注册到 Claude Desktop
```

日志统一走 **stderr**，级别由 `LOG_LEVEL` 控制（默认 `info`）。
想看每次 OpenGrok REST 调用的明细，设成 `LOG_LEVEL=debug`。

---

## License

MIT
