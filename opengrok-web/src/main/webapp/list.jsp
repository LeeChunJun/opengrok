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

Copyright (c) 2005, 2025, Oracle and/or its affiliates. All rights reserved.
Portions Copyright 2011 Jens Elkner.
Portions Copyright (c) 2017-2020, Chris Fraire <cfraire@me.com>.

--%>
<%@page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@page session="false" errorPage="error.jsp" %>
<%@page import="
java.text.SimpleDateFormat,
java.util.Date,
org.opengrok.indexer.Info,
org.opengrok.indexer.web.QueryParameters,
java.io.BufferedInputStream,
java.io.File,
java.io.FileInputStream,
java.io.InputStreamReader,
java.io.Reader,
java.net.URLEncoder,
java.nio.charset.StandardCharsets,
java.util.List,
java.util.Locale,
java.util.Set,
org.opengrok.indexer.analysis.AnalyzerGuru,
org.opengrok.indexer.analysis.Definitions,
org.opengrok.indexer.analysis.AbstractAnalyzer,
org.opengrok.indexer.analysis.AnalyzerFactory,
org.opengrok.indexer.analysis.NullableNumLinesLOC,
org.opengrok.indexer.history.Annotation,
org.opengrok.indexer.history.HistoryGuru,
org.opengrok.indexer.index.IndexDatabase,
org.opengrok.indexer.search.DirectoryEntry,
org.opengrok.indexer.util.FileExtraZipper,
org.opengrok.indexer.util.IOUtils,
org.opengrok.web.DirectoryListing"
%>
<%@ page import="static org.opengrok.web.PageConfig.DUMMY_REVISION" %>
<%@ page import="static org.opengrok.indexer.history.LatestRevisionUtil.getLatestRevision" %>
<%@ page import="jakarta.servlet.http.Cookie" %>
<%@ page import="java.util.stream.Collectors" %>
<%@ page import="org.opengrok.indexer.util.Statistics" %>
<%@ page import="org.opengrok.indexer.logger.LoggerFactory" %>
<%@ page import="java.util.logging.Logger" %>
<%
{
    // need to set it here since requesting parameters
    if (request.getCharacterEncoding() == null) {
        request.setCharacterEncoding("UTF-8");
    }

    PageConfig cfg = PageConfig.get(request);
    cfg.checkSourceRootExistence();

    String rev = cfg.getRequestedRevision();
    if (!cfg.isDir() && rev.isEmpty()) {
        /*
         * Get the latest revision and redirect so that the revision number
         * appears in the URL.
         */
        String latestRevision = getLatestRevision(cfg.getResourceFile());
        if (latestRevision != null) {
            cfg.evaluateMatchOffset();
            String location = cfg.getRevisionLocation(latestRevision);
            response.sendRedirect(location);
            return;
        }
        if (!cfg.getEnv().isGenerateHtml()) {
            cfg.evaluateMatchOffset();
            /*
             * Economy mode is on and failed to get the last revision
             * (presumably running with history turned off).  Use dummy
             * revision string so that xref can be generated from the resource
             * file directly.
             */
            String location = cfg.getRevisionLocation(DUMMY_REVISION);
            response.sendRedirect(location);
            return;
        }

        if (cfg.evaluateMatchOffset()) {
            /*
             * If after calling, a match offset has been translated to a
             * fragment identifier (specifying a line#), then redirect to self.
             * This block will not be activated again the second time.
             */
            String location = cfg.getRevisionLocation(""); // empty
            response.sendRedirect(location);
            return;
        }
    }

    Annotation annotation = cfg.getAnnotation();
    if (annotation != null) {
        int r = annotation.getWidestRevision();
        int a = annotation.getWidestAuthor();
        cfg.addHeaderData("<style type=\"text/css\">"
            + ".blame .r { width: " + (r == 0 ? 6 : Math.ceil(r * 0.7)) + "em; } "
            + ".blame .a { width: " + (a == 0 ? 6 : Math.ceil(a * 0.7)) + "em; } "
            + "</style>");
    }
}
%><%@include

file="mast.jsp"

%><script type="text/javascript">/* <![CDATA[ */
document.pageReady.push(function() { pageReadyList();});
/* ]]> */</script>
<%
/* ---------------------- list.jsp start --------------------- */
{
    final Logger LOGGER = LoggerFactory.getLogger(getClass());

    PageConfig cfg = PageConfig.get(request);
    String rev = cfg.getRequestedRevision();
    Project project = cfg.getProject();

    String navigateWindowEnabled = project != null ? Boolean.toString(
            project.isNavigateWindowEnabled()) : "false";
    File resourceFile = cfg.getResourceFile();
    String path = cfg.getPath();
    String basename = resourceFile.getName();
    String rawPath = request.getContextPath() + Prefix.DOWNLOAD_P + path;
    Reader r = null;
    if (cfg.isDir()) {
        Statistics statistics = new Statistics();

        // valid resource is requested
        // mast.jsp assures, that resourceFile is valid and not /
        // see cfg.resourceNotAvailable()
        String cookieValue = cfg.getRequestedProjectsAsString();
        String projectName = null;
        if (project != null) {
            projectName = project.getName();
            Set<String>  projects = cfg.getRequestedProjects();
            if (!projects.contains(projectName)) {
                projects.add(projectName);
                // update cookie
                cookieValue = cookieValue.isEmpty() ? projectName : projectName + ',' + cookieValue;
                Cookie cookie = new Cookie(PageConfig.OPEN_GROK_PROJECT, URLEncoder.encode(cookieValue, StandardCharsets.UTF_8));
                // TODO hmmm, projects.jspf doesn't set a path
                cookie.setPath(request.getContextPath() + '/');
                response.addCookie(cookie);
            }
        }
        // requesting a directory listing
        DirectoryListing dl = new DirectoryListing(cfg.getEftarReader());
        List<String> files = cfg.getResourceFileList();
        if (!files.isEmpty()) {
            List<DirectoryEntry> entries = dl.createDirectoryEntries(resourceFile, path, files);

            List<NullableNumLinesLOC> extras = cfg.getExtras(project, request);
            FileExtraZipper zipper = new FileExtraZipper();
            zipper.zip(entries, extras);

            // UI refactor 2a: bypass DirectoryListing.extraListTo() and render inline
            // using the already-computed `entries` list.
            String ctxPath = request.getContextPath();
            String uriEncodedPath = cfg.getUriEncodedPath();
            SimpleDateFormat dateFmt = new SimpleDateFormat("yyyy-MM-dd", Locale.ROOT);
            HistoryGuru hg = HistoryGuru.getInstance();
            File srcRoot = cfg.getEnv().getSourceRootFile();
            /* ---------------------- list-dir-page start --------------------- */
            Date dateForLastIndexRun = cfg.getEnv().getDateForLastIndexRun();
%>
<style>
/* ── UI refactor 2a — directory-view styles ── */
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

/* Hide mast.jsp legacy UI — list.jsp provides its own header/compact-nav/breadcrumb/footer.
 * Hide unconditionally: list-dir-page is the only intended consumer of mast.jsp's chrome,
 * and the legacy fixed-position 70px whole_header would otherwise leave a blank band. */
html.xref #whole_header,
html.xref #Masthead,
html.xref #bar { display: none !important; }
/* Cancel the 70px top margin that style-1.0.6.css reserves for the legacy fixed
 * whole_header. Our new chrome (header/compact-nav/breadcrumb) sits inside #content
 * starting at top:0 with no extra spacing needed. */
#content { margin-top: 0 !important; padding: 0 !important; }

/* ── Page Header (logo + title + code-browse link) ── */
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

/* ── Footer (matches index.jsp style) ── */
.dir-footer {
    text-align: center;
    font-size: 12px;
    color: var(--muted);
    padding: 16px 0 24px;
}
.dir-footer a { color: var(--accent); text-decoration: none; }
.dir-footer a:hover { text-decoration: underline; }

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
.nav-pill svg {
    width: 14px; height: 14px;
    stroke: currentColor; fill: none; stroke-width: 2;
}

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

.container { max-width: 1200px; margin: 0 auto; padding: 24px; }

.file-table-wrapper {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
}
.file-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13.5px;
}
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
    display: inline-block;
    margin-left: 4px;
    opacity: 0.4;
    font-size: 10px;
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
.file-name svg {
    width: 16px; height: 16px;
    stroke: var(--muted); fill: none; stroke-width: 1.8;
    flex-shrink: 0;
}
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
.action-btn svg {
    width: 15px; height: 15px;
    stroke: currentColor; fill: none; stroke-width: 2;
}

@media (max-width: 768px) {
    .compact-nav { padding: 8px 16px; }
    .container { padding: 16px; }
    .file-table th, .file-table td { padding: 8px 12px; font-size: 12.5px; }
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
    .file-table-wrapper { border-radius: 8px; overflow-x: auto; -webkit-overflow-scrolling: touch; }
    .file-table { min-width: 520px; font-size: 13px; }
    .file-table th { padding: 8px 10px; font-size: 12px; }
    .file-table td { padding: 8px 10px; font-size: 12.5px; }
    .file-table th:nth-child(5), .file-table td[data-label="LOC"] { display: none; }
    .action-btn { width: 32px; height: 32px; }
    .dir-footer { font-size: 11px; padding: 12px 0 20px; }
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
<div id="list-dir-page">
    <header class="header">
        <div class="header-logo">
            <svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><line x1="16.5" y1="16.5" x2="21" y2="21"/></svg>
        </div>
        <div class="header-title">OpenGrok <span>Code Search</span></div>
        <a href="<%= ctxPath %><%= Prefix.XREF_P %>" class="header-link">
            <svg viewBox="0 0 24 24"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>
            代码浏览
        </a>
    </header>
    <div class="compact-nav">
        <div class="compact-nav-left">
            <a href="<%= ctxPath %>/" class="nav-pill">
                <svg viewBox="0 0 24 24"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>
                <span class="nav-label">Home</span>
            </a>
            <a href="<%= ctxPath %><%= Prefix.HIST_L %><%= uriEncodedPath %>" class="nav-pill">
                <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                <span class="nav-label">History</span>
            </a>
        </div>
        <div class="compact-nav-right">
            <form action="<%= ctxPath %><%= Prefix.SEARCH_P %>" class="search-form">
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
        <a href="<%= ctxPath %>/">Home</a>
        <span class="path-sep">/</span><%
            if (project != null) { %>
        <a href="<%= ctxPath %><%= Prefix.XREF_P %>/<%= Util.uriEncodePath(project.getName()) %>"><%= Util.htmlize(project.getName()) %></a>
        <span class="path-sep">/</span><%
            }
            String[] pathSegs = path.split("/");
            StringBuilder cum = new StringBuilder();
            for (int si = 0; si < pathSegs.length; si++) {
                if (pathSegs[si].isEmpty()) continue;
                cum.append("/").append(pathSegs[si]);
                if (si == pathSegs.length - 1) { %>
        <span class="path-current"><%= Util.htmlize(pathSegs[si]) %></span><%
                } else { %>
        <a href="<%= ctxPath %><%= Prefix.XREF_P %><%= Util.uriEncodePath(cum.toString()) %>/"><%= Util.htmlize(pathSegs[si]) %></a>
        <span class="path-sep">/</span><%
                }
            } %>
    </nav>
    <div class="container">
        <div class="file-table-wrapper">
            <table class="file-table">
                <thead>
                    <tr>
                        <th class="sortable sorted" onclick="sortTable(this, 0)">名称 <span class="sort-icon">▲</span></th>
                        <th class="sortable" onclick="sortTable(this, 1)">日期 <span class="sort-icon">▼</span></th>
                        <th class="sortable" onclick="sortTable(this, 2)">大小 <span class="sort-icon">▼</span></th>
                        <th class="sortable" onclick="sortTable(this, 3)">行数 <span class="sort-icon">▼</span></th>
                        <th class="sortable" onclick="sortTable(this, 4)">LOC <span class="sort-icon">▼</span></th>
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
                        <td class="file-actions" data-label="操作"></td>
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
                            numlines = extra.getNumLines();
                            loc = extra.getLOC();
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
    </div>
    <script>
    (function() {
        function sortTable(th, colIndex) {
            var table = th.closest('table');
            var tbody = table.querySelector('tbody');
            if (!tbody) return;
            var rows = Array.prototype.slice.call(tbody.querySelectorAll('tr'));
            var asc = th.querySelector('.sort-icon').textContent === '▲';
            table.querySelectorAll('th .sort-icon').forEach(function(s) { s.textContent = '▼'; });
            table.querySelectorAll('th.sorted').forEach(function(h) { h.classList.remove('sorted'); });
            th.classList.add('sorted');
            th.querySelector('.sort-icon').textContent = asc ? '▼' : '▲';
            rows.sort(function(a, b) {
                var aIsDir = a.getAttribute('data-is-dir') === 'true';
                var bIsDir = b.getAttribute('data-is-dir') === 'true';
                if (aIsDir !== bIsDir) return aIsDir ? -1 : 1;
                var aCells = a.querySelectorAll('td');
                var bCells = b.querySelectorAll('td');
                var aVal = (aCells[colIndex] && aCells[colIndex].textContent) || '';
                var bVal = (bCells[colIndex] && bCells[colIndex].textContent) || '';
                var aNum = parseFloat(aVal.replace(/,/g, ''));
                var bNum = parseFloat(bVal.replace(/,/g, ''));
                if (!isNaN(aNum) && !isNaN(bNum)) {
                    return asc ? aNum - bNum : bNum - aNum;
                }
                return asc ? aVal.localeCompare(bVal) : bVal.localeCompare(aVal);
            });
            rows.forEach(function(r) { tbody.appendChild(r); });
        }
        window.sortTable = sortTable;
        /* Remove the legacy mast.jsp chrome from the DOM IMMEDIATELY (before utils.js's
         * $(document).ready fires). If the legacy #bar's <input id="search"> is still in DOM
         * when domReadyMenu(true) → initMinisearchAutocomplete runs, utils.js's $("search")
         * will grab the LEGACY hidden input (since #bar comes earlier in the DOM) and bind
         * autocomplete to it, leaving our visible input unhandled.
         */
        ['whole_header', 'Masthead', 'bar', 'footer'].forEach(function(id) {
            var el = document.getElementById(id);
            if (el && el.parentNode) el.parentNode.removeChild(el);
        });

        /* Replicate original minisearch pattern (see HEAD: .../minisearch.jspf + utils-0.0.48.js):
         *   1) hidden #minisearch-project input gives the project
         *   2) #minisearch-path checkbox toggles the path constraint
         *   3) domReadyMenu(true) wires utils.js's initMinisearchAutocomplete to <input id="search">
         * The project for `getSelectedProjectNames()` is read from #minisearch-project.val() inside utils.js.
         */
        document.domReady.push(function() {
            console.log('[list.jsp] domReady: calling domReadyMenu(true) for minisearch autocomplete');
            if (typeof domReadyMenu === 'function') {
                domReadyMenu(true);
            } else {
                console.error('[list.jsp] domReadyMenu not loaded — utils.js failed?');
            }
        });
    })();
    </script>
    <div class="dir-footer">
        由 <a href="https://oracle.github.io/opengrok/">OpenGrok</a> 托管<%
            if (dateForLastIndexRun != null) {
                SimpleDateFormat lastIdxFmt = new SimpleDateFormat("yyyy 年 M 月 d 日 HH:mm zzz", Locale.US);
                String lastIdxText = lastIdxFmt.format(dateForLastIndexRun); %>
        &nbsp;·&nbsp; 最后索引更新：<%= lastIdxText %><%
            } %>
        &nbsp;·&nbsp; <%= Info.getVersion() %> (<%= Info.getShortRevision() %>)
    </div>
</div>
<%
            /* ---------------------- list-dir-page end --------------------- */

            List<String> readMes = null;
            if (entries != null) {
                readMes = entries.stream().
                        filter(e -> e.getFile().getName().toLowerCase(Locale.ROOT).startsWith("readme") ||
                                e.getFile().getName().toLowerCase(Locale.ROOT).endsWith("readme")).
                        map(e -> e.getFile().getName()).
                        collect(Collectors.toList());
            }

            File[] catfiles = cfg.findDataFiles(readMes);
            for (int i = 0; i < catfiles.length; i++) {
                if (catfiles[i] == null) {
                    continue;
                }
%>
<%
    String lcName = readMes.get(i).toLowerCase(Locale.ROOT);
    if (lcName.endsWith(".md") || lcName.endsWith(".markdown")) {
    %><div id="src<%=i%>" data-markdown>
        <div class="markdown-heading">
            <h3><%= readMes.get(i) %></h3>
        </div>
        <div class="markdown-content"
             data-markdown-download="<%= request.getContextPath() + Prefix.DOWNLOAD_P + Util.uriEncodePath(cfg.getPath() + readMes.get(i)) %>">
        </div>
        <pre data-markdown-original><%
            Util.dump(out, catfiles[i], catfiles[i].getName().endsWith(".gz"));
        %></pre>
    </div>
<% } else { %>
    <h3><%= readMes.get(i) %></h3>
    <div id="src<%=i%>">
        <pre><%
            Util.dump(out, catfiles[i], catfiles[i].getName().endsWith(".gz"));
        %></pre>
    </div>
<%
    }

            }
        }

        statistics.report(LOGGER, Level.FINE, "directory listing done", "dir.list.latency");
    } else if (!rev.isEmpty()) {
        // requesting a revision
        File xrefFile;
        if (cfg.isLatestRevision(rev) && (xrefFile = cfg.findDataFile()) != null) {
            if (cfg.annotate()) {
                // annotate
                BufferedInputStream bin = new BufferedInputStream(new FileInputStream(resourceFile));
                try {
                    AnalyzerFactory a = AnalyzerGuru.find(basename);
                    AbstractAnalyzer.Genre g = AnalyzerGuru.getGenre(a);
                    if (g == null) {
                        a = AnalyzerGuru.find(bin);
                        g = AnalyzerGuru.getGenre(a);
                    }
                    if (g == AbstractAnalyzer.Genre.IMAGE) {
%>
<div id="src">
    <img src="<%= rawPath %>" alt="from Source Repository"/>
</div><%
                    } else if ( g == AbstractAnalyzer.Genre.HTML) {
                        /*
                         * For backward compatibility, read the OpenGrok-produced
                         * document using the system default charset.
                         */
                        r = new InputStreamReader(bin);
                        // dumpXref() is also useful here for translating links.
                        Util.dumpXref(out, r, request.getContextPath(), resourceFile);
                    } else if (g == AbstractAnalyzer.Genre.PLAIN) {
%>
<div id="src" data-navigate-window-enabled="<%= navigateWindowEnabled %>">
    <pre><%
                        // We're generating xref for the latest revision, so we can
                        // find the definitions in the index.
                        Definitions defs = IndexDatabase.getDefinitions(resourceFile);
    Annotation annotation = cfg.getAnnotation();
                        // Data under source root is read with UTF-8 as a default.
                        r = IOUtils.createBOMStrippedReader(bin,
                            StandardCharsets.UTF_8.name());
                        AnalyzerGuru.writeDumpedXref(request.getContextPath(), a,
                                r, out, defs, annotation, project, resourceFile);
    %></pre>
</div><%
                    } else {
%>
Click <a href="<%= rawPath %>">download <%= basename %></a><%
                    }
                } finally {
                    if (r != null) {
                        IOUtils.close(r);
                        bin = null;
                    }
                    if (bin != null) {
                        IOUtils.close(bin);
                        bin = null;
                    }
                }

            } else {
%>
<div id="src" data-navigate-window-enabled="<%= navigateWindowEnabled %>">
    <pre><%
                    boolean compressed = xrefFile.getName().endsWith(".gz");
                    Util.dumpXref(out, xrefFile, compressed,
                            request.getContextPath());
    %></pre>
</div>
<%
            }
        } else {
%>
<%@

include file="/xref.jspf"

%>
<%
        }
    } else {
        // Requesting cross-referenced file with no known revision.
        File xrefFile = cfg.findDataFile();
        if (xrefFile != null) {
%>
<div id="src" data-navigate-window-enabled="<%= navigateWindowEnabled %>">
    <pre><%
            boolean compressed = xrefFile.getName().endsWith(".gz");
            Util.dumpXref(out, xrefFile, compressed, request.getContextPath());
    %></pre>
</div>
<%
        } else {
            // Failed to get xref, generate on the fly.
%>
<%@

include file="/xref.jspf"

%>
<%
        }
    }
}
/* ---------------------- list.jsp end --------------------- */
%><%@

include file="/foot.jspf"

%>
