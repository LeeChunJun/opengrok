# OpenGrok Web Module Overview

## Purpose
The `opengrok-web` module provides the web-based user interface for OpenGrok, a fast and powerful source code search and cross-reference engine. It serves HTML pages for browsing source code, viewing revision history, displaying diffs, and performing searches. Additionally, it offers a RESTful API (v1) for programmatic access to OpenGrok data.

## Key Components

### Web Configuration (`src/main/webapp/WEB-INF/web.xml`)
- Defines servlet mappings for core functionality:
  - `/search`, `/s` → `search.jsp` (search interface)
  - `/history/*` → `history.jsp` (revision history)
  - `/xref/*` → `list.jsp` (directory listing and source cross-reference)
  - `/diff/*` → `diff.jsp` (diff view)
  - `/more/*` → `more.jsp` (additional context lines)
  - `/rss/*` → `rss.jsp` (RSS feeds)
  - `/opensearch` → `opensearch.jsp` (OpenSearch description)
  - `/raw/*` and `/download/*` → `GetFile` servlet (raw file download)
  - Error handlers: `/error`, `/enoent`, `/eforbidden` → respective JSP pages
- Filters applied to all requests (`/*`):
  - `StatisticsFilter` – collects request metrics
  - `AuthorizationFilter` – enforces access control
  - `CookieFilter` – manages SameSite and Secure cookie attributes
  - `ResponseHeaderFilter` – sets caching headers based on URL patterns
- Error pages for HTTP 404, 403, and 500 status codes.

### Core Java Classes

#### `PageConfig` (`src/main/java/org/opengrok/web/PageConfig.java`)
- Request-scoped bean that lazily initializes and caches data needed for rendering a page.
- Responsibilities include:
  - Parsing and validating request parameters (project, group, revision, path, etc.)
  - Managing source root existence and readability checks
  - Providing helper methods for:
    - Retrieving projects, groups, and authentication status
    - Building file paths and revisions
    - Preparing search queries via `SearchHelper`
    - Managing cookies and sort order preferences
    - Generating ETags for caching
    - Handling annotations and blame views
- Ensures thread safety by not sharing instances across requests; cleanup performed via `WebappListener`.

#### `GetFile` (`src/main/java/org/opengrok/web/GetFile.java`)
- Servlet serving raw file contents from the source repository under `/raw` and `/download`.
- Supports:
  - Revision-specific file retrieval via `HistoryGuru`
  - Conditional GET (If-Modified-Since) for performance
  - Content-Type detection and content-disposition for downloads (`/download` adds attachment header)
- Delegates to `PageConfig` for request processing and security checks.

#### Filters
- `AuthorizationFilter`: Uses the underlying authorization framework to check if the current request is allowed to access projects/groups.
- `StatisticsFilter`: Increments request counters for monitoring.
- `CookieFilter`: Applies SameSite=Strict and optional Secure flags to cookies.
- `ResponseHeaderFilter`: Configures caching (max-age) for static resources, history, raw/download, RSS, and error pages.

#### JSP Pages (under `src/main/webapp`)
- `index.jsp`: Main entry point; redirects to search interface after checking source root.
- `search.jsp`: Search form and results display.
- `list.jsp`: Directory listing and source cross-reference (XREF) view; handles:
  - Directory browsing with file listings
  - Revision selection and annotation (blame) display
  - README file rendering (Markdown or plain text)
  - Source rendering with syntax highlighting via XREF generation
  - Project and group cookie persistence
- `history.jsp`: Displays revision history for a file or directory.
- `diff.jsp`: Shows differences between two revisions of a file.
- `more.jsp`: Displays additional context lines around search matches.
- `rss.jsp`: Generates RSS feed for recent changes.
- `opensearch.jsp`: Provides OpenSearch description for browser integration.
- Error pages (`error.jsp`, `enoent.jsp`, `eforbidden.jsp`): Render appropriate error messages.

### API (v1)
- Located under `src/main/java/org/opengrok/web/api/v1/`
- RESTful endpoints served via JAX-RS (Jersey) under `/api/*` )
- Controllers for:
  - `AnnotationController` – retrieve file annotations
  - `ConfigurationController` – access OpenGrok configuration
  - `DirectoryListingController` – programmatic directory listings
  - `FileController` – retrieve file contents and metadata
  - `GroupsController` – manage user groups
  - `HistoryController` – retrieve revision history
  - `MessagesController` – access system messages
  - `ProjectsController` – list and search projects
  - `RepositoriesController` – manage repositories
  - `SearchController` – execute searches
  - `StatusController` – service status and metrics
  - `SuggesterController` – provide search suggestions
  - `SystemController` – system information and administrative actions
- Includes filters for CORS, path authorization, and incoming request processing.
- Exception mappers translate internal exceptions to appropriate HTTP responses.

### Supporting Utilities
- `Scripts`: Manages JavaScript inclusion (minified/debug) for pages.
- `Util`: Contains helper methods for HTML escaping, URL encoding, file dumping, etc.
- `DTOUtil`: Data transfer object conversions (if present).
- `WebappListener`: Servlet context listener initializing OpenGrok environment and cleaning up request-scoped objects.

## Request Flow
1. An HTTP request arrives at the web container.
2. Filters process the request in order: Statistics → Authorization → Cookie → ResponseHeader (based on URL patterns).
3. The request is dispatched to the appropriate servlet or JSP based on `web.xml` mappings:
   - Static resources (CSS, JS, images) are served directly.
   - JSPs (search, history, list, etc.) are compiled and executed.
   - Servlets like `GetFile` handle raw/download requests.
4. Within JSPs or servlets, `PageConfig.get(request)` retrieves the request-scoped configuration.
5. `PageConfig` validates the request, checks source existence, resolves projects/groups, and prepares data for display.
6. Business logic (search, history retrieval, diff generation, etc.) is delegated to OpenGrok indexer libraries (`org.opengrok.indexer.*`).
7. The response is rendered (HTML, XML, plain text, or JSON) and sent back to the client.
8. `WebappListener.cleanup()` is called to release request-scoped resources.

## Dependencies
- Jakarta Servlet API (version 6.0)
- OpenGrok indexer (`org.opengrok.indexer`)
- Apache Lucene (via indexer)
- JAX-RS (Jersey) for REST API
- Micrometer for metrics
- Various libraries for Diff, HTML processing, etc.

## Extension Points
- Add new JSP pages or servlets by declaring them in `web.xml`.
- Implement new API controllers under `api/v1/controller` and register in `RestApp`.
- Create custom filters by implementing `jakarta.servlet.Filter` and adding to `web.xml`.
- Extend `PageConfig` if additional request-scoped data is needed (though discouraged; prefer utility classes).

## Summary
The `opengrok-web` module is the presentation layer of OpenGrok, transforming the powerful indexing and search capabilities of the backend into an accessible web interface. It balances performance (caching, conditional GET, efficient data retrieval) with features (revision tracking, blame, cross-reference, search suggestions) and provides both a traditional HTML UI and a modern REST API for integration with other tools.