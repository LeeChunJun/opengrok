<%--
$Id$

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
Portions Copyright (c) 2018-2020, Chris Fraire <cfraire@me.com>.
Portions Copyright (c) 2026, UI Refactor.
--%>
<%@page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@page errorPage="error.jsp" import="
java.io.IOException,
java.io.File,
java.text.Format,
java.text.SimpleDateFormat,
java.util.Date,
java.util.logging.Level,
java.util.logging.Logger,
java.util.Objects,
java.util.Set,
java.util.regex.Pattern,

org.opengrok.indexer.Info,
org.opengrok.indexer.configuration.RuntimeEnvironment,
org.opengrok.indexer.history.History,
org.opengrok.indexer.history.HistoryEntry,
org.opengrok.indexer.history.HistoryGuru,
org.opengrok.indexer.logger.LoggerFactory,
org.opengrok.indexer.util.ForbiddenSymlinkException,
org.opengrok.indexer.web.QueryParameters,
org.opengrok.indexer.web.SearchHelper,
org.opengrok.indexer.web.Util"
%>
<%@ page import="jakarta.servlet.http.HttpServletResponse" %>
<%@ page import="org.opengrok.indexer.web.SortOrder" %>
<%@ page import="java.util.Optional" %>
<%@ page import="org.opengrok.indexer.web.Laundromat" %>
<%@ page import="java.util.Locale" %>
<%@ page import="org.opengrok.indexer.configuration.Project" %>
<%@ page import="org.opengrok.indexer.web.Prefix" %>
<%@ page import="org.opengrok.web.PageConfig" %>
<%{
    /* ---------------------- history.jsp start --------------------- */
    final Logger LOGGER = LoggerFactory.getLogger(getClass());

    PageConfig cfg = PageConfig.get(request);
    cfg.checkSourceRootExistence();

    // Need to set the title before including mast.jsp (which includes httpheader.jspf)
    cfg.setTitle(cfg.getHistoryTitle());

    String path = cfg.getPath();

    if (!path.isEmpty()) {
        String primePath = path;
        Project project = cfg.getProject();
        if (project != null) {
            SearchHelper searchHelper = cfg.prepareInternalSearch(SortOrder.RELEVANCY);
            /*
             * N.b. searchHelper.destroy() is called via
             * WebappListener.requestDestroyed() on presence of the following
             * REQUEST_ATTR.
             */
            request.setAttribute(SearchHelper.REQUEST_ATTR, searchHelper);
            searchHelper.prepareExec(project);

            try {
                primePath = searchHelper.getPrimeRelativePath(project.getName(), path);
            } catch (IOException | ForbiddenSymlinkException ex) {
                LOGGER.log(Level.WARNING, String.format("Error getting prime relative for '%s'", path), ex);
            }
        }

        File file = cfg.getResourceFile(primePath);
        History hist;
        try {
            hist = HistoryGuru.getInstance().getHistoryUI(file);
        } catch (Exception e) {
            // should not happen
            response.sendError(HttpServletResponse.SC_NOT_FOUND, e.getMessage());
            return;
        }

        if (hist == null) {
            /*
             * The history is not available even for a renamed file.
             * Send 404 Not Found.
             */
            response.sendError(HttpServletResponse.SC_NOT_FOUND);
            return;
        }
        request.setAttribute(cfg.getHistoryAttrName(), hist);
    }
}
%><%@ include file="/mast.jsp" %><script type="text/javascript">/* <![CDATA[ */
    document.domReady.push(function() { domReadyHistory(); });
    document.domReady.push(function() { domReadyMast(); });
    document.pageReady.push(function() { pageReadyMast(); });
/* ]]> */</script>
<%
/* ---------------------- history-page render start --------------------- */
{
    PageConfig cfg = PageConfig.get(request);
    String context = request.getContextPath();
    String path = cfg.getPath();
    History hist;

    if ((hist = (History) request.getAttribute(cfg.getHistoryAttrName())) != null) {

        int startIndex = cfg.getStartIndex();
        int max = cfg.getMaxItems();
        long totalHits = hist.getHistoryEntries().size();
        long thisPageIndex = Math.min(totalHits - startIndex, max);

        // We have potentially a lots of results to show: create a slider for them
        request.setAttribute("history.jsp-slider", Util.createSlider(startIndex, max, totalHits, request));

        RuntimeEnvironment env = cfg.getEnv();
        String uriEncodedName = cfg.getUriEncodedPath();
        Project project = cfg.getProject();

        boolean striked = false;
        String userPage = env.getUserPage();
        String userPageSuffix = env.getUserPageSuffix();
        String bugPage = project != null ? project.getBugPage() : env.getBugPage();
        String bugRegex = project != null ? project.getBugPattern() : env.getBugPattern();
        Pattern bugPattern = null;
        if (bugRegex != null) {
            bugPattern = Pattern.compile(bugRegex);
        }
        String reviewPage = project != null ? project.getReviewPage() : env.getReviewPage();
        String reviewRegex = project != null ? project.getReviewPattern() : env.getReviewPattern();
        Pattern reviewPattern = null;
        if (reviewRegex != null) {
            reviewPattern = Pattern.compile(reviewRegex);
        }

        Format dayFmt = new SimpleDateFormat("M月d日", Locale.CHINA);
        Format yearFmt = new SimpleDateFormat("yyyy年", Locale.CHINA);

        int revision2Index = Math.max(cfg.getIntParam(QueryParameters.REVISION_2_PARAM, -1), 0);
        int revision1Index = cfg.getIntParam(QueryParameters.REVISION_1_PARAM, -1) < revision2Index ?
                revision2Index + 1 : cfg.getIntParam(QueryParameters.REVISION_1_PARAM, -1);
        revision2Index = revision2Index >= hist.getHistoryEntries().size() ? hist.getHistoryEntries().size() - 1 : revision2Index;

        // Strip the leading project prefix from `path` so the title and
        // breadcrumb don't double up. cfg.getPath() is the absolute path
        // from source root, which for /history/<proj>/<dir> looks like
        // "/<proj>/<dir>" (already includes the project name). Without this
        // stripping the title reads "/mosaic//mosaic/mosaic-tty//" instead
        // of "/mosaic/mosaic-tty/".
        String subPath = path;
        if (project != null) {
            String prefix = "/" + project.getName();
            if (subPath.startsWith(prefix)) {
                subPath = subPath.substring(prefix.length());
            }
        }
        if (subPath.startsWith("/")) {
            subPath = subPath.substring(1);
        }
        // cfg.getPath() for a directory ends with "/", which would cause
        // double slashes in the title/breadcrumb once we add our own trailing
        // slash for directories. Trim any trailing slash here.
        while (subPath.endsWith("/")) {
            subPath = subPath.substring(0, subPath.length() - 1);
        }
        String titlePathStr;
        if (project != null) {
            titlePathStr = "/" + project.getName()
                    + (subPath.isEmpty() ? "/" : "/" + subPath + (cfg.isDir() ? "/" : ""));
        } else {
            titlePathStr = subPath.isEmpty() ? "/" : ("/" + subPath + (cfg.isDir() ? "/" : ""));
        }
%>
<style>
/* ── UI refactor 3a — directory-history styles ── */
:root {
    --bg: #f6f8fa;
    --surface: #ffffff;
    --fg: #24292f;
    --muted: #57606a;
    --border: #d0d7de;
    --border-light: #eaeef2;
    --accent: #0969da;
    --accent-dim: rgba(9,105,218,0.08);
    --font-sans: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif;
    --font-mono: ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, 'Liberation Mono', monospace;
}

/* Hide mast.jsp legacy chrome — history.jsp provides its own. */
html.history_jsp #whole_header,
html.history_jsp #Masthead,
html.history_jsp #bar { display: none !important; }
#content { margin-top: 0 !important; padding: 0 !important; }

/* ── Header (logo + title + code-browse link) ── */
.header {
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    padding: 14px 32px;
    display: flex;
    align-items: center;
    gap: 12px;
}
.header-logo {
    width: 28px; height: 28px;
    background: var(--fg);
    border-radius: 7px;
    display: grid; place-items: center;
    flex-shrink: 0;
}
.header-logo svg {
    width: 14px; height: 14px;
    stroke: #60a5fa; fill: none; stroke-width: 2.5;
}
.header-title {
    font-size: 16px;
    font-weight: 600;
    letter-spacing: -0.02em;
}
.header-title span {
    color: var(--muted);
    font-weight: 400;
    margin-left: 4px;
}
.header-link {
    margin-left: auto;
    font-size: 13px;
    color: var(--muted);
    text-decoration: none;
    transition: color 0.12s;
}
.header-link:hover { color: var(--accent); }
.header-link svg {
    width: 14px; height: 14px;
    stroke: currentColor; fill: none; stroke-width: 2;
    vertical-align: -1px;
    margin-right: 4px;
}

/* ── Compact Nav ── */
.compact-nav {
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    padding: 8px 24px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 13px;
    gap: 12px;
}
.compact-nav-left { display: flex; align-items: center; gap: 4px; flex-wrap: wrap; }
.compact-nav-right { display: flex; align-items: center; gap: 8px; flex-shrink: 0; }
.search-form { display: flex; align-items: center; gap: 8px; flex-shrink: 0; }
.search-group {
    display: flex; align-items: center;
    border: 1px solid var(--border); border-radius: 6px;
    overflow: hidden;
    transition: border-color 0.15s, box-shadow 0.15s;
    flex-shrink: 0;
}
.search-group:focus-within {
    border-color: var(--accent);
    box-shadow: 0 0 0 3px var(--accent-dim);
}
.search-group .search-input-wrap {
    position: relative; display: flex; align-items: center;
}
.search-group .search-input-wrap svg {
    position: absolute; left: 8px;
    width: 14px; height: 14px;
    stroke: var(--muted); fill: none; stroke-width: 2;
    pointer-events: none;
}
.search-group .search-input {
    width: 170px; height: 30px;
    border: none;
    padding: 0 8px 0 28px;
    font-size: 12.5px;
    font-family: var(--font-sans);
    outline: none; background: transparent;
    flex-shrink: 0;
}
.search-group .search-btn {
    display: inline-flex; align-items: center;
    height: 30px; padding: 0 14px;
    border: none;
    border-left: 1px solid var(--border);
    border-radius: 0 5px 5px 0;
    background: var(--bg); color: var(--fg);
    font-size: 12.5px; font-weight: 500;
    font-family: var(--font-sans);
    cursor: pointer;
    transition: background 0.12s;
    white-space: nowrap;
}
.search-group .search-btn:hover { background: #f3f4f6; }
.search-btn-icon { display: none; }
.current-dir-label {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-size: 12.5px;
    color: var(--muted);
    cursor: pointer;
    user-select: none;
    padding: 4px 10px;
    border: 1px solid var(--border);
    border-radius: 6px;
    transition: background 0.12s;
    flex-shrink: 0;
    white-space: nowrap;
    height: 30px;
    box-sizing: border-box;
}
.current-dir-label:hover { background: #f6f8fa; }
.current-dir-label input[type="checkbox"] {
    margin: 0;
    accent-color: var(--accent);
}
.nav-pill {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 5px 14px;
    border-radius: 6px;
    color: var(--fg);
    text-decoration: none;
    font-weight: 500;
    font-size: 13px;
    transition: background 0.12s, color 0.12s;
}
.nav-pill:hover { background: var(--accent-dim); color: var(--accent); }
.nav-pill.active { background: var(--accent); color: #fff; cursor: default; }
.nav-pill.active:hover { background: var(--accent); color: #fff; }
.nav-pill svg {
    width: 14px; height: 14px;
    stroke: currentColor; fill: none; stroke-width: 2;
}

/* ── Breadcrumb ── */
.dir-path {
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    padding: 6px 24px;
    font-size: 13px;
    color: var(--muted);
    display: flex;
    align-items: center;
    gap: 4px;
    overflow-x: auto;
    flex-wrap: wrap;
}
.dir-path a { color: var(--accent); text-decoration: none; white-space: nowrap; }
.dir-path a:hover { text-decoration: underline; }
.dir-path .path-sep { color: var(--border); flex-shrink: 0; }
.dir-path .path-current { color: var(--fg); font-weight: 500; white-space: nowrap; }

/* ── Container ── */
.container { max-width: 1200px; margin: 0 auto; padding: 24px; }

/* ── History Title ── */
.history-title {
    font-size: 14px;
    color: var(--fg);
    margin-bottom: 16px;
    font-weight: 400;
    display: flex;
    align-items: baseline;
    gap: 6px;
    flex-wrap: wrap;
}
.history-title strong { font-weight: 600; }
.history-title .path {
    font-family: var(--font-mono);
    font-size: 13px;
    color: var(--accent);
}
.history-title .revtags-toggle-anchor {
    margin-left: auto;
    font-size: 12px;
    color: var(--accent);
    text-decoration: none;
    white-space: nowrap;
}
.history-title .revtags-toggle-anchor:hover { text-decoration: underline; }

/* ── History Table ── */
.history-table-wrapper {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
}
.history-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
}
.history-table thead th {
    text-align: left;
    padding: 10px 12px;
    font-weight: 600;
    color: var(--fg);
    border-bottom: 2px solid var(--border);
    font-size: 12.5px;
    white-space: nowrap;
    vertical-align: bottom;
    background: #fafbfc;
}
.history-table thead th .filelist-toggle-anchor {
    float: right;
    font-size: 12px;
    color: var(--accent);
    text-decoration: none;
    font-weight: 400;
}
.history-table thead th .filelist-toggle-anchor:hover { text-decoration: underline; }
.history-table td {
    padding: 10px 12px;
    border-bottom: 1px solid var(--border-light);
    vertical-align: top;
}
.history-table tbody tr:hover { background: #f6f8fa; }
.history-table tbody tr:last-child td { border-bottom: none; }

/* Column widths */
.col-revision { width: 130px; }
.col-date { width: 90px; }
.col-author { width: 240px; }
.col-comments { width: auto; }

/* Revision cell */
.revision-hash {
    font-family: var(--font-mono);
    font-size: 12.5px;
    color: var(--accent);
    text-decoration: none;
    cursor: pointer;
}
.revision-hash:hover { text-decoration: underline; }
.revision-anchor {
    color: var(--muted);
    text-decoration: none;
    margin-right: 4px;
    font-family: var(--font-mono);
    font-size: 12.5px;
}
.revision-anchor:hover { color: var(--accent); }
.revision-radio {
    display: flex;
    gap: 10px;
    align-items: center;
    margin-top: 6px;
    font-size: 11.5px;
    color: var(--muted);
}
.revision-radio label {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    cursor: pointer;
}
.revision-radio input[type="radio"] {
    margin: 0;
    accent-color: var(--accent);
    cursor: pointer;
}

/* Date cell */
.date-day {
    font-size: 13px;
    color: var(--fg);
    font-family: var(--font-mono);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
}
.date-year {
    font-size: 11px;
    color: var(--muted);
    font-family: var(--font-mono);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
    margin-top: 2px;
}

/* Author cell */
.author-name {
    font-size: 13px;
    font-weight: 500;
    word-break: break-word;
}
.author-name a { color: var(--fg); text-decoration: none; }
.author-name a:hover { color: var(--accent); text-decoration: underline; }
.author-email {
    font-size: 11.5px;
    color: var(--muted);
    word-break: break-all;
    margin-top: 2px;
    font-family: var(--font-mono);
}

/* Comments cell */
.comment-entry {
    margin-bottom: 4px;
    font-size: 13px;
    line-height: 1.5;
    word-break: break-word;
}
.comment-entry::before {
    content: '• ';
    color: var(--muted);
}
.comment-entry.bullet::before {
    content: '* ';
    color: var(--muted);
}
.comment-separator {
    font-size: 11px;
    color: var(--muted);
    margin: 4px 0;
    font-family: var(--font-mono);
}
.co-authored {
    font-size: 11.5px;
    color: var(--muted);
    margin-top: 6px;
    margin-bottom: 4px;
    word-break: break-word;
}
.rev-message-summary,
.rev-message-full { font-size: 13px; line-height: 1.5; word-break: break-word; margin: 0 0 4px; }
.rev-message-hidden { display: none; }
.rev-message-toggle {
    margin: 4px 0;
    font-size: 12px;
}
.rev-message-toggle a {
    color: var(--accent);
    text-decoration: none;
}
.rev-message-toggle a:hover { text-decoration: underline; }

/* Hide / Show modified files (legacy classes preserved for utils.js toggle_filelist) */
.filelist,
.filelist-hidden {
    margin-top: 6px;
}
.filelist > a,
.filelist-hidden > a {
    display: block;
    font-family: var(--font-mono);
    font-size: 11.5px;
    color: var(--accent);
    text-decoration: none;
    line-height: 1.7;
    word-break: break-all;
}
.filelist > a:hover,
.filelist-hidden > a:hover { text-decoration: underline; }

/* Revision tags row */
tr.revtags td {
    background: var(--accent-dim);
    border-bottom: 1px solid var(--border-light);
    font-size: 12.5px;
    color: var(--fg);
}
tr.revtags .bold { font-weight: 600; }
tr.revtags-hidden { display: none; }

/* ── Pagination (re-styled Util.createSlider output) ── */
.pagination {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 4px;
    padding: 20px 0 8px;
    flex-wrap: wrap;
}
.pagination a,
.pagination span {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 34px;
    height: 34px;
    padding: 0 10px;
    border-radius: 7px;
    border: 1px solid var(--border);
    background: var(--surface);
    font-size: 13px;
    font-family: var(--font-sans);
    font-weight: 500;
    color: var(--fg);
    cursor: pointer;
    transition: all 0.12s;
    text-decoration: none;
}
.pagination a:hover {
    background: #f3f4f6;
    border-color: #ccc;
}
.pagination span.sel {
    background: var(--accent);
    color: #fff;
    border-color: var(--accent);
    cursor: default;
}
.pagination span:not(.sel) {
    border-color: transparent;
    background: transparent;
    cursor: default;
}

/* ── Note about striked revisions ── */
.strike-note {
    font-size: 12.5px;
    color: var(--muted);
    margin: 16px 0 0;
}
.strike-note del { color: var(--muted); }

/* ── RSS badge ── */
.rssbadge {
    margin: 16px 0 0;
    font-size: 12.5px;
}
.rssbadge a {
    color: var(--muted);
    text-decoration: none;
    display: inline-flex;
    align-items: center;
    gap: 6px;
}
.rssbadge a:hover { color: var(--accent); }
.rssbadge #rssi {
    display: inline-block;
    width: 14px; height: 14px;
    background: #f26522;
    border-radius: 3px;
    position: relative;
}
.rssbadge #rssi::before {
    content: 'R';
    color: #fff;
    font-size: 9px;
    font-weight: 700;
    position: absolute;
    left: 50%; top: 50%;
    transform: translate(-50%, -50%);
    font-family: var(--font-sans);
}

/* ── Responsive ── */
@media (max-width: 768px) {
    .compact-nav { padding: 8px 16px; }
    .container { padding: 16px; }
    .history-table th, .history-table td { padding: 8px 10px; font-size: 12.5px; }
}
@media (max-width: 600px) {
    .nav-label, .dir-label, .search-label { display: none; }
    .header { padding: 8px 12px; }
    .header-title { font-size: 14px; }
    .header-link { display: none; }
    .compact-nav { padding: 6px 12px; gap: 6px; flex-wrap: nowrap; }
    .compact-nav-left { gap: 2px; flex-shrink: 0; flex-wrap: nowrap; }
    .nav-pill { padding: 6px; border-radius: 6px; gap: 0; }
    .nav-pill svg { width: 16px; height: 16px; }
    .compact-nav-right { gap: 6px; flex-shrink: 0; min-width: 0; }
    .search-form { gap: 6px; min-width: 0; }
    .search-group { flex: 1; min-width: 0; }
    .search-group .search-input { width: 70px; min-width: 0; font-size: 12px; }
    .search-group .search-btn { padding: 0 8px; gap: 0; }
    .search-btn-icon { display: block; width: 14px; height: 14px; stroke: currentColor; fill: none; stroke-width: 2; }
    .current-dir-label { font-size: 0; padding: 5px; gap: 0; height: auto; }
    .current-dir-label input[type="checkbox"] { width: 16px; height: 16px; margin: 0; }
    .dir-path { padding: 5px 12px; font-size: 11.5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; flex-wrap: nowrap; }
    .container { padding: 12px; }
    .history-table-wrapper { border-radius: 8px; overflow-x: auto; -webkit-overflow-scrolling: touch; }
    .history-table { min-width: 600px; font-size: 13px; }
    .col-author { width: 200px; }
    .col-date { width: 70px; }
    .col-revision { width: 110px; }
}
@media (max-width: 380px) {
    .search-group .search-input-wrap { display: none; }
    .search-group .search-btn {
        border-radius: 6px;
        border: 1px solid var(--border);
        padding: 6px;
    }
    .search-btn-icon { width: 16px; height: 16px; stroke: var(--fg); }
    .current-dir-label { padding: 4px; }
    .current-dir-label input[type="checkbox"] { width: 18px; height: 18px; }
}
</style>
<div id="history-page">
    <header class="header">
        <div class="header-logo">
            <svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><line x1="16.5" y1="16.5" x2="21" y2="21"/></svg>
        </div>
        <div class="header-title">OpenGrok <span>Code Search</span></div>
        <a href="<%= context %><%= Prefix.XREF_P %>" class="header-link">
            <svg viewBox="0 0 24 24"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>
            代码浏览
        </a>
    </header>
    <div class="compact-nav">
        <div class="compact-nav-left">
            <a href="<%= context %>/" class="nav-pill">
                <svg viewBox="0 0 24 24"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>
                <span class="nav-label">Home</span>
            </a>
            <span class="nav-pill active">
                <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                <span class="nav-label">History</span>
            </span>
        </div>
        <div class="compact-nav-right">
            <form action="<%= context %><%= Prefix.SEARCH_P %>" class="search-form">
                <div class="search-group">
                    <div class="search-input-wrap">
                        <svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><line x1="16.5" y1="16.5" x2="21" y2="21"/></svg>
                        <input type="text" id="search" name="<%= QueryParameters.FULL_SEARCH_PARAM %>" class="search-input" placeholder="Search..." aria-label="Search"/>
                    </div>
                    <button type="submit" class="search-btn"><svg class="search-btn-icon" viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><line x1="16.5" y1="16.5" x2="21" y2="21"/></svg><span class="search-label">Search</span></button>
                </div>
                <% if (project != null) { %>
                <input id="minisearch-project" type="hidden" name="<%= QueryParameters.PROJECT_SEARCH_PARAM %>" value="<%= project.getName() %>" />
                <% } %>
                <label class="current-dir-label" for="minisearch-path">
                    <input id="minisearch-path" type="checkbox" name="<%= QueryParameters.PATH_SEARCH_PARAM %>" value='"<%= path %>"' checked /> <span class="dir-label">current directory</span>
                </label>
            </form>
        </div>
    </div>
    <nav class="dir-path">
        <a href="<%= context %>/">Home</a>
        <span class="path-sep">/</span><%
            if (project != null) { %>
        <a href="<%= context %><%= Prefix.XREF_P %>/<%= Util.uriEncodePath(project.getName()) %>"><%= Util.htmlize(project.getName()) %></a><%
            }
            // Render only the project-relative portion of the path (subPath).
            // The project link above already covers the project segment; the
            // segments below would otherwise duplicate it.
            if (!subPath.isEmpty()) { %><span class="path-sep">/</span><%
                String[] subSegs = subPath.split("/");
                String prefixRoot = "/" + (project != null ? Util.uriEncodePath(project.getName()) : "");
                StringBuilder subBuilder = new StringBuilder(prefixRoot);
                for (int si = 0; si < subSegs.length; si++) {
                    if (subSegs[si].isEmpty()) continue;
                    subBuilder.append("/").append(subSegs[si]);
                    if (si == subSegs.length - 1) { %>
        <span class="path-current"><%= Util.htmlize(subSegs[si]) %></span><%
                    } else { %>
        <a href="<%= context %><%= Prefix.XREF_P %><%= Util.uriEncodePath(subBuilder.toString()) %>/"><%= Util.htmlize(subSegs[si]) %></a>
        <span class="path-sep">/</span><%
                    }
                }
            } %>
    </nav>
    <div class="container">
        <div class="history-title">
            History log of <span class="path"><%= Util.htmlize(titlePathStr) %></span>
            (Results <strong> <%= totalHits != 0 ? startIndex + 1 : 0 %> – <%= startIndex + thisPageIndex %></strong> of <strong><%= totalHits %></strong>)
            <% if (hist.hasTags()) { %>
            <a href="#" class="revtags-toggle-anchor" onclick="toggle_revtags(); return false;">&lt;&lt;&lt; Hide revision tags</a>
            <% } %>
        </div>
        <div class="history-table-wrapper">
            <form action="<%= context + Prefix.DIFF_P + uriEncodedName %>">
            <table class="history-table" aria-label="table of revisions">
                <thead>
                    <tr>
                        <th class="col-revision">Revision</th>
                        <th class="col-date">Date</th>
                        <th class="col-author">Author</th>
                        <th class="col-comments">Comments
                            <% if (hist.hasFileList()) { %>
                            <a href="#" class="filelist-toggle-anchor" onclick="toggle_filelist(); return false;">&lt;&lt;&lt; Hide modified files</a>
                            <% } %>
                        </th>
                    </tr>
                </thead>
                <tbody>
                    <%
                    // Render revision tags rows (collapsed by default)
                    java.util.Map<String, String> tagsMap = hist.getTags();
                    for (java.util.Map.Entry<String, String> tagEntry : tagsMap.entrySet()) {
                        String tags = tagEntry.getValue();
                        if (tags != null && !tags.isEmpty()) {
                    %>
                    <tr class="revtags-hidden">
                        <td colspan="4">
                            <span class="bold">Revision tags:</span> <%= Util.htmlize(tags) %>
                        </td>
                    </tr>
                    <%      }
                    }
                    int count=0;
                    for (HistoryEntry entry : hist.getHistoryEntries(max, startIndex)) {
                        if (Objects.isNull(entry)) {
                            continue;
                        }

                        final String htmlEncodedDisplayRevision = Optional.ofNullable(entry.getDisplayRevision()).
                                map(Util::htmlize).
                                orElse("");
                        final String rev = Optional.ofNullable(entry.getRevision()).
                                orElse("");
                    %>
                    <tr>
                        <td class="col-revision"><%
                            if (cfg.isDir()) { %>
                            <a href="<%= context + Prefix.XREF_P + uriEncodedName + "?" +
                                    QueryParameters.REVISION_PARAM_EQ + Util.uriEncode(rev) %>" class="revision-hash"><%= htmlEncodedDisplayRevision %></a>
                            <% } else {
                                if (entry.isActive()) {
                                    StringBuffer urlBuffer = new StringBuffer(context + Prefix.HIST_L + uriEncodedName);
                                    if (request.getQueryString() != null) {
                                        urlBuffer.append('?').append(Laundromat.launderPaginationQuery(request.getQueryString()));
                                    }
                                    urlBuffer.append('#').append(Util.uriEncode(rev));
                            %>
                            <a href="<%= urlBuffer %>" class="revision-anchor" title="link to revision line">#</a>
                            <a href="<%= context + Prefix.XREF_P + uriEncodedName + "?" +
                                    QueryParameters.REVISION_PARAM_EQ + Util.uriEncode(rev) %>" class="revision-hash"><%= htmlEncodedDisplayRevision %></a>
                            <div class="revision-radio">
                                <label title="From (older)">
                                    <input type="radio"
                                            aria-label="From"
                                            data-revision-1="<%= (startIndex + count) %>"
                                            data-revision-2="<%= revision2Index %>"
                                            data-diff-revision="<%= QueryParameters.REVISION_1_PARAM %>"
                                            data-revision-path="<%= path + '@' + hist.getHistoryEntries().get(startIndex + count).getRevision()%>"
                                    <%
                                    if (count + startIndex > revision1Index || (count + startIndex > revision2Index && count + startIndex <= revision1Index - 1)) {
                                        // revision1 enabled
                                    } else if (count + startIndex == revision1Index) {
                                        // revision1 selected
                                        %> checked="checked"<%
                                    } else if (count + startIndex <= revision2Index) {
                                        // revision1 disabled
                                        %> disabled="disabled" <%
                                    }
                                    %>/>
                                    <span>From</span>
                                </label>
                                <label title="To (newer)">
                                    <input type="radio"
                                            aria-label="To"
                                            data-revision-1="<%= revision1Index %>"
                                            data-revision-2="<%= (startIndex + count) %>"
                                            data-diff-revision="<%= QueryParameters.REVISION_2_PARAM %>"
                                            data-revision-path="<%= path + '@' + hist.getHistoryEntries().get(startIndex + count).getRevision() %>"
                                    <%
                                    if (count + startIndex < revision2Index || (count + startIndex > revision2Index && count + startIndex <= revision1Index - 1)) {
                                        // revision2 enabled
                                    } else if (count + startIndex == revision2Index) {
                                        // revision2 selected
                                        %> checked="checked" <%
                                    } else if (count + startIndex >= revision1Index) {
                                        // revision2 disabled
                                        %> disabled="disabled" <%
                                    }
                                    %>/>
                                    <span>To</span>
                                </label>
                            </div>
                            <%      } else {
                                    striked = true;
                            %>
                            <del><%= htmlEncodedDisplayRevision %></del>
                            <%      }
                            } %>
                        </td>
                        <td class="col-date"><%
                            Date date = entry.getDate();
                            if (date != null) {
                        %><div class="date-day"><%= dayFmt.format(date) %></div>
                        <div class="date-year"><%= yearFmt.format(date) %></div><%
                            } %>
                        </td>
                        <td class="col-author"><%
                            String author = entry.getAuthor();
                            if (author == null) {
                            %><div class="author-name">(no author)</div><%
                            } else if (userPage != null && !userPage.isEmpty()) {
                                String alink = Util.getEmail(author);
                            %><div class="author-name"><a href="<%= userPage + Util.htmlize(alink) + userPageSuffix %>"><%= Util.htmlize(author)%></a></div>
                            <div class="author-email">&lt;<%= Util.htmlize(alink) %>&gt;</div><%
                            } else {
                            %><div class="author-name"><%= Util.htmlize(author) %></div><%
                            } %>
                        </td>
                        <td class="col-comments"><a id="<%= htmlEncodedDisplayRevision %>"></a><%
                            // revision message collapse threshold minimum of 10
                            int summaryLength = Math.max(10, cfg.getRevisionMessageCollapseThreshold());
                            String cout = Util.htmlize(entry.getMessage());

                            if (bugPage != null && !bugPage.isEmpty() && bugPattern != null) {
                                cout = Util.linkifyPattern(cout, bugPattern, Util.completeUrl(bugPage, request));
                            }
                            if (reviewPage != null && !reviewPage.isEmpty() && reviewPattern != null) {
                                cout = Util.linkifyPattern(cout, reviewPattern, Util.completeUrl(reviewPage, request));
                            }

                            boolean showSummary = false;
                            String coutSummary = entry.getMessage();
                            if (coutSummary.length() > summaryLength) {
                                showSummary = true;
                                coutSummary = coutSummary.substring(0, summaryLength - 1);
                                coutSummary = Util.htmlize(coutSummary);
                                if (bugPage != null && !bugPage.isEmpty() && bugPattern != null) {
                                    coutSummary = Util.linkifyPattern(coutSummary, bugPattern, Util.completeUrl(bugPage, request));
                                }
                                if (reviewPage != null && !reviewPage.isEmpty() && reviewPattern != null) {
                                    coutSummary = Util.linkifyPattern(coutSummary, reviewPattern, Util.completeUrl(reviewPage, request));
                                }
                            }

                            if (showSummary) {
                            %><p class="rev-message-summary"><%= coutSummary %></p>
                            <p class="rev-message-full rev-message-hidden"><%= cout %></p>
                            <p class="rev-message-toggle" data-toggle-state="less"><a class="rev-toggle-a" href="#">show more ... </a></p><%
                            } else {
                            %><p class="rev-message-full"><%= cout %></p><%
                            }

                            Set<String> files = entry.getFiles();
                            if (files != null) {
                            %><div class="filelist-hidden"><%
                                for (String ifile : files) {
                                    ifile = Util.fixPathIfWindows(ifile);
                                    String jfile = Util.stripPathPrefix(path, ifile);
                                    if (Objects.equals(rev, "")) {
                            %><a href="<%= context + Prefix.XREF_P + Util.uriEncodePath(ifile) %>"><%= Util.htmlize(jfile) %></a><%
                                    } else {
                            %><a href="<%= context + Prefix.XREF_P + Util.uriEncodePath(ifile) + "?" + QueryParameters.REVISION_PARAM_EQ + Util.uriEncode(rev) %>"><%= Util.htmlize(jfile) %></a><%
                                    }
                                }
                            %></div><%
                            } %>
                        </td>
                    </tr>
                    <%
                            count++;
                        }
                    %>
                </tbody>
            </table>
            </form>
        </div>
        <div class="pagination">
            <%
            String slider;
            if ((slider = (String) request.getAttribute("history.jsp-slider")) != null) {
                %><%= slider %><%
            }
            %>
        </div>
        <% if (striked) { %>
        <p class="strike-note"><strong>Note:</strong> No associated file changes are available for revisions with strike-through numbers (eg. <del>1.45</del>)</p>
        <% } %>
        <p class="rssbadge"><a href="<%= context + Prefix.RSS_P + uriEncodedName %>" title="RSS XML Feed of latest changes"><span id="rssi"></span>RSS feed</a></p>
    </div>
</div>
<script type="text/javascript">
(function() {
    /*
     * Remove legacy mast.jsp chrome from the DOM AFTER our new chrome is in place.
     * This prevents utils.js's $("#search") selector from grabbing the legacy
     * #bar input (which appears earlier in the DOM) and leaving our new
     * visible #search unhandled by initMinisearchAutocomplete.
     */
    ['whole_header', 'Masthead', 'bar', 'footer'].forEach(function(id) {
        var el = document.getElementById(id);
        if (el && el.parentNode) el.parentNode.removeChild(el);
    });

    /* Wire the minisearch autocomplete to our visible <input id="search">.
     * utils.js:1751 initMinisearchAutocomplete() reads #minisearch-project for
     * the project context and #minisearch-path for the directory constraint. */
    document.domReady.push(function() {
        if (typeof domReadyMenu === 'function') {
            domReadyMenu(true);
        }
    });

    /* Hook the "Hide / Show modified files" anchor label flipping. utils.js
     * toggle_filelist() toggles display of the .filelist/.filelist-hidden
     * pairs but does NOT flip the anchor's own text — handle that here. */
    var filelistToggle = document.querySelector('.history-table thead .filelist-toggle-anchor');
    if (filelistToggle) {
        filelistToggle.addEventListener('click', function(ev) {
            setTimeout(function() {
                var visible = document.querySelector('.filelist:not(.filelist-hidden)');
                filelistToggle.textContent = visible ? '>>> Show modified files' : '<<< Hide modified files';
            }, 0);
        }, true);
    }

    /* Same for revision tags. utils.js toggle_revtags() flips .revtags /
     * .revtags-hidden class on rows but does not flip the anchor text. */
    var revtagsToggle = document.querySelector('.history-title .revtags-toggle-anchor');
    if (revtagsToggle) {
        revtagsToggle.addEventListener('click', function(ev) {
            setTimeout(function() {
                var visibleRow = document.querySelector('tr.revtags:not(.revtags-hidden)');
                revtagsToggle.textContent = visibleRow ? '(Show revision tags >>>)' : '(<<< Hide revision tags)';
            }, 0);
        }, true);
    }
})();
</script>
<%
    }
}
/* ---------------------- history-page render end --------------------- */
%><%@ include file="/foot.jspf" %>
