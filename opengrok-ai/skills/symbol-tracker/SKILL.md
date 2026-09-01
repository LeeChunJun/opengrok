---
name: symbol-tracker
description: 当用户需要查找某个类、方法、常量在多个项目里的所有出现位置，或评估改动影响面时加载。典型场景：API 重命名前的影响分析、删除工具方法前的安全审查、追踪某个错误码的全链路使用。
---

# symbol-tracker

> "这个类在哪些项目里被用到了？"、"把 `FooService` 改成 `BarService`
> 影响大吗？"、"项目 X 里有没有用 `javax.xml.bind`？"——
> 本 skill 把「跨项目符号追踪」做成一个可重复的工作流。

## 适用场景

匹配以下用户原话之一时优先加载：

- 「`OrderRepository` 在哪些项目里被 import 了」
- 「如果我把 `getUserById` 改成 `findUser`，影响哪些调用方」
- 「项目 `legacy-portal` 用没用过我们新的 `PaymentClient`」
- 「`IllegalStateException` 在我们整个代码库里抛出最多的是哪几处」
- 「我们的 SDK 在客户的 codebase 里被怎么用的」

## 不适用场景

- **理解单个文件 / 函数** → 用 `code-investigator`
- **某行代码的修改历史 / blame** → 用 `git-archaeologist`
- **整体 review PR** → 用 `pr-review-assistant`

## 前置条件

- **不需要写工具**。
- 建议 `projects` 列表已通过 `list_projects` 取过一次缓存（避免每
  次调用都拉一遍）。
- 如果跨 5 个以上项目，把 `maxresults` 显式调高（比如 200），否则
  OpenGrok 默认只返回前 25 条。

## 工作流

### 阶段 1 — 决定搜索范围

判断用户是想**全局**还是**指定子集**：

| 用户原话 | 行为 |
|---|---|
| "在所有项目里找 ..." | `projects=[]`（不传，由 OpenGrok 跨所有项目搜） |
| "在 opengrok-web 和 opengrok-indexer 里找 ..." | `projects=["opengrok-web","opengrok-indexer"]` |
| "在我们 SDK 里找 ..." | 先 `search_code` 的 `type=def` 找 SDK 的项目名，再限定 |

### 阶段 2 — 选择搜索类型

| 目标 | `type` | 例子 |
|---|---|---|
| 类 / 方法 / 变量定义 | `def` | 找 `OrderService` 类的所有定义 |
| 引用（import、调用、注释里出现） | `symbol` | 找所有 `OrderService.` 出现的位置 |
| 完整文本（含注释、字符串） | `full` | 找 `IllegalStateException` 的所有抛出点 |
| 路径名匹配 | `path` | 找所有路径里含 `OrderService` 的文件 |

**经验法则**：

- 想找**所有定义** → `def`
- 想找**所有引用** → `symbol`
- 想找**字符串 / 注释里**的提及 → `full`

### 阶段 3 — 主搜索

```
调用 search_code
  参数:
    type=<def | symbol | full | path>
    query=<用户提供的符号>
    projects=<阶段 1 决定的列表>
    maxresults=200
    sort=relevancy
```

### 阶段 4 — 结果聚合

按"项目 → 文件 → 行号"三层聚合：

```
返回示例：
{
  "results": [
    { "project": "opengrok-web",     "path": ".../OrderController.java", "line": 42 },
    { "project": "opengrok-indexer", "path": ".../OrderIndexer.java",    "line": 17 },
    { "project": "opengrok-tools",   "path": ".../OrderMigration.java",  "line": 88 }
  ]
}
```

整理成表格：

| 项目 | 文件 | 行号 |
|---|---|---|
| opengrok-web | src/.../OrderController.java | 42 |
| opengrok-indexer | src/.../OrderIndexer.java | 17 |
| opengrok-tools | src/.../OrderMigration.java | 88 |

**总计 N 个项目，M 处使用**

### 阶段 5 — 影响面分析

根据聚合结果回答用户的「改/删/统计」问题：

- **删除前**：先 grep `def` 找到定义点；再 grep `symbol` 找引用点；
  引用数 = 0 才安全。
- **重命名前**：先 grep `symbol` 找所有引用；用户给出新名后再考虑
  批量改名（用 `bulk-refactor` 实际执行）。
- **统计热门符号**：grep `full` 后用模型自带的频率统计。

## 示例对话

### 示例 1：API 重命名前的影响分析

**用户**：我们想把 `PaymentClient.charge()` 改名为 `PaymentClient.pay()`，
影响面有多大？

**模型动作**：
1. 调用 `list_projects` → 假设拿到 12 个项目
2. 调用 `search_code`：
   - `type=symbol`, `query=PaymentClient.charge`,
     `projects=[]`, `maxresults=200`
3. 拿到 47 条结果，聚合到 6 个项目里
4. 调用 `search_code`（type=`def`, query=`PaymentClient`）确认定义点
5. 回答：47 处调用、6 个项目，分布如下表

**输出**（节选）：
```
## 影响面分析：`PaymentClient.charge` → `PaymentClient.pay`

| 项目 | 调用点 |
|---|---|
| opengrok-web | 12 |
| opengrok-tools | 8 |
| billing-service | 15 |
| partner-portal | 6 |
| internal-tools | 4 |
| sdk-java | 2 |

**总计 47 处调用，分布于 6 个项目。**

建议操作顺序：
1. 先改 SDK（sdk-java），发布 0.2.0
2. 再改 billing-service 等 4 个内部服务，一次性跑全量回归
3. 最后改 partner-portal（外部 API，谨慎）

是否需要我接着执行批量改名？可加载 `bulk-refactor` skill。
```

### 示例 2：删除前安全审查

**用户**：我们想删掉 `LegacyEncoder` 这个类，安全吗？

**模型动作**：
1. 先 `search_code`，`type=def`, `query=LegacyEncoder` 确认所有定义点
2. 再 `search_code`，`type=symbol`, `query=LegacyEncoder` 找所有引用
3. 引用数 = 0 才回报"安全"，否则列出所有引用点

**输出**：
```
## LegacyEncoder 引用统计

- 定义点：2 处（`legacy-common/.../LegacyEncoder.java`、`legacy-api/.../LegacyEncoder.java`）
- 引用点：**3 处**，详见下表

| 项目 | 文件 | 行号 |
|---|---|---|
| billing-service | src/main/.../BillEncoder.java | 88 |
| archive-tool | src/main/.../ArchiveRunner.java | 41 |
| integration-tests | src/test/.../LegacyIT.java | 102 |

**结论：暂不建议直接删除。**引用点集中在 3 个外部项目，需要先
清理调用方。
```

## 错误处理

| 工具返回 | 模型应做的事 |
|---|---|
| `results` 数组为空 | 提示"OpenGrok 索引里没找到，可能项目还没建索引"，建议用 `list_indexed_projects` 确认 |
| `maxresults` 触顶 | 提示用户"当前只看前 200 条"，建议提高上限或缩小 `projects` 范围 |
| 跨项目搜索很慢 | 提示用户耐心等待，或拆成多次按项目搜 |

## 自检清单

- [ ] 我有没有先调用 `list_projects` 决定搜索范围？
- [ ] 我用的 `type` 是不是用户**实际意图**对应的（def / symbol / full）？
- [ ] 我有没有把结果按"项目 → 文件 → 行号"聚合，而不是直接 dump？
- [ ] 我的回答是否给了**总数 + 分布**这两个汇总指标？

## 修改建议

- **大量符号**：把 `maxresults` 调到 500+ 并提醒用户分页
- **语言敏感**：Java 用 `def` / `symbol` 准确；Python / JS 用 `full` 更稳
- **SDK 兼容性查询**：可结合 `get_popularity` 找出哪些 API 最热门
