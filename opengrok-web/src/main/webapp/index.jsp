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
<%@ page session="false" errorPage="error.jsp" import="
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

.result-file-header > a {
  display: flex;
  align-items: center;
  gap: 8px;
  flex: 1;
  min-width: 0;
  text-decoration: none;
  color: var(--muted);
  transition: color 0.12s;
}

.result-file-header > a:hover {
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

.result-file-header .file-path {
  font-family: var(--font-mono);
  font-size: 12px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  flex: 1;
}

.result-file-header .file-actions {
  display: flex;
  gap: 4px;
  flex-shrink: 0;
  margin-left: auto;
}

.action-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 4px 10px;
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
    <div class="results-list" id="results-list"></div>
    <div class="pagination" id="pagination">
      <button class="page-btn nav-btn" disabled>
        <svg viewBox="0 0 24 24"><polyline points="15 18 9 12 15 6"/></svg> Previous
      </button>
      <button class="page-btn active">1</button>
      <button class="page-btn">2</button>
      <button class="page-btn">3</button>
      <button class="page-btn">4</button>
      <button class="page-btn">5</button>
      <button class="page-btn">6</button>
      <button class="page-btn">7</button>
      <span class="page-ellipsis">…</span>
      <button class="page-btn">100</button>
      <button class="page-btn nav-btn">
        Next <svg viewBox="0 0 24 24"><polyline points="9 18 15 12 9 6"/></svg>
      </button>
    </div>
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
 * The chip / adv-toggle / ⌘K handlers live in menu.jspf; this script
 * coordinates with them via the shared #sbox, #full, #_menu-project-select
 * elements. */
(function () {
  var sbox          = document.getElementById('sbox');
  var fullInput     = document.getElementById('full');
  var projectSelect = document.getElementById('_menu-project-select');
  var resultsSection = document.getElementById('results-section');
  var resultsHeader  = document.getElementById('results-header');
  var resultsList    = document.getElementById('results-list');
  var repoSection    = document.getElementById('repo-section');

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

  window.changeSort = function (el) {
    var sortAttr = el.getAttribute('data-sort');
    var apiSort  = SORT_KEY_MAP[sortAttr] || 'relevancy';
    var opts = document.querySelectorAll('.sort-option');
    for (var i = 0; i < opts.length; i++) opts[i].classList.remove('active');
    el.classList.add('active');
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
    params.set('sort', apiSort);
    var url = (window.contextPath || '') + '/api/v1/search?' + params.toString();
    fetch(url, { headers: { 'Accept': 'application/json' } })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (data) { renderResults(data, query); })
      .catch(function () { if (sbox) sbox.submit(); });
  };

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c];
    });
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

    resultsHeader.innerHTML =
      '命中 <strong>' + resultCount + '</strong> 条结果' +
      (filePaths.length > 0 ? '（' + startDocument + '\u2013' + endDocument + '）' : '') +
      (query ? '，查询 <span class="query-term">' + escapeHtml(query) + '</span>' : '');

    var html = '';
    if (filePaths.length === 0) {
      html = '<div class="results-empty">未找到匹配项</div>';
    } else {
      var groups = Object.create(null);
      filePaths.forEach(function (path) {
        var dir = path.substring(0, path.lastIndexOf('/')) || '';
        if (!groups[dir]) groups[dir] = [];
        groups[dir].push({ path: path, hits: resultsMap[path] || [] });
      });

      var MAX_HITS_PER_CARD = 10;
      Object.keys(groups).forEach(function (dir) {
        var totalHits = 0;
        groups[dir].forEach(function (entry) { totalHits += entry.hits.length; });
        html += '<div class="result-group-header">';
        if (dir) {
          html += '<a href="' + window.contextPath + '/xref/' + encodeURIComponent(dir) + '">' + escapeHtml(dir) + '/</a>';
        } else {
          html += '<span class="group-root">（项目根）</span>';
        }
        html += '<span class="group-count">' + totalHits + '</span>';
        html += '</div>';

        groups[dir].forEach(function (entry) {
          var hits = entry.hits;
          html += '<div class="result-file-card">';
          html += '<div class="result-file-header">';
          html += '<a href="' + window.contextPath + '/xref/' + encodeURIComponent(entry.path) + '">' + escapeHtml(entry.path) + '</a>';
          html += '<a class="action-btn" title="History" href="' + window.contextPath + '/history/' + encodeURIComponent(entry.path) + '"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg></a>';
          html += '<a class="action-btn" title="Annotate" href="' + window.contextPath + '/xref/' + encodeURIComponent(entry.path) + '?an=true"><svg viewBox="0 0 24 24"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg></a>';
          html += '<a class="action-btn" title="Download" href="' + window.contextPath + '/download/' + encodeURIComponent(entry.path) + '"><svg viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg></a>';
          html += '</div>';
          hits.forEach(function (h, i) {
            var lineClass = (i >= MAX_HITS_PER_CARD) ? 'result-line result-line-overflow' : 'result-line';
            var href = window.contextPath + '/xref/' + encodeURIComponent(entry.path) + '#L' + h.lineNumber;
            html += '<a class="' + lineClass + '" href="' + href + '">';
            html += '<span class="line-num">' + h.lineNumber + '</span>';
            html += '<span class="line-code">' + h.line + '</span>';
            html += '</a>';
          });
          if (hits.length > MAX_HITS_PER_CARD) {
            var hiddenCount = hits.length - MAX_HITS_PER_CARD;
            html += '<button class="result-expand-btn" type="button">\u25bc 显示剩余 ' + hiddenCount + ' 条匹配行</button>';
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
        btn.innerHTML = (expanded ? '\u25b2 收起' : '\u25bc 显示剩余 ' + totalHidden + ' 条匹配行');
      });
    }
  }

  function performInlineSearch() {
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
    var url = (window.contextPath || '') + '/api/v1/search?' + params.toString();
    fetch(url, { headers: { 'Accept': 'application/json' } })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (data) { renderResults(data, query); })
      .catch(function () { if (sbox) sbox.submit(); });
  }

  if (sbox) {
    sbox.addEventListener('submit', function (ev) {
      ev.preventDefault();
      performInlineSearch();
    });
  }
  if (fullInput) {
    fullInput.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') {
        e.preventDefault();
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
</body>
</html>