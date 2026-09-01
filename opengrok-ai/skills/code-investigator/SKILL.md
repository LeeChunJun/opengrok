---
name: code-investigator
description: 当用户需要理解一段代码的工作原理、阅读函数实现、查看类结构时加载。本 skill 是其他阅读类 skill（symbol-tracker / git-archaeologist / pr-review-assistant）的基础。
---

# code-investigator

> "帮我看懂这段代码"、"这个函数做了什么"、"这个类有哪些方法"——
> 本 skill 教模型用 `opengrok-mcp` 的读工具，把一个陌生函数 / 类 /
> 文件彻底讲清楚。

## 适用场景

匹配以下用户原话之一时优先加载本 skill：

- 「帮我看看 `XXXService.java` 是怎么实现的」
- 「这个报错是在哪个方法里抛出来的」
- 「讲一下 `createOrder` 这个函数的逻辑」
- 「这个项目用了哪些设计模式」
- 「我想理解 `YyyConfig` 这个配置类」
- 「这段代码是怎么连数据库的」

## 不适用场景

- **追踪某个符号在多个项目里的所有出现位置** → 用 `symbol-tracker`
- **追溯某行代码的变更历史 / 谁改的** → 用 `git-archaeologist`
- **整体 review 一个 PR** → 用 `pr-review-assistant`
- **修改 / 重命名 / 删除代码** → 用 `bulk-refactor`（需写工具）
- **新建项目 / 重建索引** → 用 `repo-operator`（需写工具）

## 前置条件

- **不需要写工具**，`ENABLE_WRITE_TOOLS` 默认 `false` 即可使用。
- `OPENGROK_BASE_URL` 必须可达，建议先用 `ping` 工具探活。

## 工作流（模型应严格按顺序执行）

### 阶段 1 — 定位项目

```
调用 list_projects
  ↓ 得到 [{"name": "opengrok-web", ...}, ...]
```

如果用户已经指定了项目名（例如「opengrok-indexer 里的 …」），
跳过这一步。

### 阶段 2 — 定位文件

**两种策略，按场景选择**：

| 场景 | 工具 | 关键参数 |
|---|---|---|
| 用户给的是文件名 / 路径 | `list_directory` | `path="<父目录>"` |
| 用户给的是符号名 | `search_code` | `type=def`, `query=<符号>` |
| 用户描述模糊（"那个订单服务"） | `search_code` | `type=full`, `query=<关键词>` |

**搜索时**：使用最小、最精确的关键词。例如要看 `OrderService` 类
不要搜 "order service"，要搜 `OrderService`。

### 阶段 3 — 读取符号定义

文件路径确定后，调用：

```
调用 get_file_definitions
  参数: path="<文件路径>"
  ↓ 得到 [{ "line": 42, "symbol": "OrderService", "kind": "class" }, ...]
```

如果返回为空（说明 OpenGrok 没解析出来），直接跳到阶段 4 读全文。

### 阶段 4 — 读取全文

```
调用 get_file_content
  参数: path="<文件路径>"
```

如果文件超过 ~300 行，分段读：
- 用 `get_file_genre` 确认是文本（避免读二进制）
- 让模型按需只读相关段落

### 阶段 5 — 综合回答

按下面这个**模板**输出：

```
## 文件
<绝对路径>

## 核心类型（来自 get_file_definitions）
- `OrderService` (class, line 42)
  - `createOrder(...)` (line 58)
  - `cancelOrder(...)` (line 89)

## 实现概要
<分 3-5 段叙述，每段不超过 5 行>

## 关键依赖
<从 import / 调用关系里抽取的外部符号>

## 可能的疑问点
<列出 2-3 个你不能 100% 确定的地方，提示用户人工确认>
```

## 示例对话

### 示例 1：理解单个方法

**用户**：`opengrok-web` 里 `ProjectController` 的 `addProject` 方法做了什么？

**模型动作**：
1. 调用 `list_projects` → 找到 `opengrok-web` 项目存在
2. 调用 `search_code`，`type=def`, `query=ProjectController`, `projects=["opengrok-web"]`
3. 找到 `ProjectController.java`，记录路径 `opengrok-web/src/main/java/.../ProjectController.java`
4. 调用 `get_file_definitions`，确认 `addProject` 方法存在，记录行号
5. 调用 `get_file_content` 读全文（如果是 Servlet，可能 200-400 行，一次读完）
6. 综合输出

**输出**（节选）：
```
## 文件
opengrok-web/src/main/java/org/opengrok/web/controller/ProjectController.java

## 核心类型
- `ProjectController` (class, line 31)
  - `addProject` (POST, line 58) — 注册新项目
  - `deleteProject` (DELETE, line 92)
  - `listProjects` (GET, line 41)

## 实现概要
`addProject` 是一个 Jersey REST 端点，路径 `POST /api/v1/projects`：
1. 从请求体读取纯文本项目名（line 60-62）
2. 调用 `Config` 的 `registerProject()` 校验名称合法
3. 通过 `IndexDatabase` 触发异步索引（不阻塞 HTTP 响应）
4. 返回 201 + 项目元数据 JSON

## 可能的疑问点
- 注册失败的具体异常类型需要进一步看 `Config.registerProject()`
- 是否在写入前做了重复检查，需查 IndexDatabase 的索引逻辑
```

### 示例 2：从错误反推代码

**用户**：线上报错 `NullPointerException at WebappListener.contextInitialized:127`，这个方法干了啥？

**模型动作**：
1. 调用 `search_code`，`type=def`, `query=WebappListener`, `projects=[]`
2. 找到文件路径，调用 `get_file_content` 读全文
3. 重点阅读 127 行附近 30 行上下文
4. 解释上下文，提示用户 NPE 的可能来源

## 错误处理

| 工具返回 | 模型应做的事 |
|---|---|
| `401 Unauthorized` | 提示用户检查 `OPENGROK_AUTH_TYPE` / `OPENGROK_TOKEN` |
| `404 Not Found` | 路径可能拼错，建议用 `search_code` 重新定位 |
| `get_file_definitions` 返回空 | 跳到阶段 4 直接读全文，靠正则 / 模型自身识别符号 |
| `get_file_content` 返回值异常大 | 提示用户这个文件过大，分段处理 |

## 自检清单（模型加载本 skill 后应自检）

- [ ] 我有没有先调 `list_projects` / `ping` 确认 OpenGrok 可达？
- [ ] 我搜的关键词是不是**最精确**的（避免宽泛词导致噪音）？
- [ ] 我有没有先看 `get_file_definitions` 再决定要不要读全文？
- [ ] 我的回答有没有明确标注「哪些是 100% 确定、哪些需要人工确认」？

## 修改建议

如果你的代码库有以下特征，可在本 skill 基础上扩展：

- **多语言混合**（Java + JS + Python）：在阶段 2 增加文件后缀判断
- **代码生成**（`target/generated-sources/`）：在阶段 4 优先跳过
- **文档目录**（`docs/`）：可附加 `list_directory` 搜索 `.md` 文件
