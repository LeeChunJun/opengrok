# OpenGrok Web 模块全面解析

## 一、模块概述

`opengrok-web` 是 OpenGrok 源码浏览器和搜索引擎的 **Web 应用层**。它同时提供 **JSP 页面 UI** 和 **RESTful API**，用于浏览、搜索和管理源代码仓库。

- **打包方式**: WAR 文件（`source.war`，版本 1.14.15）
- **核心技术**: Jakarta EE（Servlets 6.0, JSP, JAX-RS/Jersey）、Apache Lucene、Micrometer 指标、WebJars
- **依赖模块**: `opengrok`（核心索引器）、`suggester`（自动补全）

---

## 二、整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    Servlet Container (Tomcat 10.x)               │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │                    Filter Chain（过滤器链）                 │    │
│  │  CharacterEncoding → Statistics → Authorization →         │    │
│  │  ResponseHeader → CookieFilter                            │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                   │
│  ┌─────────────────────┐       ┌──────────────────────────┐     │
│  │    JSP 页面层         │       │   REST API (/api/v1)      │     │
│  │    (用户交互界面)      │       │   (程序化接口)             │     │
│  │                      │       │   ├── Controllers         │     │
│  │  index.jsp (首页)     │       │   ├── Filters             │     │
│  │  search.jsp (搜索)    │       │   ├── Error Mappers       │     │
│  │  list.jsp (浏览)      │       │   └── Suggester           │     │
│  │  diff.jsp (对比)      │       │       ├── Service         │     │
│  │  history.jsp (历史)   │       │       ├── Query Parser    │     │
│  │  more.jsp (上下文)    │       │       └── Filters         │     │
│  │  ...                 │       │                            │     │
│  │         ↓            │       └──────────────────────────┘     │
│  │  ┌────────────────┐ │                                          │
│  │  │ PageConfig      │ │    ┌──────────────────────────┐        │
│  │  │ ProjectHelper   │ │    │   核心依赖层               │        │
│  │  │ DirectoryListing│ │    │  RuntimeEnvironment       │        │
│  │  │ DiffData        │ │    │  HistoryGuru              │        │
│  │  │ Scripts         │ │    │  AuthorizationFramework   │        │
│  │  └────────────────┘ │    │  SearchEngine             │        │
│  └─────────────────────┘    │  IndexDatabase             │        │
│                              │  Suggester                │        │
│                              └──────────────────────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 三、请求处理流程

### 3.1 典型请求生命周期

```
用户浏览器 → Filter链 → Servlet/JSP → PageConfig(数据准备) → JSP渲染 → HTML响应
             │
             ├── 1. CharacterEncodingFilter: 强制UTF-8编码
             ├── 2. StatisticsFilter: 记录请求指标(Micrometer)
             ├── 3. AuthorizationFilter: 检查项目访问权限
             ├── 4. ResponseHeaderFilter: 添加缓存头(30min/1day/1year)
             └── 5. CookieFilter: 添加SameSite=Strict; Secure
```

### 3.2 数据流向

```
web.xml 配置 → Servlet/JSP 路由 → PageConfig.get(request) 懒加载数据
                                          │
                                    ┌─────┼─────────┐
                                    ↓     ↓         ↓
                              RuntimeEnv  HistoryGuru  SearchEngine
                              (配置)     (SCM历史)    (Lucene搜索)
                                    ↓     ↓         ↓
                              ┌──────────────────────────┐
                              │     JSP 页面渲染           │
                              │  使用 PageConfig 提供的     │
                              │  数据生成 HTML              │
                              └──────────────────────────┘
```

---

## 四、URL 路由映射（web.xml）

| Servlet | URL Pattern | 处理类/JSP | 功能说明 |
|---------|-------------|-----------|---------|
| search | `/search`, `/s` | search.jsp | 全文搜索结果页 |
| opensearch | `/opensearch` | opensearch.jsp | OpenSearch 描述 XML |
| history | `/history/*` | history.jsp | 文件/目录版本历史 |
| lister | `/xref/*` | list.jsp | 目录列表 / 源码交叉引用 |
| raw | `/raw/*` | GetFile.java | 原始文件内容（text/plain） |
| download | `/download/*` | GetFile.java | 文件下载（Content-Disposition: attachment） |
| diff | `/diff/*` | diff.jsp | 两版本差异对比 |
| more | `/more/*` | more.jsp | 搜索匹配行上下文展示 |
| rss | `/rss/*` | rss.jsp | RSS 2.0 订阅源 |
| error | `/error` | error.jsp | 500 通用错误页 |
| enoent | `/enoent` | enoent.jsp | 404 资源不存在 |
| eforbidden | `/eforbidden` | eforbidden.jsp | 403 访问被拒绝 |

**REST API 路由**: `/api/v1/*` → Jersey JAX-RS（RestApp.java 注册）

---

## 五、核心 Java 文件详解

### 5.1 基础层（`org.opengrok.web`）

#### PageConfig.java —— 请求级数据中心
- **角色**: 所有 JSP 页面的核心数据提供者，每个请求一个实例
- **核心能力**:
  - 路径解析：`getPath()`, `getResourceFile()`, `getUriEncodedPath()`
  - 项目管理：`getProject()`, `getRequestedProjects()`, `isAllowed()`
  - 搜索准备：`getQueryBuilder()`, `prepareSearch()`, `getSortOrder()`
  - Diff 数据：`getDiffData()`, `getDiffType()`, `fullDiff()`
  - 历史/注释：`hasHistory()`, `hasAnnotations()`, `getAnnotation()`
  - 缓存验证：`isNotModified()`, `getEtag()`
  - UI 辅助：`getTitle()`, `getSearchTitle()`, `getPathTitle()`
- **常量**: `OPEN_GROK_PROJECT`（Cookie名）、`DUMMY_REVISION`、`SORTING_COOKIE_NAME`
- **依赖**: 几乎所有核心类

#### ProjectHelper.java —— 项目/分组组织器
- **角色**: 为 UI 展示预处理项目、仓库和分组信息
- **核心方法**:
  - `getInstance(PageConfig)` — 请求级单例
  - `getGroups()` — 过滤后的分组（考虑权限）
  - `getProjects()` / `getRepositories()` — 未分组的项目/仓库
  - `getGroupedProjects()` / `getGroupedRepositories()` — 已分组的项目/仓库
  - `hasFavourite()` / `isFavourite()` — 基于 Cookie 的收藏检测
  - `getRepositoryInfo()` / `getSortedRepositoryInfo()` — 仓库元数据
- **设计**: 结果缓存在 request 属性中，避免重复计算

#### DirectoryListing.java —— 目录列表生成器
- **角色**: 生成带文件元数据的 HTML 目录列表
- **核心方法**:
  - `listTo()` / `extraListTo()` — 生成完整 HTML 文件表格
  - `createDirectoryEntries()` — 构建带历史日期、描述、行数的条目列表
  - `printDateSize()` — 输出修改日期和文件大小的表格单元格
  - `printNumlines()` / `printLoc()` — 输出行数/代码行列
  - `getSimplifiedPath()` — 穿越单子目录简化路径
- **依赖**: `EftarFileReader`（路径描述）、`HistoryGuru`（修改日期）

#### DiffData.java —— Diff 数据容器
- **角色**: 持有渲染 diff 视图所需的全部数据
- **关键字段**: `path`, `filename`, `genre`, `revision`, `param[]`, `rev[]`, `file[][]`（两版本的逐行内容）, `type`(DiffType), `full`

#### DiffType.java —— Diff 显示格式枚举
- **枚举值**:
  - `SIDEBYSIDE` ('s', "sdiff") — 并排对比
  - `UNIFIED` ('u', "udiff") — 统一 diff（带上下文）
  - `TEXT` ('t', "text") — 传统 ed diff
  - `OLD` ('o', "old") — 仅旧版本
  - `NEW` ('n', "new") — 仅新版本

#### GetFile.java —— 文件下载 Servlet
- **角色**: 服务 `/raw` 和 `/download` URL
- **核心逻辑**:
  - 支持通过 `HistoryGuru` 获取指定版本文件
  - HTTP 缓存支持（`If-Modified-Since` / `Last-Modified`）
  - `/download` 设置 `Content-Disposition: attachment`
  - `/raw` 以 `text/plain` 输出
  - 8KB 块流式传输

#### Scripts.java —— JavaScript 资源管理器
- **角色**: 管理 JSP 页面的 JS 资源，按优先级排序
- **预注册脚本**: jQuery 3.6.4, jQuery UI, tablesorter, searchable-option-list, utils, repos, diff, jquery-caret
- **核心方法**: `addScript()`, `toHtml()` — 生成排序后的 `<script>` 标签

### 5.2 过滤器层

#### AuthorizationFilter.java —— 访问控制过滤器
- **角色**: 对所有 HTTP 请求执行授权检查
- **核心逻辑**:
  - REST API 路径 (`/api/v1/*`) 豁免（它们有自己的 `IncomingFilter`）
  - 使用 `PageConfig` 确定请求对应的项目
  - 通过 `AuthorizationFramework` 检查用户权限
  - 未授权返回 HTTP 403，支持自定义错误页

#### CharacterEncodingFilter.java —— 编码过滤器
- **角色**: 强制 UTF-8 编码，防止乱码
- **设计**: 应在 web.xml 中排第一位

#### CookieFilter.java —— Cookie 安全过滤器
- **角色**: 为所有 Cookie 添加 `SameSite` 和 `Secure` 属性
- **配置**: 通过 web.xml 过滤器初始化参数

#### ResponseHeaderFilter.java —— 响应头过滤器
- **角色**: 添加配置的 HTTP 响应头（如 Cache-Control）
- **用途**: 不同 URL 模式设置不同缓存策略（30分钟/1天/1年）

#### StatisticsFilter.java —— 指标收集过滤器
- **角色**: 使用 Micrometer/Prometheus 收集请求指标
- **指标**:
  - `requests` — 请求分布统计
  - `requests.latency` — 按类别和状态码统计延迟
  - `search.latency` — 搜索操作延迟

### 5.3 生命周期

#### WebappListener.java —— 应用生命周期监听器
- **contextInitialized()（启动）**:
  1. 检查 Java 版本兼容性
  2. 读取配置（`configuration.xml`）
  3. 验证 Tomcat 版本（需要 10.x）
  4. 初始化 `AuthorizationFramework`
  5. 可选验证 Universal Ctags
  6. 启动授权看门狗
  7. 执行索引版本检查（`IndexCheck`）
  8. 启动过期定时器
  9. 初始化 `ApiTaskManager`（异步任务线程池）
- **contextDestroyed()（关闭）**:
  - 关闭执行器（revision, search, directory listing）
  - 关闭 `SuggesterService`
  - 关闭 `ApiTaskManager`
- **requestDestroyed()**: 清理 `PageConfig`, `SearchHelper`

#### WebappError.java —— 自定义错误类
- 用于 Web 应用初始化失败

### 5.4 工具类（`org.opengrok.web.util`）

| 文件 | 功能 |
|------|------|
| `DTOUtil.java` | 使用 CGLIB + ModelMapper 从领域对象创建 DTO |
| `FileUtil.java` | 安全的文件路径解析，防止路径穿越攻击 |
| `NoPathParameterException.java` | 缺少 `path` 参数时抛出的异常 |

### 5.5 Servlet

| 文件 | 功能 |
|------|------|
| `MetricsServlet.java` | 在 `/metrics/prometheus` 暴露 Prometheus 指标 |

---

## 六、REST API 文件详解（`org.opengrok.web.api`）

### 6.1 API 基础设施

#### ApiTask.java —— 异步任务
- **状态流转**: `INITIAL` → `SUBMITTED` → `COMPLETED`
- **核心方法**: `getCallable()`, `getResponse()`, `mapExceptionToStatus()`, `getUuid()`

#### ApiTaskManager.java —— 异步任务管理器（单例）
- **核心方法**:
  - `submitApiTask()` — 提交到命名队列，返回 202 ACCEPTED
  - `getApiTask()` — 按 UUID 获取任务
  - `deleteApiTask()` — 删除已完成任务
  - `addPool()` — 创建命名线程池
  - `shutdown()` — 优雅关闭（60秒超时）

### 6.2 错误处理（`api.error`）

| 文件 | 功能 |
|------|------|
| `ExceptionMapperUtils.java` | 异常→JSON 错误响应转换工具 |
| `GenericExceptionMapper.java` | 兜底：所有异常 → 500 |
| `ValidationExceptionMapper.java` | `ValidationException` → 400 |
| `WebApplicationExceptionMapper.java` | 透传 `WebApplicationException` |

### 6.3 REST 应用配置（`api.v1`）

#### RestApp.java —— JAX-RS 应用入口
- **API 路径**: `/api/v1`
- 注册所有 Controller、Filter、ErrorMapper、SuggesterAppBinder

#### 异常映射器
| 文件 | 功能 |
|------|------|
| `FileNotFoundExceptionMapper.java` | `FileNotFoundException` → 404 |
| `NoPathParameterExceptionMapper.java` | `NoPathParameterException` → 400 |

### 6.4 API 过滤器（`api.v1.filter`）

| 文件 | 注解 | 功能 |
|------|------|------|
| `IncomingFilter.java` | — | API 认证：验证 Bearer Token，白名单路径放行，要求 HTTPS |
| `PathAuthorizationFilter.java` | `@PathAuthorized` | 检查 `path` 参数对应项目的访问权限 |
| `CorsFilter.java` | `@CorsEnable` | 添加 `Access-Control-Allow-Origin: *` |
| `CorsEnable.java` | — | 名称绑定注解，标记启用 CORS 的端点 |
| `PathAuthorized.java` | — | 名称绑定注解，标记需要路径授权的端点 |

### 6.5 API 控制器（`api.v1.controller`）

#### AnnotationController.java —— 文件注释/Blame
- **路径**: `/api/v1/annotation`
- **端点**: `GET ?path=...&revision=...`
- **返回**: `AnnotationDTO` 列表（revision, author, description, version）

#### ConfigurationController.java —— 配置管理
- **路径**: `/api/v1/configuration`
- **端点**:
  - `GET` — 返回完整配置 XML
  - `PUT` — 应用新配置（异步）
  - `GET /{field}` — 读取单个配置字段
  - `PUT /{field}` — 设置单个字段（异步）
  - `POST /authorization/reload` — 重载授权插件（异步）

#### DirectoryListingController.java —— 目录列表
- **路径**: `/api/v1/list`
- **端点**: `GET ?path=...`
- **返回**: `DirectoryEntryDTO` 列表（path, numLines, loc, date, description, isDirectory, size）

#### FileController.java —— 文件内容与元数据
- **路径**: `/api/v1/file`
- **端点**:
  - `GET /content` — 文件内容（text/plain 或 octet-stream）
  - `GET /genre` — 文件类型/种类
  - `GET /defs` — 定义（标签）JSON 数组

#### GroupsController.java —— 分组管理
- **路径**: `/api/v1/groups`
- **端点**:
  - `GET` — 列出所有分组名
  - `GET /{group}/allprojects` — 组内所有项目
  - `GET /{group}/pattern` — 组匹配模式
  - `POST /{group}/match` — 测试项目名是否匹配

#### HistoryController.java —— 版本历史
- **路径**: `/api/v1/history`
- **端点**: `GET ?path=...&withFiles=...&max=...&start=...`
- **返回**: `HistoryDTO`（`HistoryEntryDTO` 列表 + 分页信息）

#### MessagesController.java —— 系统消息
- **路径**: `/api/v1/messages`
- **端点**:
  - `POST` — 添加消息
  - `DELETE ?tag=...` — 按标签删除
  - `GET ?tag=...` — 获取消息

#### ProjectsController.java —— 项目生命周期管理
- **路径**: `/api/v1/projects`
- **端点**:
  - `POST` — 添加项目（发现仓库）（异步）
  - `DELETE /{project}` — 删除项目配置和数据（异步）
  - `DELETE /{project}/data` — 删除索引/交叉引用数据（异步）
  - `DELETE /{project}/historycache` — 删除历史缓存（异步）
  - `DELETE /{project}/annotationcache` — 删除注释缓存（异步）
  - `PUT /{project}/indexed` — 标记已索引，刷新搜索器，重建建议器（异步）
  - `PUT/GET /{project}/property/{field}` — 读写项目属性
  - `GET` — 列出所有项目名
  - `GET /indexed` — 列出已索引项目名
  - `GET /{project}/repositories` — 列出仓库路径
  - `GET /{project}/repositories/type` — 列出仓库类型
  - `GET /{project}/files` — 列出已索引文件

#### RepositoriesController.java —— 仓库属性
- **路径**: `/api/v1/repositories`
- **端点**: `GET /property/{field}?repository=...`

#### SearchController.java —— 全文搜索
- **路径**: `/api/v1/search`
- **端点**: `GET` 参数: `full`, `def`, `symbol`, `path`, `hist`, `type`, `projects`, `maxresults`, `start`, `sort`, `maxhitsperfile`
- **返回**: `SearchResult` 记录（time, resultCount, results, startDocument, endDocument）
- **内部**: 使用 `SearchEngine`，通知 suggester 搜索行为

#### StatusController.java —— 异步任务状态
- **路径**: `/api/v1/status`
- **端点**:
  - `GET /{uuid}` — 返回任务结果（200）或仍在运行（202）
  - `DELETE /{uuid}` — 删除已完成任务

#### SuggesterController.java —— 自动补全
- **路径**: `/api/v1/suggest`
- **端点**:
  - `GET` — 获取查询建议
  - `GET /config` — 获取建议器配置
  - `PUT /rebuild` — 重建所有建议数据
  - `PUT /rebuild/{project}` — 重建项目建议数据
  - `POST /init/queries` — 从 URL 初始化热度数据
  - `POST /init/raw` — 从词条增量初始化热度
  - `GET /popularity/{project}` — 获取热门搜索词

#### SystemController.java —— 系统操作
- **路径**: `/api/v1/system`
- **端点**:
  - `PUT /includes/reload` — 重载包含文件
  - `POST /pathdesc` — 加载路径描述到 Eftar 文件
  - `GET /indextime` — 获取最后索引时间（ISO 8601）
  - `GET /version` — 获取版本号
  - `GET /ping` — 健康检查（返回空 200）

### 6.6 建议器子系统（`api.v1.suggester`）

#### 核心组件

| 文件 | 角色 |
|------|------|
| `SuggesterAppBinder.java` | Jersey DI 绑定器，绑定 `SuggesterService` 单例 |
| `model/SuggesterData.java` | 处理后的建议请求数据（query, projects, identifier） |
| `model/SuggesterQueryData.java` | 原始 HTTP 请求参数（@QueryParam 绑定） |
| `parser/SuggesterQueryDataParser.java` | 将原始参数转为 `SuggesterData`，在光标位置插入随机标识符 |

#### 过滤器

| 文件 | 功能 |
|------|------|
| `filter/AuthorizationFilter.java` | 检查每个项目的访问权限 |
| `filter/Authorized.java` | 名称绑定注解 |
| `filter/Suggester.java` | 名称绑定注解（建议器端点标记） |
| `filter/SuggestionsEnabledFilter.java` | 检查建议器是否启用，未启用返回 404 |
| `ParseExceptionMapper.java` | Lucene `ParseException` → 400 |

#### 服务层

| 文件 | 功能 |
|------|------|
| `service/SuggesterService.java` | 接口：`getSuggestions()`, `refresh()`, `rebuild()`, `delete()`, `onSearch()`, `close()` |
| `service/SuggesterServiceFactory.java` | 获取 `SuggesterService` 单例的工厂 |
| `service/impl/SuggesterServiceImpl.java` | 完整实现：后台线程初始化、定期重建（cron）、`ReadWriteLock` 线程安全 |

#### 查询处理

| 文件 | 功能 |
|------|------|
| `query/SuggesterQueryBuilder.java` | 自定义 `QueryBuilder`，对目标字段使用 `SuggesterQueryParser` |
| `query/SuggesterQueryParser.java` | Lucene 查询解析器，将查询拆分为 `SuggesterQuery`（用于建议）和普通 `Query`（用于过滤）。支持前缀、通配符、正则、模糊、短语、范围查询 |

---

## 七、JSP/JSPF 文件详解

### 7.1 页面文件（`.jsp`）

#### index.jsp —— 首页
- **功能**: 应用主入口，展示搜索界面和仓库卡片
- **结构**: `search-hero`（搜索表单）→ `#results`（内容区）→ `#repo-section`（仓库卡片网格）
- **包含**: `projects.jspf`, `httpheader.jspf`, `pageheader.jspf`, `menu.jspf`, `repos.jspf`, `foot.jspf`

#### search.jsp —— 搜索结果页
- **功能**: 执行 Lucene 搜索并展示分页结果
- **关键变量**: `SearchHelper`, `QueryBuilder`, `Suggestion`（提示）, `SortOrder`
- **特性**: 支持全文、定义、符号、路径、历史、类型搜索；分页；排序（相关性/日期）；"您可能想找"建议
- **包含**: `projects.jspf`, `httpheader.jspf`, `pageheader.jspf`, `foot.jspf`

#### list.jsp —— 文件浏览器/交叉引用查看器（最复杂页面）
- **功能**: 目录列表 **或** 源码交叉引用
- **逻辑分支**:
  1. 目录 → 文件表格（名称/日期/大小/行数/LOC/操作）+ README 渲染
  2. 文件 + 最新版本 → 缓存的 xref 或 annotate
  3. 文件 + 历史版本 → 包含 `xref.jspf` 即时生成
  4. 根据 Genre（IMAGE/HTML/PLAIN）分别处理
- **包含**: `mast.jsp`, `xref.jspf`（按需）, `foot.jspf`

#### diff.jsp —— 差异对比查看器
- **功能**: 展示文件两个版本间的差异
- **支持格式**: Text / Side-by-Side / Unified / Old / New
- **特性**: 完整/紧凑视图切换、diff 下载（.diff 文件）、图片并排对比
- **渲染**: 遍历 `Delta` 对象，使用 `Util.diffline()` 进行内联高亮
- **包含**: `httpheader.jspf`, `pageheader.jspf`, `foot.jspf`

#### history.jsp —— 版本历史查看器
- **功能**: 展示文件/目录的 SCM 提交历史
- **特性**:
  - 修订标签（可切换）
  - Bug/Review 模式链接化
  - 修订对比单选按钮（POST 到 diff 页面）
  - 每个提交的修改文件列表
  - 长提交消息的"展开/收起"
  - 分页滑块
- **包含**: `httpheader.jspf`, `pageheader.jspf`, `minisearch.jspf`, `foot.jspf`

#### more.jsp —— 上下文查看器
- **功能**: 展示文件中所有匹配搜索查询的行及其上下文
- **逻辑**: `docId >= 0` 时使用 `SourceContext`，否则回退到重新分析
- **包含**: `mast.jsp`, `foot.jspf`

#### help.jsp —— 帮助页
- **功能**: 搜索语法和使用帮助
- **包含**: `httpheader.jspf`, `pageheader.jspf`, `foot.jspf`

#### settings.jsp —— 用户设置页
- **功能**: 客户端偏好设置
- **设置项**: 主题（auto/light/dark）、建议器开关
- **存储**: `localStorage`
- **包含**: `httpheader.jspf`, `pageheader.jspf`, `foot.jspf`

#### status.jsp —— 服务器状态页
- **功能**: 管理员诊断页面
- **行为**: 默认显示安全提示；`chattyStatusPage=true` 时 dump 所有内部配置
- **包含**: `projects.jspf`, `httpheader.jspf`, `pageheader.jspf`, `foot.jspf`

#### error.jsp —— 500 错误页
- **功能**: 通用错误捕获页
- **内容**: 红色错误标题、配置问题、异常消息、堆栈跟踪

#### eforbidden.jsp —— 403 错误页
- **功能**: 访问被拒绝页面

#### enoent.jsp —— 404 错误页
- **功能**: 资源不存在页面

#### opensearch.jsp —— OpenSearch 描述
- **功能**: 输出 XML `OpenSearchDescription`，允许浏览器添加 OpenGrok 为搜索引擎
- **包含**: `projects.jspf`

#### rss.jsp —— RSS 订阅源
- **功能**: 将版本历史以 RSS 2.0 格式输出
- **条目**: 最多 20 条，包含标题（版本+消息首行）、链接、描述（完整消息+文件列表）、日期、作者

#### mast.jsp —— 主头部片段
- **功能**: 文件导向页面的共享预处理和头部
- **处理**: 检查 `isUnreadable()` → 403、`canProcess()` → 重定向/404、`isNotModified()` → 304
- **被包含于**: `list.jsp`, `more.jsp`

### 7.2 片段文件（`.jspf`）

#### httpheader.jspf —— HTML `<head>` 生成器
- **被所有页面包含**
- **输出**: `<!DOCTYPE html>` → `<html>` → `<head>`: charset, viewport, robots, theme-color, favicon, 字体预加载, 主题初始化脚本, CSS, JS 注册, RSS 自动发现, OpenSearch 链接, `<title>`

#### pageheader.jspf —— 站点页头
- **被所有页面包含**
- **输出**: Logo SVG + 标题 "OpenGrok Code Search" + "代码浏览" 链接

#### foot.jspf —— 站点页脚
- **被所有页面包含**
- **输出**: 版本信息、最后索引更新时间、自定义页脚内容、关闭 HTML 标签、注入所有 JS

#### menu.jspf —— 完整搜索表单
- **被包含于**: `index.jsp`
- **内容**:
  - 项目选择区（标签 + 全选/反选/清除 + chip UI）
  - 主搜索输入框（⌘K 快捷键）
  - 高级搜索面板（定义、符号、文件路径、历史）
  - 文件类型筛选下拉
  - 搜索/清除/帮助/设置按钮

#### minisearch.jspf —— 精简内联搜索表单
- **被包含于**: `history.jsp`
- **内容**: 文本输入 + 提交按钮 + "当前目录"复选框

#### projects.jspf —— 项目 Cookie 处理器
- **被包含于**: `index.jsp`, `search.jsp`, `opensearch.jsp`, `status.jsp`
- **功能**: 设置/更新项目选择 Cookie（`PageConfig.OPEN_GROK_PROJECT`）

#### repos.jspf —— 仓库卡片网格
- **被包含于**: `index.jsp`
- **功能**: 展示所有已索引仓库的可视化卡片
- **卡片内容**: 项目名、仓库类型徽章、远程 URL、当前分支、短版本号

#### xref.jspf —— 即时交叉引用生成器
- **被包含于**: `list.jsp`（无缓存 xref 时）
- **逻辑**:
  1. 通过 `AnalyzerGuru` 确定文件类型
  2. PLAIN → 运行 ctags 获取定义 → `writeDumpedXref()`
  3. IMAGE → 显示 `<img>`
  4. HTML → `Util.dumpXref()` 链接转换
  5. DATA/二进制 → 提供下载链接

### 7.3 其他 Web 资源

| 文件 | 功能 |
|------|------|
| `rss.xsl.xml` | RSS XSL 样式表，浏览器打开 RSS 时转换为可读 HTML |
| `META-INF/context.xml` | Tomcat 上下文描述符，设置路径为 `/source` |

---

## 八、JSP 页面包含关系图

```
index.jsp ──┬── projects.jspf (Cookie)
            ├── httpheader.jspf → (HTML <head>)
            ├── pageheader.jspf → (站点页头)
            ├── menu.jspf → (完整搜索表单)
            ├── repos.jspf → (仓库卡片)
            └── foot.jspf → (页脚 + 脚本)

search.jsp ─┬── projects.jspf
            ├── httpheader.jspf
            ├── pageheader.jspf
            └── foot.jspf

list.jsp ───┬── mast.jsp ──┬── httpheader.jspf
            │              └── pageheader.jspf
            ├── xref.jspf (按需)
            └── foot.jspf

diff.jsp ───┬── httpheader.jspf
            ├── pageheader.jspf
            └── foot.jspf

history.jsp ┬── httpheader.jspf
            ├── pageheader.jspf
            ├── minisearch.jspf
            └── foot.jspf

more.jsp ───┬── mast.jsp
            └── foot.jspf

help.jsp ───┬── httpheader.jspf
            ├── pageheader.jspf
            └── foot.jspf

settings.jsp ┬── httpheader.jspf
             ├── pageheader.jspf
             └── foot.jspf

status.jsp ─┬── projects.jspf
            ├── httpheader.jspf
            ├── pageheader.jspf
            └── foot.jspf

error.jsp ──┬── httpheader.jspf
            ├── pageheader.jspf
            └── foot.jspf

eforbidden.jsp ┬── httpheader.jspf
               ├── pageheader.jspf
               └── foot.jspf

enoent.jsp ───┬── httpheader.jspf
              ├── pageheader.jspf
              └── foot.jspf
```

---

## 九、JSP 页面使用的核心共享类

| 类/变量 | 使用页面 | 用途 |
|---------|---------|------|
| `PageConfig` | 所有页面 | 请求级数据中心，提供访问参数、环境、项目、资源、授权 |
| `PageConfig.get(request)` | 所有页面 | 每请求单例获取 |
| `cfg.setTitle()` | 所有页面 | 设置 HTML `<title>` |
| `cfg.checkSourceRootExistence()` | 所有页面 | 验证源根目录已配置 |
| `cfg.getEnv()` | 多数页面 | 返回 `RuntimeEnvironment` |
| `cfg.getPath()` | list, diff, history, more, rss | 当前文件/目录路径 |
| `cfg.getProject()` | list, history, minisearch, repos | 当前项目 |
| `cfg.getQueryBuilder()` | search, menu, more | Lucene 查询构建器 |
| `SearchHelper` | search, history, more | 搜索执行协调器 |
| `ProjectHelper` | menu, repos | 项目/分组层级管理 |
| `HistoryGuru` | history, rss, xref | SCM 历史访问 |
| `AnalyzerGuru` | list, xref | 文件类型检测和分析 |
| `Util` | 所有页面 | HTML 转义、URI 编码、面包屑、分页滑块等 |
| `Prefix` | 所有页面 | URL 前缀常量（XREF_P, HIST_L, DIFF_P 等） |
| `QueryParameters` | search, history, diff, menu | 查询参数名常量 |

---

## 十、文件清单总览

### 10.1 Java 文件清单（src/main/java）

```
src/main/java/org/opengrok/web/
├── AuthorizationFilter.java          # 访问控制过滤器
├── CharacterEncodingFilter.java      # UTF-8 编码过滤器
├── CookieFilter.java                 # Cookie 安全属性过滤器
├── DiffData.java                     # Diff 数据容器
├── DiffType.java                     # Diff 格式枚举
├── DirectoryListing.java             # 目录列表生成器
├── GetFile.java                      # 文件下载 Servlet
├── PageConfig.java                   # 请求级数据中心（核心）
├── ProjectHelper.java                # 项目/分组组织器
├── ResponseHeaderFilter.java         # 响应头过滤器
├── Scripts.java                      # JS 资源管理器
├── StatisticsFilter.java             # 指标收集过滤器
├── WebappError.java                  # 自定义错误类
├── WebappListener.java               # 应用生命周期监听器
├── servlet/
│   └── MetricsServlet.java           # Prometheus 指标 Servlet
├── util/
│   ├── DTOUtil.java                  # DTO 创建工具
│   ├── FileUtil.java                 # 安全文件路径解析
│   └── NoPathParameterException.java # 缺少 path 参数异常
└── api/
    ├── ApiTask.java                  # 异步 API 任务
    ├── ApiTaskManager.java           # 异步任务管理器
    ├── error/
    │   ├── ExceptionMapperUtils.java     # 异常→JSON 工具
    │   ├── GenericExceptionMapper.java   # 500 兜底
    │   ├── ValidationExceptionMapper.java # 400 映射
    │   └── WebApplicationExceptionMapper.java # Web 异常透传
    └── v1/
        ├── RestApp.java                  # JAX-RS 应用入口
        ├── FileNotFoundExceptionMapper.java # 404 映射
        ├── NoPathParameterExceptionMapper.java # 400 映射
        ├── filter/
        │   ├── CorsEnable.java           # CORS 启用注解
        │   ├── CorsFilter.java           # CORS 过滤器
        │   ├── IncomingFilter.java       # API 认证过滤器
        │   ├── PathAuthorizationFilter.java # 路径授权过滤器
        │   └── PathAuthorized.java       # 路径授权注解
        ├── controller/
        │   ├── AnnotationController.java     # 文件注释/Blame
        │   ├── ConfigurationController.java  # 配置管理
        │   ├── DirectoryListingController.java # 目录列表
        │   ├── FileController.java           # 文件内容
        │   ├── GroupsController.java         # 分组管理
        │   ├── HistoryController.java        # 版本历史
        │   ├── MessagesController.java       # 系统消息
        │   ├── ProjectsController.java       # 项目管理
        │   ├── RepositoriesController.java   # 仓库属性
        │   ├── SearchController.java         # 全文搜索
        │   ├── StatusController.java         # 任务状态
        │   ├── SuggesterController.java      # 自动补全
        │   └── SystemController.java         # 系统操作
        └── suggester/
            ├── SuggesterAppBinder.java       # DI 绑定器
            ├── model/
            │   ├── SuggesterData.java        # 处理后数据
            │   └── SuggesterQueryData.java   # 原始请求参数
            ├── parser/
            │   └── SuggesterQueryDataParser.java # 参数解析器
            ├── provider/
            │   ├── filter/
            │   │   ├── AuthorizationFilter.java  # 建议器授权
            │   │   ├── Authorized.java           # 授权注解
            │   │   ├── Suggester.java            # 建议器注解
            │   │   └── SuggestionsEnabledFilter.java # 启用检查
            │   ├── ParseExceptionMapper.java     # 解析异常映射
            │   └── service/
            │       ├── SuggesterService.java          # 服务接口
            │       ├── SuggesterServiceFactory.java   # 服务工厂
            │       └── impl/
            │           └── SuggesterServiceImpl.java  # 服务实现
            └── query/
                ├── SuggesterQueryBuilder.java    # 查询构建器
                └── SuggesterQueryParser.java     # 查询解析器
```

### 10.2 JSP/JSPF 文件清单（src/main/webapp）

```
src/main/webapp/
├── index.jsp              # 首页（搜索界面 + 仓库卡片）
├── search.jsp             # 搜索结果页
├── list.jsp               # 文件浏览器 / 源码交叉引用
├── diff.jsp               # 差异对比查看器
├── history.jsp            # 版本历史查看器
├── more.jsp               # 搜索匹配行上下文
├── help.jsp               # 帮助页
├── settings.jsp           # 用户设置页
├── status.jsp             # 服务器状态页
├── error.jsp              # 500 错误页
├── eforbidden.jsp         # 403 错误页
├── enoent.jsp             # 404 错误页
├── opensearch.jsp         # OpenSearch 描述 XML
├── rss.jsp                # RSS 2.0 订阅源
├── mast.jsp               # 主头部片段（文件页面共享预处理）
├── pageheader.jspf        # 站点页头（Logo + 导航）
├── foot.jspf              # 站点页脚（版本 + 脚本注入）
├── httpheader.jspf        # HTML <head> 生成器
├── menu.jspf              # 完整搜索表单
├── minisearch.jspf        # 精简内联搜索表单
├── projects.jspf          # 项目 Cookie 处理器
├── repos.jspf             # 仓库卡片网格
├── xref.jspf              # 即时交叉引用生成器
├── rss.xsl.xml            # RSS XSL 样式表
├── META-INF/
│   └── context.xml        # Tomcat 上下文描述符
└── WEB-INF/
    └── web.xml            # Web 应用部署描述符
```

---

## 十一、前端资源文件

### 11.1 JavaScript 文件

| 文件 | 功能 |
|------|------|
| `js/utils-0.0.48.js` | 通用工具函数（DOM 操作、搜索辅助、设置管理） |
| `js/diff-0.0.5.js` | Diff 视图交互逻辑 |
| `js/repos-0.0.3.js` | 仓库卡片交互 |
| `js/jquery-ui-1.12.1-custom.min.js` | jQuery UI 组件 |
| `js/jquery-ui-1.12.1-draggable.min.js` | jQuery UI 可拖拽 |
| `js/jquery.caret-1.5.2.min.js` | 光标位置管理 |
| `js/searchable-option-list-2.0.16.js` | 可搜索选项列表（项目选择） |
| `js/tablesorter-parsers-0.0.4.js` | 表格排序自定义解析器 |

### 11.2 CSS 文件

| 文件 | 功能 |
|------|------|
| `default/style-2.0.0.css` | 主样式表 |
| `default/jquery-ui-1.12.1-custom.min.css` | jQuery UI 样式 |
| `default/jquery-ui-1.12.1-custom.structure.min.css` | jQuery UI 结构样式 |
| `default/jquery-ui-1.12.1-custom.theme.min.css` | jQuery UI 主题样式 |
| `default/jquery.autocomplete.css` | 自动完成样式 |
| `default/jquery.combo.css` | 下拉组合框样式 |
| `default/jquery.tablesorter.css` | 表格排序样式 |
| `default/jquery.tooltip.css` | 提示工具样式 |
| `default/mandoc-1.0.0.css` | man 文档样式 |
| `default/print-1.0.3.css` | 打印样式 |
| `default/searchable-option-list-2.0.3.css` | 可搜索选项列表样式 |

---

## 十二、构建配置（pom.xml）

- **打包**: WAR（`source.war`）
- **主要依赖**:
  - `opengrok`（核心索引器）、`suggester`
  - Jakarta Servlet/JSP/JSTL API
  - Jersey（JAX-RS）、Jackson（JSON/YAML）、JAXB
  - WebJars: jQuery 3.6.4, Showdown 2.1.0, Tablesorter 2.31.3, XSS 1.0.10
  - JRCS diff 库、CGLIB、ModelMapper
- **构建插件**:
  - Jetty EE10（开发服务器，端口 8081）
  - WAR 打包
  - Tomcat 部署（tomcat7-maven-plugin）
  - Closure Compiler（JS 压缩）
  - YUI Compressor（CSS 压缩）
  - Checkstyle（代码风格检查）

---

## 十三、快速入门指南

### 13.1 如果你想修改搜索功能
→ 关注: `search.jsp`, `menu.jspf`, `SearchController.java`, `PageConfig.java`（搜索准备部分）

### 13.2 如果你想修改文件浏览
→ 关注: `list.jsp`, `xref.jspf`, `DirectoryListing.java`, `DirectoryListingController.java`

### 13.3 如果你想修改 Diff 对比
→ 关注: `diff.jsp`, `DiffData.java`, `DiffType.java`

### 13.4 如果你想修改历史记录
→ 关注: `history.jsp`, `HistoryController.java`

### 13.5 如果你想修改页面外观
→ 关注: `default/style-2.0.0.css`, `httpheader.jspf`, `pageheader.jspf`, `foot.jspf`

### 13.6 如果你想添加新的 API 端点
→ 关注: `RestApp.java`（注册）, `api/v1/controller/`（添加 Controller）, `api/v1/filter/`（如需新过滤器）

### 13.7 如果你想修改自动补全
→ 关注: `SuggesterController.java`, `SuggesterServiceImpl.java`, `SuggesterQueryParser.java`

### 13.8 如果你想修改权限控制
→ 关注: `AuthorizationFilter.java`, `IncomingFilter.java`, `PathAuthorizationFilter.java`
