# OpenGrok Skills 集合

> 面向 LLM/Agent 的「工作流脚本」，告诉模型**怎么**调用 `opengrok-mcp`
> 的 30 个工具来完成特定任务。
>
> 本目录遵循 OpenAI / Claude Skills 规范：每个 skill 是一个目录，
> 入口为 `SKILL.md`，文件头是 YAML frontmatter（`name` + `description`）。

---

## 目录结构

```
skills/
├── README.md                       # 本文件：索引 + 加载说明
├── code-investigator/SKILL.md      # 1. 看懂一段代码
├── symbol-tracker/SKILL.md         # 2. 跨项目追踪符号
├── git-archaeologist/SKILL.md      # 3. blame + 历史考古
├── pr-review-assistant/SKILL.md    # 4. PR 审查辅助
├── bulk-refactor/SKILL.md          # 5. 批量重构（写）
├── repo-operator/SKILL.md          # 6. 仓库运营（写）
├── incident-responder/SKILL.md     # 7. 线上事件定位
└── onboarding-tutor/SKILL.md       # 8. 新成员上手
```

## Skill 速查表

| Skill | 一句话定位 | 是否需要写工具 | 前置 Skill |
|---|---|:---:|---|
| `code-investigator` | "帮我看懂这段代码是怎么工作的" | ❌ | — |
| `symbol-tracker` | "这个 API 在哪些项目里被用到" | ❌ | — |
| `git-archaeologist` | "这行代码谁改的？当时为什么？" | ❌ | — |
| `pr-review-assistant` | "帮我 review 这个 PR" | ❌ | code-investigator |
| `bulk-refactor` | "把所有项目里的 X 描述统一改成 Y" | ✅ | code-investigator |
| `repo-operator` | "新建一个项目 / 重建索引 / 广播通知" | ✅ | — |
| `incident-responder` | "线上报错，找到底是哪次改动引入的" | ❌ | git-archaeologist |
| `onboarding-tutor` | "我刚加入团队，给我讲讲这个仓库" | ❌ | — |

## 写工具前置条件

涉及「写」的 skill（`bulk-refactor`、`repo-operator`）会调用
`add_project` / `delete_project_data` / `load_path_descriptions` /
`add_message` / `rebuild_suggester_index` 等破坏性工具。

要让这些 skill 真正生效，**`opengrok-mcp` 启动时必须设置**：

```bash
ENABLE_WRITE_TOOLS=true
```

否则这些 skill 在工具列表里根本看不到对应工具，会进入「只读退化
模式」并在 SKILL.md 中显式提示用户。

## 如何被 MCP 客户端加载

不同客户端加载 skill 的方式不同，下面给出三种主流用法。

### Claude Desktop（推荐）

Claude Desktop **当前版本不支持第三方 skill 目录**，但你仍可以
把整个 `SKILL.md` 内容粘进对话 / Project Knowledge，让模型把它
当作 system prompt 使用。

进阶做法：用 [Claude Code](https://docs.claude.com/en/docs/claude-code)
的 `/skill` 命令加载本目录——把下面这段加进 `~/.claude/CLAUDE.md`：

```markdown
## 可用 Skills
当用户提出与代码搜索 / 仓库运营相关的问题时，按需加载以下 skill：
- 代码理解：skills/code-investigator/SKILL.md
- 符号追踪：skills/symbol-tracker/SKILL.md
- 仓库考古：skills/git-archaeologist/SKILL.md
- PR 审查：skills/pr-review-assistant/SKILL.md
- 批量重构：skills/bulk-refactor/SKILL.md
- 仓库运营：skills/repo-operator/SKILL.md
- 事件定位：skills/incident-responder/SKILL.md
- 新人上手：skills/onboarding-tutor/SKILL.md
```

### Continue（VS Code / JetBrains）

`~/.continue/config.json` 的 `system` 字段：

```json
{
  "system": [
    "你是 OpenGrok 代码检索助手。",
    "下面是 8 个 skill 的入口，按需加载：",
    "--- code-investigator ---", "<(cat skills/code-investigator/SKILL.md)>",
    "--- symbol-tracker ---",    "<(cat skills/symbol-tracker/SKILL.md)>",
    "..."
  ]
}
```

### Cursor

`Settings → Rules for AI` 添加指向本目录的规则：

```
阅读以下 skill 文件，根据用户问题加载对应章节：
- D:/AppsData/deploy/opengrok/opengrok-ai/skills/README.md
- D:/AppsData/deploy/opengrok/opengrok-ai/skills/<skill-name>/SKILL.md
```

## 如何新增 / 修改 skill

每个 skill 只有一个文件：`skills/<skill-name>/SKILL.md`，结构如下：

```markdown
---
name: my-skill                    # skill 标识，文件名同
description: <一行话描述>         # LLM 用于判断何时加载
---

# 我的 Skill

## 适用场景
> 列举 3-5 个用户原话风格的问题描述

## 不适用场景
> 明确边界，避免误用

## 前置条件
- 需要的 MCP 工具 / 写开关 / 数据前置

## 工作流（步骤化）
1. 第 1 步：调用 XXX 工具，参数 XXX
2. 第 2 步：根据返回值决定 ...
3. ...

## 示例对话

### 示例 1
**用户**：...
**模型动作**：
1. 调用 `list_projects`
2. ...
**输出**：...

## 错误处理
- 当工具返回 401 时：...
- 当工具返回 404 时：...

## 自检清单（模型加载本 skill 后应自检）
- [ ] 我理解了这个 skill 的适用边界吗？
- [ ] 我准备好需要的写开关了吗？
```

每次新增 skill 后，跑一遍下面这个简单的校验：

```bash
# 校验所有 SKILL.md 都有合法 frontmatter
ls skills/*/SKILL.md | while read f; do
  head -1 "$f" | grep -q '^---$' || { echo "MISSING frontmatter: $f"; exit 1; }
  grep -q '^name:' "$f" || { echo "MISSING name: $f"; exit 1; }
  grep -q '^description:' "$f" || { echo "MISSING description: $f"; exit 1; }
done
echo "OK: all $(ls skills | wc -l) skills have valid frontmatter"
```

## License

MIT
