---
name: onboarding-tutor
description: 当用户是新成员 / 临时支援 / 面试候选人，需要快速建立对 OpenGrok 项目的整体认知时加载。本 skill 把"看仓库地图"做成一堂引导课：从目录结构到关键类，从模块边界到代码规范。
---

# onboarding-tutor

> "我刚加入团队，给我讲讲 OpenGrok"、
> "我是新来的 SRE，需要快速看懂 opengrok-indexer"、
> "我要面试这家公司，先给我一个全局视角"——
> 本 skill 是「仓库导览」skill，给新人一个 30-60 分钟可读完的
> 入门指南。

## 适用场景

匹配以下用户原话之一时优先加载：

- 「我是新来的，给我讲讲这个项目」
- 「我想快速看懂 OpenGrok 的架构」
- 「面试准备：介绍下 opengrok-web 的核心模块」
- 「临时支援 opengrok-indexer，给我一个 high-level 视角」
- 「新人 onboarding，给我列必读文件」

## 不适用场景

- **查询具体某个方法实现** → 用 `code-investigator`
- **追查代码历史 / blame** → 用 `git-archaeologist`
- **跨项目符号追踪** → 用 `symbol-tracker`
- **修 bug / 改代码** → 用 `bulk-refactor`（写）
- **仓库运维** → 用 `repo-operator`（写）

## 前置条件

- **不需要写工具**。
- 建议用户指定一个**目标项目**（否则会跨所有项目，规模过大）。

## 工作流

### 阶段 1 — 项目地图

调 `list_projects` 让用户先选目标项目（如果他还没选的话）：

```
OpenGrok 当前注册的项目：
1. opengrok-indexer — 后端索引引擎（Java）
2. opengrok-web — Web UI（Java + JSP）
3. suggester — 自动补全服务（Java）
4. plugins — 插件系统
5. distribution — 打包与分发
6. tools — 构建脚本
7. dev — 开发辅助

你想了解哪个？
```

### 阶段 2 — 顶层目录结构

对目标项目，调 `list_directory` 顶层：

```
调 list_directory
  path=""   ← 空字符串表示根
  → 拿到顶层目录 + 文件列表
```

按这个模板整理：

```
# <项目名> 顶层目录

| 路径 | 类型 | 一句话说明 |
|---|---|---|
| src/main/java | 目录 | 业务代码 |
| src/main/webapp | 目录 | Web 资源（JSP / 静态文件） |
| src/test/java | 目录 | 测试代码 |
| pom.xml | 文件 | Maven 配置 |
| README.md | 文件 | 项目说明 |
| docs/ | 目录 | 文档 |
```

### 阶段 3 — 核心包结构

调 `list_directory` 深入到 `src/main/java/<组织域名>/...`：

```
调 list_directory
  path="src/main/java/org/opengrok"
  → 拿到所有一级包
```

每个一级包都点进去看 `list_directory`：

```
调 list_directory
  path="src/main/java/org/opengrok/web"
  → Web 层
```

按这个模板整理：

```
## 包结构

- `org.opengrok.index` — 索引核心（Indexer、IndexDatabase、Lucene wrapper）
- `org.opengrok.search` — 搜索核心（QueryBuilder、HitCollector）
- `org.opengrok.web` — Web 层（Servlet、Controller、JSP 标签）
- `org.opengrok.analysis` — 语言分析器（Java、Python、JS、C/C++...）
- `org.opengrok.history` — SCM 历史（Git、SVN、Mercurial 适配）
- `org.opengrok.config` — 配置加载和持久化
- `org.opengrok.tools` — 独立命令行工具
```

### 阶段 4 — 关键类清单

调 `get_file_definitions` **对核心目录批量调用**（一次只取一个文件），
先按 `search_code type=def` 找到每个包里的"门面类"（名字最像包名的类）：

```
# 比如要找 index 包的入口
调 search_code
  type=def
  query="class Indexer"
  projects=[<目标项目>]

# 拿到 Indexer.java 路径后
调 get_file_definitions
  path=".../Indexer.java"
  → 拿到所有 public 方法
```

整理成"门面类速查表"：

```
## 关键类速查

| 类名 | 包 | 职责 | 关键方法 |
|---|---|---|---|
| `Indexer` | org.opengrok.index | 索引入口 | `indexProjects()`、`update()` |
| `SearchHelper` | org.opengrok.search | 搜索执行 | `search()`、`executeQuery()` |
| `WebappListener` | org.opengrok.web | 启动钩子 | `contextInitialized()` |
| `Configuration` | org.opengrok.config | 配置 | `registerProject()`、`getProjects()` |
| `Repository` | org.opengrok.history | SCM 抽象 | `getHistory()`、`createHistory()` |
```

### 阶段 5 — 代码规范与约定

调 `search_code` 看一些约定俗成的写法：

```
调 search_code
  type=full
  query="@deprecated"
  projects=[<项目>]
  maxresults=20
  → 看看哪些旧 API 被标记

调 search_code
  type=full
  query="System.out.println"
  projects=[<项目>]
  → 排查是否有直接用 println 而不用 logger 的违规写法
```

### 阶段 6 — 必读文件清单

按重要性排序：

```
## 必读文件清单（按推荐顺序）

1. **README.md**（5 分钟）
   - 项目目标和一句话描述

2. **顶层 pom.xml**（10 分钟）
   - 依赖、模块划分、构建目标

3. **src/main/java/<pkg>/<MainClass>.java**（30 分钟）
   - 入口类，跟一遍主流程

4. **docs/architecture.md** 或类似（30 分钟）
   - 如果有架构图必读

5. **src/test/java/** 一个典型测试（20 分钟）
   - 了解测试风格和覆盖率期望
```

### 阶段 7 — 输出新人指南

按下面这个长模板输出（用户可以保存到 onboarding 文档）：

```
# OpenGrok <项目名> 新人指南

> 编写时间：2025-02-15
> 适合对象：刚加入团队的工程师
> 预计阅读时长：60 分钟

## 1. 一句话定位
<用一句话讲清楚这个项目是干嘛的>

## 2. 架构图（文字版）
```
[外部请求] → [Web 层] → [搜索核心] → [Lucene 索引]
                  ↓
              [配置中心] ← [文件系统 + SCM]
                  ↓
              [Indexer]（后台异步）
```

## 3. 顶层目录
| 路径 | 作用 |
|---|---|
| ... | ... |

## 4. 核心包结构
- `pkg1` — 负责 XXX
- `pkg2` — 负责 YYY

## 5. 关键类速查
| 类名 | 职责 | 何时读 |
|---|---|---|
| `A` | ... | 修改 X 功能时 |
| `B` | ... | 添加新 Y 时 |

## 6. 必读文件清单
1. README.md
2. pom.xml
3. ...

## 7. 代码规范
- 用 SLF4J + JDK logger，不允许 `System.out.println`
- 公共 API 必须有 javadoc
- 提交前跑 `mvn verify`，覆盖率不能降

## 8. 第一次上手任务建议
- 找一个 good-first-issue 标签的 ticket
- 或：在测试套件里挑一个跳过/失败的测试，修一下
- 或：跑一遍 `Indexer.indexProjects()` 看日志，验证本地环境

## 9. 常见问题
- Q: 索引为什么这么慢？
  A: 看 `IndexerConfig` 里的 `max内存` / `线程数` 设置
- Q: 搜索结果不对？
  A: 先确认项目已 `list_indexed_projects` 是 indexed 状态
- Q: 怎么新增一个语言分析器？
  A: 实现 `AnalyzerGuru` 接口，参考 `JavaAnalyzer`

## 10. 找人问问题
- Web 相关：@alice
- 索引核心：@bob
- 配置/部署：@charlie
```

## 示例对话

### 示例 1：纯新人视角

**用户**：我刚加入 OpenGrok 团队，给我讲讲 opengrok-web 是干嘛的。

**模型动作**：
1. 加载本 skill
2. 调 `list_projects` 确认 `opengrok-web` 存在
3. 调 `list_directory`，`path=""` 拿到顶层
4. 深入 `src/main/java/org/opengrok/web`
5. 调 `get_file_definitions` 看几个核心 Servlet / Listener
6. 输出新人指南

### 示例 2：面试候选人视角

**用户**：我要面试 OpenGrok，给我一个 30 分钟的 high-level 介绍。

**模型动作**：
1. 同上，但**精简输出**：
   - 一句话定位
   - 文字版架构图
   - 5 个最核心的类
   - 不展开细节，让候选人自己追问

### 示例 3：临时支援 SRE

**用户**：我下周临时支援 opengrok-indexer 维护，给我看运维视角的关键类。

**模型动作**：
1. 加载本 skill，但**聚焦运维相关类**：
   - 调 `search_code`，`type=def`, `query="Indexer"`
   - 调 `search_code`，`type=def`, `query="Config"`
   - 调 `search_code`，`type=def`, `query="IndexerException"` 找错误处理
2. 输出"运维视角"特别版：
   - 索引生命周期
   - 常见错误和恢复手段
   - 监控指标
   - 日志路径

## 错误处理

| 工具返回 | 模型应做的事 |
|---|---|
| 项目不在 `list_projects` | 提示用户该项目可能没在 OpenGrok 注册 |
| `list_directory` 返回空 | 项目可能没建索引，建议 `list_indexed_projects` |
| `get_file_definitions` 返回空 | 用 `search_code type=def` 重新找关键类路径 |
| 用户没指定项目 | 列出所有项目让用户挑 |

## 自检清单

- [ ] 我有没有先**列出项目**让用户选目标？
- [ ] 我有没有按"顶层 → 包 → 类"三层递进，而不是一上来就 dump 类清单？
- [ ] 我有没有给新人**第一次上手任务**（不只是被动阅读）？
- [ ] 我有没有留**找人问问题**的指引？（AI 不能替代团队 buddy）

## 修改建议

- **大项目**：分多次引导，每次聚焦一个子系统
- **多语言项目**：可加 language-specific 章节（如 Java vs C++ 风格差异）
- **历史悠久的项目**：补"已知技术债清单"章节（用 `search_code type=full` 搜 `@Deprecated`）
- **跨项目**：在新手指南末尾给一个"上下游依赖关系图"
