---
name: pr-review-assistant
description: 当用户需要对一个 PR / diff / 代码变更做审查时加载。综合 code-investigator（理解代码）、git-archaeologist（看历史）、symbol-tracker（看影响面）的能力，从风格、安全、复用、回归四个维度给出 review 意见。
---

# pr-review-assistant

> "帮我 review 一下这个 PR"、"这个改动有什么风险"、"这里是不是
> 重复造轮子了"——
> 本 skill 不直接拿到 diff（OpenGrok 不暴露 diff API），而是让用户
> 把变更文件列表给出来，由 skill 围绕这些文件做多角度审查。

## 适用场景

匹配以下用户原话之一时优先加载：

- 「帮我 review 一下 PR #1234」
- 「`PR-5678` 这个改动有什么风险」
- 「看看 `FooService` 这个重构合理吗」
- 「这个新加的 API 是不是重复了」
- 「我改的这块代码有什么边界情况没考虑到」

## 不适用场景

- **理解代码但不动它** → 用 `code-investigator`
- **只关心代码历史 / blame** → 用 `git-archaeologist`
- **跨项目追踪某个符号** → 用 `symbol-tracker`
- **真正修改代码** → 用 `bulk-refactor`（写）

## 前置条件

- **不需要写工具**。
- 用户需要给出 PR 涉及的文件列表（绝对路径或仓库相对路径均可）。
- 如果用户直接贴 diff，更好——可以更准确地定位改动行。

## 工作流

### 阶段 1 — 收集 PR 元数据

让用户提供：

| 信息 | 必填 | 说明 |
|---|---|:---:|
| 项目名（projects[]） | ✅ | 用于限定搜索范围 |
| 涉及的文件路径列表 | ✅ | 至少 1 个 |
| PR 描述 / 标题 | ❌ | 帮助理解意图 |
| diff 全文 | ❌ | 有的话粘进来 |

如果用户没给项目名，先 `list_projects` 让用户挑。

### 阶段 2 — 理解变更内容

对每个变更文件：

```
调用 get_file_definitions
  path=<文件路径>
  → 拿到所有符号清单

调用 get_file_content
  path=<文件路径>
  → 拿到当前完整内容
```

如果用户给了 diff，重点 diff 涉及的方法 / 类，跳过无关代码。

### 阶段 3 — 四维度审查

#### 维度 A：风格一致性

对照仓库已有的「邻居代码」：

```
调用 search_code
  type=full
  query=<本次 PR 新引入的关键字串>
  projects=<同一项目>
  → 看是否与已有命名 / 错误处理风格一致
```

#### 维度 B：复用检查（避免重复造轮子）

```
调用 search_code
  type=def
  query=<PR 新加的类名 / 方法名>
  projects=[]
  maxresults=50
  → 是否已有类似实现？
```

如果发现 ≥2 个相似实现，提醒用户考虑抽取公共基类 / 工具方法。

#### 维度 C：影响面（symbol-tracker 复用）

对 PR 中改名的方法 / 删除的类 / 改签名的 API：

```
调用 search_code
  type=symbol
  query=<被改动的符号>
  projects=[]
  maxresults=200
  → 所有调用方是否都已同步修改？
```

#### 维度 D：历史背景（git-archaeologist 复用）

对 PR 修改的「老 hack」：

```
调用 get_file_history
  path=<文件>
  withFiles=true
  max=10
  → 这个 hack 是哪次 commit 加的，issue 编号是什么
```

如果历史 commit 信息提到「workaround for #NNN」，去查 issue 是否
仍有效。

### 阶段 4 — 输出审查报告

按这个模板输出：

```
# PR Review：<标题>

## 概要
<1-2 句概括本次改动>

## 文件清单
- `path/to/A.java`（新增 / 修改 / 删除，N 行变更）
- `path/to/B.java`（...）

## ✅ 优点
- ...

## ⚠️ 建议改进
### 复用
- ...

### 一致性
- ...

### 边界情况
- ...

## ❌ 阻塞问题
- ...

## 测试覆盖
- 现有测试是否覆盖新逻辑？
- 建议补充的边界测试：...

## 决策点（需要人类判断）
- ...
```

## 示例对话

### 示例 1：简单 PR review

**用户**：review 一下 `opengrok-web` 的 PR #5678，修改了
`ProjectController.java` 加了一个 `updateProject` 方法。

**模型动作**：
1. 调 `search_code` 找到 `ProjectController.java` 当前内容
2. 调 `get_file_definitions` 列出所有方法，定位 `updateProject` 行号
3. 调 `get_file_content` 读全文
4. 用户粘 diff：插入 50 行，包含 `@PUT` 注解、`@PathParam`、
   `Config.updateProject()` 调用、错误处理
5. 调 `search_code`，`type=def`, `query=updateProject`, `projects=[]`
   → 发现 `Config.java` 里已经有同名方法，签名不一致（缺一个参数）
6. 调 `search_code`，`type=symbol`, `query=Config.updateProject` 找
   所有调用方
7. 调 `get_file_history`，`path=ProjectController.java`, `max=5`
   → 最近是 2 个月前的「init」commit
8. 输出报告

**输出**（节选）：
```
# PR Review：ProjectController.updateProject

## 概要
新增 PUT 端点用于更新项目配置。

## ✅ 优点
- 错误处理与 `addProject` 风格一致
- 用了 `@Valid` 注解校验输入

## ⚠️ 建议改进
### 复用
- `Config.updateProject(String name, Map<String,String> updates)` 已有
  旧签名；新代码传的是 `ProjectDTO`，签名不匹配。需统一。
- 建议直接复用 `Config.updateProject()`，避免另写一份。

### 边界情况
- 当 `name` 指向不存在的项目时，没有 404 处理（当前是 500）
- `updates` 为空 map 时是否要拒绝？

### 影响面
- `Config.updateProject` 被 4 处调用，本次 PR 没动这些调用方，
  确认它们仍兼容旧签名。

## ❌ 阻塞问题
- 与 `Config.updateProject()` 签名不一致，必须先对齐

## 决策点
- 是否要把 `ProjectDTO` 作为通用契约，还是直接传 Map？
```

### 示例 2：删除类前的 review

**用户**：PR 想删掉 `LegacyFoo` 类，影响面怎么评估？

**模型动作**：
1. 调 `search_code`，`type=def`, `query=LegacyFoo`，全项目搜
2. 调 `search_code`，`type=symbol`, `query=LegacyFoo`，找引用
3. 调 `get_file_history`，`path=LegacyFoo.java`，看历史
4. 输出"删除前安全审查"报告

## 错误处理

| 工具返回 | 模型应做的事 |
|---|---|
| 文件不存在 | 提示用户路径可能拼错，建议用 `search_code` 重新定位 |
| 项目不在 `list_projects` 里 | 提示用户先注册该项目（`repo-operator` skill） |
| 用户只给了 PR 链接但没给文件列表 | 提示必须给文件路径，OpenGrok 没有 PR 概念 |

## 自检清单

- [ ] 我有没有要用户提供**变更文件清单**，而不是猜？
- [ ] 我有没有从 4 个维度（风格/复用/影响/历史）都过一遍？
- [ ] 我的建议是不是**可操作**（具体到行号、文件、方法名）？
- [ ] 我有没有明确区分「阻塞」vs「建议」vs「可选」？

## 修改建议

- **大型 PR**：分多次审查（按文件分组），不要一次过完所有维度
- **新文件**：聚焦「命名一致性」「职责单一性」，减少过度设计担忧
- **依赖升级**：额外调 `search_code` 看是否使用了新版本才有的 API
- **数据库迁移**：提醒人工确认 DBA / DBA bot 走过的迁移流程
