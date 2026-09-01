---
name: git-archaeologist
description: 当用户想了解某行 / 某段代码的变更历史、为什么这样写、谁引入的、什么时候重构过时，加载本 skill。典型场景：复盘一个 bug 的引入点、理解一段 hack 的历史背景、对老代码做考古。
---

# git-archaeologist

> "这行代码谁写的？"、"为什么这里要 sleep 100ms？"、"这个正则
> 是什么时候加的？"——
> 本 skill 用 `annotate_file` + `get_file_history` + `get_file_content`
> 把代码的历史翻给你看。

## 适用场景

匹配以下用户原话之一时优先加载：

- 「`FooService.java:88` 这段谁加的」
- 「为什么 `parseConfig` 里有个奇怪的 fallback」
- 「这个 sleep 100ms 是哪里来的」
- 「这个 bug 是哪个提交引入的」
- 「上次重构掉这块代码是哪个 PR」
- 「给我看看 `Xxx.java` 最近 30 天的改动」

## 不适用场景

- **理解当前代码** → 用 `code-investigator`
- **跨项目追踪符号使用** → 用 `symbol-tracker`
- **整体 PR review** → 用 `pr-review-assistant`
- **线上问题定位（结合日志）** → 用 `incident-responder`

## 前置条件

- **不需要写工具**。
- `annotate_file` 返回数据量可能很大（每行一条），建议对超大文件
  （>2000 行）先缩小到关键段落。
- `get_file_history` 默认返回前 1000 条修订；如果文件历史极长，
  用 `start` + `max` 分页。

## 工作流

### 阶段 1 — 定位文件

如果用户给了文件路径，直接进入阶段 2。
否则：

```
调用 search_code
  type=def
  query=<用户提到的类或方法>
  → 得到文件路径
```

### 阶段 2 — 查看文件级历史

```
调用 get_file_history
  参数:
    path="<文件路径>"
    withFiles=true        ← 重要：返回每次提交改动的文件
    max=30                ← 最近 30 次提交就够
    start=0
```

返回形如：

```json
{
  "revisions": [
    { "revision": "abc1234", "author": "alice", "date": "2025-01-15",
      "message": "fix: NPE in edge case", "files": ["OrderService.java"] },
    ...
  ]
}
```

### 阶段 3 — Blame 关键行

```
调用 annotate_file
  参数:
    path="<文件路径>"
    revision=<可选，默认 HEAD>
```

返回形如：

```json
{
  "annotations": [
    { "line": 88, "revision": "abc1234", "author": "bob",
      "date": "2024-08-22", "message": "workaround for issue #234" },
    ...
  ]
}
```

只对用户**关心的行**（1-10 行）重点分析，不要把整个文件 dump 出来。

### 阶段 4 — 看当时的内容

对于最关键的修订（比如用户问的那个 hack），读它前后的代码：

```
调用 get_file_content
  path="<文件路径>"
  ← 但只能读当前版本
```

**注意**：`get_file_content` 只能读**当前 HEAD** 的内容。
要看历史版本只能：

- 用 `annotate_file` 的 `revision` 参数重新读
- 或者让用户从 git 仓库直接 `git show <rev>:<path>`

### 阶段 5 — 综合回答

按下面这个模板输出：

```
## 关注行
`XxxService.java:88`

## 当前内容
```java
Thread.sleep(100); // workaround for issue #234
```

## Blame 信息
- **作者**：bob
- **提交**：abc1234（2024-08-22）
- **提交信息**：workaround for issue #234
- **上一次改动该行**：def5678（2023-12-10，alice，「init」）

## 文件近期历史
| 日期 | 作者 | 提交 | 信息 |
|---|---|---|---|
| 2025-01-15 | alice | abc1234 | fix: NPE in edge case |
| 2024-11-03 | bob   | 9876fed | refactor: extract helper |
| 2024-08-22 | bob   | abc1234 | workaround for issue #234 |
| ... | ... | ... | ... |

## 推测 / 待人工确认
- issue #234 可能描述的是某个旧 bug 引发的不稳定网络请求
- 这个 workaround 是否仍然需要，可查 issue #234 当前状态
```

## 示例对话

### 示例 1：理解一个 hack

**用户**：`UserService.java:42` 那个奇怪的 `password = "default"` 是
谁加的？

**模型动作**：
1. `search_code`，`type=def`, `query=UserService` → 找到路径
2. `annotate_file`，`path=<路径>` → 拿到所有行的 blame
3. 重点看 line 42 → 拿到 author / revision / message
4. `get_file_history`，`path=<路径>`, `max=20`, `withFiles=true` → 看上下文
5. 输出综合分析

**输出**（节选）：
```
## 关注行
`src/main/java/.../UserService.java:42`

## 当前内容
```java
if (password == null) password = "default"; // TODO: remove
```

## Blame 信息
- **作者**：charlie
- **提交**：deadbeef（2023-04-12）
- **信息**：`temp: silence NPE during migration`

## 文件近期历史
| 日期 | 作者 | 提交 | 信息 |
|---|---|---|---|
| 2025-02-01 | alice | aaa111 | refactor: split UserService |
| 2024-09-15 | bob   | bbb222 | fix: auth flow |
| 2024-03-08 | alice | ccc333 | cleanup legacy fields |
| 2023-04-12 | charlie | deadbeef | temp: silence NPE during migration |

## 推测
- 这是 2023 年数据迁移期间的临时方案，TODO 明确标注要清理
- 已过去近 2 年，最近的 `aaa111` 重构并没碰这一行
- 建议：开一个新 PR 移除，并加单元测试覆盖 null password 场景
```

### 示例 2：找 bug 引入点

**用户**：上周线上 NPE 在 `PaymentService.java:155`，是哪个 PR 引入的？

**模型动作**：
1. 同上，定位到 `PaymentService.java`
2. `annotate_file` 拿到 line 155 的 blame
3. `get_file_history` 看那段时间前后的提交
4. 看其它文件是否也有类似改动（用 `withFiles=true`）

**输出**：
```
## Bug 引入点

**提交**：`pr-1234` (commit fedcba98)
**作者**：dan
**日期**：2025-01-08
**信息**：`feat: support refund flow`
**改动文件**：PaymentService.java、RefundController.java、PaymentDTO.java

## 分析
- dan 在新增退款流程时，把 `payment.getRefundId()` 放在 if 块外
- 但当 payment.status == SUCCESS 时 refundId 为 null，触发 NPE
- 单元测试覆盖不完整：只测了 REFUND_PENDING 分支

## 修复建议
- 在 line 155 加 null 检查：`if (payment.getRefundId() != null) { ... }`
- 补充单元测试覆盖 SUCCESS 分支
- 建议联系 dan 一起 review 修复方案
```

## 错误处理

| 工具返回 | 模型应做的事 |
|---|---|
| `annotate_file` 返回为空 | 项目可能没建索引，建议先 `list_indexed_projects` 确认 |
| `get_file_history` 拿不到 withFiles 数据 | 减少 max、只取 summary |
| 行号定位错（用户报的行号已过时） | 用 `get_file_definitions` + `search_code` 重新定位 |
| 文件已被删除 | 提示用户文件已不存在，建议用 `git log --diff-filter=D` 在仓库里查 |

## 自检清单

- [ ] 我有没有先定位文件路径（而不是直接猜）？
- [ ] `annotate_file` 的结果我有没有筛选到**关键行**，而不是全部 dump？
- [ ] 我有没有同时给「当前内容 + blame + 文件近期历史」三件套？
- [ ] 我有没有标注哪些是「推测」，哪些是「事实」？

## 修改建议

- **超大文件**：先 `get_file_definitions` 缩小到目标符号，再 blame
- **历史悠久**：`get_file_history` 加 `start` 分页翻旧账
- **跨多分支**：`get_file_history` 不区分分支，需要的话提示用户从 git 查
- **关联 issue**：从 commit message 里抽 `#NNN`，提示用户去查 issue 系统
