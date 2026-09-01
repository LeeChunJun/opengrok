---
name: repo-operator
description: 当用户需要管理 OpenGrok 仓库本身（新建/删除项目、清理缓存、触发重建索引、广播消息、重载配置）时加载。**所有操作都是写**，需要 ENABLE_WRITE_TOOLS=true。
---

# repo-operator

> "在 OpenGrok 里新建一个项目对应 `/data/repos/xxx`"、
> "把过时的 annotation 缓存清掉"、"reindex 整个 opengrok-web"、
> "给全公司发条索引升级通知"——
> 本 skill 是 OpenGrok 仓库运营的"运维工具箱"。

> ⚠️ **所有动作都是写操作**，必须 `ENABLE_WRITE_TOOLS=true`。

## 适用场景

匹配以下用户原话之一时优先加载：

- 「给 OpenGrok 注册一个新项目」
- 「重建 `opengrok-web` 的索引」
- 「重建所有项目的 suggester 索引」
- 「清掉 `opengrok-tools` 的 annotation 缓存」
- 「广播一条系统消息」
- 「reload 一下授权插件配置」
- 「reload 一下 OpenGrok 的 include 定义」
- 「把某个项目标为 indexed」

## 不适用场景

- **修改项目业务属性**（tabSize 等） → 用 `bulk-refactor`
- **代码本身**（读 / 改） → 用 `code-investigator` / `bulk-refactor`
- **追查代码历史** → 用 `git-archaeologist`

## 前置条件（**必读**）

| 条件 | 说明 |
|---|---|
| `ENABLE_WRITE_TOOLS=true` | 必须 |
| 操作员权限 | OpenGrok 通常默认开放写权限；带授权插件的环境需 `admin` 角色 |
| 明确目标 | 用户必须给清楚"哪个项目 / 哪个缓存 / 哪条消息" |

**写开关未启用时**：

加载 skill 后第一件事告诉用户：

```
要执行写操作，但当前 MCP 服务似乎未启用写工具。
请用以下命令重启：

ENABLE_WRITE_TOOLS=true OPENGROK_TOKEN=... node dist/index.js --stdio

然后再发起你的请求。
```

## 涉及的工具

| 工具 | 操作 | 用途 |
|---|---|---|
| `add_project` | POST | 注册新项目（请求体：项目名纯文本） |
| `delete_project` | DELETE | **危险**：删项目及索引 |
| `delete_project_data` | DELETE | 清空项目索引数据（保留注册） |
| `delete_project_annotation_cache` | DELETE | 清空 annotation 缓存 |
| `delete_project_history_cache` | DELETE | 清空 history 缓存 |
| `mark_project_indexed` | PUT | 标记项目为已索引 |
| `rebuild_suggester_index` | PUT | 重建 suggester 索引 |
| `reload_includes` | PUT | 重载 include 文件 |
| `reload_authorization` | POST | 重载授权插件 |
| `add_message` | POST | 广播消息 |
| `remove_messages_with_tag` | DELETE | 清空某 tag 的消息 |

## 危险等级

模型加载本 skill 后，应按危险等级提示用户：

| 等级 | 操作 | 提示强度 |
|---|---|---|
| 🟢 低 | `mark_project_indexed`, `reload_includes`, `reload_authorization`, `add_message` | 单次确认即可 |
| 🟡 中 | `delete_project_data`（清空索引）、`delete_project_annotation_cache`、`delete_project_history_cache`、`rebuild_suggester_index` | 列出影响范围 + 确认 |
| 🔴 高 | `delete_project`、`remove_messages_with_tag`（带通配 tag） | **双重确认 + 列出可恢复性** |

## 工作流

### 阶段 1 — 解析意图

把用户的自然语言映射到具体工具，例如：

| 用户原话 | 工具调用 |
|---|---|
| "建个项目叫 `myrepo`" | `add_project(name="myrepo")` |
| "reindex 整个 web" | `rebuild_suggester_index()` 或外部 `opengrok-indexer` 命令 |
| "清掉 `myrepo` 的 annotation 缓存" | `delete_project_annotation_cache(project="myrepo")` |
| "给所有项目广播一条索引升级通知" | 对 `list_projects` 返回的每个项目调 `add_message` |

### 阶段 2 — 影响评估

执行前必须告诉用户：

```
即将执行：
- 工具：delete_project_data
- 目标：opengrok-web
- 影响：清空索引数据，项目注册信息保留，下次需触发 reindex

⚠️ 此操作不可恢复（索引重建需要时间）
确认执行吗？(yes / no / dry-run)
```

### 阶段 3 — Dry-run

对所有 🟡 及以上操作，建议先 dry-run。OpenGrok 本身没有 dry-run
模式，所以"dry-run"在 MCP 层的意思是：

```
1. 调用 get_project_property（拿当前值，验证项目存在）
2. 调用 list_indexed_projects（确认状态）
3. 不真正调写工具
4. 把"如果执行会发生什么"展示给用户
```

### 阶段 4 — 执行

按确认顺序执行。

**长任务的轮询**：

`rebuild_suggester_index` 是异步任务，会返回 UUID：

```
调用 rebuild_suggester_index
  → 返回 {"uuid": "abc-123"}

调用 get_job_status
  uuid="abc-123"
  → 每 5 秒轮询，直到 status=done / failed
```

### 阶段 5 — 输出运维报告

```
# Repo Operator 执行报告

## 任务
opengrok-web 项目 annotation 缓存清理

## 影响评估
- 项目状态：已索引，最后索引时间 2025-02-10
- 缓存大小预估：~50MB（根据 OpenGrok 历史数据）
- 预计耗时：< 30 秒

## 执行步骤
1. 调 `get_project_property` 确认项目存在 ✅
2. 调 `delete_project_annotation_cache` ✅（HTTP 200）
3. 调 `list_indexed_projects` 验证 ✅

## 结果
✅ 缓存已清空，项目注册信息和索引数据未受影响
⏱️ 耗时：12 秒

## 后续
- 建议下次 blame 操作会触发缓存重建
- 无需重新索引
```

## 示例对话

### 示例 1：注册新项目

**用户**：把 `/data/repos/newportal` 注册成 OpenGrok 项目。

**模型动作**：
1. 加载本 skill，检查写开关
2. 询问用户确认：「注册新项目 `newportal` 后，OpenGrok 会开始索引
   这个目录，预计耗时取决于仓库大小，确认吗？」
3. 用户确认 → 调 `add_project(name="newportal")`
4. 调 `list_projects` 验证
5. 提示：「新项目已注册，但索引可能异步进行。可用
   `list_indexed_projects` 跟踪完成情况。」

### 示例 2：清理缓存

**用户**：清掉 `opengrok-web` 的 annotation 缓存。

**模型动作**：
1. 评估影响：缓存清空后，下次 blame 会重新生成（慢一点但准确）
2. 询问用户确认
3. 调 `delete_project_annotation_cache(project="opengrok-web")`
4. 调 `get_project_index_files` 或类似工具验证（如适用）
5. 输出报告

### 示例 3：重建索引

**用户**：reindex 一下 `opengrok-web` 的 suggester 索引。

**模型动作**：
1. **重要**：告知用户 OpenGrok 的 suggester 索引和主索引是分开的，
   `rebuild_suggester_index` 只重建 suggester；如需重建主索引，
   要在 OpenGrok 服务端跑 `opengrok-indexer` 命令
2. 询问用户确认
3. 调 `rebuild_suggester_index(project="opengrok-web")` → 拿到 UUID
4. 轮询 `get_job_status`，直到完成
5. 输出报告

### 示例 4：广播消息

**用户**：给所有项目广播一条通知 "2025-03-01 索引升级"。

**模型动作**：
1. 调 `list_projects` 拿所有项目
2. 对每个项目调 `add_message`：
   ```json
   {
     "tag": "announce-2025-03-01",
     "text": "2025-03-01 索引升级",
     "createdAt": "2025-02-15T10:00:00Z"
   }
   ```
3. 对每个项目调 `get_messages`，`tag="announce-2025-03-01"` 验证
4. 输出报告（带每个项目的状态）

## 错误处理

| 工具返回 | 模型应做的事 |
|---|---|
| `401 Unauthorized` | 检查 `OPENGROK_TOKEN` |
| `403 Forbidden` | 当前用户无写权限 |
| `404 Not Found` | 项目名拼错，列出 `list_projects` 让用户选 |
| `409 Conflict` | 资源冲突（如项目已存在、状态不允许删除） |
| 任务长时间 `pending` | 提示用户检查 OpenGrok 服务端日志 |

## 安全护栏

1. **绝不**直接执行写操作
2. 🟡🟠🔴 操作必须先 dry-run 评估影响
3. 🔴 操作必须双重确认（输入完整字符串如 "yes, delete opengrok-web"）
4. 删除类操作前**自动备份当前状态**（调 `get_project_property` /
   `get_messages` 留档）
5. 所有执行结果写入报告，便于审计

## 自检清单

- [ ] 我有没有先问用户确认？
- [ ] 我有没有按危险等级区分确认强度？
- [ ] 涉及删除的操作我有没有先读出当前状态做"备份"？
- [ ] 异步任务我有没有轮询到完成？
- [ ] 我有没有给出一份**带时间戳和影响范围**的报告？

## 修改建议

- **CI 接入**：所有写操作可输出 JSON 报告，便于接入运维审计系统
- **审批流**：对 🔴 操作，可在执行前要求特定审批 token（可后续扩展）
- **批量回滚**：执行成功后生成 `rollback.sh`，记录所有反向操作
- **健康检查前置**：执行前先 `ping`，避免对已挂掉的实例写
