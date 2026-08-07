# OpenGrok Web UI 重构计划

## 一、总体目标

将 `opengrok-web/docs/ui/` 中的新版 UI 设计（静态 HTML 模板）落地到实际的 JSP 技术栈中，覆盖 `opengrok-web/src/main/webapp/` 下的 JSP/JSPF/Tag 文件。本次重构采用**渐进式、按页面分阶段**实施：每完成一个页面就验收一次，验收失败立即回滚并记录原因。

## 二、新旧文件映射

| 新 UI 设计（参考） | 现有 JSP 实现 | 状态 |
| --- | --- | --- |
| `docs/ui/index.html` | `src/main/webapp/index.jsp` + `menu.jspf` + `repos.jspf` | 待重构 |
| `docs/ui/code-view.html` | `src/main/webapp/list.jsp` + `mast.jsp` + `xref.jspf` + `tags/repositories.tag` + `tags/repository.tag` + `tags/projects.tag` + `tags/project.tag` | 待重构 |
| `docs/ui/directory-history.html` | `src/main/webapp/history.jsp` + `minisearch.jspf` | 待重构 |
| `docs/ui/directory-view.html` | `src/main/webapp/list.jsp`（目录列表分支） | 待重构 |
| `docs/ui/file-diff-detail.html` | `src/main/webapp/diff.jsp` | 待重构 |
| `docs/ui/file-history-diff.html` | `src/main/webapp/diff.jsp`（历史对比） | 待重构 |
| （无新设计） | `src/main/webapp/search.jsp` | 保持现有 |
| （无新设计） | `src/main/webapp/more.jsp` | 保持现有 |
| （无新设计） | `src/main/webapp/help.jsp` | 保持现有 |
| （无新设计） | `src/main/webapp/settings.jsp` | 保持现有 |
| （无新设计） | `src/main/webapp/status.jsp` | 保持现有 |
| （无新设计） | `src/main/webapp/error.jsp` / `eforbidden.jsp` / `enoent.jsp` | 保持现有 |
| （无新设计） | `src/main/webapp/opensearch.jsp` / `rss.jsp` | 保持现有 |

## 三、共享层文件

| 共享文件 | 用途 | 重构策略 |
| --- | --- | --- |
| `src/main/webapp/httpheader.jspf` | HTML `<head>` 生成器（含 CSS/JS 注入） | **保持现有**，第一阶段不引入新 CSS 文件以避免影响其他页面。后续阶段考虑新增 `default/style-2.0.0.min.css` 并由 `httpheader.jspf` 加载。 |
| `src/main/webapp/pageheader.jspf` | 站点页头（Logo + 自定义 include） | 第一阶段在 `index.jsp` 内联新 Logo + 标题，不修改 `pageheader.jspf` |
| `src/main/webapp/foot.jspf` | 站点页脚 + 脚本注入 + HTML 闭合 | 第一阶段 `index.jsp` 不引入 `foot.jspf`，由 `index.jsp` 自闭合 `<body></html>` 并手动注入 `PageConfig.getScripts()` |
| `src/main/webapp/projects.jspf` | 项目 Cookie 持久化 | 必须在 `index.jsp` 顶部 `<%@ include %>` 保留（功能需要） |
| `src/main/webapp/menu.jspf` | 完整搜索表单（旧 UI） | **第一阶段不修改**。`index.jsp` 改为内联新搜索表单，避免破坏其他可能的引用 |
| `src/main/webapp/repos.jspf` | 仓库面板（旧 UI） | **第一阶段不修改**。`index.jsp` 改为内联新仓库卡片网格 |
| `src/main/webapp/WEB-INF/tags/*.tag` | 自定义 JSP Tag | 后续阶段使用 |

## 四、执行顺序（迭代交付）

1. **第一阶段：index.jsp**
   - 改造 `index.jsp` 应用 `docs/ui/index.html` 设计
   - 内联新 CSS（`<style>` 块）+ 新 JS（`<script>` 块）
   - 内联搜索表单 + 项目 chips + 仓库卡片网格
   - 验收：浏览器访问首页，UI 与新设计一致；搜索表单提交后能正确跳转到 search.jsp
2. **第二阶段：list.jsp（含 xref.jspf、mast.jsp、tags）**
   - 对应 `docs/ui/code-view.html` + `docs/ui/directory-view.html`
3. **第三阶段：history.jsp + minisearch.jspf**
   - 对应 `docs/ui/directory-history.html`
4. **第四阶段：diff.jsp**
   - 对应 `docs/ui/file-diff-detail.html` + `docs/ui/file-history-diff.html`
5. **第五阶段：共享层重构**
   - 把内联的新 CSS 抽离为 `default/style-2.0.0.css`，由 `httpheader.jspf` 加载
   - 重写 `pageheader.jspf` 渲染新 Logo 头
   - 重新评估 `menu.jspf` / `repos.jspf` 的去留

## 五、每轮修改记录（追加）

> 每次执行修改前必须先向用户说明改动点；执行后等待验收；验收通过则在本节追加 ✅ 条目，失败则追加 ❌ 条目并立即回滚（用 `git checkout` 或手工还原）。

### 修改 #1 — index.jsp 重构为新版 UI（首页）

- **计划日期**：2026-08-06
- **改动范围**：仅 `opengrok-web/src/main/webapp/index.jsp` 一个文件
- **未改动**：`httpheader.jspf`、`pageheader.jspf`、`foot.jspf`、`menu.jspf`、`repos.jspf`、`projects.jspf`、所有 tag、其他 JSP

#### 准备项（执行前已记录）
- [x] 已通读 `opengrok-web/docs/intro/{overview.md,open-grok-web-guide.md,run.md}`
- [x] 已通读 `opengrok-web/docs/ui/index.html`（新 UI 设计稿）
- [x] 已通读当前 `index.jsp` / `menu.jspf` / `repos.jspf` / `pageheader.jspf` / `foot.jspf` / `projects.jspf` / `httpheader.jspf`
- [x] 已通读 `WEB-INF/tags/{repository,repositories,project,projects}.tag`
- [x] 已确认目录与文件清单，确认 `opengrok-web/docs/plan/` 目录已创建

#### 变更点（执行前已说明，详见对话上下文）

实际写入文件后核对清单：

1. **保留 CDDL HEADER**，在原 Copyright 行后追加一行 `Portions Copyright (c) 2026, UI Refactor.`
2. **保留** `<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>` 和 `<%@ page session="false" errorPage="error.jsp" %>`
3. **新增** `<%@ page import %>` 块：`java.util.{Date,Map,Set,SortedSet}` + `org.opengrok.indexer.{Info,configuration.{Group,Project},history.RepositoryInfo,search.QueryBuilder,web.{Prefix,QueryParameters,SearchHelper,Util}}` + `org.opengrok.web.{PageConfig,ProjectHelper}`
4. **保留** `<%@ include file="/projects.jspf" %>`（Cookie 持久化功能必需）
5. **顶部脚本段**：保留 `PageConfig.get(request)` / `cfg.checkSourceRootExistence()`；`cfg.setTitle("Search")` → 改为 `cfg.setTitle("OpenGrok Code Search")`；新增 `ProjectHelper.getInstance(cfg)`、`ctxPath`、`styleDir = cfg.getCssDir()`、`QueryBuilder qb = cfg.getQueryBuilder()`、`displayRepos = cfg.getEnv().isDisplayRepositories()`、`projects = ph.getAllProjects()`、`requestedProjects = cfg.getRequestedProjects()`、`anyRequested = !requestedProjects.isEmpty()`、`selectedType = qb.getType() == null ? "" : qb.getType()`、`typeDescriptions = SearchHelper.getFileTypeDescriptions()`、`dateForLastIndexRun = cfg.getEnv().getDateForLastIndexRun()`、遍历 `ph.getGroups()` / `ph.getUngroupedProjects()` / `ph.getUngroupedRepositories()` 计算 `repoCount`
6. **移除** `<%@ include file="httpheader.jspf" %>` —— 内联 `<head>`（charset / viewport / robots / generator / theme-color / favicon / 默认 style-1.0.6.min.css / 完整新 UI CSS）
7. **移除** `<%@ include file="/pageheader.jspf" %>` —— 直接写新 `<header class="header">`（Logo SVG + "OpenGrok Code Search" 标题 + "代码浏览" 链接到 `<%=ctxPath%><%=Prefix.XREF_P%>`）
8. **移除** `<%@ include file="menu.jspf" %>` —— 在 `<section class="search-hero">` 内直接写新搜索表单 `id="sbox"`：`action="<%=ctxPath%>/search"` `method="get"`，含主搜索框 (`name=<%=QueryParameters.FULL_SEARCH_PARAM%>`) + 高级搜索按钮 + 类型筛选下拉 (`name=<%=QueryParameters.TYPE_SEARCH_PARAM%>`，从 `typeDescriptions.entrySet()` 生成 option) + 高级面板（`name=QueryParameters.{DEFS,REFS,PATH,HIST}_SEARCH_PARAM` 四个 `adv-input`）+ 隐藏多选 `<select id="project-select" name=<%=QueryParameters.PROJECT_SEARCH_PARAM%>>` 兜底提交
9. **移除** `<%@ include file="repos.jspf" %>` —— 在 `<section id="repo-section">` 内直接写新仓库卡片网格：按 `ph.getGroups()` → `ph.getProjects(g)` / `ph.getRepositories(g)` 和 `ph.getUngroupedProjects()` / `ph.getUngroupedRepositories()` 顺序遍历，每个项目渲染一个 `<a class="repo-card">`：项目名 + 类型徽章（badge-git/svn/hg/cvs/default）+ 远程 URL + 分支 + 短版本号（前 4 字符）+ "浏览 →" 链接；卡片链接 `href="<%=ctxPath%><%=Prefix.XREF_P%>/<%=Util.uriEncodePath(p.getName())%>"`
10. **保留** `<%= cfg.getEnv().getIncludeFiles().getBodyIncludeFileContent(false) %>`（在 footer 之前注入配置中的 body include）
11. **移除** `<%@ include file="/foot.jspf" %>` —— 文件末尾自闭合 `</body></html>`；新增 `<%= PageConfig.get(request).getScripts() %>` 兼容 `cfg.addScript(...)` 注册的脚本（当前为空集合，保留调用以便未来扩展）
12. **新增 `<section class="results-section">`**：保留 `docs/ui/index.html` 设计稿的占位结构（sort-bar / results-header / results-list / pagination），CSS 已内联，但**实际数据由 `search.jsp` 渲染**，本首页上的结果区默认 `display:none`
13. **新增 `<div class="footer">`**：由 OpenGrok 托管 + 最后索引更新时间 + 版本号短哈希
14. **新增内联 JS**（约 100 行）：`searchData` 占位 + chips 与隐藏 `<select>` 双向同步 `refreshProjectSelect()` + `toggleChip / selectAllProjects / invertAllProjects / deselectAllProjects` + 高级面板切换 + sort 切换 + 分页点击 + ⌘K 快捷键

未改动文件：`httpheader.jspf` / `pageheader.jspf` / `foot.jspf` / `menu.jspf` / `repos.jspf` / `projects.jspf` / `WEB-INF/tags/*.tag` / `web.xml` / 其他所有 JSP / 任何 CSS 或 JS 文件。

#### 备份点（回滚用）

| 项 | 值 |
| --- | --- |
| 修改前文件 | `opengrok-web/src/main/webapp/index.jsp`（59 行，原版） |
| 修改前 git 提交 | 当前 HEAD（执行本次修改前最新提交） |
| 修改后文件 | `opengrok-web/src/main/webapp/index.jsp`（1327 行，重构版） |
| 修改后文件大小 | 45968 字节（≈ 46 KB） |
| 修改后 git 状态 | 未提交，工作区脏（待验收后决定 `git add` / `git commit` / `git checkout`） |

#### 回滚方案（任选其一）

**方案 A —— 整文件回滚（最干净，推荐）：**
```bash
git checkout -- opengrok-web/src/main/webapp/index.jsp
```

**方案 B —— 仅撤销本次修改的提交（若已 commit）：**
```bash
git revert HEAD -- opengrok-web/src/main/webapp/index.jsp
```

**方案 C —— 手工对照本节「变更点」逐项还原：**
1. 删除 `<%@ page import %>` 新增块
2. 删除 CDDL 末尾的 `Portions Copyright (c) 2026, UI Refactor.` 行
3. 把 `cfg.setTitle("OpenGrok Code Search")` 改回 `cfg.setTitle("Search")`
4. 删除内联 `<style>` 块（CSS 700+ 行）
5. 删除 `<header class="header">` 整块
6. 删除 `<section class="search-hero">` 整块（含 `<form id="sbox">`）
7. 删除 `<section class="project-section">` 整块
8. 删除 `<section class="results-section">` 整块
9. 删除 `<% if (displayRepos && repoCount > 0) { %> ... <% } %>` 整块
10. 删除 `<div class="footer">` 整块，替换为原 `<%@ include file="/foot.jspf" %>`
11. 删除底部 `<script>` 整块（含 `refreshProjectSelect` 等）
12. 在 `<head>` 之前/之后插入 `<%@ include file="httpheader.jspf" %>`
13. 在 `<header class="header">` 处插入 `<%@ include file="/pageheader.jspf" %>`
14. 在搜索表单处插入 `<%@ include file="menu.jspf" %>`
15. 在 repo-section 处插入 `<%@ include file="repos.jspf" %>`

#### 验收结果（执行后填写）

⏳ **待用户验收**

请用户在浏览器访问首页（`/source/`），确认以下要点：

| # | 验收点 | 期望 |
| --- | --- | --- |
| 1 | 页面整体布局 | header（黑底 logo + 标题 + 代码浏览链接）+ 单列 container |
| 2 | 搜索表单 | 主搜索框 + "高级搜索" 折叠按钮 + 类型筛选下拉 |
| 3 | 高级搜索面板 | 点击"高级搜索"展开，露出定义/符号/文件路径/历史 4 个输入框 + 搜索/清除按钮 |
| 4 | 项目 chips | 显示所有已索引项目（按授权过滤），默认全选；点击切换选中；全选/反选/清除按钮工作 |
| 5 | 仓库卡片 | 显示每个项目的卡片：名称 + 类型徽章 + URL + 分支 + 短版本号 + "浏览 →" 链接 |
| 6 | 提交搜索 | 输入查询后回车 / 点搜索按钮，URL 跳到 `/search?full=...&project=...` 并显示 search.jsp 结果 |
| 7 | 代码浏览链接 | header 右上角"代码浏览"跳到 `/source/xref` |
| 8 | ⌘K / Ctrl+K | 聚焦主搜索框 |
| 9 | 页脚 | 显示 "由 OpenGrok 托管 · 最后索引更新：… · 版本号 (短哈希)" |
| 10 | Cookie 持久化 | 选择项目后刷新，项目选择保留（来自 `projects.jspf` 的 Cookie 写入） |

---

### 修复 #1a — JSP 编译错（2 类问题）

- **触发时间**：用户执行步骤二（`mvn install`）时 Jasper 报错
- **错误 1**：`typeDescriptions` 类型不匹配
  - 现象：`Type mismatch: cannot convert from Set<Map.Entry<String,String>> to Map<String,String>`（行 60）
  - 原因：`SearchHelper.getFileTypeDescriptions()` 实际返回 `Set<Map.Entry<String,String>>`，不是 `Map<String,String>`
  - 修复：把声明从 `Map<String, String> typeDescriptions = ...` 改为 `Set<Map.Entry<String, String>> typeDescriptions = ...`；遍历时从 `typeDescriptions.entrySet()` 改为直接 `typeDescriptions`（行 884）
- **错误 2**：`anyRequested` cannot be resolved（行 941、943、958）
  - 现象：后续 `<% %>` 块引用不到脚本段顶部声明的 `anyRequested`
  - 原因：原版把 setup 代码包在 `{ ... }` 大括号块里，JSP 编译后大括号就是局部作用域，块外不可见
  - 修复：把顶部 setup 段的 `{ ... }` 大括号去掉，让 `cfg / ph / ctxPath / projects / requestedProjects / anyRequested / typeDescriptions / dateForLastIndexRun / repoCount` 都在同一个 `_jspService` 方法作用域内，跨 `<% %>` 块可见
- **影响范围**：仅 `opengrok-web/src/main/webapp/index.jsp` 一处脚本段 + 一处 for 循环
- **未改动**：其他文件 / 其他变量 / 其他逻辑
- **回滚**：直接 `git checkout -- opengrok-web/src/main/webapp/index.jsp` 回到修改 #1 的版本（修复前的状态可参考修改 #1 备份点），或手工把 `{` 加回去、把 `Map<String, String>` 改回去

---

### 修复 #1b — 文件末尾多余的 `}`

- **触发时间**：修复 #1a 后用户重新构建
- **错误现象**：`Syntax error, insert "Finally" to complete TryStatement`，行 1326
- **根因**：修复 #1a 把顶部 setup 段的 `{` 删了，但文件最末尾的 `}` 忘了删，导致大括号不平衡
- **修复**：删除第 1326 行的 `}`（保留 `/* index.jsp end */` 注释和结尾 `%>`）
- **影响范围**：仅 `opengrok-web/src/main/webapp/index.jsp` 末尾 1 行
- **回滚**：手工把 `}` 加回第 1325 行（`/* index.jsp end */` 之后）

---

### 修复 #1c — 4 项 UI/功能问题

- **触发时间**：用户验收 UI 后反馈
- **修复的问题**：

| # | 问题 | 修复内容 |
| --- | --- | --- |
| 1 | 全文搜索输入框没有推荐功能 | 改 `id="full-search"` → `id="full"`（utils.js 期望的 ID）；同时给 defs/refs/path/hist 加上 `id="defs"/"refs"/"path"/"hist"`；type 也改 `id="type"`；在 setup 段加 `cfg.addScript("jquery") / ("jquery-ui") / ("utils")` 三个脚本注册；在 `<head>` 加 setup脚本（设置 `window.contextPath` 和 `document.domReady[]`）；底部 JS 末尾追加 `document.domReady.push(function(){ domReadyMenu(); })` 触发 utils.js 里的 `initAutocomplete` |
| 2 | 高级搜索按钮悬停文字变白 | CSS 加 `.ctrl-btn:hover { color: var(--fg); }` 显式锁定文字色；加 `.ctrl-btn:focus / :focus-visible` 移除默认 outline 改用柔和阴影；加 `.ctrl-btn.active:hover` 锁定 active 态文字色 |
| 3 | 搜索后无结果列表 | 重写底部 JS，加 `performInlineSearch()`：拦截 form submit，调 `/api/v1/search` (JSON)，把结果渲染到 `.results-section` 里的 `results-list`，隐藏 `#仓库section`。失败时回退到 `sbox.submit()` 跳 `/search` 页 |
| 4 | 仓库卡片高度不一致 / 边界溢出 | 抽取 helper 方法 `renderRepoCard(...)`（用 `<%! %>` 声明），把 4 段重复的内联卡片模板（groups/projects、groups/repositories、ungrouped/projects、ungrouped/repositories）替换成 4 行 helper 调用；helper 始终渲染 `.repo-card-url`（空时显示 "N/A"）和 `.repo-card-meta`，保证每张卡都有相同数量的子元素，grid 自动对齐 |

- **新加 `<head>` 片段**（line ~150）：
  ```jsp
  <script>/* <![CDATA[ */
      window.contextPath = '<%= ctxPath %>';
      document.pageReady = [];
      document.domReady = [];
  /* ]]> */</script>
  ```

- **新加 `<%! %>` helper**（line ~45）：
  ```jsp
  private void renderRepoCard(JspWriter out, PageConfig cfg, String ctxPath,
                              ProjectHelper ph, Project p) throws java.io.IOException {
      if (!p.isIndexed() || !cfg.isAllowed(p)) return;
      // …始终渲染 5 个子元素：header / url / meta / footer
  }
  ```

- **新加 adv-actions 按钮**：帮助 / 设置（与设计稿一致）

- **影响范围**：仅 `opengrok-web/src/main/webapp/index.jsp`（同一个文件）
- **回滚**：`git checkout -- opengrok-web/src/main/webapp/index.jsp` 回到修改 #1b 状态

---

### 修复 #1d — `cfg.addScript(...)` 引用顺序错

- **触发时间**：修复 #1c 后用户重新构建
- **错误现象**：`cfg cannot be resolved`（行 95–97）
- **根因**：修复 #1c 把 `cfg.addScript("jquery") / ("jquery-ui") / ("utils")` 三行加在了 `PageConfig cfg = ...` 声明的**前面**，引用顺序反了
- **修复**：把这三行挪到 `cfg.setTitle(...)` 之后、`ProjectHelper ph = ...` 之前（line 99–102）
- **影响范围**：仅 `opengrok-web/src/main/webapp/index.jsp`，3 行移动
- **回滚**：把 `cfg.addScript` 三行再挪回 `PageConfig cfg = ...` 之前即可

---

### 修复 #1e — 「任意类型」dropdown 还原为设计稿 6 选项

- **触发时间**：用户验收后反馈
- **问题**：之前 #1c 用 `SearchHelper.getFileTypeDescriptions()` 动态生成下拉项（实际有几百种），跟 `docs/ui/index.html` 设计稿（仅 6 个固定项）不一致
- **修复**：
  - 把 `<select id="type">` 里动态 `<option>` 循环改成 6 个硬编码 `<option>`，与设计稿完全一致：
    - 任意类型（value=""）
    - Java 源文件（value="Java"）
    - XML 文件（value="XML"）
    - 纯文本（value="Plain Text"）
    - 配置文件（value="Properties"）
    - 图片（value="Image"）
  - 删除不再使用的 `Set<Map.Entry<String, String>> typeDescriptions = ...` 变量和 `java.util.Map` import
- **影响范围**：仅 `opengrok-web/src/main/webapp/index.jsp` 一处
- **回滚**：把 `<option value="Java">...</option>` 等 6 个写死项改回 `<% for (Map.Entry ...) { %> ... <% } %>` 循环即可

---

### 修复 #1f — 仓库卡片顶部行样式异常（CSS Grid 拉伸 + flex 截断失效）

- **触发时间**：用户验收后反馈
- **现象**：仓库区**只有最底下一排**样式正常，上面几排异常（高矮不一、超出边界）
- **根因**：**两处 CSS 问题**叠加
  1. `.repo-card-url`（以及其它文字子项）位于 `display: flex; flex-direction: column` 容器内，flex 子项默认 `min-width: auto` → **不允许收缩到内容以下**。结果 `text-overflow: ellipsis` 失效，长 URL **强制换行**成多行，把这张卡片撑得很高。
  2. `.repo-grid` 用 `display: grid` 默认 `align-items: stretch` → **同一行所有卡片被最高的那张拉高**，短的卡底部留空，高的卡越界。
- **修复**：
  - 给所有可能溢出的子项加 `min-width: 0`：`.repo-card-header / .repo-card-name / .repo-card-url / .repo-card-meta / .repo-card-meta .meta-item / .repo-card-footer / .repo-card-branch`
  - 给文本子项加 `overflow: hidden; text-overflow: ellipsis; white-space: nowrap`（`.repo-card-name / .repo-card-branch`）
  - 给 `.repo-card-meta` 加 `flex-wrap: wrap`，让 2 个 meta-item 在空间不够时折行而不是撑高
  - 给 `.repo-grid` 加 `align-items: start`，**禁止**行内拉伸（每张卡按自然高度渲染）
  - 给徽章和链接加 `flex-shrink: 0`，保证不被压缩成 0
- **影响范围**：仅 `opengrok-web/src/main/webapp/index.jsp` 的 `<style>` 块
- **回滚**：把上面加的 `min-width: 0` / `overflow: hidden` / `align-items: start` 等行删掉即可

---

### 修复 #1g — meta/footer 长文本未截断（flex 容器 text-overflow 失效）

- **触发时间**：#1f 之后用户刷新验收
- **现象**：
  - android6_0_1 卡的 meta 第 2 项（40 字符 commit hash 被当作 branch）依然**垂直换行成 2 行**
  - footer 里同样的 hash 也**撑爆**，把"浏览 →"挤到了第 2 行
- **根因**：`text-overflow: ellipsis` + `white-space: nowrap` 这两个属性**只能作用于文本节点本身**，不能作用于 flex 容器（`.meta-item` 本身是 `display: flex`）
- **修复**：
  - helper 里把 meta-item 和 branch 的**文本单独包一层**：
    - `<span class="meta-item"><svg.../><span class="meta-text">TEXT</span></span>`
    - `<span class="repo-card-branch"><span class="branch-text">TEXT</span></span>`
  - 新增 CSS：
    - `.meta-item { flex: 0 1 auto; max-width: 100%; }`（让它能缩小）
    - `.meta-text { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; flex: 1 1 auto; }`（真正的截断作用点）
    - `.repo-card-branch { flex: 1 1 auto; }` + `.branch-text { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; display: inline-block; max-width: 100%; }`
- **影响范围**：仅 `opengrok-web/src/main/webapp/index.jsp` 的 helper 输出 + `<style>` 块
- **回滚**：把 helper 里多套的 `<span class="meta-text">` / `<span class="branch-text">` 去掉即可

### 关于"是数据问题还是CSS问题"

- **CSS 问题**：✓ 已修复（上面 #1f）
- **数据问题（备查，未修复）**：从你之前的截图看，android6_0_1 卡的 meta 显示的是**完整 40 字符的 commit hash**（`f42ee8bd0cb51c571dd6dfcf71c61dce377768cd`），而不是分支名。这说明该项目配置的 `RepositoryInfo.branch` 字段**被填成了 commit hash**（或者 SVN/Mercurial 类的 repository 实现里 branch getter 返回的就是 revision）。其它卡显示的是 `main / trunk`，是正常的。
  - 这是 OpenGrok indexer 端的配置 / analyzer 实现问题，**不属于本次 UI 重构的范围**
  - 如果想统一显示：可以改 helper 里第二项 meta 改用 `ri.getCurrentVersion().substring(0, 4)`（短版本号），但这会覆盖正常分支名的显示

---

### 已知未实现（计划文件外、留待后续）

- ⏳ `archiveOpengrok`（自动重索引）按钮——设计稿右下角有 4 个：搜索 /  / 帮助 / / 设置。✅ 已加（搜索/清除/帮助/设置）
- ⏳ 搜索结果行内跳转后的精确锚点（`#L123`）由 xref 页面支持；前端已用 `encodeURIComponent(path) + '#L' + num` 拼接
- ⏳ Issue 2 真正的复现：CSS 现在显式锁定了 hover/focus 颜色，但**根因可能是浏览器对 `<button>` 默认 focus 样式叠加**。若用户复测仍异常，请用 DevTools 检查 Computed `color` 看是哪条规则在生效，告诉我，我再针对性加 `!important`

---

### 修复 #1h — 首页三项遗失功能恢复（autocomplete / 类型下拉 / 真实搜索结果）

- **触发时间**：用户在验收 UI 后反馈，原 `index.jsp`（含 `menu.jspf`）支持的 3 项功能在新 UI 中遗失
- **修复的 3 个问题**：

| # | 问题 | 根因 | 修复内容 |
| --- | --- | --- | --- |
| 1 | 搜索框编辑时不出推荐搜索文字（autocomplete） | 底部 JS 末尾的 `if (typeof window.domReadyMenu === 'function' && ...)` 守卫判断在内联 `<script>` 执行时运行，**此时 jquery / utils 还没加载**，`window.domReadyMenu` 必定为 `undefined`，条件永远为 false，回调从不被 push | 删掉 `typeof` 守卫（utils.js 在 `<%= PageConfig.get(request).getScripts() %>` 之后才加载，且 `$(document).ready` 回调会在所有脚本就绪后才触发）。保留 `document.domReady.push(function () { window.domReadyMenu(); })` 模式（与原 `menu.jspf` 第 56-59 行一致）。加注释解释这个时序陷阱，避免后续误改回 |
| 2 | 「任意类型」下拉只有 6 个写死选项（Java/XML/纯文本/配置文件/图片） | 修复 #1e 按设计稿写死了 6 项，但用户希望恢复**与原 `menu.jspf` 行为一致**——用 `SearchHelper.getFileTypeDescriptions()` 动态生成几百项支持的类型 | ① page import 重新加 `java.util.Map`；② setup 段加 `Set<Map.Entry<String, String>> typeDescriptions = SearchHelper.getFileTypeDescriptions();`；③ `<select id="type">` 内首项保留 `<option value="">任意类型</option>`，之后用 `<% for (Map.Entry<String, String> d : typeDescriptions) { %>` 动态渲染所有项（与 `menu.jspf` 第 195-203 行逻辑一致），用 `Util.formQuoteEscape(tval)` / `Util.htmlize(tlabel)` / `tval.equals(selectedType)` 处理转义与选中态 |
| 3 | 提交搜索时显示的是模拟/假的列表，没有真实结果 | `performInlineSearch` 把表单字段直接转给 `/api/v1/search`，但 **API 字段名和表单字段名不一致**：表单用 `defs/refs/project`，API 用 `def/symbol/projects`（见 `SearchController.search()` 注解）。且 `renderResults` 把 `data.results` 当数组遍历、把 `r.path/r.lines/ln.lineno/ln.lineText` 当字段读取，但 `SearchResult.results` 实际是 **`Map<String, List<SearchHit>>`（按文件路径分组）**，每个 `SearchHit` 字段是 `line/lineNumber/tag` | ① `performInlineSearch` 加 `var FORM_TO_API_PARAM = { 'defs': 'def', 'refs': 'symbol', 'project': 'projects' }`，把表单 key 映射到 API key（其它字段如 `full/path/hist/type` 名字不变）；FormData 多个 project 会产生多个同名条目，`URLSearchParams.append` 正确处理为 `?projects=a&projects=b` ② `renderResults` 重写：先取 `resultCount/startDocument/endDocument` 标头；用 `Object.keys(resultsMap)` 遍历路径；对每条 `[path, hits]` 渲染文件头 + 行列表；hit 行读取 `h.lineNumber / h.line / h.tag`（`tag` 是查询关键词高亮，加 `<span class="match">` 包裹）；无结果显示 `未找到匹配项`（用 `.results-empty` 类，不再用 `.results-header` 避免和真正的结果头混淆） |

- **影响范围**：仅 `opengrok-web/src/main/webapp/index.jsp`（同一文件）
  - `<%@ page import %>` 块：+1 行（`java.util.Map,`）
  - setup 段：+1 行（`typeDescriptions = ...`）
  - `<select id="type">` 块：8 行 → 8 行（结构替换，内容从 6 项硬编码改为动态循环）
  - 底部 `<script>` 内：
    - `renderResults` 函数体替换（约 50 行）
    - `FORM_TO_API_PARAM` 常量新增（5 行）
    - `performInlineSearch` 函数体替换（约 20 行）
    - domReady push 守卫判断简化（5 行 → 8 行，含注释）
- **未改动**：其他文件 / 其他变量 / 其他逻辑 / 任何 CSS / 任何 JS 库 / 任何 Java 类
- **回滚**：
  ```bash
  git checkout -- opengrok-web/src/main/webapp/index.jsp
  ```
  即可回到修复 #1g 的状态（仍保留 #1a-#1g 的所有修复，仅丢失本次 #1h 新增的 3 项功能）

- **验收点（用户在浏览器验证）**：

  | # | 验收点 | 期望 |
  | --- | --- | --- |
  | 1 | 自动补全 | 在主搜索框输入任意字符，应弹出 jQuery UI 自动补全下拉（来自 `/api/v1/suggest`），点击建议项回填到输入框 |
  | 2 | 类型下拉 | 「任意类型」下拉展开时，选项应远多于 6 个（取决于 OpenGrok 注册的所有 Analyzer/文件类型，通常几十到几百个） |
  | 3 | 真实结果 | 输入查询并提交，下方 `.results-section` 应显示真实的搜索结果（文件路径 + 高亮的命中行），点击命中行跳到 xref 锚点；仓库卡片区自动隐藏；空结果显示「未找到匹配项」 |
  | 4 | 高级字段 | 在 `defs/refs/path/hist` 任意输入框输入字符，也应弹出对应字段的补全建议（5 个输入框都会自动启用） |
  | 5 | 类型过滤 | 在类型下拉选非「任意类型」再搜索，结果应只包含所选类型文件；选回「任意类型」恢复全量 |

---

### 修复 #1i — chip 按钮改为 `addEventListener` 方式（解决 Jetty 热重载遗留的失效问题）

- **触发时间**：用户验收修复 #1h 后反馈"项目旁边的【全选】【反选】【清除】也都失效了"
- **调查过程**：
  1. 检查源码：`onclick="selectAllProjects()"` 等 inline 写法存在；`window.selectAllProjects/invertAllProjects/deselectAllProjects/toggleChip` 在 IIFE 内已赋值（`src/main/webapp/index.jsp:1176-1194`，后改为 1178-1197）
  2. 检查编译产物：`target/jspc/org/apache/jsp/index_jsp.class`（56473 字节，`2026/8/7 15:11:56`）含 `FORM_TO_API_PARAM`/`SearchHelper.getFileTypeDescriptions` 字符串，确认 #1h 的 JSP 改动已被 JSPC 编译进 class
  3. 检查 war：`target/source.war`（15:27 打包）的 `index.jsp` 含完整动态循环，证实 mvn package 已生效
  4. **关键观察**：用户截图里下拉只有 6 项且 labels 是中文硬编码"任意类型/Java 源文件/XML 文件/纯文本/配置文件/图片"，而 `SearchHelper.getFileTypeDescriptions()` 返回的描述是英文（如 "Plain Text"/"Image file"/"Java"），新代码不可能渲染出中文 label → **用户正在运行的 Jetty 进程是修改前启动的，JSP class 没热重载**
- **根因**：
  - Jetty 12 的 JSP 引擎对 `_jspService` 字节码改动有缓存策略；某些版本对 mtime 比对宽松，且 JSP 热重载依赖 `target/jspc` 的 .class 文件被清空重建
  - 用户运行的是 `mvnw jetty:run`（用户已确认），JSP 是被 JSPC 预编译到 `target/jspc` 的，**Jetty 启动后不会自动 watch 这些 .class**；要重新加载 JSP，必须重启 Jetty
  - 同时 chip 按钮用 inline `onclick` 也是脆弱写法：若 JS 因任何原因早期抛错（脚本阻塞、其他组件抛错），`window.selectAllProjects` 等就根本没绑上，按钮直接失效
- **修复**（双管齐下）：
  1. **HTML 模板**：把 inline `onclick` 全部去掉，换成 `data-action="select-all|invert-all|deselect-all"` 属性；chip 元素也去掉 `onclick="toggleChip(this)"`（用 `closest('.chip')` 替代）
  2. **JS 绑定**：在 IIFE 内用 `addEventListener` 绑定：
     - `projectChips.addEventListener('click', handleChipClick)` —— 事件委托，单击任一 chip 走 `handleChipClick`
     - `document.querySelectorAll('.chip-action[data-action]').forEach(btn => btn.addEventListener('click', fn))` —— 按 `data-action` 名字查表派发
     - 函数定义改为普通 `function selectAllProjects() { ... }`（不再用 `window.selectAllProjects = ...` 包），最后再赋值到 `window` 兼容任何遗留 `onclick`
  3. **好处**：
     - 即便 inline `onclick` 因 HTML 缓存残留也不影响（事件已绑到 DOM 元素上）
     - JS 早期抛错也只影响后续代码（chip 按钮绑定在 refreshProjectSelect 之后，但与 submit 拦截互不依赖）
     - `closest('.chip')` 即使点到 chip-dot 子元素也能正确触发
- **影响范围**：仅 `opengrok-web/src/main/webapp/index.jsp`（同一文件）
  - HTML：3 个 `.chip-action` 按钮 + 所有 `.chip` 元素去 inline `onclick`，加 `data-action` 属性
  - JS：~15 行调整（chip handler 改委托 + 按钮改 addEventListener + 函数定义去 `window.` 前缀）
- **回滚**：
  ```bash
  git checkout -- opengrok-web/src/main/webapp/index.jsp
  ```
  即可回到 #1h 状态（inline onclick + 旧 hardcode dropdown）

- **用户操作指南（让改动生效））**：

  > **Jetty 热重载的 JSP 改动必须重启服务**——inline `mvn jetty:run` 不会自动 pick up `target/jspc/` 下的新 class。
  > 
  > 推荐流程：
  > 1. **Ctrl+C** 停掉当前 Jetty 进程（PID 24592，端口 8081）
  > 2. 重新运行：`mvnw jetty:run`（自动先执行 jspc 重新编译，再启动 Jetty）
  > 3. 浏览器**硬刷新**（Ctrl+Shift+R / Cmd+Shift+R）清缓存
  > 
  > 验证标准：
  > - 类型下拉展开后**远多于 6 项**（约 30~50 项，labels 是英文如 "Plain Text"/"Image file"/"C++ Source" 等）
  > - 点 chip 立即切换选中态；点 全选/反选/清除 也立即生效
  > - 浏览器 DevTools Console 无 JS 报错

- **如果重启后 dropdown 仍然只有 6 项**（troubleshoot 步骤）：
  1. 浏览器 F12 → Network → 勾选 Disable cache，硬刷新一次
  2. DevTools → Elements → 搜索 `<select id="type">` → 看 option 子节点数是不是只有 7 个（含首项"任意类型"）。若是，说明浏览器拿到的是旧 HTML，**强刷**即可
  3. 若仍是旧 HTML：检查 `target/source/index.jsp` 的 mtime 是否晚于 Jetty 启动时间；或强制 `mvn clean` 再 `mvn jetty:run`
  4. 若 source 已经是新代码但 Jetty 不加载：可能是 Jetty 12 在 jspc 模式下不读取 `target/source/index.jsp`，而是读 `target/jspc/org/apache/jsp/index_jsp.class` 的预编译结果——此时**只要 JSPC 重跑就行**（已绑定到 process-classes 阶段，clean 后会自动重跑）

---

## 六、约束与原则

1. **不破坏现有功能**：搜索提交 URL、表单字段名、Cookie 行为、授权逻辑必须保持兼容。
2. **CDDL 头部**：所有被改动的 JSP/JSPF/Tag 文件保留 CDDL HEADER + Copyright 注释，仅追加本次重构的 Copyright 行。
3. **表单兼容性**：新 UI 的表单字段 `name` 必须沿用 `QueryParameters.*` 常量，保证与 `search.jsp` 等后端兼容。
4. **可回滚性**：每个阶段的改动尽量限定在一个或少数几个文件，便于 `git checkout` 回滚。
5. **下次 AI 智能体接手**：阅读本文档后，按「四、执行顺序」中下一个未完成阶段继续；先看「五、修改记录」了解已完成项，再开始新一轮修改并追加新条目。

## 七、参考资料

- 新 UI 设计：`opengrok-web/docs/ui/*.html`
- 模块导览：`opengrok-web/docs/intro/open-grok-web-guide.md`
- 模块概览：`opengrok-web/docs/intro/overview.md`
- 构建与运行：`opengrok-web/docs/intro/run.md`
- 关键 Java 类：`PageConfig.java`、`ProjectHelper.java`、`Scripts.java`、`Util.java`、`Prefix.java`、`QueryParameters.java`

---

### 修复 #1j — 「任意类型」下拉 DOM 存在但页面不显示（被遗留的 SOL 插件/CSS hack 隐藏）

- **触发时间**：#1h/#1i 修复后用户验收，反馈"代码里能看到 `<select id="type">`，但页面上看不到下拉框"
- **截图证据**：
  - DevTools Elements 面板展开 `<select class="ctrl-select" id="type" name="type">` → 子节点 50+ 项（Ada/Asm/Bzip2/C/Clojure/COBOL/C#/C++ ...）说明数据渲染正确
  - DevTools 提示元素尺寸 `30 × 20` ← 与下边 CSS 规则吻合
- **根因**（两个旧文件叠加影响）：

  | # | 文件 | 关键代码 | 影响 |
  | --- | --- | --- | --- |
  | 1 | `default/style-1.0.6.css:1513-1517` | `select#project, select#type { height: 20px; width: 30px; visibility: hidden; }` | **强制把 `<select id="type">` 锁成 30×20 且不可见** |
  | 2 | `js/utils-0.0.48.js:1353-1374`（`init_searchable_option_list` → `init_sol_on_type_combobox`） | `$('#type').searchableOptionList({ resultsContainer: $("#type-select-container") })` | SOL 插件试图把自定义 widget 渲染到 `#type-select-container`，**但新页面根本没有这个容器** → widget 无处渲染 |

  原页面（`menu.jspf:189-206`）的写法是：`<select id="type">` + `<td id="type-select-container">` 紧挨着，SOL 插件负责把原生 `<select>` 隐藏、用自定义 widget 替换。原 CSS `select#type { visibility:hidden }` 正是为此配套的 "SOL workaround"。新设计用纯原生 `<select>` + `.ctrl-select` 美化，**这两个组件就成了 bug 来源**。
- **修复方案**：
  - **HTML**：把 `<select>` 的 `id` 从 `"type"` 改为 `"filetype"`（避开旧 CSS `select#type` 和旧 JS `$('#type')`）；`name` 属性**保持** `"<%= QueryParameters.TYPE_SEARCH_PARAM %>"` 即 `"type"`，因为后端 `SearchController` 期望的 URL 参数名是 `type`，**表单提交字段名不变**
  - **CSS**：给 `.ctrl-select` 显式声明 `visibility: visible; width: auto; height: auto; min-width: 120px;`，**作为防御层**盖住任何后续可能注入的 `select#*` 隐藏样式
  - **JS**：不需要改 — 新 IIFE 没引用 `#type`；遗留 `clearSearchFrom()` / `$('#type').searchableOptionList()` 等在 utils.js 中，新页面不调用它们
- **影响范围**：
  - `opengrok-web/src/main/webapp/index.jsp:984` — `id` 改名 + 加注释
  - `opengrok-web/src/main/webapp/index.jsp:335-345` — `.ctrl-select` 加 4 行防御样式
- **回滚**：
  - 把 `id="filetype"` 改回 `id="type"`，删掉新增的 4 行 `.ctrl-select` 属性即可
- **验收点**：
  - 类型下拉可见，宽度 ≥ 120px，高度正常
  - 下拉展开后可看到 50+ 个英文 label 的 option（Ada/Asm/Bzip2/C ...）
  - 切换选项后下拉首项显示当前选中项的中/英文标签
  - 表单提交时 URL 含 `&type=ada` 之类参数（DevTools Network 看 Query String）

---

### 修复 #1k — 仓库卡片字段按截图重新组织 + 缺字段占位 + 修日期截断 bug

- **触发时间**：#1j 之后用户反馈"按这个截图来展示"
- **截图**：7 个槽位 → ①名字 ②仓库(URL) ③git 标识 ④仓库/工程 ⑤版本时间(年月日时分) ⑥分支·最后一次提交 ⑦浏览→
- **根因**：
  - 原 helper 把所有缺失字段一律显示成 `"N/A"` 字面量，破坏布局
  - `summary.substring(0,4)` 把 `"2026-02-06 11:40 +0800 34c4"` 截成 `"2026"` —— **真正的 bug**，这就是之前截图里 footer 显示 `2026 · 7909` 的根源（#1f 只修了 CSS 没修 Java 解析）
  - meta[0] 写死 "浏览"，与截图的"仓库/工程"语义不符
  - meta[1] 把 branch 塞到时钟图标位，错了
- **修复方案**：
  - **字段语义重写**（helper 顶部新增 3 个工具方法 + ICON 常量）：
    - `extractVersionDateTime(s)` → 取 `currentVersion` 前 16 字符（`YYYY-MM-DD HH:mm`）；不匹配返回 null
    - `extractLastToken(s)` → 取最后一个空格分隔 token（如 `34c4`）；null/无空格返回 null
    - `repoTypeBadgeClass(s)` → 复用旧的 badge 颜色映射（git/svn/hg/cvs）
    - `hasText(s)` → null/空字符串判定
  - **3 个 SVG 常量**：
    - `ICON_REPO_BRANCH` → 仓库图标（git branch 分叉样式）
    - `ICON_PROJECT` → 工程图标（folder/document 样式）
    - `ICON_CLOCK` → 时钟图标
  - **槽位渲染逻辑**（`renderRepoCard` 中重写）：
    | 槽位 | 数据 | 缺失行为 |
    | --- | --- | --- |
    | ② 仓库(URL) | `Util.redactUri(ri.parent)` | `.empty` → `visibility:hidden` 保留行高 |
    | ③ git 标识 | `ri.type` + badgeClass | `.empty` → `visibility:hidden` 保留 pill 宽度 |
    | ④ 仓库/工程 | `hasRepoType ? ICON_REPO_BRANCH+仓库 : ICON_PROJECT+工程` | 始终渲染（项目必有） |
    | ⑤ 版本时间 | `extractVersionDateTime(currentVersion)` | `.empty` → `visibility:hidden` |
    | ⑥ 分支·hash | `branch + " · " + lastToken(currentVersion)` | 都缺 → 「暂无分支」+ `.placeholder` 类（斜体灰） |
  - **CSS 新增 4 条规则**（最小侵入）：
    ```css
    .repo-card-badge.empty          { visibility: hidden; }
    .repo-card-url.empty            { visibility: hidden; }
    .repo-card-meta .meta-item.empty { visibility: hidden; }
    .repo-card-branch.placeholder   { color: var(--muted); font-style: italic; }
    ```
- **影响范围**：
  - `opengrok-web/src/main/webapp/index.jsp:43-181` —— helper 完全重写（新增 3 个工具方法 + 3 个 ICON 常量 + 新逻辑）
  - `opengrok-web/src/main/webapp/index.jsp:567-750` —— CSS 4 处新增
- **回滚**：
  ```bash
  git checkout -- opengrok-web/src/main/webapp/index.jsp
  ```
  回到 #1j 状态
- **验收点**：

  | # | 场景 | 期望 |
  | --- | --- | --- |
  | 1 | A2UI（git 仓库，full info） | 卡片右上 `git` pill（蓝色），URL 行 `github.com/...`，meta[0] 显示仓库图标+「仓库」，meta[1] 显示 `2026-01-24 11:40`，footer 显示 `main · 34c4` |
  | 2 | breakpad（git，无 parent URL） | URL 行 `visibility:hidden` 但行高保留；其它行正常 |
  | 3 | android6_0_1（git，branch 为空） | URL 行可见，pill 可见，footer 显示 `34c4`（只有 hash）或「暂无分支」 |
| 4 | 纯文件夹工程（无 SCM） | 右上无 pill（`visibility:hidden`），meta[0] 显示文件夹图标+「工程」，footer 显示「暂无分支」斜体灰 |
| 5 | 卡片高度对齐 | 同一行卡片高度一致（grid `align-items:start` + 行高保留保证） |

---

### 修复 #1l — `Util.htmlize(null)` NPE 导致首页整页挂掉（#1k 引入）

- **触发时间**：用户验收 #1k 后反馈"页面只渲染到搜索表单，底部全空白"
- **截图证据**：搜索表单（输入框 + 高级搜索按钮 + 任意类型下拉）正常渲染，下面整片空白
- **根因**：
  - `renderRepoCard` helper 改用 `null` 表达"字段缺失"（之前是 `"N/A"` 字面量），更干净也更语义化
  - 但 `Util.htmlize(String)` 内部调用 `needsHtmlize(s, false)`，后者直接 `for (int i = 0; i < q.length(); ++i)` —— **没有 null 检查**
  - 因此任何 `Util.htmlize(null)` 都会抛 NPE
  - 我在 helper 里 5 处 `Util.htmlize(repoType|remoteUrl|branch|versionDate|versionHash)` 都传了可能为 null 的字段 → 第一个为 null 的字段就炸
  - 实际栈：
    ```
    java.lang.NullPointerException: Cannot invoke "java.lang.CharSequence.length()" because "q" is null
        at org.opengrok.indexer.web.Util.needsHtmlize(Util.java:345)
        at org.opengrok.indexer.web.Util.htmlize(Util.java:183)
        at org.apache.jsp.index_jsp.renderRepoCard(index_jsp.java:132)
    ```
  - 因为 `renderRepoCard` 在 `<section id="repo-section">` 里被调用，**NPE 抛出后整个 JSP 后续内容（chips 区、results 区、repo 区、footer、`<script>`）全部丢失**
- **修复**：
  - helper 顶部加 `nz(String s)` 工具方法：`return s == null ? "" : s;`
  - 5 处 `Util.htmlize(...)` 包一层 `nz()`：`Util.htmlize(nz(repoType))` 等
  - 同步检查 `Util.redactUri(null)`：也会 NPE（`new URI(null)` 抛 NPE）；但 #1k 已不在 helper 里调用 `redactUri`（直接 `ri.getParent()`），所以这一项不受影响
- **影响范围**：仅 `opengrok-web/src/main/webapp/index.jsp` 的 `renderRepoCard`（10 行内）
- **回滚**：
  ```bash
  git checkout -- opengrok-web/src/main/webapp/index.jsp
  ```
- **用户操作（让改动生效）**：**必须重启 Jetty**——`mvn jetty:run` 模式用的是 JSPC 预编译产物 `target/jspc/.../index_jsp.class`，运行时不会自动 watch .jsp 改动
  ```powershell
  Stop-Process -Id 14300 -Force
  cd D:\AppsData\deploy\opengrok\opengrok-web
  .\..\mvnw.cmd jetty:run
  # 浏览器硬刷新 Ctrl+Shift+R
  ```
- **验收点**：
  - 首页完整渲染：搜索表单 + 高级面板 + 项目 chips + 仓库卡片列表 + 页脚
  - 没有 5xx 错误，没有 JSP 错误页
  - 仓库卡片按 #1k 验收表显示（仓库/工程图标按 SCM 类型切换、版本时间、暂无分支占位等）

---

### 修复 #1m — `extractLastToken` 取错了 hash（截到 commit message 末尾）

- **触发时间**：#1l 之后用户验收，发现 footer 显示 `main · (#545)` / `main · symbols"` / `trunk · (#1076)` / `feature/develop · mars升级至1.1.5...` —— **都不是 hash**
- **截图证据**：footer 行 · 后面是 PR 号、commit message 末尾、不是 git short hash
- **根因**：
  - `extractLastToken` 用 `lastIndexOf(' ')` 取最后一个空格分隔 token
  - 但 `RepositoryInfo.currentVersion` 的实际格式（[GitRepository.java:866-884](opengrok-indexer/src/main/java/org/opengrok/indexer/history/GitRepository.java)）是：
    ```java
    return String.format("%s %s %s %s",
        format(date),                                          // 0: 2026-01-24
        reader.abbreviate(head.getObjectId()).name(),          // ... wait no, format(date) is the whole formatted date+time+tz
        commit.getAuthorIdent().getName(),                     // ...
        commit.getShortMessage());
    ```
    实际展开是：
    ```
    "{date} {time} {tz} {shortHash} {author} {message}"
    ```
    也就是 `"2026-01-24 11:40 +0800 34c4909 alan blount chore(docs): reduced size of hero img (#545)"` 这种结构
  - token index：
    - `[0]` 日期 `2026-01-24`
    - `[1]` 时间 `11:40`
    - `[2]` 时区 `+0800`
    - `[3]` **short hash** `34c4909` ← 这里才是 hash
    - `[4]` 作者名 `alan`
    - `[5]` ...
    - `[6..]` commit message `chore(docs): reduced size of hero img (#545)`
  - `lastIndexOf(' ')` 取到的是 commit message 最后一词 `(#545)` —— 不是 hash
- **修复**：
  - 新增 `extractShortHash(String s)`：按空白分割取 `tokens[3]`，再用正则校验是否像 hash（hex 4-40 字符）或版本号（数字 1-20 字符）
    ```java
    if (candidate.matches("[0-9a-fA-F]{4,40}") || candidate.matches("\\d{1,20}")) {
        return candidate;
    }
    return null;
    ```
  - `renderRepoCard` 调用 `extractShortHash(currentVer)` 取代 `extractLastToken(currentVer)`
  - 校验失败时返回 null → 自动回落到：仅 branch / 暂无分支
- **影响范围**：仅 `opengrok-web/src/main/webapp/index.jsp`（helper 改 1 个方法名 + 1 个新方法）
- **回滚**：
  ```bash
  git checkout -- opengrok-web/src/main/webapp/index.jsp
  ```
- **用户操作**：照旧必须重启 Jetty
- **验收点**：

  | Repo | footer 期望（修复后） |
  | --- | --- |
  | A2UI | `main · 34c4909` |
  | breakpad | `main · 79099fd` |
  | mosaic | `trunk · a6223d8` |
  | sf_archives | `feature/develop · c7df27d` |
  | android6_0_1 | `f42ee8bd0cb51c571dd6dfcf71c61dce377768cd`（40 字符 git 全 hash，CSS 自动 ellipsis） |
  | 无 hash 数据的项目 | 仅 branch / 「暂无分支」占位 |

---