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

Copyright (c) 2007, 2026, Oracle and/or its affiliates. All rights reserved.
Portions Copyright 2011 Jens Elkner.
Portions Copyright (c) 2026, UI Refactor.
--%>

<%-- index.jsp - application home page.

    Owns:
      * request-time setup (charset, PageConfig.get(request))
      * project-selection cookie persistence (delegated to projects.jspf)
      * page title
      * search-hero heading + subtitle (and their styles)
      * page-specific <style> block (search-hero / results / pagination /
        autocomplete)
      * results-section HTML skeleton
      * inline search-results renderer + sort handler

    Chrome (header, body open/close, compact-nav, breadcrumb, footer) is
    provided by pageheader.jspf + foot.jspf. The search form + project
    chips live in menu.jspf. The repository grid lives in repos.jspf.

    search.jsp is the non-JS fallback for the /api/v1/search path used here.
--%>

<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page session="false" errorPage="error.jsp"%>
<%@ page import="
org.opengrok.indexer.web.QueryParameters,
org.opengrok.web.PageConfig"%>

<%
{
  /* ---------------------- index.jsp setup (before chrome) ---------------------
   *
   * Setup vars live in {}-scoped block so they remain accessible to the
   * pageheader.jspf include and the page body below.
   *
   * httpheader.jspf uses _chromeHttpCfg inside its own block, so there is
   * no Jasper-level duplicate-variable collision with this _chromeIndexCfg. */
  if (request.getCharacterEncoding() == null) {
    request.setCharacterEncoding("UTF-8");
  }
  PageConfig _chromeIndexCfg = PageConfig.get(request);
  _chromeIndexCfg.checkSourceRootExistence();

  /* Page title. httpheader.jspf renders it inside <title>. */
  _chromeIndexCfg.setTitle("OpenGrok Code Index");
}
%>

<%-- Cookie persistence for the selected projects (no HTML output). --%>
<%@ include file="projects.jspf"%>

<%-- Chrome: <!DOCTYPE>, <head>, stylesheets, logo header, (optional) mast +
     breadcrumb, and <body> open. The calling page is responsible for its
     own <main>...</main> pair below. --%>
<%@ include file="pageheader.jspf"%>

<style>
/* ── index.jsp page-specific styles ──────────────────────────────────────────
 *
   * Placed immediately after the chrome include so the rules apply before
   * first paint and override any chrome rules of the same specificity.
   * Theme variables (--bg / --surface / --fg / --muted / --border /
   * --accent / --accent-dim / --font-sans / --font-mono) are inherited
   * from httpheader.jspf and are NOT redefined here. */

/* ── Page background + container width (index.jsp override) ──
 *
 * httpheader.jspf ships a 1200px-wide shared container and no explicit
 * <body> background, which leaves <body> at the browser default (white).
 * The design (docs/ui/index.html) targets a 960px content column on a
 * light gray (#f4f5f7) page background. We pin both here so other pages
 * that share the same chrome keep their 1200px layout while this page
 * alone matches the design. */
body {
  background: var(--bg);
}

main.container {
  max-width: 960px;
  padding: 36px 24px 48px;
}

@media (max-width: 700px) {
  main.container { padding: 24px 16px 36px; }
}

/* ── Search hero (heading + subtitle) ──
 *
   * The <h1 class="search-hero-heading"> and
   * <p class="search-hero-subtitle"> live directly in index.jsp (not in
   * menu.jspf) so each page that includes menu.jspf can supply its own
   * hero copy. The rules below intentionally sit outside the .menu-root
   * scope and target the bare class names. */
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
  display: none;
  margin-top: 24px;
  animation: fadeIn 0.3s ease;
}

.results-section.visible {
  display: block;
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

/* ── Result group header ── */
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

/* File-path link is the only direct-child <a> that should fill the
 * remaining width. Earlier rules used `.result-file-header > a` which
 * also matched the three .action-btn links and made them stretch. */
.result-file-header > a.file-link {
  display: block;          /* keep the path on a single line */
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

/* Action-button cluster sits on the right and must NOT stretch even
 * though it lives in the same flex row as the file-link. */
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

/* Down-arrow SVG inside the expand button. Rotates 180° when the
 * file card is expanded so the same icon flips from "down" to "up". */
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

/* ── Pagination ── */
.pagination {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 4px;
  padding: 20px 0 8px;
}

/* The top pagination mirrors the bottom one. We render two bars (above
 * the results-list and below the results-list) so the user can jump
 * pages without scrolling. The page config (current / total / pageSize)
 * is shared between them via renderPagination() in the inline script. */
.pagination-top {
  padding: 4px 0 12px;
  border-bottom: 1px solid var(--border);
  margin-bottom: 16px;
}

.pagination-top:empty,
.pagination:empty {
  display: none;
}

.pagination-top .page-jump-hint {
  margin-left: auto;
  color: var(--muted);
  font-size: 12px;
}

.pagination-top .page-jump-hint input {
  width: 56px;
  height: 28px;
  padding: 0 6px;
  margin: 0 4px;
  border: 1px solid var(--border);
  border-radius: 6px;
  font-size: 13px;
  font-family: var(--font-sans);
  color: var(--fg);
  background: var(--surface);
  text-align: center;
  outline: none;
}

.pagination-top .page-jump-hint input:focus {
  border-color: var(--accent);
}

.page-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  min-width: 36px;
  height: 36px;
  padding: 0 10px;
  border-radius: 8px;
  border: none;
  background: transparent;
  font-size: 14px;
  font-family: var(--font-sans);
  font-weight: 500;
  color: var(--fg);
  cursor: pointer;
  transition: background 0.12s, color 0.12s;
  text-decoration: none;
}

.page-btn:hover {
  background: #f0f1f3;
}

.page-btn.active {
  background: var(--accent);
  color: #fff;
}

.page-btn.active:hover {
  background: #1e40af;
}

.page-btn:disabled {
  opacity: 0.4;
  cursor: default;
  pointer-events: none;
}

.page-btn.nav-btn {
  color: var(--muted);
  font-weight: 400;
}

.page-btn.nav-btn:hover {
  color: var(--accent);
}

.page-btn.nav-btn svg {
  width: 14px;
  height: 14px;
  stroke: currentColor;
  fill: none;
  stroke-width: 2;
}

.page-ellipsis {
  min-width: 36px;
  height: 36px;
  display: grid;
  place-items: center;
  font-size: 14px;
  color: var(--muted);
}

/* ── Responsive — tablet / mobile ── */
@media (max-width: 700px) {
  .result-line { font-size: 11.5px; }
  .line-num    { width: 36px; min-width: 36px; font-size: 10.5px; }
}

@media (max-width: 480px) {
  .search-hero-heading { font-size: 19px; }
  .pagination .page-btn:nth-child(n+5):nth-child(-n+8) { display: none; }
}

/* ── jQuery UI autocomplete popup override ── */
.ui-autocomplete {
  box-sizing: border-box;
  border-radius: 8px;
  overflow: hidden;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.08);
  font-size: 13.5px;
}

.ui-autocomplete .ui-menu-item {
  margin: 0;
  border: 0;
  display: block;
}

.ui-autocomplete .ui-menu-item-wrapper {
  height: 32px !important;
  padding: 0 12px !important;
  display: flex !important;
  align-items: baseline !important;
  gap: 12px;
  min-width: 0;
}

.ui-autocomplete .ui-menu-item-wrapper > span {
  float: none !important;
  max-height: none !important;
  padding: 0 !important;
  line-height: 1.5;
  color: var(--fg);
  font-style: normal;
}

.ui-autocomplete .ui-menu-item-wrapper > span:first-child {
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ui-autocomplete .ui-menu-item-wrapper > span:last-child {
  flex: 0 0 auto;
  color: var(--muted);
  font-style: italic;
  font-size: 12.5px;
}

.ui-autocomplete .ui-menu-item.ui-state-focus .ui-menu-item-wrapper,
.ui-autocomplete .ui-menu-item:hover .ui-menu-item-wrapper {
  background: var(--accent-dim);
}

.ui-autocomplete .ui-menu-item.ui-state-focus .ui-menu-item-wrapper > span,
.ui-autocomplete .ui-menu-item:hover .ui-menu-item-wrapper > span {
  color: var(--fg);
}
</style>

<main class="container">

  <h1 class="search-hero-heading">搜索代码</h1>
  <p class="search-hero-subtitle">在已索引的代码仓库中进行多维度检索</p>

  <%-- Search form + project chips live in menu.jspf. --%>
  <%@ include file="menu.jspf"%>

  <section class="results-section" id="results-section">
    <div class="sort-bar" id="sort-bar">
      <span class="sort-label">排序：</span>
      <button class="sort-option" data-sort="modified"
        onclick="changeSort(this)">最后修改时间</button>
      <span class="sort-sep">|</span>
      <button class="sort-option active" data-sort="relevance"
        onclick="changeSort(this)">相关度</button>
      <span class="sort-sep">|</span>
      <button class="sort-option" data-sort="path"
        onclick="changeSort(this)">路径</button>
    </div>

    <div class="results-header" id="results-header"></div>

    <%-- Top pagination bar — placed right above the results list so
         it's visually adjacent to the data it paginates. The bottom
         bar sits below the list. renderPagination() in the inline
         script writes the same buttons into both #pagination-top and
         #pagination, and empty containers collapse via CSS. --%>
    <div class="pagination pagination-top" id="pagination-top"></div>

    <div class="results-list" id="results-list"></div>
    <div class="pagination" id="pagination"></div>
  </section>

  <%-- Repository grid. --%>
  <%@ include file="repos.jspf"%>

</main>

<%-- Project-supplied body include content. --%>
<%= PageConfig.get(request).getEnv().getIncludeFiles().getBodyIncludeFileContent(false) %>

<%-- Common footer. --%>
<%@ include file="foot.jspf"%>

<script type="text/javascript">
/* <![CDATA[ */
/* Inline search-results renderer + sort handler.
 *
 * Pagination strategy mirrors the legacy `search.jsp` /
 * `Util.createSlider` model: each API call requests a fixed Lucene
 * document window (PAGE_SIZE = 25) via the `maxresults` parameter, the
 * `start` parameter advances the offset for subsequent pages, and the
 * total page count is derived from `resultCount` (total Lucene
 * documents). The /api/v1/search response groups hits by file path so
 * each page renders a handful of `.result-file-card` elements, but the
 * page cursor lives in doc space — same as the legacy UI.
 *
 * The chip / adv-toggle / ⌘K handlers live in menu.jspf; this script
 * coordinates with them via the shared #sbox, #full, #_menu-project-select
 * elements. */
(function () {
  var PAGE_SIZE = 25;
  var MAX_PAGINATION_BUTTONS = 10;
  var sbox          = document.getElementById('sbox');
  var fullInput     = document.getElementById('full');
  var projectSelect = document.getElementById('_menu-project-select');
  var resultsSection = document.getElementById('results-section');
  var resultsHeader  = document.getElementById('results-header');
  var resultsList    = document.getElementById('results-list');
  var paginationEl   = document.getElementById('pagination');
  var paginationTop  = document.getElementById('pagination-top');
  var repoSection    = document.getElementById('repo-section');

  /* `currentStart` mirrors the legacy SearchHelper#getStart() value:
   * the 0-based Lucene document offset of the first hit on the
   * currently displayed page. goToPage() converts a 1-based page
   * number back into this offset before re-issuing the request. */
  var currentStart = 0;

  var SORT_KEY_MAP = {
    'modified':  'lastmodtime',
    'relevance': 'relevancy',
    'path':     'fullpath'
  };
  var FORM_TO_API_PARAM = {
    'defs':    'def',
    'refs':    'symbol',
    'project': 'projects'
  };

  /* computePageWindow mirrors the legacy Util.createSlider window
   * algorithm: pick a contiguous run of up to MAX_PAGINATION_BUTTONS
   * pages that contains `currentPage`, anchored near the start or end
   * when currentPage is close to either boundary. This gives the same
   * "1 2 3 4 5 6 7 ... 156" pattern as the old JSP. */
  function computePageWindow(currentPage, lastPage) {
    var first = 1;
    var last  = lastPage;
    if (lastPage > MAX_PAGINATION_BUTTONS) {
      /* Try to centre the window around currentPage, but always keep
       * a full MAX_PAGINATION_BUTTONS window where possible. */
      var half = Math.floor(MAX_PAGINATION_BUTTONS / 2);
      first = Math.max(1, currentPage - half);
      last  = first + MAX_PAGINATION_BUTTONS - 1;
      if (last > lastPage) {
        last  = lastPage;
        first = Math.max(1, last - MAX_PAGINATION_BUTTONS + 1);
      }
    }
    return { first: first, last: last };
  }

  /* renderPagination writes the same Previous / page-number / Next bar
   * into both the top and bottom containers. The two bars stay in sync
   * by sharing `currentStart` via the closure and by re-rendering both
   * containers from a single call. */
  function renderPagination(currentPage, lastPage) {
    if (lastPage <= 1) {
      if (paginationEl)  paginationEl.innerHTML  = '';
      if (paginationTop) paginationTop.innerHTML = '';
      return;
    }
    var win = computePageWindow(currentPage, lastPage);
    var html = '';
    html += '<button class="page-btn nav-btn" type="button" data-page="prev"'
          + (currentPage <= 1 ? ' disabled' : '') + '>'
          + '<svg viewBox="0 0 24 24"><polyline points="15 18 9 12 15 6"/></svg> Previous</button>';

    if (win.first > 1) {
      html += '<button class="page-btn" type="button" data-page="1">1</button>';
      if (win.first > 2) {
        html += '<span class="page-ellipsis">…</span>';
      }
    }
    for (var p = win.first; p <= win.last; p++) {
      if (p === currentPage) {
        html += '<button class="page-btn active" type="button" data-page="' + p + '">' + p + '</button>';
      } else {
        html += '<button class="page-btn" type="button" data-page="' + p + '">' + p + '</button>';
      }
    }
    if (win.last < lastPage) {
      if (win.last < lastPage - 1) {
        html += '<span class="page-ellipsis">…</span>';
      }
      html += '<button class="page-btn" type="button" data-page="' + lastPage + '">' + lastPage + '</button>';
    }

    html += '<button class="page-btn nav-btn" type="button" data-page="next"'
          + (currentPage >= lastPage ? ' disabled' : '') + '>'
          + 'Next <svg viewBox="0 0 24 24"><polyline points="9 18 15 12 9 6"/></svg></button>';

    if (paginationEl)  paginationEl.innerHTML  = html;
    if (paginationTop) paginationTop.innerHTML = html;
  }

  /* Centralized page-click handler. Bound once on each container; uses
   * data-page (a string: "prev"/"next" or a 1-based page number) to
   * decide which offset to fetch. The handler relies on the closure
   * variables currentStart and latestTotalCount (updated by every
   * renderResults() call) so it never has to re-query the API to know
   * which page is currently visible. */
  function bindPaginationClicks(container) {
    if (!container || container._pageBound) return;
    container._pageBound = true;
    container.addEventListener('click', function (ev) {
      var btn = ev.target.closest('[data-page]');
      if (!btn || btn.disabled) return;
      ev.preventDefault();
      var attr = btn.getAttribute('data-page');
      var totalPages = Math.max(1, Math.ceil(
        (Number(latestTotalCount) || 0) / PAGE_SIZE));
      var currentPage = Math.floor(currentStart / PAGE_SIZE) + 1;
      var target;
      if (attr === 'prev') {
        target = Math.max(1, currentPage - 1);
      } else if (attr === 'next') {
        target = Math.min(totalPages, currentPage + 1);
      } else {
        target = parseInt(attr, 10);
        if (!target || target < 1) return;
      }
      if (target === currentPage) return;
      goToPage(target);
    });
  }

  /* latestTotalCount is updated by every renderResults() call. The
   * pagination click handler uses it (via closure) to compute totalPages
   * without re-querying the API. */
  var latestTotalCount = 0;

  /* currentSort is the active Lucene SortOrder string ('relevancy' /
   * 'lastmodtime' / 'fullpath'). The sort buttons live OUTSIDE the
   * search form, so new FormData(sbox) cannot see them — every fetch
   * must explicitly append `sort=currentSort` from this closure var.
   * Default to 'relevancy' to match the controller's DEFAULT_SORT_ORDER
   * (org.opengrok.web.api.v1.controller.SearchController). */
  var currentSort = 'relevancy';

  window.changeSort = function (el) {
    var sortAttr = el.getAttribute('data-sort');
    var apiSort  = SORT_KEY_MAP[sortAttr] || 'relevancy';
    var opts = document.querySelectorAll('.sort-option');
    for (var i = 0; i < opts.length; i++) opts[i].classList.remove('active');
    el.classList.add('active');
    /* Changing sort resets the cursor to page 1 — same as the legacy
     * search.jsp which always re-issues the query from offset 0. */
    currentSort  = apiSort;
    currentStart = 0;
    performInlineSearch();
  };

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c];
    });
  }

  /* encodeURIComponent keeps '/' encoded as %2F by default, which makes
   * hover tooltips and status-bar links unreadable (e.g.
   * "goldfish%2Ftools%2F..." instead of "goldfish/tools/..."). Server-side
   * URIEncoder used by the upstream OpenGrok JSPs leaves '/' untouched,
   * so we mirror that here. */
  function encodePath(s) {
    return encodeURIComponent(String(s)).replace(/%2F/g, '/');
  }

  function renderResults(data, query) {
    if (!resultsSection || !resultsList || !resultsHeader) return;
    resultsSection.classList.add('visible');
    if (repoSection) repoSection.style.display = 'none';

    var resultCount   = (data && typeof data.resultCount   === 'number') ? data.resultCount   : 0;
    var startDocument = (data && typeof data.startDocument === 'number') ? data.startDocument : 0;
    var endDocument   = (data && typeof data.endDocument   === 'number') ? data.endDocument   : startDocument;
    var resultsMap    = (data && data.results) ? data.results : {};
    var filePaths     = Object.keys(resultsMap);

    latestTotalCount = resultCount;
    currentStart     = startDocument;

    /* The legacy search.jsp reports the result range 1-based ("Results
     * 1 – 25 of 3886"). The /api/v1/search response returns 0-based
     * document offsets, so add 1 here to keep the new UI aligned with
     * the legacy wording. */
    var displayStart = resultCount > 0 ? startDocument + 1 : 0;
    var displayEnd   = endDocument + 1;
    var totalPages   = Math.max(1, Math.ceil(resultCount / PAGE_SIZE));
    var currentPage  = Math.floor(startDocument / PAGE_SIZE) + 1;

    /* Human-readable label for the active sort order. Mirrors SortOrder.getDesc()
     * from org.opengrok.indexer.web.SortOrder so the wording stays consistent
     * with the controller's accepted values. */
    var SORT_LABELS = {
      'relevancy':   '相关度',
      'lastmodtime': '最后修改时间',
      'fullpath':    '路径'
    };
    var sortLabel = SORT_LABELS[currentSort] || currentSort;

    resultsHeader.innerHTML =
      '命中 <strong>' + resultCount + '</strong> 条结果' +
      (filePaths.length > 0 ? '（' + displayStart + '\u2013' + displayEnd + '）' : '') +
      (query ? '，查询 <span class="query-term">' + escapeHtml(query) + '</span>' : '') +
      '<span class="result-meta-sep">·</span>' +
      '<span class="result-meta">排序：<strong>' + escapeHtml(sortLabel) + '</strong></span>';

    renderPagination(currentPage, totalPages);
    bindPaginationClicks(paginationEl);
    bindPaginationClicks(paginationTop);

    var html = '';
    if (filePaths.length === 0) {
      html = '<div class="results-empty">未找到匹配项</div>';
    } else {
      var groups = Object.create(null);
      filePaths.forEach(function (rawPath) {
        /* Search-result paths returned by /api/v1/search are stored in
         * Lucene as project-relative paths that BEGIN with '/' (see
         * IndexDatabase#addFile and AnalyzerGuru#populateDocument where
         * QueryBuilder.PATH is the path from source root). Strip that
         * leading slash so we don't end up with a doubled slash like
         * "/xref//goldfish/...". Trailing slashes should never appear
         * here because every hit is a file, not a directory. */
        var path = rawPath.charAt(0) === '/' ? rawPath.substring(1) : rawPath;
        var dir = path.substring(0, path.lastIndexOf('/')) || '';
        if (!groups[dir]) groups[dir] = [];
        groups[dir].push({ path: path, hits: resultsMap[rawPath] || [] });
      });

      var MAX_HITS_PER_CARD = 10;
      Object.keys(groups).forEach(function (dir) {
        var totalHits = 0;
        groups[dir].forEach(function (entry) { totalHits += entry.hits.length; });
        html += '<div class="result-group-header">';
        if (dir) {
          html += '<a href="' + window.contextPath + '/xref/' + encodePath(dir) + '">' + escapeHtml(dir) + '/</a>';
        } else {
          html += '<span class="group-root">（项目根）</span>';
        }
        html += '<span class="group-count">' + totalHits + '</span>';
        html += '</div>';

        groups[dir].forEach(function (entry) {
          var hits = entry.hits;
          html += '<div class="result-file-card">';
          html += '<div class="result-file-header">';
          html += '<a class="file-link" href="' + window.contextPath + '/xref/' + encodePath(entry.path) + '">' + escapeHtml(entry.path) + '</a>';
          html += '<div class="file-actions">';
          html += '<a class="action-btn" title="History" href="' + window.contextPath + '/history/' + encodePath(entry.path) + '"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg></a>';
          html += '<a class="action-btn" title="Annotate" href="' + window.contextPath + '/xref/' + encodePath(entry.path) + '?an=true"><svg viewBox="0 0 24 24"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg></a>';
          html += '<a class="action-btn" title="Download" href="' + window.contextPath + '/download/' + encodePath(entry.path) + '"><svg viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg></a>';
          html += '</div>';
          html += '</div>';
          hits.forEach(function (h, i) {
            var lineClass = (i >= MAX_HITS_PER_CARD) ? 'result-line result-line-overflow' : 'result-line';
            var href = window.contextPath + '/xref/' + encodePath(entry.path) + '#L' + h.lineNumber;
            html += '<a class="' + lineClass + '" href="' + href + '">';
            html += '<span class="line-num">' + h.lineNumber + '</span>';
            html += '<span class="line-code">' + h.line + '</span>';
            html += '</a>';
          });
          if (hits.length > MAX_HITS_PER_CARD) {
            var hiddenCount = hits.length - MAX_HITS_PER_CARD;
            html += '<button class="result-expand-btn" type="button">'
                  + '显示剩余 ' + hiddenCount + ' 条匹配行'
                  + '<svg class="arrow" viewBox="0 0 24 24"><polyline points="6 9 12 15 18 9"/></svg>'
                  + '</button>';
          }
          html += '</div>';
        });
      });
    }
    resultsList.innerHTML = html;

    if (!resultsList._expandBound) {
      resultsList._expandBound = true;
      resultsList.addEventListener('click', function (ev) {
        var btn = ev.target.closest('.result-expand-btn');
        if (!btn) return;
        var card = btn.closest('.result-file-card');
        if (!card) return;
        var expanded = card.classList.toggle('expanded');
        var totalHidden = card.querySelectorAll('.result-line-overflow').length;
        btn.innerHTML = (expanded
          ? '收起<svg class="arrow" viewBox="0 0 24 24"><polyline points="6 9 12 15 18 9"/></svg>'
          : '显示剩余 ' + totalHidden + ' 条匹配行<svg class="arrow" viewBox="0 0 24 24"><polyline points="6 9 12 15 18 9"/></svg>');
      });
    }
  }

  function performInlineSearch() {
    /* Fetches a single 25-doc window starting at currentStart. Identical
     * shape to the legacy Util.createSlider pipeline: maxresults=PAGE_SIZE
     * (env hitsPerPage) plus a `start` offset for subsequent pages. */
    if (!sbox) return;
    var fd = new FormData(sbox);
    var params = new URLSearchParams();
    fd.forEach(function (v, k) {
      if (typeof v === 'string' && v.length) {
        var apiKey = FORM_TO_API_PARAM[k] || k;
        params.append(apiKey, v);
      }
    });
    var query = (fullInput && fullInput.value) ? fullInput.value.trim() : '';
    if (query) params.set('full', query);
    params.set('maxresults', String(PAGE_SIZE));
    if (currentStart > 0) params.set('start', String(currentStart));
    /* Append the active Lucene sort order. The sort buttons are outside
     * the search form, so we carry the value through the currentSort
     * closure variable rather than relying on FormData(sbox). */
    params.set('sort', currentSort);
    var url = (window.contextPath || '') + '/api/v1/search?' + params.toString();
    fetch(url, { headers: { 'Accept': 'application/json' } })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (data) { renderResults(data, query); })
      .catch(function () { if (sbox) sbox.submit(); });
  }

  /* goToPage(page) converts a 1-based page number back to the 0-based
   * Lucene document offset and re-issues the search. Bound to the page
   * buttons via bindPaginationClicks(). */
  function goToPage(page) {
    var target = (page - 1) * PAGE_SIZE;
    if (target < 0) target = 0;
    currentStart = target;
    performInlineSearch();
  }
  /* Expose goToPage on window so external scripts / future event hooks
   * can drive the pager the same way. */
  window.goToPage = goToPage;

  if (sbox) {
    sbox.addEventListener('submit', function (ev) {
      ev.preventDefault();
      currentStart = 0;
      performInlineSearch();
    });
  }
  if (fullInput) {
    fullInput.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') {
        e.preventDefault();
        currentStart = 0;
        performInlineSearch();
      }
    });
  }

  /* If the URL still carries a search query on load, run it once and
   * strip the query string so the URL stays clean for sharing. */
  (function () {
    var urlParams = new URLSearchParams(window.location.search);
    var initialQuery = urlParams.get('<%=QueryParameters.FULL_SEARCH_PARAM%>');
    if (!initialQuery || !initialQuery.trim()) return;
    if (!sbox || !fullInput) return;
    Promise.resolve().then(function () {
      currentStart = 0;
      performInlineSearch();
      try {
        var cleanUrl = window.location.pathname + window.location.hash;
        window.history.replaceState({}, document.title, cleanUrl);
      } catch (_) { /* very old browsers: ignore */ }
    });
  })();

  /* Hook used by utils.js (registered via document.domReady). */
  if (document && Array.isArray(document.domReady)) {
    document.domReady.push(function () {
      window.getSelectedProjectNames = function () {
        if (!projectSelect) return [];
        var names = [];
        for (var i = 0; i < projectSelect.options.length; i++) {
          if (projectSelect.options[i].selected) names.push(projectSelect.options[i].value);
        }
        return names;
      };
      if (window.jQuery) {
        window.jQuery('#full, #defs, #refs, #path, #hist').on('autocompleteopen', function () {
          var $input = window.jQuery(this);
          var $ul = $input.autocomplete('widget');
          $ul.outerWidth($input.outerWidth());
        });
      }
    });
  }
})();
/* ]]> */
</script>
<%= PageConfig.get(request).getScripts() %>
</body>
</html>