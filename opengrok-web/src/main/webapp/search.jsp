<%--
CDDL HEADER START

The contents of this file are subject to the terms of the
Common Development and Distribution License (the "License").
You may not use this file except in compliance with the License.

See LICENSE.txt included in this distribution for the specific
language governing permissions and limitations under the License.

When distributing Covered Code, include this CDDL HEADER in each
file and include the License file at LICENSE.txt.
If applicable, add the following below this CDDL HEADER, with the
fields enclosed by brackets "[]" replaced with your own identifying
information: Portions Copyright [yyyy] [name of copyright owner]

CDDL HEADER END

Copyright (c) 2005, 2026, Oracle and/or its affiliates. All rights reserved.
Portions Copyright 2011 Jens Elkner.
Portions Copyright (c) 2017-2018, 2020, Chris Fraire <cfraire@me.com>.
Portions Copyright (c) 2026, UI Refactor.
--%>

<%-- search.jsp - non-JS / fallback results page.

     Mirrors index.jsp's results layout (card-based groups, file cards,
     line-numbered code preview, action buttons, expand button) but
     renders them server-side by running SearchHelper + SearchEngine
     directly instead of calling /api/v1/search from JavaScript.

     Hit paths / line numbers / line fragments come from
     SearchEngine.results(start, end, ret) — the same data source that
     powers the SearchController REST endpoint. The DOM emitted below
     is identical (class-for-class) to what index.jsp's renderResults()
     produces, so the server-rendered fallback is visually
     indistinguishable from the JS-driven primary page.

     This page is hit by two paths:
       1. The user submits the form normally (no JS): GET /search?... →
          PageConfig.prepareSearch() parses the request, the body
          renders the results.
       2. The user's JS is broken / blocked: index.jsp's
          performInlineSearch() catch() falls back to sbox.submit()
          which posts to /search.

     Chrome (header, body open/close, compact-nav, breadcrumb, footer) is
     shared with index.jsp via pageheader.jspf + foot.jspf. The search
     form + project chips are shared via menu.jspf. The results section
     below mirrors index.jsp's #results-section element-by-element, so
     the visual layout is identical whether results arrive via fetch()
     or via this server-side render.

     index.jsp is the JS-driven primary page; search.jsp is the
     no-JS / degraded fallback. --%>

<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page session="false" errorPage="error.jsp" buffer="8192kb" autoFlush="false" %>
<%@ page import="
org.opengrok.indexer.configuration.Project,
org.opengrok.indexer.search.Hit,
org.opengrok.indexer.search.QueryBuilder,
org.opengrok.indexer.search.SearchEngine,
org.opengrok.indexer.web.Prefix,
org.opengrok.indexer.web.QueryParameters,
org.opengrok.indexer.web.SearchHelper,
org.opengrok.indexer.web.SortOrder,
org.opengrok.indexer.web.Suggestion,
org.opengrok.indexer.web.Util,
org.opengrok.web.PageConfig,
org.opengrok.web.api.v1.suggester.provider.service.SuggesterServiceFactory,
jakarta.servlet.http.HttpServletResponse,
jakarta.servlet.http.HttpServletRequest,
jakarta.servlet.http.Cookie,

java.nio.charset.StandardCharsets,
java.net.URLEncoder,
java.util.ArrayList,
java.util.LinkedHashMap,
java.util.List,
java.util.Map"
%>

<%!
/* ---------------------- search.jsp rendering helpers ----------------------
 *
 * JSP declarations become methods on the generated servlet. The single
 * tunable here is MAX_HITS_PER_CARD: how many .result-line entries
 * show by default inside a single .result-file-card before the
 * "显示剩余 N 条匹配行" expand button kicks in. Mirrors index.jsp's
 * MAX_HITS_PER_CARD constant.
 */
private static final int MAX_HITS_PER_CARD = 10;
%>

<%
{
    /* ---------------------- search.jsp setup (before chrome) --------------------- */
    PageConfig _searchCfg = PageConfig.get(request);
    _searchCfg.checkSourceRootExistence();

    /* Run the query and prepare the search helper. */
    SearchHelper searchHelper = _searchCfg.prepareSearch();
    request.setAttribute(SearchHelper.REQUEST_ATTR, searchHelper);
    searchHelper.prepareExec(_searchCfg.getRequestedProjects()).executeQuery().prepareSummary();
    SuggesterServiceFactory.getDefault().onSearch(_searchCfg.getRequestedProjects(), searchHelper.getQuery());

    String redirect = searchHelper.getRedirect();
    if (redirect != null) {
        response.sendRedirect(redirect);
        return;
    }
    if (searchHelper.getErrorMsg() != null) {
        _searchCfg.setTitle("OpenGrok Search Error");
        response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
    } else {
        _searchCfg.setTitle(_searchCfg.getSearchTitle());
    }
    response.addCookie(new Cookie("OpenGrokSorting",
            URLEncoder.encode(searchHelper.getOrder().toString(), StandardCharsets.UTF_8)));

    /* Pre-compute display values used by the body block below so they
     * remain accessible after the chrome include flushes the response
     * buffer. None of these depend on the request attributes set above
     * being mutable — they are snapshots. */
    SortOrder _searchOrder = searchHelper.getOrder();
    int _searchStart = searchHelper.getStart();
    int _searchMax = searchHelper.getMaxItems();
    long _searchTotal = searchHelper.getTotalHits();
    long _searchThisPage = Math.max(0, Math.min(_searchTotal - _searchStart, _searchMax));
    String _searchErrorMsg = searchHelper.getErrorMsg();
    request.setAttribute("_searchOrder", _searchOrder);
    request.setAttribute("_searchStart", _searchStart);
    request.setAttribute("_searchMax", _searchMax);
    request.setAttribute("_searchTotal", _searchTotal);
    request.setAttribute("_searchThisPage", _searchThisPage);
    request.setAttribute("_searchErrorMsg", _searchErrorMsg);
}
%>

<%-- Home pill is active (search lives at the application root). --%>
<% pageContext.setAttribute("activeNav", "home"); %>
<%@ include file="pageheader.jspf" %>

<%-- Shared pagination chrome (independent <style> block). Must be
     included OUTSIDE any other <style> block because pager.jspf emits
     its own complete <style>...</style>; nesting two <style> blocks
     inside one another makes the inner rules invisible to the browser. --%>
<%@ include file="pager.jspf" %>

<style>
/* ── search.jsp page-specific styles ──
 *
 * These rules are copied verbatim from index.jsp so the fallback
 * page renders identically to the JS-driven primary page when
 * results arrive server-side. menu.jspf owns the search-form +
 * project-chip styles (defined under .menu-root) — those do NOT
 * need to be repeated here because menu.jspf re-emits them on
 * every include. httpheader.jspf + pageheader.jspf already ship
 * the theme variables (--bg / --surface / --fg / --muted / --border /
 * --accent / --accent-dim / --font-sans / --font-mono); we don't
 * redefine them. */

body {
  background: var(--bg);
}

main.container {
  max-width: 960px;
  margin: 0 auto;
  padding: 36px 24px 48px;
}

@media (max-width: 700px) {
  main.container { padding: 24px 16px 36px; }
}

.search-hero-heading {
  font-size: 22px;
  font-weight: 600;
  letter-spacing: -0.02em;
  margin-bottom: 4px;
}

.search-hero-subtitle {
  font-size: 14px;
  color: var(--muted);
  margin-bottom: 20px;
}

/* ── Results section ── */
.results-section {
  margin-top: 24px;
  animation: fadeIn 0.3s ease;
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(8px); }
  to   { opacity: 1; transform: translateY(0); }
}

.results-header {
  font-size: 13px;
  color: var(--muted);
  margin-bottom: 16px;
  padding-bottom: 10px;
  border-bottom: 1px solid var(--border);
}

.results-header strong {
  color: var(--fg);
  font-weight: 600;
}

.results-header .query-term {
  color: var(--accent);
  font-weight: 500;
}
.results-header .result-meta-sep {
  margin: 0 8px;
  color: var(--border);
}
.results-header .result-meta {
  color: var(--muted);
}
.results-header .result-meta strong {
  color: var(--fg);
  font-weight: 600;
}

/* ── Sort bar ── */
.sort-bar {
  display: flex;
  align-items: center;
  gap: 4px;
  margin-bottom: 16px;
  font-size: 13px;
  color: var(--muted);
  padding-bottom: 10px;
  border-bottom: 1px solid var(--border);
}

.sort-bar .sort-label {
  font-weight: 500;
  color: var(--fg);
  margin-right: 4px;
}

.sort-bar .sort-option {
  padding: 4px 10px;
  border-radius: 5px;
  cursor: pointer;
  transition: background 0.12s, color 0.12s;
  border: none;
  background: none;
  font-size: 13px;
  font-family: var(--font-sans);
  color: var(--muted);
  text-decoration: none;
}

.sort-bar .sort-option:hover {
  background: #f0f1f3;
  color: var(--fg);
}

.sort-bar .sort-option.active {
  background: var(--accent-dim);
  color: var(--accent);
  font-weight: 500;
}

.sort-bar .sort-sep {
  color: #d1d5db;
  margin: 0 2px;
}

/* ── Result group header (one per directory) ── */
.result-group-header {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 16px 4px 10px;
  font-size: 14px;
  font-weight: 600;
  color: var(--accent);
  font-family: var(--font-mono);
  letter-spacing: -0.01em;
  min-width: 0;
}

.result-group-header:first-child {
  padding-top: 4px;
}

.result-group-header svg {
  width: 14px;
  height: 14px;
  stroke: currentColor;
  fill: none;
  stroke-width: 2;
  flex-shrink: 0;
}

.result-group-header a,
.result-group-header .group-root {
  color: var(--accent);
  text-decoration: none;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  min-width: 0;
  flex: 1 1 auto;
}

.result-group-header a:hover {
  text-decoration: underline;
}

.result-group-header .group-root {
  color: var(--muted);
  font-style: italic;
}

.group-count {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 22px;
  height: 20px;
  padding: 0 6px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 600;
  font-family: var(--font-sans);
  background: var(--accent-dim);
  color: var(--accent);
  flex-shrink: 0;
}

/* ── Result file card ── */
.result-file-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  margin-bottom: 10px;
  overflow: hidden;
  transition: border-color 0.12s, box-shadow 0.12s;
}

.result-file-card:hover {
  border-color: #c7c9d0;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
}

.result-file-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 14px;
  background: #fafbfc;
  border-bottom: 1px solid var(--border);
  flex-wrap: nowrap;
}

.result-file-header > a.file-link {
  display: block;
  flex: 1 1 0;
  min-width: 0;
  max-width: 100%;
  text-decoration: none;
  color: var(--muted);
  font-family: var(--font-mono);
  font-size: 12px;
  line-height: 1.4;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  transition: color 0.12s;
}

.result-file-header > a.file-link:hover {
  color: var(--accent);
}

.result-file-header svg {
  width: 14px;
  height: 14px;
  stroke: #9ca3af;
  fill: none;
  stroke-width: 2;
  flex-shrink: 0;
}

.result-file-header .file-actions {
  display: flex;
  align-items: center;
  gap: 4px;
  flex: 0 0 auto;
  flex-shrink: 0;
  margin-left: auto;
}

.action-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 4px;
  width: 28px;
  height: 28px;
  padding: 0;
  border-radius: 5px;
  font-size: 12px;
  border: 1px solid #e5e7eb;
  background: #f9fafb;
  color: var(--muted);
  cursor: pointer;
  font-family: var(--font-sans);
  transition: background 0.12s, color 0.12s, border-color 0.12s;
  text-decoration: none;
  white-space: nowrap;
  flex: 0 0 auto;
  flex-shrink: 0;
}

.action-btn:hover {
  background: #f3f4f6;
  color: var(--fg);
  border-color: #d1d5db;
}

.action-btn svg {
  width: 12px;
  height: 12px;
  stroke: currentColor;
  fill: none;
  stroke-width: 2;
}

/* ── Result lines ── */
.result-lines {
  padding: 4px 0;
}

.result-line {
  display: flex;
  align-items: baseline;
  padding: 2px 14px 2px 0;
  font-family: var(--font-mono);
  font-size: 12.5px;
  line-height: 1.7;
  cursor: pointer;
  text-decoration: none;
  color: inherit;
  transition: background 0.1s;
}

.result-line:hover {
  background: #eef2ff;
}

.result-line:hover .line-num {
  color: var(--accent);
}

.line-num {
  width: 44px;
  min-width: 44px;
  text-align: right;
  padding-right: 12px;
  color: #b0b4bc;
  font-size: 11.5px;
  user-select: none;
  flex-shrink: 0;
}

.line-code {
  flex: 1;
  min-width: 0;
  padding-right: 14px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.line-code .match {
  background: #fef08a;
  border-bottom: 2px solid #fde047;
  padding: 0 1px;
  border-radius: 2px;
  flex-shrink: 0;
}

.result-file-card .result-line.result-line-overflow {
  display: none;
}

.result-file-card.expanded .result-line.result-line-overflow {
  display: flex;
}

/* ── Expand button ── */
.result-expand-btn {
  display: block;
  width: 100%;
  padding: 8px 14px;
  margin-top: 2px;
  background: transparent;
  border: 0;
  border-top: 1px dashed var(--border);
  color: var(--accent);
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
  text-align: center;
  transition: background 0.12s, color 0.12s;
  font-family: var(--font-sans);
}

.result-expand-btn:hover {
  background: #dbeafe;
  color: #1e40af;
}

.result-expand-btn .arrow {
  display: inline-block;
  vertical-align: -2px;
  margin-left: 4px;
  width: 12px;
  height: 12px;
  stroke: currentColor;
  fill: none;
  stroke-width: 2.2;
  stroke-linecap: round;
  stroke-linejoin: round;
  transition: transform 0.2s;
}

.result-file-card.expanded .result-expand-btn .arrow {
  transform: rotate(180deg);
}

/* ── Pagination ──
 *
 * Container / button / ellipsis rules live in pager.jspf (included
 * earlier — see the top of this page). Do NOT include pager.jspf
 * again here; nesting two <style> blocks inside one another makes
 * the inner rules invisible to the browser. */

/* ── Empty / no-results / error states ── */
.results-empty {
  padding: 32px 8px;
  text-align: center;
  color: var(--muted);
  font-size: 14px;
}

.results-error {
  padding: 24px 8px;
  color: var(--muted);
  font-size: 14px;
}

.results-error h3 {
  color: #c00;
  font-size: 15px;
  margin-bottom: 10px;
}

.results-error code {
  background: #f3f4f6;
  padding: 1px 5px;
  border-radius: 4px;
  font-family: var(--font-mono);
  font-size: 12px;
}

.results-error a {
  color: var(--accent);
  text-decoration: none;
}

.results-error a:hover {
  text-decoration: underline;
}

.results-suggestions {
  font-size: 13px;
  color: var(--muted);
  margin: 8px 0 16px;
}

.results-suggestions .hint-label {
  color: #c00;
  margin-right: 8px;
}

.results-suggestions a {
  color: var(--accent);
  text-decoration: none;
  margin-right: 8px;
}

.results-suggestions a:hover {
  text-decoration: underline;
}

/* ── Responsive — tablet / mobile ── */
@media (max-width: 700px) {
  .result-line { font-size: 11.5px; }
  .line-num    { width: 36px; min-width: 36px; font-size: 10.5px; }
}

@media (max-width: 480px) {
  .search-hero-heading { font-size: 19px; }
  /* Pagination bar shrinking on narrow screens is now handled in
   * pager.jspf; no page-specific override needed here. */
}
</style>

<main class="container">

  <h1 class="search-hero-heading">搜索代码</h1>
  <p class="search-hero-subtitle">在已索引的代码仓库中进行多维度检索</p>

  <%-- Search form + project chips live in menu.jspf (shared with index.jsp). --%>
  <%@ include file="menu.jspf"%>

  <%
    /* ---------------------- search.jsp results section ---------------------
     *
     * Mirrors index.jsp's #results-section element-by-element:
     *   .sort-bar          (server-side active state from _searchOrder)
     *   .results-header    (1-based range + active sort label)
     *   .pagination-top    (Previous / page-btn / Next)
     *   .results-list      (server-side HTML — .result-group-header +
     *                       .result-file-card cards OR empty state OR
     *                       error block OR Did-you-mean suggestions)
     *   .pagination        (mirror of the top bar)
     *
     * Always visible (no .visible toggle needed): search.jsp is hit only
     * after a query has been issued, so the section is never empty in
     * the "no query yet" sense. */
    PageConfig _searchCfg = PageConfig.get(request);
    SearchHelper _searchHelper = (SearchHelper) request.getAttribute(SearchHelper.REQUEST_ATTR);
    SortOrder _searchOrder = (SortOrder) request.getAttribute("_searchOrder");
    int _searchStart = (Integer) request.getAttribute("_searchStart");
    int _searchMax = (Integer) request.getAttribute("_searchMax");
    long _searchTotal = (Long) request.getAttribute("_searchTotal");
    long _searchThisPage = (Long) request.getAttribute("_searchThisPage");
    String _searchErrorMsg = (String) request.getAttribute("_searchErrorMsg");
    String _searchQueryStr = _searchHelper.getQuery() == null ? "" : _searchHelper.getQuery().toString();
    String _searchCtxPath = _searchHelper.getContextPath();

    /* Build the canonical page URL used by the sort buttons and
     * pagination links. The URL carries the active query parameters
     * (full / defs / refs / path / hist / type / project) so each
     * sub-resource is self-contained when shared. The base URL
     * intentionally omits `start` and `n` so the per-page links can
     * append those themselves without tripping over duplicates. */
    StringBuilder _searchUrl = new StringBuilder(64);
    {
        QueryBuilder qb = _searchHelper.getBuilder();
        _searchUrl.append("search?");
        if (qb != null) {
            Util.appendQuery(_searchUrl, QueryParameters.FULL_SEARCH_PARAM, qb.getFreetext());
            Util.appendQuery(_searchUrl, QueryParameters.DEFS_SEARCH_PARAM, qb.getDefs());
            Util.appendQuery(_searchUrl, QueryParameters.REFS_SEARCH_PARAM, qb.getRefs());
            Util.appendQuery(_searchUrl, QueryParameters.PATH_SEARCH_PARAM, qb.getPath());
            Util.appendQuery(_searchUrl, QueryParameters.HIST_SEARCH_PARAM, qb.getHist());
            Util.appendQuery(_searchUrl, QueryParameters.TYPE_SEARCH_PARAM, qb.getType());
        }
        if (_searchHelper.getProjects() != null && !_searchHelper.getProjects().isEmpty()) {
            if (Boolean.parseBoolean(request.getParameter(QueryParameters.ALL_PROJECT_SEARCH))) {
                Util.appendQuery(_searchUrl, QueryParameters.ALL_PROJECT_SEARCH, Boolean.TRUE.toString());
            } else {
                Util.appendQuery(_searchUrl, QueryParameters.PROJECT_SEARCH_PARAM,
                        _searchCfg.getRequestedProjectsAsString());
            }
        }
        /* Append the page size so the rendered pagination links
         * preserve the current per-page count when the user pages
         * forward / backward. PageConfig#getMaxItems() reads `n` via
         * getIntParam(QueryParameters.COUNT_PARAM, default); if we
         * don't include it here, a later paging click would lose the
         * size and fall back to the global default. */
        Util.appendQuery(_searchUrl, QueryParameters.COUNT_PARAM,
                Integer.toString(_searchMax));
    }

    /* SORT_KEY_MAP mirrors index.jsp's mapping from the user-facing
     * data-sort attribute (lastmodified/relevance/path) to the
     * Lucene SortOrder enum (relevancy/lastmodtime/fullpath). The
     * sort-bar markup uses the same data-sort values so the labels
     * stay consistent across pages. */
    String _searchActiveSortAttr = "relevance";
    if (_searchOrder != null) {
        String o = _searchOrder.toString();
        if ("lastmodtime".equals(o))      _searchActiveSortAttr = "lastmodified";
        else if ("fullpath".equals(o))    _searchActiveSortAttr = "path";
        else                              _searchActiveSortAttr = "relevance";
    }
  %>

  <section class="results-section">
    <div class="sort-bar">
      <span class="sort-label">排序：</span>
      <a class="sort-option <%= "lastmodified".equals(_searchActiveSortAttr) ? "active" : "" %>"
         data-sort="lastmodified"
         href="<%= _searchUrl %><%= QueryParameters.SORT_PARAM_EQ %>lastmodtime">最后修改时间</a>
      <span class="sort-sep">|</span>
      <a class="sort-option <%= "relevance".equals(_searchActiveSortAttr) ? "active" : "" %>"
         data-sort="relevance"
         href="<%= _searchUrl %><%= QueryParameters.SORT_PARAM_EQ %>relevancy">相关度</a>
      <span class="sort-sep">|</span>
      <a class="sort-option <%= "path".equals(_searchActiveSortAttr) ? "active" : "" %>"
         data-sort="path"
         href="<%= _searchUrl %><%= QueryParameters.SORT_PARAM_EQ %>fullpath">路径</a>
    </div>

    <%
      /* results-header text — same wording as index.jsp. 1-based range
       * "1 – 25 of 3886" plus the human-readable sort label. */
      long _displayStart = _searchTotal > 0 ? _searchStart + 1 : 0;
      long _displayEnd   = _searchStart + _searchThisPage;
      String _searchSortLabel = "相关度";
      if (_searchOrder != null) {
          String o = _searchOrder.toString();
          if ("lastmodtime".equals(o)) _searchSortLabel = "最后修改时间";
          else if ("fullpath".equals(o)) _searchSortLabel = "路径";
      }
    %>
    <div class="results-header">
      命中 <strong><%= _searchTotal %></strong> 条结果<%
        if (_searchTotal > 0) { %>（<%= _displayStart %>–<%= _displayEnd %>）<% } %><%
        if (_searchQueryStr != null && !_searchQueryStr.isEmpty()) { %>，查询 <span class="query-term"><%= Util.htmlize(_searchQueryStr) %></span><% } %>
      <span class="result-meta-sep">·</span>
      <span class="result-meta">排序：<strong><%= _searchSortLabel %></strong></span>
    </div>

    <%
      /* ---------------------- pagination (server-side) ----------------------
       *
       * Replicates index.jsp's renderPagination() in JSP:
       *   - Compute the visible page window (≤10 buttons, anchored
       * near start / end as needed).
       *   - Render Previous + page numbers + ellipsis + Next as
       *     <a class="page-btn"> elements with href="?start=...".
       *   - The same HTML is emitted in both #pagination-top and
       * #pagination so the two bars stay in sync.
       *
       * The slider URL is the request's current query string with
       * the `start` parameter rewritten per page. Empty state when
       * totalHits ≤ maxItems. */
      int _searchLastPage = (int) Math.max(1, Math.ceil((double) _searchTotal / _searchMax));
      int _searchCurrentPage = (_searchStart / _searchMax) + 1;
      if (_searchCurrentPage < 1) _searchCurrentPage = 1;
      if (_searchCurrentPage > _searchLastPage) _searchCurrentPage = _searchLastPage;

      String _searchSliderHtml = "";
      if (_searchLastPage > 1) {
          int _searchWinFirst = 1;
          int _searchWinLast  = _searchLastPage;
          int _searchMaxButtons = 10;
          if (_searchLastPage > _searchMaxButtons) {
              int _searchHalf = _searchMaxButtons / 2;
              _searchWinFirst = Math.max(1, _searchCurrentPage - _searchHalf);
              _searchWinLast  = _searchWinFirst + _searchMaxButtons - 1;
              if (_searchWinLast > _searchLastPage) {
                  _searchWinLast  = _searchLastPage;
                  _searchWinFirst = Math.max(1, _searchWinLast - _searchMaxButtons + 1);
              }
          }
          StringBuilder _searchSlider = new StringBuilder(512);
          boolean _searchPrevDisabled = _searchCurrentPage <= 1;
          boolean _searchNextDisabled = _searchCurrentPage >= _searchLastPage;
          int _searchPrevStart = Math.max(0, (_searchCurrentPage - 2) * _searchMax);
          int _searchNextStart = Math.min((_searchLastPage - 1) * _searchMax,
                  _searchCurrentPage * _searchMax);

          _searchSlider.append("<a class=\"page-btn nav-btn");
          if (_searchPrevDisabled) _searchSlider.append(" disabled");
          _searchSlider.append("\"");
          if (!_searchPrevDisabled) {
              _searchSlider.append(" href=\"").append(_searchUrl);
              _searchSlider.append("&amp;").append(QueryParameters.START_PARAM).append("=").append(_searchPrevStart);
              _searchSlider.append("\"");
          }
          _searchSlider.append("><svg viewBox=\"0 0 24 24\"><polyline points=\"15 18 9 12 15 6\"/></svg> Previous</a>");

          if (_searchWinFirst > 1) {
              _searchSlider.append("<a class=\"page-btn\" href=\"").append(_searchUrl).append("\">1</a>");
              if (_searchWinFirst > 2) {
                  _searchSlider.append("<span class=\"page-ellipsis\">…</span>");
              }
          }
          for (int _p = _searchWinFirst; _p <= _searchWinLast; _p++) {
              int _pStart = (_p - 1) * _searchMax;
              if (_p == _searchCurrentPage) {
                  _searchSlider.append("<a class=\"page-btn active\" href=\"")
                               .append(_searchUrl)
                               .append("&amp;").append(QueryParameters.START_PARAM).append("=").append(_pStart)
                               .append("\">").append(_p).append("</a>");
              } else {
                  _searchSlider.append("<a class=\"page-btn\" href=\"")
                               .append(_searchUrl)
                               .append("&amp;").append(QueryParameters.START_PARAM).append("=").append(_pStart)
                               .append("\">").append(_p).append("</a>");
              }
          }
          if (_searchWinLast < _searchLastPage) {
              if (_searchWinLast < _searchLastPage - 1) {
                  _searchSlider.append("<span class=\"page-ellipsis\">…</span>");
              }
              int _pStart = (_searchLastPage - 1) * _searchMax;
              _searchSlider.append("<a class=\"page-btn\" href=\"")
                           .append(_searchUrl)
                           .append("&amp;").append(QueryParameters.START_PARAM).append("=").append(_pStart)
                           .append("\">").append(_searchLastPage).append("</a>");
          }

          _searchSlider.append("<a class=\"page-btn nav-btn");
          if (_searchNextDisabled) _searchSlider.append(" disabled");
          _searchSlider.append("\"");
          if (!_searchNextDisabled) {
              _searchSlider.append(" href=\"").append(_searchUrl);
              _searchSlider.append("&amp;").append(QueryParameters.START_PARAM).append("=").append(_searchNextStart);
              _searchSlider.append("\"");
          }
          _searchSlider.append(">Next <svg viewBox=\"0 0 24 24\"><polyline points=\"9 18 15 12 9 6\"/></svg></a>");

          _searchSliderHtml = _searchSlider.toString();
      }
    %>

    <div class="pagination pagination-top"><%= _searchSliderHtml %></div>

    <div class="results-list">
      <%
        if (_searchErrorMsg != null) {
            /* Parse-error or other failure: keep the legacy "Error"
             * heading so the user knows what went wrong, but render it
             * inside the .results-list container so the rest of the
             * chrome stays consistent with index.jsp. */
      %>
        <div class="results-error">
          <h3>Error</h3>
          <%
            if (_searchErrorMsg.startsWith(SearchHelper.PARSE_ERROR_MSG)) {
          %>
            <p><%= Util.htmlize(SearchHelper.PARSE_ERROR_MSG) %></p>
            <p>You might try to enclose your search term in quotes,
              <a href="help.jsp#escaping">escape special characters</a>
              with <code>\</code>, or read the <a href="help.jsp">Help</a>
              on the query language. Error message from parser:</p>
            <p><code><%= Util.htmlize(_searchErrorMsg.substring(SearchHelper.PARSE_ERROR_MSG.length())) %></code></p>
          <%
            } else {
          %>
            <p><%= Util.htmlize(_searchErrorMsg) %></p>
          <%
            }
          %>
        </div>
      <%
        } else if (_searchHelper.getHits() == null || _searchHelper.getHits().length == 0
                   || _searchStart >= _searchHelper.getHits().length) {
      %>
        <%
          List<Suggestion> _searchHints = _searchHelper.getSuggestions();
          if (_searchHints != null) {
              for (Suggestion _searchHint : _searchHints) {
        %>
          <p class="results-suggestions">
            <span class="hint-label">Did you mean (for <%= Util.htmlize(_searchHint.getName()) %>)</span>:
            <%
              if (_searchHint.getFreetext() != null) {
                  for (String _searchWord : _searchHint.getFreetext()) {
            %>
              <a href="search?<%= QueryParameters.FULL_SEARCH_PARAM_EQ %><%= Util.uriEncode(_searchWord) %>"><%= Util.htmlize(_searchWord) %></a>
            <%
                  }
              }
              if (_searchHint.getRefs() != null) {
                  for (String _searchWord : _searchHint.getRefs()) {
            %>
              <a href="search?<%= QueryParameters.REFS_SEARCH_PARAM_EQ %><%= Util.uriEncode(_searchWord) %>"><%= Util.htmlize(_searchWord) %></a>
            <%
                  }
              }
              if (_searchHint.getDefs() != null) {
                  for (String _searchWord : _searchHint.getDefs()) {
            %>
              <a href="search?<%= QueryParameters.DEFS_SEARCH_PARAM_EQ %><%= Util.uriEncode(_searchWord) %>"><%= Util.htmlize(_searchWord) %></a>
            <%
                  }
              }
            %>
          </p>
        <%
              }
          }
        %>
        <div class="results-empty">
          <% if (_searchQueryStr != null && !_searchQueryStr.isEmpty()) { %>
            Your search <strong><%= Util.htmlize(_searchQueryStr) %></strong>
            did not match any files.<br/>
            Suggestions:
          <% } else { %>
            未找到匹配项
          <% } %>
          <ul style="text-align: left; display: inline-block; margin-top: 8px;">
            <li>Make sure all terms are spelled correctly.</li>
            <li>Try different keywords.</li>
            <li>Try more general keywords.</li>
            <li>Use <code>wil*</code> cards if you are looking for partial match.</li>
          </ul>
        </div>
      <%
        } else {
            /* Happy path: render the result groups server-side. Run
             * SearchEngine once on the same query so we can extract
             * rich Hit objects with .line (rendered HTML) and .lineno
             * for the current Lucene-doc window. The engine is the
             * same one SearchController uses, so the per-hit output
             * matches what /api/v1/search would have delivered. */
            List<Hit> _searchHits = new ArrayList<>();
            SearchEngine _engine = null;
            try {
                QueryBuilder _qb = _searchHelper.getBuilder();
                int _engineMaxDocs = Math.max(1, _searchStart + _searchMax);
                _engine = new SearchEngine(_engineMaxDocs);
                if (_qb != null) {
                    _engine.setFreetext(_qb.getFreetext());
                    _engine.setDefinition(_qb.getDefs());
                    _engine.setSymbol(_qb.getRefs());
                    _engine.setFile(_qb.getPath());
                    _engine.setHistory(_qb.getHist());
                    _engine.setType(_qb.getType());
                }
                _engine.setSortOrder(_searchHelper.getOrder());
                java.util.SortedSet<String> _searchEngineProjects =
                        _searchCfg.getRequestedProjects();
                List<Project> _searchEngineProjectList = new ArrayList<>();
                if (_searchEngineProjects != null) {
                    for (String _pn : _searchEngineProjects) {
                        Project _pp = Project.getByName(_pn);
                        if (_pp != null) _searchEngineProjectList.add(_pp);
                    }
                }
                if (_searchEngineProjectList.isEmpty()) {
                    /* Mirror SearchHelper.prepareExec: if no project was
                     * requested but the env has projects, fall through to
                     * engine.search() default-project-list path. */
                    _engine.search();
                } else {
                    _engine.search(_searchEngineProjectList);
                }
                int _hitEnd = (int) Math.min(
                        (long) _searchStart + _searchThisPage,
                        _engine.scoreDocs() == null ? 0 : _engine.scoreDocs().length);
                _engine.results(_searchStart, _hitEnd, _searchHits);
            } catch (Exception _e) {
                /* If the secondary SearchEngine call fails for any
                 * reason, fall back to a minimal "no results" message
                 * rather than throwing a 500. */
                _searchHits.clear();
            } finally {
                if (_engine != null) {
                    try { _engine.destroy(); } catch (Exception _ignored) {}
                }
            }

            /* Group by directory → ordered list of file paths → ordered list of
             * (file path, hits-in-file). LinkedHashMap keeps the Lucene hit
             * ordering so the visual order matches what index.jsp's JS would
             * have produced.
             *
             * Search-result paths returned by SearchEngine.results() are
             * stored in Lucene as project-relative paths that BEGIN with
             * '/' (see IndexDatabase.addFile and AnalyzerGuru.populateDocument
             * where QueryBuilder.PATH is set to a /-prefixed string). The
             * /api/v1/search endpoint returns them with the leading slash
             * intact, and index.jsp's JS strips it before grouping; we do
             * the same here so URLs don't end up with a doubled slash like
             * "/xref//goldfish/...". */
            LinkedHashMap<String, LinkedHashMap<String, List<Hit>>> _searchGroups =
                    new LinkedHashMap<>();
            for (Hit _h : _searchHits) {
                String _rawPath = _h.getPath();
                if (_rawPath == null) continue;
                String _path = _rawPath.charAt(0) == '/'
                        ? _rawPath.substring(1) : _rawPath;
                String _dir;
                int _slashIdx = _path.lastIndexOf('/');
                if (_slashIdx >= 0) {
                    _dir = _path.substring(0, _slashIdx);
                } else {
                    _dir = "";
                }
                LinkedHashMap<String, List<Hit>> _filesInDir =
                        _searchGroups.computeIfAbsent(_dir, k -> new LinkedHashMap<>());
                List<Hit> _fileHits =
                        _filesInDir.computeIfAbsent(_path, k -> new ArrayList<>());
                _fileHits.add(_h);
            }

            for (Map.Entry<String, LinkedHashMap<String, List<Hit>>> _dirEntry
                    : _searchGroups.entrySet()) {
                String _dir = _dirEntry.getKey();
                LinkedHashMap<String, List<Hit>> _filesInDir = _dirEntry.getValue();
                int _dirTotalHits = 0;
                for (List<Hit> _hs : _filesInDir.values()) _dirTotalHits += _hs.size();
      %>
        <div class="result-group-header">
          <% if (_dir.isEmpty()) { %>
            <span class="group-root">（项目根）</span>
          <% } else { %>
            <a href="<%= _searchCtxPath %><%= Prefix.XREF_P %>/<%= Util.uriEncodePath(_dir) %>/"><%= Util.htmlize(_dir) %>/</a>
          <% } %>
          <span class="group-count"><%= _dirTotalHits %></span>
        </div>
        <%
          for (Map.Entry<String, List<Hit>> _fileEntry : _filesInDir.entrySet()) {
              String _filePath = _fileEntry.getKey();
              List<Hit> _fileHits = _fileEntry.getValue();
              String _filePathE = Util.uriEncodePath(_filePath);
              String _xrefHref = _searchCtxPath + "/xref/" + _filePathE;
              String _histHref = _searchCtxPath + "/history/" + _filePathE;
              String _dlHref   = _searchCtxPath + "/download/" + _filePathE;
              String _annHref  = _xrefHref + "?an=true";
              int _totalHitsInFile = _fileHits.size();
        %>
        <div class="result-file-card">
          <div class="result-file-header">
            <a class="file-link" href="<%= _xrefHref %>" title="<%= Util.htmlize(_filePath) %>"><%= Util.htmlize(_filePath) %></a>
            <div class="file-actions">
              <a class="action-btn" title="History" href="<%= _histHref %>">
                <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
              </a>
              <a class="action-btn" title="Annotate" href="<%= _annHref %>">
                <svg viewBox="0 0 24 24"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>
              </a>
              <a class="action-btn" title="Download" href="<%= _dlHref %>">
                <svg viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
              </a>
            </div>
          </div>
          <div class="result-lines">
            <%
              int _hitIdx = 0;
              for (Hit _h : _fileHits) {
                  _hitIdx++;
                  String _lineNum = _h.getLineno();
                  String _line    = _h.getLine();
                  if (_line == null) _line = "";
                  String _lineHref = _xrefHref
                          + ((_lineNum != null && !_lineNum.isEmpty()) ? "#L" + Util.uriEncode(_lineNum) : "");
                  String _overflowClass = (_hitIdx > MAX_HITS_PER_CARD) ? " result-line-overflow" : "";
            %>
            <a class="result-line<%= _overflowClass %>" href="<%= _lineHref %>">
              <span class="line-num"><%= Util.htmlize(_lineNum == null ? "" : _lineNum) %></span>
              <span class="line-code"><%= _line %></span>
            </a>
            <%
              }
              if (_totalHitsInFile > MAX_HITS_PER_CARD) {
                  int _hidden = _totalHitsInFile - MAX_HITS_PER_CARD;
            %>
            <button class="result-expand-btn" type="button"
                data-expand-target="result-file-card">
              显示剩余 <%= _hidden %> 条匹配行
              <svg class="arrow" viewBox="0 0 24 24"><polyline points="6 9 12 15 18 9"/></svg>
            </button>
            <%
              }
            %>
          </div>
        </div>
        <%
          } /* foreach file */
          } /* foreach dir */
        if (_searchHits.isEmpty()) {
            /* SearchEngine call succeeded but produced no usable Hit
             * objects for the current window (e.g. an internal error
             * left hits[] populated but extractResults returned empty).
             * Render a minimal empty-state message rather than nothing
             * so the user isn't left staring at a blank results list. */
      %>
        <div class="results-empty">未找到匹配项</div>
      <%
        }
        } /* end happy-path */
      %>
    </div>

    <div class="pagination"><%= _searchSliderHtml %></div>
  </section>

</main>

<%@ include file="foot.jspf"%>

<%-- search.jsp — server-side render.

     No client-side renderer is needed because every interaction
     (sort change, page jump, form submit) is a plain GET request
     to /search, which re-runs the search helper and re-renders the
     page. menu.jspf already wires up the autocomplete + chip
     handlers; utils.js (loaded by httpheader.jspf) registers the
     domReady queue that menu.jspf pushes onto.

     The expand button is the one interaction that does NOT trigger a
     full reload — it's a pure DOM toggle (toggle .expanded on the
     parent .result-file-card). A small inline script below binds it
     after the page loads. --%>
<script type="text/javascript">
/* <![CDATA[ */
(function () {
  document.addEventListener('click', function (ev) {
    var btn = ev.target.closest('.result-expand-btn');
    if (!btn) return;
    var card = btn.closest('.result-file-card');
    if (!card) return;
    var expanded = card.classList.toggle('expanded');
    var hidden = card.querySelectorAll('.result-line-overflow').length;
    if (expanded) {
      btn.innerHTML = '收起<svg class="arrow" viewBox="0 0 24 24"><polyline points="6 9 12 15 18 9"/></svg>';
    } else {
      btn.innerHTML = '显示剩余 ' + hidden + ' 条匹配行<svg class="arrow" viewBox="0 0 24 24"><polyline points="6 9 12 15 18 9"/></svg>';
    }
  });
})();
/* ]]> */
</script>
<%= PageConfig.get(request).getScripts() %>
</body>
</html>