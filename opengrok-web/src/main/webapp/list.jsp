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
Portions Copyright (c) 2017-2020, Chris Fraire <cfraire@me.com>.
Portions Copyright (c) 2026, UI Refactor.
--%>

<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page session="false" errorPage="error.jsp" buffer="8192kb" autoFlush="false" %>
<%@ page import="
java.text.SimpleDateFormat,
java.util.Date,
java.util.Locale,
java.util.Set,
java.util.List,
java.util.stream.Collectors,
java.util.logging.Level,
java.util.logging.Logger,

org.opengrok.indexer.Info,
org.opengrok.indexer.configuration.Project,
org.opengrok.indexer.web.Prefix,
org.opengrok.indexer.web.QueryParameters,
org.opengrok.indexer.web.Util,

java.io.BufferedInputStream,
java.io.File,
java.io.FileInputStream,
java.io.InputStreamReader,
java.io.Reader,
java.net.URLEncoder,
java.nio.charset.StandardCharsets,

org.opengrok.indexer.analysis.AnalyzerGuru,
org.opengrok.indexer.analysis.AbstractAnalyzer,
org.opengrok.indexer.analysis.AnalyzerFactory,
org.opengrok.indexer.analysis.NullableNumLinesLOC,
org.opengrok.indexer.analysis.Definitions,
org.opengrok.indexer.history.Annotation,
org.opengrok.indexer.history.HistoryGuru,
org.opengrok.indexer.index.IndexDatabase,
org.opengrok.indexer.search.DirectoryEntry,
org.opengrok.indexer.util.FileExtraZipper,
org.opengrok.indexer.util.IOUtils,
org.opengrok.indexer.util.Statistics,
org.opengrok.indexer.logger.LoggerFactory,

org.opengrok.web.DirectoryListing,
org.opengrok.web.PageConfig"%>
<%@ page import="jakarta.servlet.http.Cookie" %>
<%@ page import="static org.opengrok.web.PageConfig.DUMMY_REVISION" %>
<%@ page import="static org.opengrok.indexer.history.LatestRevisionUtil.getLatestRevision" %>

<%-- list.jspf start

    Both share the same chrome (header / compact-nav / breadcrumb / footer)
    provided by mast.jsp + foot.jspf. The page-specific CSS lives in the
    <style> block below the chrome include (same pattern as index.jsp).
--%>

<%
{
    /* ---------------------- list.jsp setup (before chrome) ---------------------
     * Stay inside this block so the variables we declare here do NOT collide
     * with the chrome variables (ctxPath, project, path, activeNav) that
     * mast.jsp declares in its own block. */

    /* need to set it here since requesting parameters */
    if (request.getCharacterEncoding() == null) {
        request.setCharacterEncoding("UTF-8");
    }

    PageConfig _chromeListCfg = PageConfig.get(request);
    _chromeListCfg.checkSourceRootExistence();

    /* Page title. httpheader.jspf renders it inside <title>.
     * Use the project name from the URL path when present, falling back
     * to the generic title otherwise. */
    Project _tP = _chromeListCfg.getProject();
    _chromeListCfg.setTitle(_tP != null ? _tP.getName() : "OpenGrok Code List");

    /* Latest-revision redirect / economy-mode handling (same as legacy). */
    String rev = _chromeListCfg.getRequestedRevision();
    if (!_chromeListCfg.isDir() && rev.isEmpty()) {
        /*
        * Get the latest revision and redirect so that the revision number
        * appears in the URL.
        */
        String latestRevision = getLatestRevision(_chromeListCfg.getResourceFile());
        if (latestRevision != null) {
            _chromeListCfg.evaluateMatchOffset();
            String location = _chromeListCfg.getRevisionLocation(latestRevision);
            response.sendRedirect(location);
            return;
        }
        if (!_chromeListCfg.getEnv().isGenerateHtml()) {
            _chromeListCfg.evaluateMatchOffset();
            /*
             * Economy mode is on and failed to get the last revision
             * (presumably running with history turned off).  Use dummy
             * revision string so that xref can be generated from the resource
             * file directly.
             */
            String location = _chromeListCfg.getRevisionLocation(DUMMY_REVISION);
            response.sendRedirect(location);
            return;
        }
        if (_chromeListCfg.evaluateMatchOffset()) {
            /*
             * If after calling, a match offset has been translated to a
             * fragment identifier (specifying a line#), then redirect to self.
             * This block will not be activated again the second time.
             */
            String location = _chromeListCfg.getRevisionLocation("");
            response.sendRedirect(location);
            return;
        }
    }

    /* Annotation CSS sizing. */
    Annotation annotation = _chromeListCfg.getAnnotation();
    if (annotation != null) {
        int r = annotation.getWidestRevision();
        int a = annotation.getWidestAuthor();
        _chromeListCfg.addHeaderData("<style type=\"text/css\">"
            + ".blame .r { width: " + (r == 0 ? 6 : Math.ceil(r * 0.7)) + "em; } "
            + ".blame .a { width: " + (a == 0 ? 6 : Math.ceil(a * 0.7)) + "em; } "
            + "</style>");
    }

    /* Scripts that httpheader.jspf used to register; mast.jsp re-includes
     * httpheader.jspf so we don't need to re-add them here. */
}
%>
<%-- Chrome: pageheader.jspf opens <head> + <body> + header; conditionally
     renders compact-nav (via mast.jsp) + breadcrumb (via breadcrumb.jspf).
     Each branch below opens and closes its own <main> element:
       • directory listing → <main class="container"> … </main>
       • code-view         → <main class="code-area" id="code-area"> … </main>
     The page-buffer is enlarged (buffer="8192kb" autoFlush="false") so a
     thrown exception in the body clears cleanly before error.jsp runs;
     without this, Tomcat cannot reset the partial chrome output when
     forwarding, and the chrome appears twice (once from this JSP and
     once from error.jsp). For very large directory listings (e.g. tens
     of thousands of files with long annotations) the 8mb buffer is
     enough to avoid the "JSP Buffer overflow" thrown by Jasper when
     the table body alone exceeds 1mb.
     The page-specific styles live in a <style> block right after the
     pageheader.jspf include below (mirrors index.jsp's pattern). This
     works in all modern browsers; <style> inside <body> is technically
     invalid HTML5 but the HTML parser hoists the rules into the
     document scope. The block also re-declares main.container so the
     1200px width constraint is applied even if the chrome stylesheet
     changes. --%>
<%@ include file="pageheader.jspf" %>
<style>
/* ── list.jsp page-specific styles ──
 *
 * Placed immediately after the chrome include (mirrors index.jsp's
 * pattern) so the rules apply before first paint and override any
 * chrome rules of the same specificity.
 *
 * Theme variables (--bg / --surface / --fg / --muted / --border /
 * --accent / --accent-dim / --font-sans / --font-mono) are inherited
 * from httpheader.jspf and are NOT redefined here. */

/* Page-level container width — explicit re-declaration so the file
 * table stays centered at max 1200px even if the chrome stylesheet
 * changes in the future. Mirrors main.container from httpheader.jspf. */
body { background: var(--bg); }
main.container { max-width: 1200px; margin: 0 auto; padding: 24px; box-sizing: border-box; }
@media (max-width: 768px) { main.container { padding: 16px; } }

/* Directory listing */
.file-table-wrapper {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
    max-width: 100%;
}
.file-table { width: 100%; border-collapse: collapse; font-size: 13.5px; }
.file-table thead { background: #fafbfc; }
.file-table th {
    text-align: left;
    padding: 10px 16px;
    font-weight: 600;
    color: var(--fg);
    border-bottom: 1px solid var(--border);
    font-size: 12.5px;
    white-space: nowrap;
    user-select: none;
}
.file-table th.sortable { cursor: pointer; }
.file-table th.sortable:hover { background: #f3f4f6; }
.file-table th .sort-icon {
    display: inline-block; margin-left: 4px; opacity: 0.4; font-size: 10px;
}
.file-table th.sorted .sort-icon { opacity: 1; color: var(--accent); }
.file-table td {
    padding: 10px 16px;
    border-bottom: 1px solid var(--border-light);
    vertical-align: middle;
}
.file-table tbody tr { transition: background 0.1s; }
.file-table tbody tr:hover { background: #f6f8fa; }
.file-table tbody tr:last-child td { border-bottom: none; }
.file-name { display: flex; align-items: center; gap: 10px; font-weight: 500; }
.file-name a { color: var(--fg); text-decoration: none; }
.file-name a:hover { color: var(--accent); text-decoration: underline; }
.file-name svg { width: 16px; height: 16px; stroke: var(--muted); fill: none; stroke-width: 1.8; flex-shrink: 0; }
.file-name .dir-icon { stroke: var(--accent); }
.file-date { color: var(--muted); font-size: 13px; white-space: nowrap; }
.file-size { color: var(--muted); font-size: 13px; font-family: var(--font-mono); font-variant-numeric: tabular-nums; }
.file-lines { color: var(--muted); font-size: 13px; font-family: var(--font-mono); font-variant-numeric: tabular-nums; }
.file-loc { color: var(--muted); font-size: 13px; font-family: var(--font-mono); font-variant-numeric: tabular-nums; }
.file-actions { display: flex; align-items: center; gap: 2px; white-space: nowrap; }
.action-btn {
    display: inline-flex; align-items: center; justify-content: center;
    width: 28px; height: 28px;
    border-radius: 5px;
    border: none;
    background: transparent;
    color: var(--muted);
    cursor: pointer;
    text-decoration: none;
    transition: background 0.12s, color 0.12s;
}
.action-btn:hover { background: var(--accent-dim); color: var(--accent); }
.action-btn svg { width: 15px; height: 15px; stroke: currentColor; fill: none; stroke-width: 2; }
@media (max-width: 600px) {
    .file-table-wrapper { border-radius: 8px; overflow-x: auto; -webkit-overflow-scrolling: touch; }
    .file-table { min-width: 520px; font-size: 13px; }
    .file-table th { padding: 8px 10px; font-size: 12px; }
    .file-table td { padding: 8px 10px; font-size: 12.5px; }
    .file-table th:nth-child(5), .file-table td[data-label="LOC"] { display: none; }
    .action-btn { width: 32px; height: 32px; }
}

/* code-view (per docs/ui/code-view.html) */

/* The file-path breadcrumb (with revision tag) is now provided by
 * pageheader.jspf — CSS lives in httpheader.jspf under .dir-path / .revision. */

.code-toolbar {
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    padding: 6px 24px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    flex-wrap: wrap;
}
.code-toolbar-left { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
.code-toolbar-right { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
.toolbar-btn {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 4px 12px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: var(--surface);
    color: var(--fg);
    font-size: 12.5px;
    font-weight: 500;
    font-family: var(--font-sans);
    cursor: pointer;
    text-decoration: none;
    transition: background 0.12s, border-color 0.12s, color 0.12s;
    white-space: nowrap;
    user-select: none;
}
.toolbar-btn:hover { background: #f3f4f6; border-color: #c6cdd4; }
.toolbar-btn.active { background: var(--accent-dim); border-color: var(--accent); color: var(--accent); }
.toolbar-btn[disabled] { opacity: 0.4; cursor: default; }
.toolbar-btn svg { width: 13px; height: 13px; stroke: currentColor; fill: none; stroke-width: 2; flex-shrink: 0; }
.goto-line-group {
    display: flex; align-items: center; gap: 4px;
    margin-left: 8px; padding-left: 12px;
    border-left: 1px solid var(--border);
}
.goto-line-group label { font-size: 12px; color: var(--muted); white-space: nowrap; }
.goto-line-input {
    width: 64px; height: 26px;
    border: 1px solid var(--border); border-radius: 5px;
    padding: 0 6px;
    font-size: 12px; font-family: var(--font-mono);
    outline: none; background: var(--surface);
    transition: border-color 0.15s, box-shadow 0.15s;
}
.goto-line-input:focus { border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-dim); }
.goto-line-btn {
    height: 26px; padding: 0 10px;
    border: 1px solid var(--border); border-radius: 5px;
    background: var(--bg); color: var(--fg);
    font-size: 12px; font-family: var(--font-sans);
    cursor: pointer;
    transition: background 0.12s;
}
.goto-line-btn:hover { background: #f3f4f6; }

.code-area {
    background: var(--surface);
    min-height: calc(100vh - 240px);
    overflow: auto;
}
.code-area .code-content {
    padding: 16px 0;
    overflow: auto;
}
.code-area pre {
    margin: 0;
    padding: 0 24px;
    font-family: var(--font-mono);
    font-size: 13px;
    line-height: 1.6;
    color: var(--fg);
    white-space: pre;
}
.code-area a.l {
    display: inline-block;
    width: 36px;
    min-width: 36px;
    text-align: right;
    padding: 0 8px 0 0;
    margin-right: 8px;
    color: var(--muted);
    user-select: none;
    text-decoration: none;
    font-size: 11px;
    border-right: 1px solid var(--border-light);
}
.code-area a.l:hover { color: var(--accent); }
.code-area pre a { color: var(--accent); text-decoration: none; }
.code-area pre a:hover { text-decoration: underline; }
.code-area.raw-mode pre { color: var(--fg) !important; }
.code-area.raw-mode pre * { color: inherit !important; font-weight: normal !important; font-style: normal !important; }
.code-area.raw-mode pre a { text-decoration: none; }

/* Popup windows (Scopes / Navigate) */
.popup-overlay { display: none; position: fixed; inset: 0; z-index: 100; }
.popup-overlay.open { display: block; }
.popup-window {
    position: absolute;
    top: 80px; right: 60px;
    width: 360px; max-height: 520px;
    background: #fffde7;
    border: 1.5px solid #e0dcc0;
    border-radius: 8px;
    box-shadow: 0 8px 32px rgba(0,0,0,0.18), 0 2px 8px rgba(0,0,0,0.10);
    overflow: hidden;
    display: none;
    z-index: 101;
}
.popup-overlay.open .popup-window { display: block; }
.popup-titlebar {
    display: flex; align-items: center; justify-content: space-between;
    padding: 10px 14px;
    border-bottom: 1px solid #ddd9b8;
    background: #fffde7;
}
.popup-titlebar h3 { font-family: var(--font-mono); font-size: 14px; font-weight: 600; color: #333; margin: 0; }
.popup-close {
    width: 26px; height: 26px;
    border: 1.5px solid #bbb; border-radius: 4px;
    background: #fff; color: #555;
    font-size: 14px; font-weight: 700;
    cursor: pointer;
    display: grid; place-items: center;
    transition: background 0.12s, border-color 0.12s;
    line-height: 1;
}
.popup-close:hover { background: #f5f0d0; border-color: #999; }
.popup-body { padding: 12px 16px 16px; overflow-y: auto; max-height: 460px; }
.popup-section { margin-bottom: 14px; }
.popup-section-title { font-family: var(--font-mono); font-size: 13px; font-weight: 700; color: #333; margin-bottom: 4px; }
.popup-section ul { margin: 0; padding-left: 20px; list-style: disc; }
.popup-section li { font-family: var(--font-mono); font-size: 12.5px; color: #c0392b; line-height: 1.7; }
.popup-section li.muted { color: #999; font-style: italic; }

@media (max-width: 900px) {
    .code-toolbar { padding: 6px 16px; }
    .code-toolbar-left .toolbar-btn span { display: none; }
    .code-toolbar-left .toolbar-btn { padding: 5px 8px; }
    .goto-line-group { margin-left: 4px; padding-left: 8px; }
    .goto-line-group label { display: none; }
}
@media (max-width: 600px) {
    .code-area pre { padding: 0 12px; font-size: 12px; }
    .code-area a.l { width: 40px; min-width: 40px; padding-right: 6px; margin-right: 4px; }
}

/* ── Directory listing readme preview (markdown) ──
 *
 * Markdown readme (e.g. README.md) → ".readme-paper" + ".markdown"
 * A "paper" card with a title strip (filename + download link) and a
 * soft shadow so it reads as a sheet on top of the page. The rendered
 * markdown sits inside the card body. Plain-text readme files are
 * intentionally not previewed here — only the markdown flavour is.
 *
 * The styles use only theme variables (defined in httpheader.jspf) so
 * they blend with the rest of the directory listing. */
.readme-paper {
    margin-top: 20px;
    background: #ffffff;
    border: 1px solid #e3e6eb;
    border-radius: 10px;
    box-shadow:
        0 1px 2px rgba(15, 23, 42, 0.04),
        0 6px 18px rgba(15, 23, 42, 0.06);
    overflow: hidden;
}
.readme-paper-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 12px 20px;
    border-bottom: 1px solid #e9ecef;
    background: #fafbfc;
}
.readme-paper-header .readme-name {
    font-weight: 600;
    color: var(--fg);
    font-family: var(--font-mono);
    font-size: 13px;
    letter-spacing: 0.01em;
}
.readme-paper-header .readme-name::before {
    content: "";
    display: inline-block;
    width: 6px; height: 6px;
    background: #4b8bf4;
    border-radius: 50%;
    margin-right: 8px;
    vertical-align: middle;
    transform: translateY(-1px);
}
.readme-paper-header .readme-actions {
    display: inline-flex;
    align-items: center;
    gap: 4px;
}
.readme-paper-header .readme-actions a {
    font-size: 12px;
    color: var(--accent);
    text-decoration: none;
    padding: 2px 8px;
    border-radius: 4px;
    border: 1px solid transparent;
    transition: background 0.12s, border-color 0.12s;
}
.readme-paper-header .readme-actions a:hover {
    background: var(--accent-dim);
    border-color: var(--accent);
}
.readme-paper-body {
    padding: 22px 28px 26px;
    color: #2f3640;
    font-size: 14px;
    line-height: 1.7;
    background: #ffffff;
}
/* Markdown content typography, scoped to .readme-paper-body so it
 * doesn't leak into other parts of the page. */
.readme-paper-body h1,
.readme-paper-body h2,
.readme-paper-body h3,
.readme-paper-body h4,
.readme-paper-body h5,
.readme-paper-body h6 {
    margin: 1.1em 0 0.5em;
    font-weight: 600;
    line-height: 1.3;
    color: var(--fg);
}
.readme-paper-body h1 { font-size: 1.6em; border-bottom: 1px solid #e6e8eb; padding-bottom: 0.3em; }
.readme-paper-body h2 { font-size: 1.35em; border-bottom: 1px solid #e6e8eb; padding-bottom: 0.25em; }
.readme-paper-body h3 { font-size: 1.15em; }
.readme-paper-body h4 { font-size: 1.05em; }
.readme-paper-body p { margin: 0.6em 0; }
.readme-paper-body a { color: var(--accent); text-decoration: none; }
.readme-paper-body a:hover { text-decoration: underline; }
.readme-paper-body ul,
.readme-paper-body ol { padding-left: 1.6em; margin: 0.5em 0; }
.readme-paper-body li { margin: 0.2em 0; }
.readme-paper-body code {
    font-family: var(--font-mono);
    font-size: 0.9em;
    background: #f3f5f8;
    border: 1px solid #e6e9ee;
    border-radius: 4px;
    padding: 1px 5px;
    color: #c0392b;
}
.readme-paper-body pre {
    background: #f7f8fa;
    border: 1px solid #e6e9ee;
    border-radius: 6px;
    padding: 12px 14px;
    overflow-x: auto;
    line-height: 1.55;
}
.readme-paper-body pre code {
    background: transparent;
    border: none;
    padding: 0;
    color: inherit;
}
.readme-paper-body blockquote {
    margin: 0.8em 0;
    padding: 6px 14px;
    border-left: 3px solid #c8d1da;
    color: #57606a;
    background: #fafbfc;
    border-radius: 0 4px 4px 0;
}
.readme-paper-body img { max-width: 100%; height: auto; }
.readme-paper-body table {
    border-collapse: collapse;
    margin: 0.6em 0;
    width: auto;
}
.readme-paper-body th,
.readme-paper-body td {
    border: 1px solid #e3e6eb;
    padding: 6px 10px;
    text-align: left;
}
.readme-paper-body th { background: #f6f8fa; font-weight: 600; }
.readme-paper-body hr { border: 0; border-top: 1px solid #e6e8eb; margin: 1.2em 0; }
</style>
<%
/* ---------------------- list.jsp body --------------------- */
{
    final Logger LOGGER = LoggerFactory.getLogger(getClass());
    String ctxPath = request.getContextPath();
    PageConfig _chromeListCfg = PageConfig.get(request);
    String rev = _chromeListCfg.getRequestedRevision();
    String path = _chromeListCfg.getPath();
    Project project = _chromeListCfg.getProject();
    File resourceFile = _chromeListCfg.getResourceFile();
    String basename = resourceFile.getName();
    String rawPath = ctxPath + Prefix.DOWNLOAD_P + path;
    String navigateWindowEnabled = project != null ? Boolean.toString(project.isNavigateWindowEnabled()) : "false";
    String uriEncodedPath = _chromeListCfg.getUriEncodedPath();
    Reader r = null;
    Statistics statistics = new Statistics();

    if (_chromeListCfg.isDir()) {
        String cookieValue = _chromeListCfg.getRequestedProjectsAsString();
        String projectName = null;
        if (project != null) {
            projectName = project.getName();
            Set<String> projects = _chromeListCfg.getRequestedProjects();
            if (!projects.contains(projectName)) {
                projects.add(projectName);
                cookieValue = cookieValue.isEmpty() ? projectName : projectName + ',' + cookieValue;
                Cookie cookie = new Cookie(PageConfig.OPEN_GROK_PROJECT, URLEncoder.encode(cookieValue, StandardCharsets.UTF_8));
                cookie.setPath(request.getContextPath() + '/');
                response.addCookie(cookie);
            }
        }
        DirectoryListing dl = new DirectoryListing(_chromeListCfg.getEftarReader());
        List<String> files = _chromeListCfg.getResourceFileList();
        if (!files.isEmpty()) {
            List<DirectoryEntry> entries = dl.createDirectoryEntries(resourceFile, path, files);
            List<NullableNumLinesLOC> extras = _chromeListCfg.getExtras(project, request);
            FileExtraZipper zipper = new FileExtraZipper();
            zipper.zip(entries, extras);

            SimpleDateFormat dateFmt = new SimpleDateFormat("yyyy-MM-dd", Locale.ROOT);
            HistoryGuru hg = HistoryGuru.getInstance();
            File srcRoot = _chromeListCfg.getEnv().getSourceRootFile();
%>
<main class="container">
<div id="list-dir-page">
    <div class="file-table-wrapper">
        <table class="file-table">
            <thead>
                <tr>
                    <th class="sortable sorted" data-sort-col="0">名称 <span class="sort-icon">&#9650;</span></th>
                    <th class="sortable" data-sort-col="1">日期 <span class="sort-icon">&#9660;</span></th>
                    <th class="sortable" data-sort-col="2">大小 <span class="sort-icon">&#9660;</span></th>
                    <th class="sortable" data-sort-col="3">行数 <span class="sort-icon">&#9660;</span></th>
                    <th class="sortable" data-sort-col="4">LOC <span class="sort-icon">&#9660;</span></th>
                    <th style="width:120px;">操作</th>
                </tr>
            </thead>
            <tbody id="file-tbody"><%
                if (!path.isEmpty()) { %>
                <tr data-is-dir="true">
                    <td data-label="名称"><div class="file-name">
                        <svg class="dir-icon" viewBox="0 0 24 24"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
                        <a href="..">..</a>
                    </div></td>
                    <td class="file-date" data-label="日期">—</td>
                    <td class="file-size" data-label="大小">—</td>
                    <td class="file-lines" data-label="行数">—</td>
                    <td class="file-loc" data-label="LOC">—</td>
                    <td class="file-actions" data-label="操作">—</td>
                </tr><%
                }
                for (DirectoryEntry entry : entries) {
                    File child = entry.getFile();
                    boolean isDir = child.isDirectory();
                    String filename = child.getName();
                    Date date = entry.getDate();
                    String dateStr = date != null ? dateFmt.format(date) : "—";
                    String sizeStr = isDir ? "—" : Util.readableSize(child.length());
                    long numlines = -1, loc = -1;
                    NullableNumLinesLOC extra = entry.getExtra();
                    if (extra != null) {
                        /*
                         * NullableNumLinesLOC.getNumLines()/getLOC() return
                         * boxed Long; the wrapper itself may carry nulls
                         * for entries whose analysis data is missing.
                         * Auto-unboxing a null Long to a primitive long
                         * throws NullPointerException, so read into a
                         * boxed Long first and only assign to the long
                         * when non-null — mirroring DirectoryListing's
                         * printNumlines/printLoc helpers.
                         */
                        Long numLinesBoxed = extra.getNumLines();
                        Long locBoxed = extra.getLOC();
                        if (numLinesBoxed != null) {
                            numlines = numLinesBoxed;
                        }
                        if (locBoxed != null) {
                            loc = locBoxed;
                        }
                    }
                    String linesStr = numlines >= 0 ? Util.readableCount(numlines, isDir) : "—";
                    String locStr = loc >= 0 ? Util.readableCount(loc, isDir) : "—";
                    String entryPath = path + filename;
                    File entrySrc = new File(srcRoot, entryPath);
                    boolean hasHist = hg.hasHistory(entrySrc);
                    boolean hasAnnot = hg.hasAnnotation(entrySrc);
                    String href = ctxPath + Prefix.XREF_P + Util.uriEncodePath(entryPath) + (isDir ? "/" : "");
                    String histHref = hasHist ? ctxPath + Prefix.HIST_L + Util.uriEncodePath(entryPath) : null;
                    String annotHref = hasAnnot ? ctxPath + Prefix.XREF_P + Util.uriEncodePath(entryPath) + "?" + QueryParameters.ANNOTATION_PARAM_EQ_TRUE : null;
                    String dlHref = !isDir ? ctxPath + Prefix.DOWNLOAD_P + Util.uriEncodePath(entryPath) : null;
                    String titleAttr = entry.getDescription() != null ? Util.htmlize(entry.getDescription()) : "";
                %>
                <tr data-is-dir="<%= isDir %>">
                    <td data-label="名称"><div class="file-name"><%
                        if (isDir) { %>
                        <svg class="dir-icon" viewBox="0 0 24 24"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg><%
                        } else { %>
                        <svg viewBox="0 0 24 24"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg><%
                        } %>
                        <a href="<%= href %>"<% if (!titleAttr.isEmpty()) { %> class="title-tooltip" title="<%= titleAttr %>"<% } %>><%= Util.htmlize(filename) %><% if (isDir) { %>/<% } %></a>
                    </div></td>
                    <td class="file-date" data-label="日期"><%= dateStr %></td>
                    <td class="file-size" data-label="大小"><%= sizeStr %></td>
                    <td class="file-lines" data-label="行数"><%= linesStr %></td>
                    <td class="file-loc" data-label="LOC"><%= locStr %></td>
                    <td class="file-actions" data-label="操作"><%
                        if (histHref != null) { %>
                        <a href="<%= histHref %>" class="action-btn" title="History">
                            <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                        </a><%
                        }
                        if (annotHref != null) { %>
                        <a href="<%= annotHref %>" class="action-btn" title="Annotate">
                            <svg viewBox="0 0 24 24"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>
                        </a><%
                        }
                        if (dlHref != null) { %>
                        <a href="<%= dlHref %>" class="action-btn" title="Download">
                            <svg viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                        </a><%
                        } %>
                    </td>
                </tr><%
                } %>
            </tbody>
        </table>
    </div>
<%
            List<String> readMes = entries.stream().
                    filter(e -> e.getFile().getName().toLowerCase(Locale.ROOT).startsWith("readme") ||
                            e.getFile().getName().toLowerCase(Locale.ROOT).endsWith("readme")).
                    map(e -> e.getFile().getName()).
                    collect(Collectors.toList());

            File[] catfiles = _chromeListCfg.findDataFiles(readMes);
            for (int i = 0; i < catfiles.length; i++) {
                if (catfiles[i] == null) continue;
                String lcName = readMes.get(i).toLowerCase(Locale.ROOT);
                String readmeName = readMes.get(i);
                String readmeDownloadHref = ctxPath + Prefix.DOWNLOAD_P + Util.uriEncodePath(path + readmeName);
                if (lcName.endsWith(".md") || lcName.endsWith(".markdown")) { %>
    <section id="src<%=i%>" class="readme-paper" data-markdown>
        <header class="readme-paper-header">
            <span class="readme-name"><%= readmeName %></span>
            <span class="readme-actions">
                <a href="<%= readmeDownloadHref %>" title="Download raw file">Download</a>
            </span>
        </header>
        <div class="readme-paper-body">
            <div class="markdown-content" data-markdown-download="<%= readmeDownloadHref %>"></div>
        </div>
    </section><%
                }
            }
        }
%>
</main>
<%
        statistics.report(LOGGER, Level.FINE, "directory listing done", "dir.list.latency");
    } else {
        /* ---------------------- list.jsp code-view (per docs/ui/code-view.html) --------------------- */
        String annotHref = _chromeListCfg.hasAnnotations() && !_chromeListCfg.annotate()
                ? ctxPath + Prefix.XREF_P + uriEncodedPath + (rev.isEmpty() ? "?" : "?" + QueryParameters.REVISION_PARAM_EQ + Util.uriEncode(rev) + "&") + QueryParameters.ANNOTATION_PARAM_EQ_TRUE
                : null;
        String rawHref = ctxPath + Prefix.RAW_P + uriEncodedPath + (rev.isEmpty() ? "" : "?" + QueryParameters.REVISION_PARAM_EQ + Util.uriEncode(rev));
        String dlHref  = ctxPath + Prefix.DOWNLOAD_P + uriEncodedPath + (rev.isEmpty() ? "" : "?" + QueryParameters.REVISION_PARAM_EQ + Util.uriEncode(rev));
        String histHref = _chromeListCfg.hasHistory() ? ctxPath + Prefix.HIST_L + uriEncodedPath : null;
        String xannotateHref = _chromeListCfg.annotate() && !rev.isEmpty()
                ? ctxPath + Prefix.XREF_P + uriEncodedPath + "?" + QueryParameters.REVISION_PARAM_EQ + Util.uriEncode(rev)
                : null;

        /* The file-path breadcrumb (with revision tag on the right) is now
         * provided by pageheader.jspf — no per-page rendering needed. */
%>
    <div class="code-toolbar">
        <div class="code-toolbar-left">
            <% if (annotHref != null) { %>
            <a href="<%= annotHref %>" class="toolbar-btn" id="btn-annotate"><svg viewBox="0 0 24 24"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 1 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg><span>Annotate</span></a>
            <% } else if (xannotateHref != null) { %>
            <a href="<%= xannotateHref %>" class="toolbar-btn active" id="btn-annotate"><svg viewBox="0 0 24 24"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 1 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg><span>Annotate</span></a>
            <% } else { %>
            <button class="toolbar-btn" id="btn-annotate" disabled><svg viewBox="0 0 24 24"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 1 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg><span>Annotate</span></button>
            <% } %>
            <button class="toolbar-btn" id="btn-line"><svg viewBox="0 0 24 24"><line x1="4" y1="6" x2="20" y2="6"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="18" x2="14" y2="18"/></svg><span>Line</span></button>
            <button class="toolbar-btn" id="btn-scopes"><svg viewBox="0 0 24 24"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></svg><span>Scopes</span></button>
            <button class="toolbar-btn" id="btn-navigate"><svg viewBox="0 0 24 24"><polygon points="3 11 22 2 13 21 11 13 3 11"/></svg><span>Navigate</span></button>
            <button class="toolbar-btn" id="btn-raw"><svg viewBox="0 0 24 24"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg><span>Raw</span></button>
            <a href="<%= dlHref %>" class="toolbar-btn" id="btn-download"><svg viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg><span>Download</span></a>
        </div>
        <div class="code-toolbar-right">
            <div class="goto-line-group">
                <label for="goto-line-input">Line:</label>
                <input type="text" class="goto-line-input" id="goto-line-input" placeholder="#" />
                <button class="goto-line-btn" id="goto-line-btn">Go</button>
            </div>
        </div>
    </div>

    <main class="code-area" id="code-area">
        <div class="code-content" id="code-content"><%
            if (!rev.isEmpty()) {
                File xrefFile;
                if (_chromeListCfg.isLatestRevision(rev) && (xrefFile = _chromeListCfg.findDataFile()) != null) {
                    if (_chromeListCfg.annotate()) {
                        BufferedInputStream bin = new BufferedInputStream(new FileInputStream(resourceFile));
                        try {
                            AnalyzerFactory a = AnalyzerGuru.find(basename);
                            AbstractAnalyzer.Genre g = AnalyzerGuru.getGenre(a);
                            if (g == null) { a = AnalyzerGuru.find(bin); g = AnalyzerGuru.getGenre(a); }
                            if (g == AbstractAnalyzer.Genre.IMAGE) { %>
            <img src="<%= rawPath %>" alt="from Source Repository"/><%
                            } else if (g == AbstractAnalyzer.Genre.HTML) {
                                r = new InputStreamReader(bin);
                                Util.dumpXref(out, r, ctxPath, resourceFile);
                            } else if (g == AbstractAnalyzer.Genre.PLAIN) {
                                Definitions defs = IndexDatabase.getDefinitions(resourceFile);
                                Annotation annotationX = _chromeListCfg.getAnnotation();
                                r = IOUtils.createBOMStrippedReader(bin, StandardCharsets.UTF_8.name());
                                AnalyzerGuru.writeDumpedXref(ctxPath, a, r, out, defs, annotationX, project, resourceFile);
                            } else { %>
            Click <a href="<%= rawPath %>">download <%= basename %></a><%
                            }
                        } finally {
                            if (r != null) { IOUtils.close(r); r = null; }
                            if (bin != null) { IOUtils.close(bin); bin = null; }
                        }
                    } else { %>
            <pre><% Util.dumpXref(out, xrefFile, xrefFile.getName().endsWith(".gz"), ctxPath); %></pre><% out.flush(); %><%
                    }
                } else { %>
            <%@ include file="/xref.jspf" %><% out.flush(); %><%
                }
            } else {
                File xrefFile = _chromeListCfg.findDataFile();
                if (xrefFile != null) { %>
            <pre><% Util.dumpXref(out, xrefFile, xrefFile.getName().endsWith(".gz"), ctxPath); %></pre><% out.flush(); %><%
                } else { %>
            <%@ include file="/xref.jspf" %><% out.flush(); %><%
                }
            }
        %>
        </div>
    </main>

    <div class="popup-overlay" id="popup-scopes-overlay">
        <div class="popup-window" id="popup-scopes">
            <div class="popup-titlebar">
                <h3>Scopes Window</h3>
                <button class="popup-close" data-close="scopes">&#x2715;</button>
            </div>
            <div class="popup-body" id="popup-scopes-body">
                <p style="font-size:12px;color:#999;margin:0;">&#x2014;</p>
            </div>
        </div>
    </div>
    <div class="popup-overlay" id="popup-navigate-overlay">
        <div class="popup-window" id="popup-navigate">
            <div class="popup-titlebar">
                <h3>Navigate Window</h3>
                <button class="popup-close" data-close="navigate">&#x2715;</button>
            </div>
            <div class="popup-body" id="popup-navigate-body">
                <p style="font-size:12px;color:#999;margin:0;">&#x2014;</p>
            </div>
        </div>
    </div>
<%
    }

    if (r != null) {
        IOUtils.close(r);
        r = null;
    }
}
%>
<%@ include file="foot.jspf" %>
<%= PageConfig.get(request).getScripts() %>
</body>
</html>
