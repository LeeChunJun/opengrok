---
name: incident-responder
description: 当用户描述一个线上事件 / bug / 故障，需要快速定位根因时加载。综合 git-archaeologist（追溯变更）、code-investigator（理解代码）、symbol-tracker（追踪调用链）的能力，把「报错日志 → 代码 → 历史变更 → 根因」串成一条流水线。
---

# incident-responder

> "线上报错 `NullPointerException at Foo.bar:88`，昨晚 8 点开始的，
> 帮我定位根因"、
> "接口超时，从 14:30 开始所有请求都 500，是不是刚刚的部署有问题"、
> "用户报 `IllegalArgumentException` 频繁出现，帮我看看是什么场景触发的"——
> 本 skill 把"事件响应"做成一组可重复的诊断流程。

## 适用场景

匹配以下用户原话之一时优先加载：

- 「线上报错 X，找根因」
- 「从某时间点开始接口 Y 异常，帮我看看改了啥」
- 「某个 issue 复现不出来，帮我查代码逻辑」
- 「生产环境报 `OOM` / `StackOverflow`，可能是什么导致的」
- 「错误日志里有个奇怪的字符串，从代码里找一下来源」

## 不适用场景

- **理解代码但不紧急** → 用 `code-investigator`
- **代码 review** → 用 `pr-review-assistant`
- **修改代码修复 bug** → 用 `bulk-refactor`（写）
- **仓库运维** → 用 `repo-operator`（写）

## 前置条件

- **不需要写工具**。
- 用户最好能提供以下信息：

| 信息 | 必要 | 说明 |
|---|---|:---:|
| 错误信息（异常类、消息） | ✅ | 越具体越好 |
| 报错时间范围 | ❌ | 有的话能极大缩小范围 |
| 报错文件:行号（如果日志里有） | ❌ | 有的话直接定位 |
| 相关项目名 | ❌ | 不提供会全项目搜索，慢 |

## 工作流

### 阶段 1 — 收集证据

向用户要（或从已有上下文提取）：

```
1. 错误信息：`NullPointerException at FooService.bar:88`
2. 时间：2025-02-15 20:00 - 20:30 之间首次出现
3. 项目：billing-service（用户已知）
4. 频率：每分钟 ~50 次
```

### 阶段 2 — 定位代码

如果用户给了文件:行号：

```
调 get_file_definitions
  path=<文件>
  → 找到 bar 方法

调 get_file_content
  path=<文件>
  → 读全文，重点看 line 88 附近 30 行
```

否则用 `search_code`：

```
调 search_code
  type=def
  query=<错误信息中的类名>
  projects=[<用户给的项目>]
```

### 阶段 3 — 分析可疑变更（git-archaeologist 复用）

**重点**：线上事件的最大嫌疑是「最近一次改动」。按下面顺序查：

```
1. 调 get_file_history
     path=<出错文件>
     withFiles=true
     max=20
     start=0
   → 列出最近 20 次提交

2. 用模型自身过滤：在报错时间窗内（或报错前最近 1 周内）的提交
3. 对每个可疑 commit，调 annotate_file 拿到出错行的 blame
```

如果可疑 commit 涉及**其它文件**（用 `withFiles=true` 看），也
要读一下那些文件：

```
调 search_code
  type=full
  query=<可疑 commit message 里的关键术语>
  projects=[<项目>]
  → 找出同一次变更涉及的所有文件
```

### 阶段 4 — 检查错误消息广播

OpenGrok 自己会广播一些系统消息，可能与事件相关：

```
调 get_messages
  tag=<可选，比如 "incident" / "deploy">
  → 看是否有相关公告
```

### 阶段 5 — 影响面评估（symbol-tracker 复用）

如果 root cause 是某个方法被改签名/被删：

```
调 search_code
  type=symbol
  query=<被改动的符号>
  projects=[]
  maxresults=200
  → 所有调用方是否都已报错？
```

### 阶段 6 — 输出事件响应报告

按这个模板输出：

```
# Incident Response Report

## 事件概要
- **时间**：2025-02-15 20:00 - 至今
- **错误**：`NullPointerException at FooService.bar:88`
- **频率**：~50 次/分钟
- **影响范围**：billing-service 所有调用方（待 symbol-tracker 确认）

## 时间线
| 时间 | 事件 |
|---|---|
| 2025-02-10 | alice 合并 PR #1234，重构了 FooService |
| 2025-02-15 19:45 | 生产部署 v2.3.1 |
| 2025-02-15 20:00 | 监控告警：错误率突增 |
| 2025-02-15 20:30 | 工程师开始排查 |

## 可疑变更
### Commit abc1234（2025-02-10, alice）
```
重构 FooService.bar，新增 null check 但漏了一个分支
```

### 关键证据
- `FooService.java:88` 由本次 commit 改动
- `annotate_file` 显示该行在 2025-02-10 由 alice 修改
- 旧版本（v2.3.0）该行是直接 `payment.getRefundId()`，新版本包了
  if 判断但漏了 `else` 分支

## 根因分析
PR #1234 重构 `bar` 方法时，新增的 null check 不完整：

```java
// v2.3.0 (旧)
String refundId = payment.getRefundId();  // 可能 null
process(refundId);

// v2.3.1 (新)
if (payment != null) {
    String refundId = payment.getRefundId();
    process(refundId);  // ← refundId 仍可能 null
}
```

当 `payment != null` 但 `payment.getRefundId() == null` 时，
`process()` 内部直接调用 `refundId.length()` 抛 NPE。

## 修复建议
1. 在 `process()` 入口加 null 检查（推荐，影响小）
2. 或在 `bar` 方法里把 `payment.getRefundId()` 也包一层 null check
3. 加单元测试覆盖：`payment != null && refundId == null` 场景

## 验证
- 修复后，跑回归测试套件
- 灰度发布 1% 流量观察 30 分钟
- 监控错误率回到基线

## 后续行动
- [ ] 联系 alice 复盘 PR #1234
- [ ] 给 `process()` 加 `@NonNull` 注解 + Checker 框架
- [ ] 在 CI 加静态检查：捕获 `getXxx()` 后未 null check 的链式调用
```

## 示例对话

### 示例 1：从异常名直接定位

**用户**：线上频繁 `IllegalArgumentException: invalid foo`，最近 24
小时开始的。

**模型动作**：
1. 调 `search_code`，`type=full`, `query="invalid foo"` 全项目搜
   → 找到抛出点 `FooService.java:42`
2. 调 `annotate_file`，看 line 42 的 blame
3. 调 `get_file_history`，`path=FooService.java`, `max=20` 看变更
4. 发现昨天 alice 合并了一个校验逻辑改动，把阈值从 10 改成了 5
5. 输出报告

### 示例 2：从时间点反推

**用户**：14:30 之后所有 `/api/order/create` 都超时。

**模型动作**：
1. 调 `search_code`，`type=def`, `query=createOrder` 找代码
2. 调 `get_file_history`，`path=...`, `withFiles=true`, `max=10`
3. 看 14:00-14:30 之间的提交
4. 找到 bob 在 13:55 合并的 PR，加了一个外部 HTTP 调用但没设超时
5. 输出报告

### 示例 3：错误字符串溯源

**用户**：日志里出现 `"cache_miss_for_key_xyz"`，从代码里找一下
是哪里打的。

**模型动作**：
1. 调 `search_code`，`type=full`, `query="cache_miss_for_key_xyz"`
   → 找到 logger.error 调用
2. 调 `get_file_content` 读上下文
3. 调 `get_file_history` 看这个 logger 是何时加的
4. 输出报告

## 错误处理

| 工具返回 | 模型应做的事 |
|---|---|
| `search_code` 找不到错误信息中的类 | 在 `search_code` 里换 `type=full` 或扩大 `projects` |
| 多个可疑 commit（>=3 个） | 不要瞎猜，先列出所有可疑点给用户看 |
| `annotate_file` 返回空 | 项目可能没建索引，建议 `list_indexed_projects` 确认 |
| `get_file_history` 数据太多 | 用 `start`/`max` 分页，先看最近 20 条 |

## 自检清单

- [ ] 我有没有要用户提供**报错时间**？（事件响应的核心是缩小时间窗）
- [ ] 我有没有**先看最近变更**再去看代码逻辑？（80% 的事件是最近改动引入的）
- [ ] 我有没有给出**修复建议**而不是只诊断？
- [ ] 我有没有提醒用户**人工验证**（单元测试 / 灰度）？

## 修改建议

- **多服务架构**：先调 `symbol-tracker` 找调用链，再决定看哪边的代码
- **频繁事件**：考虑接入 OpenGrok 的 `get_messages` 看是否有相关公告
- **关联告警**：把监控系统的告警 ID 一并写进报告，便于复盘
- **跨项目影响**：用 `symbol-tracker` 评估影响面，避免"修了 A 坏 B"
