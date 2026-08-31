# OpenGrok Web UI 重构 — 改动记录与迁移指南

> **文档目的**：记录 `feature/v1.14.15` 分支相对于 OpenGrok 上游 `master` (`b9be6fdcaa`) 的所有 UI 重构改动，方便下次主分支更新时按文件清单逐项迁移。
>
> **运行约定**：旧 UI 留在 **Tomcat 8080**（`D:\Programs\apache_tomcat\webapps\source`，**不动**）；新 UI 跑 **Jetty 8081**（`mvn jetty:run`，由 `opengrok-web/pom.xml` 配置）。详见本文末档「七、运行 8081 端口方案」。

---

## 一、重构范围

| 项                   | 值                             |
|---------------------|-------------------------------|
| 工作分支                | `feature/v1.14.15`            |
| 分叉基点（与 master 合并基点） | `b9be6fdcaa`                  |
| 当前分支相对 master 领先    | 61 个 commit                   |
| 涉及文件                | 50 个（新增 9、修改 37、删除 4）         |
| 新增行                 | ~17 700                       |
| 删除行                 | ~2 700                        |
| 重构起点 commit         | `b0bd3ec80 feat: 首页 UI 重构暂存点` |
| 重构最近 commit         | `bbc911435 feat: ai 辅助提交`     |

> ⚠ 注：早期 `docs/intro/run.md` 写"本次重构只改 `index.jsp` 一个 JSP 文件"，那是 `b0bd3ec80..372005770` 阶段的描述。本次重构已扩展到 50 个文件。

---

## 二、文件改动总览（按用途分组）

### A. 共享层 / 布局层 jspf（页面 chrome）

| 文件                                   | 类型     | 行数 +/−    | 作用                | 关键改动                                                                                                                                                                                                  |
|--------------------------------------|--------|-----------|-------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `src/main/webapp/pageheader.jspf`    | 修改     | +213/-215 | 顶部 Logo + 标题条     | `<div class="common-page-header-logo">` → `<a href="/">`；新增 `:hover` 样式                                                                                                                               |
| `src/main/webapp/foot.jspf`          | 修改     | +131      | 底部 footer + 脚本注入  | 新增中文 footer；保持 `PageConfig.getScripts()` 注入                                                                                                                                                           |
| `src/main/webapp/httpheader.jspf`    | 修改     | +131 / +2 | `<head>` + CSS 变量 | **定义全局 CSS 变量** `--bg`、`--surface`、`--fg`、`--muted`、`--border`、`--accent`、`--accent-dim`、`--font-sans`、`--font-mono`；新增两条 `<link rel="icon">` / `<link rel="apple-touch-icon">` 指向 `new-touch-icon.svg`，让浏览器 tab 真正使用新 SVG（仅改 `manifest.json` 不够）                       |
| `src/main/webapp/menu.jspf`          | 修改     | +1001     | 顶部搜索表单 + 项目 chips | 搜索表单 UI 重构；`chip` 选中状态从 HTML `selected` 属性改为 `.selected` class（修复 `_menuSelAttr` bug）                                                                                                                 |
| `src/main/webapp/projects.jspf`      | 修改     | +37       | 项目 cookie 持久化     | 接入新 chrome                                                                                                                                                                                            |
| `src/main/webapp/breadcrumb.jspf`    | **新增** | +228      | 面包屑导航             | 新设计片段，被 list.jsp / history.jsp 等包含                                                                                                                                                                    |
| `src/main/webapp/chrome-guards.jspf` | **新增** | +66       | chrome 保护片段       | 某些页面需要在 include 前设置状态                                                                                                                                                                                 |
| `src/main/webapp/pager.jspf`         | **新增** | +199      | 分页器 CSS           | `.pagination` / `.page-btn` / `.page-btn.active` / `.page-btn.nav-btn` / `.page-btn:disabled` / `.page-btn.disabled` / `.page-ellipsis` / `.page-jump-hint`；被 index.jsp / search.jsp / history.jsp 引入 |

### B. 业务页面 jsp

| 文件                                | 类型 | 行数 +/− | 作用                    | 关键改动                                                                                                                                                                   |
|-----------------------------------|----|--------|-----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `src/main/webapp/index.jsp`       | 修改 | +1030  | 主入口（JS 驱动）            | 新 UI 主页：搜索框 + chips + 仓库卡片 + JS 分页 + 搜索结果；新增 JS `renderPagination()`、`performInlineSearch()`、`executeSearch()`、`buildBreadcrumb()` 等                                   |
| `src/main/webapp/search.jsp`      | 修改 | +1260  | 搜索结果（无 JS fallback）   | 服务端渲染版搜索结果页；新增 `_searchOrder` / `_searchStart` / `_searchMax` / `_searchTotal` / `_searchThisPage` / `_searchSliderHtml` 等 JSP 变量；用 `SearchEngine` 而非 `/api/v1/search` |
| `src/main/webapp/list.jsp`        | 修改 | +2548  | 目录列表 / 文件树            | 新 UI 目录浏览；面包屑 + 树状目录 + 操作按钮                                                                                                                                            |
| `src/main/webapp/xref.jspf`       | 修改 | +395   | 被 list.jsp 引用，xref 视图 | 代码查看 UI 重构                                                                                                                                                             |
| `src/main/webapp/history.jsp`     | 修改 | +844   | 文件 / 目录历史             | `Util.createSlider()` 旧分页器 → 新 `.page-btn` 词汇映射（`.more` → `.page-btn`，`.sel` → `.page-btn.active`，`<span>...</span>` → `.page-ellipsis`）                               |
| `src/main/webapp/diff.jsp`        | 修改 | +1595  | diff 视图               | diff UI 重构                                                                                                                                                             |
| `src/main/webapp/more.jsp`        | 修改 | +151   | "more" 上下文匹配          | 改用 pageheader.jspf + foot.jspf chrome；用 `_moreCfg` 局部变量                                                                                                                |
| `src/main/webapp/mast.jsp`        | 修改 | +305   | 旧 mast 头（多页面引入）       | 角色弱化，部分 chrome 移到 pageheader.jspf                                                                                                                                      |
| `src/main/webapp/minisearch.jspf` | 修改 | +335   | 搜索推荐                  | UI 调整                                                                                                                                                                  |
| `src/main/webapp/repos.jspf`      | 修改 | +592   | 仓库面板                  | UI 重构，`.repo-card` 等新 class                                                                                                                                            |

### C. 辅助 / 配置 / 错误页

| 文件                                                    | 类型 | 行数 +/− | 作用      | 关键改动                        |
|-------------------------------------------------------|----|--------|---------|-----------------------------|
| `src/main/webapp/help.jsp`                            | 修改 | +461   | 帮助页     | UI 重构                       |
| `src/main/webapp/settings.jsp`                        | 修改 | +114   | 设置页     | UI 重构                       |
| `src/main/webapp/status.jsp`                          | 修改 | +102   | 状态页     | UI 重构                       |
| `src/main/webapp/error.jsp`                           | 修改 | +98    | 错误页     | UI 重构                       |
| `src/main/webapp/eforbidden.jsp`                      | 修改 | +60    | 403 页   | UI 重构                       |
| `src/main/webapp/enoent.jsp`                          | 修改 | +68    | 404 页   | UI 重构                       |
| `src/main/webapp/opensearch.jsp`                      | 修改 | +84    | 浏览器搜索插件 | UI 重构                       |
| `src/main/webapp/rss.jsp`                             | 修改 | +141   | RSS     | UI 重构                       |
| `src/main/webapp/rss.xsl.xml`                         | 修改 | +55    | RSS XSL | UI 重构                       |
| `src/main/webapp/js/utils-0.0.48.js`                  | 修改 | +4     | 通用工具    | 新增 `domReady` 队列 / 增强的 IIFE |
| `src/main/webapp/js/searchable-option-list-2.0.16.js` | 修改 | +94    | 项目下拉    | UI 调整                       |

### D. Java 后端

| 文件                                                            | 类型     | 行数 +/− | 作用             | 关键改动                                   |
|---------------------------------------------------------------|--------|--------|----------------|----------------------------------------|
| `src/main/java/org/opengrok/web/CharacterEncodingFilter.java` | **新增** | +78    | Servlet Filter | 强制请求 / 响应编码为 UTF-8；在 `web.xml` 挂到 `/*` |
| `src/main/java/org/opengrok/web/GetFile.java`                 | 修改     | +24    | 文件下载           | 行为变更或 bug 修复                           |

### E. 删除的 tag 文件

| 文件                                              | 类型 | 备注                         |
|-------------------------------------------------|----|----------------------------|
| `src/main/webapp/WEB-INF/tags/project.tag`      | 删除 | 已被 list.jsp 内联             |
| `src/main/webapp/WEB-INF/tags/projects.tag`     | 删除 | 已被 list.jsp 内联             |
| `src/main/webapp/WEB-INF/tags/repositories.tag` | 删除 | 已被 list.jsp / index.jsp 内联 |
| `src/main/webapp/WEB-INF/tags/repository.tag`   | 删除 | 已被 list.jsp / index.jsp 内联 |

> 这些 tag 在 master 上仍存在但**不再被任何页面引用**，删除不影响功能。master 更新后这两个 tag 仍会同步回来——无须迁移动作。

### F. 配置文件

| 文件                                | 类型 | 行数 +/− | 作用       | 关键改动                                                                                                                                       |
|-----------------------------------|----|--------|----------|--------------------------------------------------------------------------------------------------------------------------------------------|
| `src/main/webapp/WEB-INF/web.xml` | 修改 | +24    | Web 应用配置 | 注册 `CharacterEncodingFilter`（`/*`，`REQUEST`+`FORWARD` dispatcher）；`configuration.xml` 路径指向本地（`D:\Programs\opengrok\etc\configuration.xml`） |
| `opengrok-web/pom.xml`            | 修改 | +21    | Maven 构建 | Jetty 插件升级到 `org.eclipse.jetty.ee10:jetty-ee10-maven-plugin:12.0.10`；`httpConnector.port=8081`；jvmArgs 增加 `--add-opens` / `--add-exports`  |

#### F.2 运行时配置文件 `D:\Programs\opengrok\etc\configuration.xml`（在仓库外，必读）

> 该文件不在 Git 仓库里、但被 8080 Tomcat 和 8081 Jetty **共享**。重构 commit 里**没有**改动它——下面的两段是 UI 重构验收期间为了「从 8081 也能调通 `/api/v1/*`」手动注入的运行时参数。**部署到任何新机器时都要重新注入一次**。

**改动 1：注入 API token（让 IncomingFilter 通过）**

- 原因：master 上 commit `76502c4bd remove localhost bypass for API checks (#4944)` 移除了「localhost 免 token」快捷通道。新 UI 在 Jetty 8081 上跑时，调 `GET /api/v1/application.wadl`（以及任何不在 `IncomingFilter.allowedPaths` 白名单里的 endpoint）一律 401——因为 `configuration.xml` 里 `authenticationTokens` 是空集。
- 改动位置：`configuration.xml` 末尾的 `</object>` 闭合前（即 `Configuration0` 的最后一个 `<void property="...">` 之后）。
- 改动内容：
  ```xml
  <void property="authenticationTokens">
   <object class="java.util.HashSet">
    <void method="add">
     <string>dev-token-123</string>
    </void>
   </object>
  </void>
  ```
- 效果：调用任何 `/api/v1/*` 时带 `Authorization: Bearer dev-token-123` 即可通过 `IncomingFilter` 第一道闸。
- ⚠ 改动 1 必须配改动 2，否则 token 仍被拒。

**改动 2：允许 token 通过明文 HTTP**

- 原因：即使 token 正确，`IncomingFilter` 还要求 `request.isSecure() || isAllowInsecureTokens()`，否则记录 `request to xxx has a valid token however is not secure` 后 401。本地开发全是 HTTP，没法满足 `isSecure()`，所以必须打开 `allowInsecureTokens`。
- 改动位置：紧接改动 1 之后。
- 改动内容：
  ```xml
  <void property="allowInsecureTokens">
   <boolean>true</boolean>
  </void>
  ```
- 效果：token 在 HTTP / HTTPS 上都生效。
- ⚠ **生产环境必须改成 `false` 并配 HTTPS**。`true` 等同于把 API 完全暴露给任何能拿到 token 的人（HTTP 抓包即泄漏）。

**为什么 8080 Tomcat 现在仍然不感知这两段改动？**

8080 Tomcat 上跑的 `webapps/source.war` 是 2026-01-24 编译的，构建基线早于 `76502c4bd`，所以那个 war 里的 `IncomingFilter` 仍然有 localhost bypass——它在源码里**根本不会读取** `authenticationTokens`，配置改了也无所谓。两端口行为暂时不一致是正常的；等 8080 war 升级到含 `76502c4bd` 的版本后，这两段配置就会自动生效。

**迁移检查清单（每次换部署机器或重装系统时跑一次）**

```powershell
# 1. 验证两段 XML 都在
Select-String -Path "D:\Programs\opengrok\etc\configuration.xml" `
  -Pattern "authenticationTokens|allowInsecureTokens"

# 2. 重启 Jetty 8081 让改动生效（Tomcat 视情况）
$pid = (Get-NetTCPConnection -LocalPort 8081 -State Listen).OwningProcess
if ($pid) { Stop-Process -Id $pid -Force }

# 3. 验证 token 通过
irm -Headers @{Authorization = "Bearer dev-token-123"} `
     "http://localhost:8081/api/v1/application.wadl"
```

### G. 文档

| 文件                                  | 类型     | 作用                                      |
|-------------------------------------|--------|-----------------------------------------|
| `docs/ui/index.html`                | **新增** | 新版首页设计稿（对应 index.jsp）                   |
| `docs/ui/code-view.html`            | **新增** | 代码查看页设计稿（对应 list.jsp + xref.jspf）       |
| `docs/ui/directory-history.html`    | **新增** | 目录历史页设计稿（对应 history.jsp）                |
| `docs/ui/directory-view.html`       | **新增** | 目录列表设计稿（对应 list.jsp）                    |
| `docs/ui/file-diff-detail.html`     | **新增** | diff 详情设计稿（对应 diff.jsp）                 |
| `docs/ui/file-history-diff.html`    | **新增** | 历史 diff 设计稿（对应 diff.jsp 历史对比分支）         |
| `docs/intro/open-grok-web-guide.md` | **新增** | 新版 opengrok-web 模块全面解析（837 行）           |
| `docs/intro/overview.md`            | 修改     | 模块概览                                    |
| `docs/intro/run.md`                 | 修改     | 运行步骤（**包含完整的 Jetty 8081 部署脚本**，本指南末尾摘录） |

### H. 工具 / 内部文件（无需迁移）

| 文件                            | 类型 | 备注                      |
|-------------------------------|----|-------------------------|
| `.claude/settings.local.json` | 新增 | Claude Code 本地配置，**忽略** |
| `.codegraph/.gitignore`       | 新增 | 内部工具，**忽略**             |
| `.codegraph/config.json`      | 新增 | 内部工具，**忽略**             |

---

## 三、关键设计词汇（迁移时 grep 这些 token 即可）

### 3.1 CSS 变量（在 `httpheader.jspf` 定义，所有页面可用）

```
--bg          --surface      --fg          --muted
--border      --accent       --accent-dim  --font-sans   --font-mono
```

### 3.2 通用 chrome class（在 `pageheader.jspf` / `foot.jspf` / `httpheader.jspf` 定义）

```
.common-page-header       .common-page-header-logo       .common-page-header-title
.common-page-footer       main.container                  .search-hero-heading
.search-hero-subtitle
```

### 3.3 分页器（在 `pager.jspf` 定义，**新引入**）

```
.pagination       .pagination-top
.page-btn         .page-btn.active       .page-btn:disabled       .page-btn.disabled
.page-btn.nav-btn .page-ellipsis         .page-jump-hint
```

> 历史 commit 用的是 `class="more"` / `class="sel"` / `<span>...</span>`（旧 `Util.createSlider()` 的产物）。`history.jsp` 里的 `renderPagination()` JS 已经做了旧 → 新 class 的翻译，所以新旧并存时仍能正确显示。

### 3.4 搜索结果卡（在 `index.jsp` / `search.jsp` 中使用）

```
.results-section       .results-header       .results-empty       .results-error       .results-list       .results-suggestions
.sort-bar              .sort-option          .sort-option.active  .sort-label         .sort-sep
.result-group-header   .group-root           .group-count
.result-file-card      .result-file-header   .file-link           .file-actions
.action-btn
.result-lines          .result-line          .result-line-overflow  .line-num       .line-code       .match
.result-expand-btn     .query-term           .result-meta-sep      .result-meta     .hint-label
```

### 3.5 关键 JS 函数（迁移时检查名字是否被 master 改过）

| JS 函数                   | 文件              | 作用                                       |
|-------------------------|-----------------|------------------------------------------|
| `renderPagination()`    | `index.jsp` 内联  | 客户端分页渲染                                  |
| `performInlineSearch()` | `index.jsp` 内联  | JS 驱动的搜索请求                               |
| `executeSearch()`       | `index.jsp` 内联  | 搜索执行                                     |
| `buildBreadcrumb()`     | `index.jsp` 内联  | 面包屑构造                                    |
| expand button click     | `search.jsp` 内联 | 展开 / 收起 `.result-file-card` 的 overflow 行 |

### 3.6 关键 Java / JSP 变量（迁移时检查名字是否被 master 改过）

| 变量                                                                                                                | 文件                        | 作用                                                   |
|-------------------------------------------------------------------------------------------------------------------|---------------------------|------------------------------------------------------|
| `_searchCfg`                                                                                                      | `search.jsp` / `more.jsp` | 局部 `PageConfig`，避免和 master 的 `cfg` 命名冲突              |
| `_searchOrder` `_searchStart` `_searchMax` `_searchTotal` `_searchThisPage` `_searchErrorMsg` `_searchSliderHtml` | `search.jsp`              | 搜索分页状态                                               |
| `_moreCfg`                                                                                                        | `more.jsp`                | `more.jsp` 的局部 `PageConfig`                          |
| `MAX_HITS_PER_CARD = 10`                                                                                          | `search.jsp` `<%! ... %>` | 单文件卡显示的默认命中行数                                        |
| `request.setAttribute(SearchHelper.REQUEST_ATTR, ...)`                                                            | 多个 jsp                    | 沿用 master 的 `WebappListener.requestDestroyed()` 清理钩子 |

---

## 四、与 master 同步时的迁移步骤

### 4.1 拉取 master 新提交后，建议迁移顺序

1. **拉取 master**：`git fetch origin` → `git log --oneline origin/master | head`
2. **对比文件清单**：`git diff --stat origin/master..HEAD -- opengrok-web/`，对比本文档「二、文件改动总览」，看 master 上有没有新增 / 改动了我们改过的同名文件
3. **按 A→F 顺序逐组处理**：

#### A 组（共享层 jspf）— 最容易冲突，先处理
- `pageheader.jspf`、`foot.jspf`、`httpheader.jspf`、`menu.jspf`、`projects.jspf`、`breadcrumb.jspf`、`chrome-guards.jspf`、`pager.jspf`
- **冲突点**：master 可能新增 CSS 类、新增 include；我们新增了 CSS 变量（`--bg` 等）和 logo `<a>` 链接
- **迁移方法**：保留 master 新增的 include + 我们新增的 CSS 变量 / class；合并后跑一次 `index.jsp` 验证 chrome 显示
- **httpheader.jspf 的 icon link**：迁移时务必保留两条我们新增的 `<link>`（指向 `new-touch-icon.svg`，`type="image/svg+xml"`），否则浏览器 tab favicon 会回退到旧 PNG。详见本文 **十**。

#### B 组（业务页面 jsp）— 体量大，建议分文件迁移
- `index.jsp`、`search.jsp`、`list.jsp`、`xref.jspf`、`history.jsp`、`diff.jsp`、`more.jsp`、`mast.jsp`、`minisearch.jspf`、`repos.jspf`
- **冲突点**：master 可能修改搜索结果渲染逻辑、目录树结构、新增排序选项
- **迁移方法**：保留我们新增的 jspf include（`pageheader.jspf`、`foot.jspf`、`pager.jspf`、`menu.jspf`、`chrome-guards.jspf`）和 class 名映射；保留 master 新增的字段映射到我们的渲染管线

#### C 组（辅助页 + JS）
- `help.jsp`、`settings.jsp`、`status.jsp`、`error.jsp`、`eforbidden.jsp`、`enoent.jsp`、`opensearch.jsp`、`rss.jsp`、`rss.xsl.xml`、`utils-0.0.48.js`、`searchable-option-list-2.0.16.js`
- **冲突点**：master 可能新增配置项
- **迁移方法**：保留我们的 chrome include；保留 master 新增的内容

#### D 组（Java）
- `CharacterEncodingFilter.java`（新增）、`GetFile.java`
- **冲突点**：master 可能修改 `GetFile.java`
- **迁移方法**：`CharacterEncodingFilter.java` 是纯新增文件，无冲突；`GetFile.java` 按 master 改动迁移后再应用我们的修改

#### E 组（tag 文件）
- 无需迁移（已删除的 4 个 tag 不再被引用）

#### F 组（配置）
- `web.xml`、`pom.xml`
- **冲突点**：master 可能新增 filter / servlet
- **迁移方法**：保留我们的 `CharacterEncodingFilter` 注册；保留 master 新增 filter 时按字母顺序插入到 `<filter>` 列表
- **运行时配置（非仓库内）**：不要忘了 `D:\Programs\opengrok\etc\configuration.xml` 里的两段手动改动——`authenticationTokens`（注入 token）+ `allowInsecureTokens=true`（HTTP 环境必加）。详见上文 **F.2**。master 同步后这两段不动。

### 4.2 关键 grep 命令

```bash
# 找 master 上 PageConfig 的方法是否改名
git diff origin/master..HEAD -- opengrok-web/src/main/java/ | grep -E "^\+.*public "

# 找所有 _search* 变量引用
grep -rn "_search" opengrok-web/src/main/webapp/

# 找所有 .page-btn 引用
grep -rn "page-btn" opengrok-web/src/main/webapp/

# 找所有 CSS 变量引用
grep -rn "\-\-accent\|\-\-bg\|\-\-surface" opengrok-web/src/main/webapp/

# 找所有 jspf include 调用
grep -rn "<%@ include" opengrok-web/src/main/webapp/
```

### 4.3 验收脚本（迁移完成后跑一遍）

| 路径                                                   | 期望                                                 |
|------------------------------------------------------|----------------------------------------------------|
| `http://localhost:8081/`                             | 新 UI 首页：搜索框 + 项目 chips + 仓库卡片网格                    |
| `http://localhost:8081/search?search=<keyword>`      | 新 UI 搜索结果：`.result-file-card` 卡片化 + `.page-btn` 分页 |
| `http://localhost:8081/help.jsp`                     | 新 UI 帮助页                                           |
| `http://localhost:8081/source?path=<file>`           | 新 UI 代码查看页面                                        |
| `http://localhost:8081/history?path=<file>`          | 新 UI 历史页（旧 `.more` `.sel` → 新 `.page-btn` 翻译正常）    |
| `http://localhost:8081/diff?path=<file1>&r2=<file2>` | 新 UI diff 页                                        |
| 浏览器硬刷新 (Ctrl+Shift+R)                                | 加载最新 CSS / JS                                      |

---

## 五、风险点（迁移时容易踩的坑）

1. **`history.jsp` 的旧 → 新 class 翻译**：我们在 `renderPagination()` JS 里把 `.more` → `.page-btn`、`.sel` → `.page-btn.active`、`<span>...</span>` → `.page-ellipsis`。如果 master 把 `Util.createSlider()` 的输出格式改了，翻译规则就失效，需要同步调整 `history.jsp` 的 replace 调用
2. **`search.jsp` 用的 `SearchEngine` 二次查询**：服务端版 fallback 直接 new `SearchEngine` 拉 hits；如果 master 修改了 `SearchEngine.results()` 的签名 / `Hit` 的字段（`getLineno()` / `getLine()`），search.jsp 的渲染逻辑要跟进
3. **`menu.jspf` 的 chip 选中修复**：早期有 bug 把 `selected` 写在 HTML 属性上，现在改成 `.selected` class。如果 master 又改回去或者改了 class 名，需要确认两边一致
4. **`httpheader.jspf` 的 CSS 变量**：所有页面（特别是 master 新加的页面）必须能依赖这些变量。如果 master 在 `httpheader.jspf` 里重命名 / 删除变量，新页面会失效
5. **`CharacterEncodingFilter` 必须挂上**：master 如果新增了别的 filter 并把它移到 `CharacterEncodingFilter` 之前，可能影响中文搜索请求编码
6. **Jetty 端口 8081 已硬编码到 `pom.xml`**：master 如果改回 8080，会和 Tomcat 8080 冲突；迁移时要确保 `<httpConnector><port>8081</port></httpConnector>` 还在

---

## 六、产物路径速查

| 产物                     | 路径                                                                                                     |
|------------------------|--------------------------------------------------------------------------------------------------------|
| 旧 UI war (Tomcat 8080) | `D:\Programs\apache_tomcat\webapps\source.war` 与 `D:\Programs\apache_tomcat\webapps\source\` — **不要碰** |
| 新 UI war 构建产物          | `D:\AppsData\deploy\opengrok\opengrok-web\target\source.war`                                           |
| 新 UI Jetty 启动端口        | 8081（由 `opengrok-web/pom.xml` 配置）                                                                      |
| 配置文件路径                 | `D:\Programs\opengrok\etc\configuration.xml`                                                           |
| 新版模块文档                 | `opengrok-web/docs/intro/open-grok-web-guide.md`（837 行）                                                |
| 运行步骤                   | `opengrok-web/docs/intro/run.md`                                                                       |
| 6 个设计稿                 | `opengrok-web/docs/ui/*.html`                                                                          |

---

## 七、运行 8081 端口方案（不干扰 8080）

> 摘录并扩充自 `docs/intro/run.md`。原则：**8080 = 现有 Tomcat，不动**；**8081 = Jetty `mvn jetty:run`**，完全独立的进程、独立的部署目录、独立的端口。

### 7.1 为什么选 Jetty 而不是新建一个 Tomcat 实例

- Jetty 由 `opengrok-web/pom.xml` 内的 `jetty-ee10-maven-plugin` 启动，**端口已在 pom 里硬编码为 8081**，所以不会和 Tomcat 8080 冲突
- 不需要复制 Tomcat 整个目录、不需要改 `server.xml`
- 直接复用 Maven 依赖，省去手动管理 jar 的麻烦
- 调试 JSP 时 `Ctrl+C` → `mvnw jetty:run` 即可重启

### 7.2 前置条件（一次性）

- **JDK 17+**（OpenGrok 1.14.x 要求）
- **Maven 3.8+**，或使用项目自带的 `mvnw.cmd`（推荐）
- **配置**：`D:\Programs\opengrok\etc\configuration.xml` 已存在且指向已索引的源码根
- **Tomcat 8080 正在跑**：旧 UI 维持不变

### 7.3 启动命令

在 **PowerShell** 下执行（在仓库根目录 `D:\AppsData\deploy\opengrok`）：

#### 步骤 1：安装父依赖（首次或 master 更新后必跑）

```powershell
.\mvnw.cmd -N install:install-file "-Dfile=pom.xml" "-DgroupId=org.opengrok" "-DartifactId=opengrok-top" "-Dversion=1.14.15" "-Dpackaging=pom"
```

#### 步骤 2：编译并安装依赖模块

```powershell
.\mvnw.cmd -DskipTests "-Dmaven.javadoc.skip=true" "-Dcheckstyle.skip=true" -pl opengrok-indexer,plugins,suggester,opengrok-web install
```

> 注：依赖模块指 `opengrok-indexer`、`plugins`、`suggester`、`opengrok-web`（顺序敏感）。如果只改了 `opengrok-web` 内的 JSP / JSPF，可以跳过步骤 1-2。

#### 步骤 3：构建 `target/source.war`（在 `opengrok-web/` 子目录）

```powershell
cd opengrok-web
..\mvnw.cmd -DskipTests clean package -q
```

这一步会跑 JSPC（JSP→Servlet 预编译）到 `target/jspc/`，并打成 `target/source.war`。

#### 步骤 4：启动 Jetty 开发服务器（端口 8081）

仍在 `opengrok-web/` 目录：

```powershell
..\mvnw.cmd -DskipTests jetty:run
```

启动后访问 **`http://localhost:8081/`** 即可看到重构后的新 UI 首页。

> ⚠ **修改 JSP 后必须重启 Jetty**：`mvn jetty:run` 用 JSPC 预编译产物，不会自动 watch JSP 改动。每次改 `.jsp` 后：
> 1. `Ctrl+C` 终止 jetty
> 2. `mvnw jetty:run` 重启
> 3. 浏览器 `Ctrl+Shift+R` 硬刷

#### 步骤 5（可选）：发布到正式 Tomcat（端口 8080）

> ⚠ **这一步是部署到 8080，会覆盖现有旧 UI**。如果只是想验证新 UI 效果，**不要执行这一步**。

```powershell
Stop-Service Tomcat9
Copy-Item "D:\Programs\apache_tomcat\webapps\source.war" "D:\Programs\apache_tomcat\webapps\source.war.bak" -Force
Copy-Item "D:\AppsData\deploy\opengrok\opengrok-web\target\source.war" "D:\Programs\apache_tomcat\webapps\source.war" -Force
Remove-Item -Recurse -Force "D:\Programs\apache_tomcat\webapps\source"
Start-Service Tomcat9
Start-Sleep -Seconds 8
```

访问 `http://localhost:8080/source/` 验证。

### 7.4 不干扰 8080 的关键点

| 关键点                                                     | 说明                                                                                           |
|---------------------------------------------------------|----------------------------------------------------------------------------------------------|
| 端口不冲突                                                   | Jetty 8081 vs Tomcat 8080，端口天然分离                                                             |
| 进程独立                                                    | Jetty 是 `mvn jetty:run` 的 JVM，Tomcat 是 `Tomcat9` 服务，互不影响                                     |
| 部署目录不冲突                                                 | Jetty 用 `opengrok-web/target/source.war`（临时）；Tomcat 用 `apache_tomcat/webapps/source.war`（固定） |
| 数据共享                                                    | 两个实例都指向同一个 `D:\Programs\opengrok\etc\configuration.xml`，索引数据一致                               |
| **不要**把 `target/source.war` 拷到 `apache_tomcat/webapps/` | 那会污染 8080 上的旧 UI                                                                             |
| **不要**改 `apache_tomcat\conf\server.xml`                 | 没必要，Jetty 已经有自己的端口配置                                                                         |

### 7.5 一键脚本（放进项目根目录的 `start-8081.ps1`）

```powershell
# start-8081.ps1 — 启动 Jetty 8081，不影响 Tomcat 8080
# 用法：cd D:\AppsData\deploy\opengrok ; .\start-8081.ps1
$ErrorActionPreference = 'Stop'

# 1. 检查 8081 是否已被占用
$port8081 = Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue
if ($port8081) {
    Write-Host "8081 已被占用，进程: PID $($port8081.OwningProcess)" -ForegroundColor Yellow
    $existing = Get-Process -Id $port8081.OwningProcess -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "进程名: $($existing.ProcessName)，启动时间: $($existing.StartTime)"
        $resp = Read-Host "要终止它再启动吗？ (y/N)"
        if ($resp -eq 'y' -or $resp -eq 'Y') {
            Stop-Process -Id $port8081.OwningProcess -Force
            Start-Sleep -Seconds 2
        } else {
            exit 1
        }
    }
}

# 2. 重新构建 war（增量）
Write-Host "[1/3] 构建 target/source.war ..." -ForegroundColor Cyan
Push-Location opengrok-web
try {
    ..\mvnw.cmd -DskipTests "-Dmaven.javadoc.skip=true" "-Dcheckstyle.skip=true" clean package -q
    if ($LASTEXITCODE -ne 0) { throw "构建失败" }
} finally {
    Pop-Location
}

# 3. 启动 Jetty（前台运行，Ctrl+C 终止）
Write-Host "[2/3] 启动 Jetty 8081 ..." -ForegroundColor Cyan
Write-Host "[3/3] 浏览器打开 http://localhost:8081/" -ForegroundColor Green
Push-Location opengrok-web
try {
    ..\mvnw.cmd -DskipTests jetty:run
} finally {
    Pop-Location
}
```

### 7.6 常见问题排查

| 现象                                     | 处理                                                                                                                   |
|----------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| 改了 `.jsp` 没生效                          | 重启 Jetty（Ctrl+C → `mvnw jetty:run`） + 浏览器硬刷新 Ctrl+Shift+R                                                            |
| Jetty 启动报 `port 8080 in use`           | 检查 `pom.xml` 的 `<httpConnector><port>` 是否还是 8081；如果被 master 改回 8080 改回来                                              |
| 8081 启动报 `port already in use`         | `Get-NetTCPConnection -LocalPort 8081` 找占用进程，按需 kill                                                                 |
| 改了 `style-*.css` / `default/img/*` 没变化 | DevTools Network 勾"Disable cache"，或硬刷新                                                                               |
| autocomplete 下拉无内容 / 项目名 baseline 不齐   | 看 `docs/plan/ui-refactor.md` 的对应修改条目排查                                                                               |
| 中文搜索无结果                                | 检查 `web.xml` 的 `CharacterEncodingFilter` 是否还在、`<dispatcher>REQUEST</dispatcher><dispatcher>FORWARD</dispatcher>` 是否齐 |

---

## 八、一句话总结

> **本次重构把 `opengrok-web/src/main/webapp/` 下 50 个文件改成新 UI 风格（卡片 + 中文 + CSS 变量 + 现代字体），新增 4 个 jspf / 1 个 Filter / 1 个 Filter 配置 / 6 个设计稿 / 1 份运行文档，删除 4 个不再使用的 tag 文件。新 UI 在 Jetty 8081 上跑（旧 UI Tomcat 8080 不动），迁移 master 时按 A→F 顺序逐组处理，重点保护 jspf include + CSS 变量 + `_search*` 等关键命名。**

---

## 九、补充：运行时配置文件 `configuration.xml` 的两处手动改动

这两处改动**不在 Git 仓库内**，但对 8081 Jetty 上跑新版 UI 至关重要。

| # | 改动                                                                       | 原因                                                                                                               | 影响范围             |
|---|--------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------|------------------|
| 1 | 新增 `<void property="authenticationTokens">` 块，注入 token `dev-token-123`   | master 的 `IncomingFilter`（commit `76502c4bd`）已删除 localhost bypass。`/api/v1/application.wadl` 不在白名单，无 token 即 401 | 8081 + 升级后的 8080 |
| 2 | 新增 `<void property="allowInsecureTokens"><boolean>true</boolean></void>` | 本地开发全是 HTTP，`request.isSecure()` 永远 false；不开此项 token 也通不过                                                        | 同上               |

**XML 片段（完整 diff）**：

```diff
   <void property="tagsEnabled">
    <object idref="Boolean0"/>
   </void>
+  <void property="authenticationTokens">
+   <object class="java.util.HashSet">
+    <void method="add">
+     <string>dev-token-123</string>
+    </void>
+   </object>
+  </void>
+  <void property="allowInsecureTokens">
+   <boolean>true</boolean>
+  </void>
  </object>
 </java>
```

**生产部署 checklist**（任何时候把 UI 搬到新机器或新 Tomcat 实例时都要做一次）：

1. 备份：`Copy-Item "D:\Programs\opengrok\etc\configuration.xml" "configuration.xml.bak" -Force`
2. 注入上面这两段
3. **把 `<string>dev-token-123</string>` 换成至少 32 位的随机串**（生产用）
4. **生产环境把 `allowInsecureTokens` 改回 `false` 并配 HTTPS**
5. 重启两个端口让 `RuntimeEnvironment` 缓存的 token 集合刷新

**验证**：

```powershell
# 8081 应返回 200
irm -Headers @{Authorization = "Bearer dev-token-123"} `
     "http://localhost:8081/api/v1/application.wadl"
```

```bash
curl -H "Authorization: Bearer dev-token-123" http://localhost:8081/api/v1/application.wadl
```

详见上文 **F.2** 段（含 why / what / 迁移检查清单）。

---

## 十、补充：品牌图标 SVG 化（`new-touch-icon.svg`）

### 10.1 背景

旧 UI 的浏览器标签页 favicon / PWA icon 是 `default/img/apple-touch-icon.png`（512×512 栅格 PNG）。本次重构新画一张矢量 SVG，与 `favicon.svg` 共用 `{O` 路径数据，确保任意 DPI 下边缘都干净；同时给 Android launcher 加白底圆角以兼容 `purpose: "any maskable"`。

### 10.2 文件改动

| 文件                                                       | 类型     | 行数 +/− | 作用              | 关键改动                                                                                                                                                          |
|----------------------------------------------------------|--------|---------|-----------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `src/main/webapp/default/img/new-touch-icon.svg`         | **新增** | +41     | 512×512 矢量图标    | 复刻 `favicon.svg` 的 `{` / `O` 路径（`#656664` / `#4783A3`），viewBox `0 0 16 16`，外面套 `clipPath rx=3.2` + 白色 `<rect>` 做 maskable 安全边                                            |
| `src/main/webapp/manifest.json`                          | 修改     | +7/-3   | PWA manifest    | `icons[]` 第一项改为新 SVG（`type: image/svg+xml` / `sizes: any` / `purpose: any maskable`），保留 PNG 作为 fallback                                                          |
| `src/main/webapp/httpheader.jspf`                        | 修改     | +2      | `<head>` 标签     | **关键**：浏览器 tab favicon 由这里决定，不读 `manifest.json`。在原 `<link rel="icon">` 之前插入 `<link rel="icon" type="image/svg+xml" sizes="any" href=".../new-touch-icon.svg">`；同时给 `<link rel="apple-touch-icon">` 加 SVG 版本 |

### 10.3 为什么仅改 `manifest.json` 不够

`manifest.json` 是 **PWA only** 协议——浏览器仅在「安装为 PWA」或「添加到主屏幕」时才读取 `icons[]`。日常浏览的 tab favicon 完全由 `<link rel="icon">` 决定。一开始只更新了 `manifest.json`，结果浏览器 tab 仍然展示旧的 PNG，于是有了 10.2 里 `httpheader.jspf` 的那一行额外 `<link>`——这才是真正让新图标生效的位置。

### 10.4 迁移到 master 时

| 文件                  | 操作                                                                                                                                                       |
|---------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------|
| `new-touch-icon.svg` | master 上不存在 → 直接把 `default/img/new-touch-icon.svg` 拷过去（**新增文件**，不会冲突）                                                                                       |
| `manifest.json`     | master 可能改过 `icons[]`。合并时保留我们把 SVG 放在数组第一位的改动，其余按 master 来的 merge                                                                                                  |
| `httpheader.jspf`   | 合并时检查 `<link rel="icon" ...>` 块，确保我们加的两条 link 都还在：① `type="image/svg+xml" sizes="any" href=".../new-touch-icon.svg"`；② `rel="apple-touch-icon" type="image/svg+xml" sizes="any" href=".../new-touch-icon.svg"` |

### 10.5 验证清单

- [ ] DevTools → Network → 过滤 `img` 类型，确认对 `http://localhost:8081/` 的请求里出现 `new-touch-icon.svg` 200，Content-Type `image/svg+xml`
- [ ] DevTools → Application → Manifest，确认 `icons[]` 第一项是 SVG 且 `purpose: "any maskable"`
- [ ] 浏览器 tab 收藏夹图标 → 应显示 `{O` 矢量标记
- [ ] Android Chrome → 菜单 → 添加到主屏幕 → 启动器图标 → 应显示白底圆角版本
