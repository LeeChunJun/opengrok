---
name: bulk-refactor
description: 当用户需要批量修改 OpenGrok 元数据（路径描述、项目属性、消息广播）时加载。本 skill 会调用**写工具**，默认情况下这些工具不会被注册——必须先把 opengrok-mcp 启动时设置 ENABLE_WRITE_TOOLS=true。
---

# bulk-refactor

> "把所有项目里路径含 `legacy/` 的文件描述统一加上 [LEGACY] 前缀"、
> "把 X 项目的 tabSize 属性从 4 改成 2"、"给所有项目的索引数据
> 加一条 'indexed-by-v2' 的消息"——
> 本 skill 是把"读 skill"产出的洞察**真正落到 OpenGrok 元数据**
> 上的桥梁。

> ⚠️ **本 skill 会执行写操作**，必须满足前置条件才能用。

## 适用场景

匹配以下用户原话之一时优先加载：

- 「把所有项目的 X 字段统一改成 Y」
- 「给项目 `opengrok-web` 的 `tabSize` 改成 2」
- 「把这次重构的描述广播给所有项目」
- 「批量给某些路径打标签」
- 「把某个文件描述改一下」
- 「为项目 `xxx` 添加一条索引消息」

## 不适用场景

- **仅理解代码** → 用 `code-investigator`
- **仅追踪符号使用** → 用 `symbol-tracker`
- **review PR 但不动它** → 用 `pr-review-assistant`
- **仓库 CRUD（建/删项目）** → 用 `repo-operator`

## 前置条件（**必读**）

| 条件 | 说明 |
|---|---|
| `ENABLE_WRITE_TOOLS=true` | 必须！否则 `set_project_property` 等工具根本不在工具列表里 |
| OpenGrok 可写 | 多数部署默认开放；带授权插件的环境需要额外 ACL |
| 明确范围 | 用户必须指定「哪些项目」「改什么字段」「改成什么值」 |

**当 `ENABLE_WRITE_TOOLS=false` 时**：

加载本 skill 后第一件事是**主动询问**用户是否已启用写开关；如果
没有，提示用户重启 `opengrok-mcp` 时加上：

```bash
ENABLE_WRITE_TOOLS=true OPENGROK_TOKEN=... node dist/index.js --stdio
```

## 涉及的工具

| 工具 | 类型 | 用途 |
|---|---|---|
| `set_project_property` | 写 | 修改项目单个属性 |
| `load_path_descriptions` | 写 | 批量上传路径描述（数组） |
| `add_message` | 写 | 广播系统消息 |
| `remove_messages_with_tag` | 写 | 按 tag 删除消息 |
| `set_configuration_field` | 写 | 修改全局配置字段 |

## 工作流

### 阶段 1 — 写前确认（必须）

**永远不要**直接执行写操作。要按下面这套确认流程：

#### 1.1 范围确认

向用户展示即将影响的范围：

```
即将修改：
- 项目：opengrok-web, opengrok-indexer
- 字段：tabSize
- 现值：4
- 新值：2

确认执行吗？（yes/no/dry-run）
```

#### 1.2 Dry-run 选项

如果用户选 dry-run，用 `get_project_property` 读出当前值，**不**调用
`set_project_property`：

```
Dry-run 结果：
- opengrok-web.tabSize = 4 → 2（将修改）
- opengrok-indexer.tabSize = 4 → 2（将修改）
- opengrok-tools.tabSize = 8（不动，不在范围内）
```

#### 1.3 逐项确认（**强烈推荐**）

对 ≥3 个项目的批量操作，**每个项目都问一次**确认；批量改 1-2 个
项目时一次性确认即可。

### 阶段 2 — 执行

按确认顺序逐个调用对应工具：

```
调用 set_project_property
  project="opengrok-web"
  field="tabSize"
  value="2"
```

每次调用都**捕获返回值**：

- 成功：记录到执行日志
- 失败（4xx/5xx）：**立即停下**，报告错误，问用户是回滚还是继续

### 阶段 3 — 验证

批量改完后，逐项验证：

```
调用 get_project_property
  project="opengrok-web"
  field="tabSize"
  → 确认返回值确实是 2
```

### 阶段 4 — 输出执行报告

```
# Bulk Refactor 执行报告

## 任务
将 {opengrok-web, opengrok-indexer} 的 tabSize 从 4 改为 2

## 执行结果
| 项目 | 操作 | 旧值 | 新值 | 状态 |
|---|---|---|---|:---:|
| opengrok-web | set tabSize=2 | 4 | 2 | ✅ |
| opengrok-indexer | set tabSize=2 | 4 | 2 | ✅ |

## 验证结果
- opengrok-web.tabSize = 2 ✅
- opengrok-indexer.tabSize = 2 ✅

## 后续
- 建议同步更新代码中相关默认值
- 提示用户检查 `.editorconfig` / `.prettierrc` 等本地配置
```

## 示例对话

### 示例 1：批量改项目属性

**用户**：把 `opengrok-web` 和 `opengrok-indexer` 的 `tabSize` 改成 2。

**模型动作**：
1. 加载本 skill，**第一件事**：检查 `ENABLE_WRITE_TOOLS` 是否启用
2. 询问用户确认（不直接调写工具）：
   ```
   即将修改：
   - opengrok-web.tabSize: ? → 2（当前值未知，建议先查）
   - opengrok-indexer.tabSize: ? → 2

   先 dry-run 一次吗？
   ```
3. 用户确认 dry-run → 调 `get_project_property` × 2
4. 显示对比表，用户再次确认执行
5. 调 `set_project_property` × 2
6. 调 `get_project_property` × 2 验证
7. 输出报告

### 示例 2：批量加路径描述

**用户**：把所有项目里包含 `legacy/` 的路径描述前缀都加上 `[DEPRECATED] `。

**模型动作**：
1. 告知用户：OpenGrok 没有"按规则查现有描述"的 API，必须用户提供
   路径列表或允许我们先用 `search_code` 全量扫一遍
2. 用户允许 → 调 `search_code`，`type=path`, `query=legacy/`,
   `maxresults=500`，分页拉
3. 对每个项目，调 `load_path_descriptions`，传 `[{path, description}]`
   数组（用项目当前已有的描述 + `[DEPRECATED] ` 前缀）
4. 验证

### 示例 3：广播消息

**用户**：给所有项目加一条系统消息："将于 2025-03-01 进行索引 v2 升级"。

**模型动作**：
1. 调 `list_projects` 拿所有项目
2. 对每个项目，调 `add_message`，body 是消息对象：
   ```json
   {
     "tag": "announce-index-v2",
     "text": "将于 2025-03-01 进行索引 v2 升级",
     "createdAt": "2025-02-15T10:00:00Z"
   }
   ```
3. 验证：调 `get_messages`，`tag="announce-index-v2"` 确认每项目都有

## 错误处理

| 工具返回 | 模型应做的事 |
|---|---|
| `401 Unauthorized` | 写工具不通过鉴权 → 检查 `OPENGROK_TOKEN` |
| `403 Forbidden` | 该 OpenGrok 实例写权限被锁 → 联系管理员 |
| `404 Not Found` | 项目名拼错 → 用 `list_projects` 重新核对 |
| `400 Bad Request` | 参数类型不对（常见：value 应为字符串而非数字） |
| `set_project_property` 返回 5xx | **立即停下所有写操作**，报告并询问是否回滚 |
| 部分项目成功部分失败 | 列出成功/失败清单，问用户是否补做失败的 |

## 安全护栏（再次强调）

1. **绝不**自动执行写操作，必须用户显式确认（"yes" 关键词）
2. 批量超过 5 个项目时，分批确认，每批一次确认
3. 涉及**删除 / 清空**的操作（`remove_messages_with_tag`、
   `delete_project_data`）必须**双重确认**（用户输入 "yes, delete"）
4. 每次执行后必须验证
5. 失败立即停止，避免"半完成"状态

## 自检清单

- [ ] 我有没有先问用户确认，**而不是直接调写工具**？
- [ ] 我有没有先做 dry-run？
- [ ] 批量大于 5 个项目时我有没有分批确认？
- [ ] 涉及删除的操作我有没有要求双重确认？
- [ ] 每次写操作后我有没有读回验证？
- [ ] 我有没有输出一份**可审计**的执行报告？

## 修改建议

- **CI/CD 集成**：可让本 skill 输出 JSON 报告，便于接入自动化审计
- **回滚脚本**：写操作前先生成 `rollback.sh` 列出所有反向操作
- **审计日志**：所有写操作记入 `opengrok-mcp` 的日志（pino）
