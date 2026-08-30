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

Copyright (c) 2006, 2026, Oracle and/or its affiliates. All rights reserved.
Portions Copyright 2011 Jens Elkner.
Portions Copyright (c) 2020, Chris Fraire <cfraire@me.com>.
Portions Copyright (c) 2026, UI Refactor.
--%>

<%-- diff.jsp - file diff page (per docs/ui/file-diff-detail.html).

The chrome (header / compact-nav / breadcrumb / footer) is provided by
mast.jsp + foot.jspf; only the page-specific styles live here.
--%>

<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page errorPage="error.jsp" import="
java.io.ByteArrayInputStream,
java.io.OutputStream,
java.io.InputStream,
java.nio.charset.StandardCharsets,

org.suigeneris.jrcs.diff.delta.Chunk,
org.suigeneris.jrcs.diff.delta.Delta,
org.opengrok.indexer.configuration.Project,
org.opengrok.indexer.analysis.AbstractAnalyzer,
org.opengrok.indexer.web.Prefix,
org.opengrok.indexer.web.QueryParameters,
org.opengrok.indexer.web.Util,

org.opengrok.web.DiffData,
org.opengrok.web.DiffType,
org.opengrok.web.PageConfig"
%>

<%!
/* Render a small inline script that overrides document.rev() with the
 * single-revision value used by OLD / NEW diff mode. Declared as a
 * class-level method so it can be invoked from multiple branches of
 * the body block below. */
private String getAnnotateRevision(DiffData data) {
    if (data.getType() == DiffType.OLD || data.getType() == DiffType.NEW) {
        String rev = data.getRev(data.getType() == DiffType.NEW ? 1 : 0);
        return "<script type=\"text/javascript\">/* <![CDATA[ */ "
            + "document.rev = function() { return " + Util.htmlize(Util.jsStringLiteral(rev))
            + "; } /* ]]> */</script>";
    }
    return "";
}
%>
<%
{
    /* ---------------------- diff.jsp setup (before chrome) ---------------------
     * The download special case must happen before any output is written,
     * so we perform it inside the pre-mast.jsp setup block. */
    PageConfig _diffCfg = PageConfig.get(request);
    _diffCfg.addScript("diff");
    _diffCfg.checkSourceRootExistence();

    /* Title is set here (before mast.jsp includes httpheader.jspf). */
    _diffCfg.setTitle(_diffCfg.getHistoryTitle());

    DiffData data = _diffCfg.getDiffData();
    request.setAttribute("diff.jsp-data", data);

    if (data.getType() == DiffType.TEXT
            && request.getParameter("action") != null
            && request.getParameter("action").equals("download")) {
        try (OutputStream o = response.getOutputStream()) {
            for (int i = 0; i < data.getRevision().size(); i++) {
                Delta delta = data.getRevision().getDelta(i);
                try (InputStream in = new ByteArrayInputStream(delta.toString().getBytes(StandardCharsets.UTF_8))) {
                    response.setHeader("content-disposition", "attachment; filename="
                            + _diffCfg.getResourceFile().getName() + "@" + data.getRev(0)
                            + "-" + data.getRev(1) + ".diff");
                    byte[] buffer = new byte[8192];
                    int nr;
                    while ((nr = in.read(buffer)) > 0) {
                        o.write(buffer, 0, nr);
                    }
                }
            }
            o.flush();
            o.close();
            return;
        }
    }

    /* Hide the revision tag in breadcrumb (diff page shows its own toolbar). */
    pageContext.setAttribute("_chromeShowRevision", Boolean.FALSE);
}
%>
<%@ include file="pageheader.jspf" %>
<main class="container">
<style>
/* ── diff.jsp page-specific styles (per docs/ui/file-diff-detail.html
 *   and docs/ui/file-history-diff.html). */

/* file-path breadcrumb (with optional revision tag on the right) is now
 * provided by pageheader.jspf (unified chrome) — no per-page CSS needed. */

/* Toolbar (Annotate / Raw / Download) above the diff */
.diff-page .toolbar {
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    padding: 6px 24px;
    display: flex;
    align-items: center;
    gap: 6px;
    flex-wrap: wrap;
}
.diff-page .toolbar-btn {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 4px 12px;
    border-radius: 6px;
    border: 1px solid var(--border);
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
.diff-page .toolbar-btn:hover { background: #f3f4f6; border-color: #c6cdd4; }
.diff-page .toolbar-btn svg { width: 13px; height: 13px; stroke: currentColor; fill: none; stroke-width: 2; flex-shrink: 0; }

/* Diff section background */
.diff-page .diff-section {
    background: var(--surface);
    border-bottom: 1px solid var(--border);
}

/* Diff sub-toolbar (legend / format tabs / view mode / download) */
/* Mirror the original apache_tomcat #diffbar layout: a single bar with
 * three inline-block sections — .legend, .tabs, .ctype — each holding
 * short text labels and pills that look like a tab strip. */
.diff-page #diffbar {
    padding: 12px 24px;
    border-bottom: 1px solid var(--border);
    white-space: nowrap;
    display: flex;
    align-items: center;
    gap: 16px;
    flex-wrap: wrap;
}
.diff-page #diffbar .d, .diff-page #diffbar .a {
    /* Legend swatches — match the deleted/added line colors used below */
    padding: 2px 10px;
    border-radius: 3px;
    font-family: var(--font-sans);
    font-size: 12px;
    font-weight: 600;
    line-height: 1.4;
}
.diff-page #diffbar .d {
    background: #ffcc40;
    color: #5c3a00;
}
.diff-page #diffbar .a {
    background: #8bd98b;
    color: #1a5c2a;
}
/* Match the original apache_tomcat `.d` / `.a` line colors used in
 * #difftable — orange for deleted (with strikethrough) and green for
 * added. The util emits <span class="d">/<span class="a"> wrappers
 * around the lines themselves (see jrcs Util.diffline preprocessing);
 * the wrapper colors apply on top of the line-row background. */
.diff-page .diff-code .d {
    color: #5c3a00;
    background-color: #ffcc40;
    text-decoration: line-through;
}
.diff-page .diff-code .a {
    color: #0a3d1a;
    background-color: #8bd98b;
}
.diff-page #diffbar .legend { display: inline-flex; gap: 6px; }
.diff-page #diffbar .tabs { display: inline-flex; gap: 1ex; }
.diff-page #diffbar .tabs span {
    padding: 5px 12px;
    border: 1px solid #999;
    border-bottom-style: solid;
    border-radius: 4px 4px 0 0;
    background-color: #fafae0;
    font-family: var(--font-sans);
    font-size: 13px;
    line-height: 1.4;
}
.diff-page #diffbar .tabs span a {
    color: var(--fg);
    text-decoration: none;
    font-family: var(--font-mono);
    font-size: 12.5px;
}
.diff-page #diffbar .tabs span a:hover { color: var(--accent); }
.diff-page #diffbar .tabs span.active {
    background-color: #c5d5a9;
    border-bottom-style: dashed;
    font-weight: 600;
}
.diff-page #diffbar .tabs span.active a { color: var(--fg); }
.diff-page #diffbar .ctype { display: inline-flex; gap: 1ex; margin-left: auto; }
.diff-page #diffbar .ctype span {
    padding: 5px 12px;
    border: 1px solid #755;
    border-radius: 4px;
    background-color: #fafae0;
    font-family: var(--font-sans);
    font-size: 12.5px;
    line-height: 1.4;
}
.diff-page #diffbar .ctype span a {
    color: var(--fg);
    text-decoration: none;
}
.diff-page #diffbar .ctype span a:hover { color: var(--accent); }
.diff-page #diffbar .ctype span.active {
    background-color: #c5d5a9;
    font-weight: 600;
}

/* Two-panel side-by-side / unified diff layout */
.diff-page .diff-panels {
    display: grid;
    grid-template-columns: 1fr 1fr;
    min-height: 420px;
}
/* For UNIFIED / TEXT / OLD / NEW, render as single full-width column
 * (the original apache_tomcat/webapps/source/diff.jsp uses a single
 * <table class="plain"> for UNIFIED with one cell per chunk row, and
 * a single full-width panel for TEXT/OLD/NEW). SDIFF stays 2-column. */
.diff-page.udiff .diff-panels,
.diff-page.text .diff-panels,
.diff-page.old .diff-panels,
.diff-page.new .diff-panels {
    grid-template-columns: 1fr;
}
/* For non-SDIFF modes, hide the right border between panels and make
 * the single visible panel span the full width. */
.diff-page.udiff .diff-panel:first-child,
.diff-page.text .diff-panel:first-child,
.diff-page.old .diff-panel:first-child,
.diff-page.new .diff-panel:first-child {
    border-right: none;
}
.diff-page .diff-panel { display: flex; flex-direction: column; overflow: hidden; }
.diff-page.sdiff .diff-panel:first-child { border-right: 1px solid var(--border); }
.diff-page .diff-panel-header {
    padding: 7px 16px;
    font-size: 12px;
    font-weight: 600;
    font-family: var(--font-mono);
    color: var(--muted);
    background: var(--bg);
    border-bottom: 1px solid var(--border-light);
    letter-spacing: 0.01em;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
.diff-page .diff-panel-header .panel-tag {
    display: inline-block;
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    padding: 1px 6px;
    border-radius: 4px;
    margin-right: 8px;
    vertical-align: middle;
}
.diff-page .diff-panel-old .panel-tag { background: #ffcc40; color: #5c3a00; }
.diff-page .diff-panel-new .panel-tag { background: #8bd98b; color: #0a3d1a; }

.diff-page .diff-code {
    flex: 1;
    overflow: auto;
    font-family: var(--font-mono);
    font-size: 12.5px;
    line-height: 1.6;
    background: var(--surface);
    max-height: calc(100vh - 240px);
}
.diff-page .diff-line {
    display: grid;
    grid-template-columns: 44px minmax(0, 1fr);
    min-height: 20px;
}
.diff-page .diff-line-content {
    min-width: 0;
    padding: 0 16px;
    white-space: pre;
    overflow: visible;
}
.diff-page .diff-line-num {
    text-align: right;
    padding: 0 10px 0 8px;
    color: var(--border);
    user-select: none;
    font-size: 11.5px;
    line-height: 1.6;
    border-right: 1px solid var(--border-light);
    white-space: nowrap;
}
/* Whole-line backgrounds: orange for deleted (matches the legend swatch),
 * green for added. The line number gutter keeps the same hue at slightly
 * higher saturation for visual rhythm. */
.diff-page .diff-line-add { background: #d6f0d6; }
.diff-page .diff-line-add .diff-line-num { color: #1a5c2a; background: #b9e5b9; border-right-color: #9dd49d; }
.diff-page .diff-line-add .diff-line-content { color: #0a3d1a; }
.diff-page .diff-line-del { background: #fff0c2; }
.diff-page .diff-line-del .diff-line-num { color: #8a5a00; background: #ffe28f; border-right-color: #f4cf6a; }
.diff-page .diff-line-del .diff-line-content {
    color: #5c3a00;
    text-decoration: line-through;
}
.diff-page .diff-line-ctx .diff-line-content { color: var(--fg); }

/* Chunk grouping — each Delta (one hunk) is wrapped in a .chunk
 * element so the diff jumper plugin (diff-0.0.5.js) can navigate
 * between hunks. The 2-column "side-by-side" effect comes from the
 * outer .diff-panels grid (one panel = one column); inside each
 * panel the .chunk holds a single column of diff lines. */
.diff-page .diff-code .chunk {
    display: block;
    border-top: 1px dashed var(--border-light);
    margin-top: 4px;
    padding-top: 4px;
}
.diff-page .diff-code .chunk:first-child {
    border-top: none;
    margin-top: 0;
    padding-top: 0;
}

/* SDIFF (side-by-side) — two panels laid out by the outer
 * .diff-panels grid (already declared above). The right panel
 * shows context + added lines; the left panel shows context +
 * deleted lines. Each .chunk inside a panel is a single column
 * of diff-line rows. */
.diff-page.sdiff .diff-code {
    padding: 0;
}
.diff-page.sdiff .diff-panel-new .diff-line-add { background: #d6f0d6; }
.diff-page.sdiff .diff-panel-new .diff-line-add .diff-line-num { color: #1a5c2a; background: #b9e5b9; border-right-color: #9dd49d; }
.diff-page.sdiff .diff-panel-new .diff-line-add .diff-line-content { color: #0a3d1a; }

/* Map old Util-style classes (.k / .it) used by the original apache_tomcat
 * diff.jsp loop to the new layout tokens (line breaks, line numbers). */
.diff-page .diff-code .k { display: block; }
.diff-page .diff-code .k.chunk { background: var(--bg); border-top: 1px dashed var(--border); }
.diff-page .diff-code .it { display: inline-block; min-width: 2.5em; padding: 0 6px; color: var(--muted); font-family: var(--font-mono); font-size: 11.5px; user-select: none; }

/* Syntax highlight tokens used by AnalyzerGuru.writeDumpedXref */
.tok-kw { color: #cf222e; font-weight: 500; }
.tok-str { color: #0a3069; }
.tok-cmt { color: #6e7781; font-style: italic; }
.tok-type { color: #953800; }
.tok-fn { color: #8250df; }
.tok-num { color: #0550ae; }
.tok-ann { color: #116329; }

/* TEXT mode (single pre block) */
.diff-page pre.diff-text {
    margin: 0;
    padding: 16px 24px;
    font-family: var(--font-mono);
    font-size: 12.5px;
    line-height: 1.6;
    white-space: pre-wrap;
    word-break: break-word;
    color: var(--fg);
    background: var(--surface);
}

/* Image diff table (2 columns) */
.diff-page table.diff-image {
    width: 100%;
    border-collapse: collapse;
    margin: 16px 0;
}
.diff-page table.diff-image th { padding: 10px 16px; font-size: 13px; font-weight: 600; background: var(--bg); border-bottom: 1px solid var(--border); color: var(--fg); }
.diff-page table.diff-image td { padding: 16px; text-align: center; vertical-align: top; }
.diff-page table.diff-image img { max-width: 100%; height: auto; border: 1px solid var(--border); border-radius: 6px; }

/* Error / binary / no-diff banners */
.diff-page .diff-banner {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 16px 20px;
    margin: 16px 0;
    font-size: 13px;
}
.diff-page .diff-banner.error { border-color: #d73a49; background: #ffebe9; color: #630c14; }
.diff-page .diff-banner h3 { margin: 0 0 6px; font-size: 14px; font-weight: 600; }
.diff-page .diff-banner a { color: var(--accent); text-decoration: none; }
.diff-page .diff-banner a:hover { text-decoration: underline; }

/* diffbar wrapper — keeps legacy CSS class names from clashing with the
 * legacy stylesheet loaded by httpheader.jspf. */
html.diff_jsp #whole_header, #Masthead, #bar, #footer, #sbar { display: none !important; }
html.diff_jsp #content { margin-top: 0 !important; padding: 0 !important; }

/* ── Diff jumper floating popup ─────────────────────────────────────
 * Cream-yellow popup (matches apache_tomcat's .diff_navigation_style
 * in style-1.0.4.css). The popup is appended to <body> by the
 * page-specific script block at the bottom of this file; it carries
 * the .diff-window / .diff_navigation_style classes that the original
 * stock plugin would have assigned. */
#diff_win, .diff-window.diff_navigation_style {
    position: fixed;
    top: 100px;
    right: 20px;
    min-width: 280px;
    max-width: 360px;
    min-height: 80px;
    background-color: rgb(255,255,204);
    border: solid 1px #c0c0c0;
    border-radius: 5px;
    box-shadow: 6px 6px 12px rgba(0,0,0,0.18);
    font-family: var(--font-sans);
    font-size: 13px;
    color: #333;
    z-index: 15000;
    display: none;
}
#diff_win .window-header {
    background: #eeeebb;
    border-bottom: 1px solid #c0c0c0;
    padding: 5px 10px;
    border-top-left-radius: 4px;
    border-top-right-radius: 4px;
}
#diff_win .window-header b {
    color: #333;
    font-size: 13px;
    font-weight: 600;
}
#diff_win .window-header .minimize {
    color: #333;
    text-decoration: none;
    padding: 0 6px;
    border: 1px solid #999;
    border-radius: 3px;
    background: #fff;
    font-family: var(--font-sans);
    font-size: 12px;
    line-height: 1.4;
}
#diff_win .window-header .minimize:hover { background: #ffebe9; }
#diff_win .window-header .clearfix::after {
    content: "";
    display: table;
    clear: both;
}
#diff_win .window-header .pull-left { float: left; }
#diff_win .window-header .pull-right { float: right; }
#diff_win .window-body {
    padding: 8px 12px;
    font-size: 12.5px;
}
#diff_win .window-body .pull-right { float: right; }
#diff_win .window-body .pull-right a {
    color: #1a4d8f;
    text-decoration: none;
    padding: 2px 4px;
    font-family: var(--font-sans);
}
#diff_win .window-body .pull-right a:hover {
    background: #fff8b0;
    text-decoration: underline;
}
#diff_win .window-body .clearfix::after {
    content: "";
    display: table;
    clear: both;
}
#diff_win .window-body .summary {
    text-align: center;
    font-weight: 600;
    color: #555;
    margin-top: 6px;
}
#diff_win .window-body .progress {
    text-align: center;
    min-height: 18px;
    margin-top: 2px;
}
#diff_win .window-body .progress p {
    display: inline-block;
    margin: 0;
    padding: 0;
    font-size: 11.5px;
    color: #555;
}

/* Responsive */
@media (max-width: 900px) {
    .diff-page #diffbar { padding-left: 16px; padding-right: 16px; }
    .diff-page .toolbar { padding-left: 16px; padding-right: 16px; }
}
@media (max-width: 600px) {
    .diff-page .toolbar { padding: 8px 12px; gap: 6px; }
    .diff-page .toolbar-btn { padding: 6px 12px; font-size: 12px; }
    .diff-page .toolbar-btn svg { width: 14px; height: 14px; }
    .diff-page #diffbar { padding: 8px 12px; gap: 8px; }
    .diff-page #diffbar .tabs span, .diff-page #diffbar .ctype span { padding: 4px 8px; font-size: 11.5px; }
    .diff-page .diff-panels { grid-template-columns: 1fr; }
    .diff-page .diff-panel:first-child { border-right: none; border-bottom: 1px solid var(--border); }
    .diff-page .diff-code { max-height: 300px; }
}
</style>
<%
/* ---------------------- diff.jsp body --------------------- */
{
    PageConfig _diffCfg = PageConfig.get(request);
    DiffData data = (DiffData) request.getAttribute("diff.jsp-data");

    String ctxPath = request.getContextPath();
    String path = _diffCfg.getPath();
    String uriEncodedPath = _diffCfg.getUriEncodedPath();
    Project project = _diffCfg.getProject();
    String filename = data.getFilename();
    String rev0 = data.getRev(0);
    String rev1 = data.getRev(1);
    DiffType type = data.getType();

    // Toolbar URLs.
    String annotHref = (_diffCfg.hasAnnotations() && !_diffCfg.annotate())
            ? ctxPath + Prefix.XREF_P + uriEncodedPath + "?" + QueryParameters.ANNOTATION_PARAM_EQ_TRUE
            : null;
    String rawHref = ctxPath + Prefix.RAW_P + uriEncodedPath;
    String dlHref = ctxPath + Prefix.DOWNLOAD_P + uriEncodedPath;

    if (data.getErrorMsg() != null) {
%>
<div class="diff-page">
    <div class="diff-banner error">
        <h3>Error</h3>
        <p><%= Util.htmlize(data.getErrorMsg()) %></p>
    </div>
<%
    } else if (data.getGenre() == AbstractAnalyzer.Genre.IMAGE) {
        String link = ctxPath + Prefix.DOWNLOAD_P + Util.htmlize(path);
%>
<div class="diff-page">
    <table class="diff-image" aria-label="table with old and new image">
        <thead>
        <tr>
            <th><%= Util.htmlize(filename) %> (revision <%= Util.htmlize(rev0) %>)</th>
            <th><%= Util.htmlize(filename) %> (revision <%= Util.htmlize(rev1) %>)</th>
        </tr>
        </thead>
        <tbody>
        <tr>
            <td><img src="<%= link %>?<%= QueryParameters.REVISION_PARAM_EQ %><%= Util.uriEncode(rev0) %>" alt="previous"/>
            </td>
            <td><img src="<%= link %>?<%= QueryParameters.REVISION_PARAM_EQ %><%= Util.uriEncode(rev1) %>" alt="new"/>
            </td>
        </tr>
        </tbody>
    </table>
<%
    } else if (data.getGenre() != AbstractAnalyzer.Genre.PLAIN && data.getGenre() != AbstractAnalyzer.Genre.HTML) {
        String link = ctxPath + Prefix.DOWNLOAD_P + Util.uriEncodePath(path);
%>
<div class="diff-page">
    <div class="diff-banner">
        <p>Diffs for binary files cannot be displayed! Files are
        <a href="<%= link %>?<%= QueryParameters.REVISION_PARAM_EQ %><%= Util.uriEncode(rev0) %>">
            <%= Util.htmlize(filename) %> (revision <%= Util.htmlize(rev0) %>)</a> and
        <a href="<%= link %>?<%= QueryParameters.REVISION_PARAM_EQ %><%= Util.uriEncode(rev1) %>">
            <%= Util.htmlize(filename) %> (revision <%= Util.htmlize(rev1) %>)</a>.</p>
    </div>
<%
    } else if (data.getRevision().size() == 0) {
%>
<div class="diff-page">
    <%= getAnnotateRevision(data) %>
    <div class="diff-banner">
        <strong>No differences found!</strong>
    </div>
<%
    } else {
        //-------- Do THE DIFFS ------------
        int ln1 = 0;
        int ln2 = 0;
        String rp1 = data.getParam(0);
        String rp2 = data.getParam(1);
        String baseURL = ctxPath + Prefix.DIFF_P + _diffCfg.getUriEncodedPath();
        String[] file1 = data.getFile(0);
        String[] file2 = data.getFile(1);
        boolean full = data.isFull();

        // Pre-compute URLs for the diff toolbar.
        StringBuilder sdiffUrl = new StringBuilder(baseURL);
        sdiffUrl.append("?").append(QueryParameters.REVISION_1_PARAM_EQ).append(rp1).append("&");
        sdiffUrl.append(QueryParameters.REVISION_2_PARAM_EQ).append(rp2).append("&");
        sdiffUrl.append(QueryParameters.FORMAT_PARAM_EQ).append(DiffType.SIDEBYSIDE.getAbbrev()).append("&");
        sdiffUrl.append(QueryParameters.DIFF_LEVEL_PARAM_EQ).append(full ? '1' : '0');

        StringBuilder udiffUrl = new StringBuilder(baseURL);
        udiffUrl.append("?").append(QueryParameters.REVISION_1_PARAM_EQ).append(rp1).append("&");
        udiffUrl.append(QueryParameters.REVISION_2_PARAM_EQ).append(rp2).append("&");
        udiffUrl.append(QueryParameters.FORMAT_PARAM_EQ).append(DiffType.UNIFIED.getAbbrev()).append("&");
        udiffUrl.append(QueryParameters.DIFF_LEVEL_PARAM_EQ).append(full ? '1' : '0');

        StringBuilder textUrl = new StringBuilder(baseURL);
        textUrl.append("?").append(QueryParameters.REVISION_1_PARAM_EQ).append(rp1).append("&");
        textUrl.append(QueryParameters.REVISION_2_PARAM_EQ).append(rp2).append("&");
        textUrl.append(QueryParameters.FORMAT_PARAM_EQ).append(DiffType.TEXT.getAbbrev()).append("&");
        textUrl.append(QueryParameters.DIFF_LEVEL_PARAM_EQ).append(full ? '1' : '0');

        String fullUrl = baseURL + "?" + QueryParameters.REVISION_1_PARAM_EQ + Util.uriEncode(rp1)
                + "&" + QueryParameters.REVISION_2_PARAM_EQ + Util.uriEncode(rp2)
                + "&" + QueryParameters.FORMAT_PARAM_EQ + type.getAbbrev()
                + "&" + QueryParameters.DIFF_LEVEL_PARAM_EQ + "1";
        String compactUrl = baseURL + "?" + QueryParameters.REVISION_1_PARAM_EQ + Util.uriEncode(rp1)
                + "&" + QueryParameters.REVISION_2_PARAM_EQ + Util.uriEncode(rp2)
                + "&" + QueryParameters.FORMAT_PARAM_EQ + type.getAbbrev()
                + "&" + QueryParameters.DIFF_LEVEL_PARAM_EQ + "0";

        String dlDiffUrl = baseURL + "?" + QueryParameters.REVISION_1_PARAM_EQ + Util.uriEncode(rp1)
                + "&" + QueryParameters.REVISION_2_PARAM_EQ + Util.uriEncode(rp2)
                + "&" + QueryParameters.FORMAT_PARAM_EQ + DiffType.TEXT
                + "&action=download";
%>
<div class="diff-page<%= type == DiffType.SIDEBYSIDE ? " sdiff" : (type == DiffType.UNIFIED ? " udiff" : (type == DiffType.TEXT ? " text" : (type == DiffType.OLD ? " old" : " new"))) %>">
<%= getAnnotateRevision(data) %>
    <div class="toolbar">
        <% if (annotHref != null) { %>
        <a href="<%= annotHref %>" class="toolbar-btn" data-od-id="btn-annotate"><svg viewBox="0 0 24 24"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 1 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>Annotate</a>
        <% } %>
        <a href="<%= rawHref %>" class="toolbar-btn" data-od-id="btn-raw"><svg viewBox="0 0 24 24"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>Raw</a>
        <a href="<%= dlHref %>" class="toolbar-btn" data-od-id="btn-download"><svg viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>Download</a>
    </div>

    <section class="diff-section" data-od-id="diff-content">
        <div id="diffbar" data-od-id="diff-toolbar">
            <div class="legend" data-od-id="diff-legend">
                <span class="d" data-od-id="diff-legend-deleted">Deleted</span>
                <span class="a" data-od-id="diff-legend-added">Added</span>
            </div>
            <div class="tabs" data-od-id="diff-tabs"><%
                /* Single row of all 5 mode tabs (sdiff / udiff / text / old / new)
                 * — matches the original apache_tomcat diff.jsp exactly.
                 * The active mode is a non-link <span>; all others are <a> links
                 * to the same diff with a different format abbreviation. */
                for (DiffType t : DiffType.values()) {
                    StringBuilder tabUrl = new StringBuilder(baseURL);
                    tabUrl.append("?").append(QueryParameters.REVISION_1_PARAM_EQ).append(rp1).append("&");
                    tabUrl.append(QueryParameters.REVISION_2_PARAM_EQ).append(rp2).append("&");
                    tabUrl.append(QueryParameters.FORMAT_PARAM_EQ).append(t.getAbbrev()).append("&");
                    tabUrl.append(QueryParameters.DIFF_LEVEL_PARAM_EQ).append(full ? '1' : '0');
                    String hashForActive = "";
                    String hashForInactive = "";
                    if (t == DiffType.OLD) {
                        hashForActive = Util.htmlize(rev0);
                        hashForInactive = Util.htmlize(data.getShortRev(0));
                    } else if (t == DiffType.NEW) {
                        hashForActive = Util.htmlize(rev1);
                        hashForInactive = Util.htmlize(data.getShortRev(1));
                    }
                    if (type == t) {
            %> <span class="active" data-od-id="diff-tab-<%= t.getAbbrev() %>"><%= t %><%
                        if (t == DiffType.OLD || t == DiffType.NEW) { %> (<%= hashForActive %>)<% }
            %></span><%
                    } else {
            %> <span data-od-id="diff-tab-<%= t.getAbbrev() %>"><a href="<%= tabUrl %>"><%= t %><%
                        if (t == DiffType.OLD || t == DiffType.NEW) { %>  (<%= hashForInactive %>)<% }
            %></a></span><%
                    }
                }
            %></div>
            <div class="ctype" data-od-id="diff-ctype">
                <% /* Always render full first, then compact — matches the original
                  * apache_tomcat diff.jsp "ctype" row (lines 187-201). */
                if (full) { %>
                <span class="active" data-od-id="diff-view-full">full</span>
                <span data-od-id="diff-view-compact"><a href="<%= compactUrl %>">compact</a></span>
                <% } else { %>
                <span data-od-id="diff-view-full"><a href="<%= fullUrl %>">full</a></span>
                <span class="active" data-od-id="diff-view-compact">compact</span>
                <% } %>
                <span data-od-id="diff-view-jumper"><a href="#" id="toggle-jumper">jumper</a></span>
                <span data-od-id="diff-download"><a href="<%= dlDiffUrl %>">download diff</a></span>
            </div>
        </div>

        <div class="diff-panels<%= type == DiffType.SIDEBYSIDE ? " sdiff" : (type == DiffType.UNIFIED ? " udiff" : (type == DiffType.TEXT ? " text" : (type == DiffType.OLD ? " old" : " new"))) %>" data-od-id="diff-panels"><%
        if (type == DiffType.SIDEBYSIDE || type == DiffType.UNIFIED) {
            String linkPrefix = ctxPath + Prefix.XREF_P + Util.uriEncodePath(path) +
                    "?" + QueryParameters.REVISION_PARAM_EQ;
            String oldFileLabel = Util.htmlize(filename) + " (old)";
            String newFileLabel = Util.htmlize(filename) + " (new)";
            String oldPath = (project != null ? project.getName() + "/" : "") + path;
            String newPath = oldPath;
%>
            <div class="diff-panel diff-panel-old">
                <div class="diff-panel-header">
                    <span class="panel-tag">old</span><%= Util.htmlize(oldPath) %>
                </div>
                <div class="diff-code" data-od-id="diff-code-old"><%
            for (int i = 0; i < data.getRevision().size(); i++) {
                Delta delta = data.getRevision().getDelta(i);
                if (type == DiffType.SIDEBYSIDE) {
                    Chunk c1 = delta.getOriginal();
                    Chunk c2 = delta.getRevised();
                    int cn1 = c1.first();
                    int cl1 = c1.last();
                    int cn2 = c2.first();
                    int cl2 = c2.last();
                    int i1 = cn1, i2 = cn2;
                    StringBuilder bl1 = new StringBuilder(80);
                    StringBuilder bl2 = new StringBuilder(80);
                    for (; i1 <= cl1 && i2 <= cl2; i1++, i2++) {
                        String[] ss = Util.diffline(
                                new StringBuilder(file1[i1]),
                                new StringBuilder(file2[i2]));
                        file1[i1] = ss[0];
                        file2[i2] = ss[1];
                    }
                    for (; i1 <= cl1; i1++) {
                        bl1.setLength(0);
                        bl1.append("<span class=\"d\">");
                        Util.htmlize(file1[i1], bl1);
                        file1[i1] = bl1.append("</span>").toString();
                    }
                    for (; i2 <= cl2; i2++) {
                        bl2.setLength(0);
                        bl2.append("<span class=\"a\">");
                        Util.htmlize(file2[i2], bl2);
                        file2[i2] = bl2.append("</span>").toString();
                    }
                    // SDIFF — open one .chunk per delta so the jumper
                    // plugin (diff-0.0.5.js) can navigate between hunks.
                    // LEFT panel (file1 view) shows context + deleted lines.
                    %><div class="chunk"><%
                    if (cn1 > ln1) {
                        if (full || cn1 - ln1 < 20) {
                            for (int j = ln1; j < cn1; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= ++ln1 %></span><span class="diff-line-content"><%= Util.htmlize(file1[ln1 - 1]) %></span></div><%
                            }
                        } else {
                            for (int j = ln1; j < ln1 + 8; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= j + 1 %></span><span class="diff-line-content"><%= Util.htmlize(file1[j]) %></span></div><%
                            }
                            int hiddenLines = cn1 - ln1 - 16; %>
            <div class="diff-line"><span class="diff-line-num"></span><span class="diff-line-content">--- <strong><%= hiddenLines %> unchanged lines hidden</strong> (<a href="<%= fullUrl %>#<%= ln1 %>">view full</a>) ---</span></div><%
                            ln1 = cn1 - 8;
                            for (int j = ln1; j < cn1; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= ++ln1 %></span><span class="diff-line-content"><%= Util.htmlize(file1[j]) %></span></div><%
                            }
                        }
                    }
                    for (int j = cn1; j <= cl1; j++) { %>
            <div class="diff-line diff-line-del"><span class="diff-line-num"><%= ++ln1 %></span><span class="diff-line-content"><%= file1[j] %></span></div><%
                    }
                    %></div><%
                } else if (type == DiffType.UNIFIED) {
                    // UDIFF — single-column layout, but we still render in the "old" panel as primary column.
                    Chunk c1 = delta.getOriginal();
                    Chunk c2 = delta.getRevised();
                    int cn1 = c1.first();
                    int cl1 = c1.last();
                    int cn2 = c2.first();
                    int cl2 = c2.last();
                    int i1 = cn1, i2 = cn2;
                    StringBuilder bl1 = new StringBuilder(80);
                    StringBuilder bl2 = new StringBuilder(80);
                    for (; i1 <= cl1 && i2 <= cl2; i1++, i2++) {
                        String[] ss = Util.diffline(
                                new StringBuilder(file1[i1]),
                                new StringBuilder(file2[i2]));
                        file1[i1] = ss[0];
                        file2[i2] = ss[1];
                    }
                    for (; i1 <= cl1; i1++) {
                        bl1.setLength(0);
                        bl1.append("<span class=\"d\">");
                        Util.htmlize(file1[i1], bl1);
                        file1[i1] = bl1.append("</span>").toString();
                    }
                    for (; i2 <= cl2; i2++) {
                        bl2.setLength(0);
                        bl2.append("<span class=\"a\">");
                        Util.htmlize(file2[i2], bl2);
                        file2[i2] = bl2.append("</span>").toString();
                    }
                    // UNIFIED — wrap each delta in one .chunk for jumper.
                    %><div class="chunk"><%
                    if (cn1 > ln1 || cn2 > ln2) {
                        if (full || (cn2 - ln2 < 20)) {
                            for (int j = ln2; j < cn2; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= ++ln2 %></span><span class="diff-line-content"><%= Util.htmlize(file2[j]) %></span></div><%
                            }
                        } else {
                            for (int j = ln2; j < ln2 + 8; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= j + 1 %></span><span class="diff-line-content"><%= Util.htmlize(file2[j]) %></span></div><%
                            }
                            int hiddenLines = cn2 - ln2 - 16; %>
            <div class="diff-line"><span class="diff-line-num"></span><span class="diff-line-content">--- <strong><%= hiddenLines %> unchanged lines hidden</strong> (<a href="<%= fullUrl %>#<%= ln2 %>">view full</a>) ---</span></div><%
                            ln2 = cn2 - 8;
                            for (int j = ln2; j < cn2; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= ++ln2 %></span><span class="diff-line-content"><%= Util.htmlize(file2[j]) %></span></div><%
                            }
                        }
                        ln1 = cn1;
                    }
                    if (cn1 <= cl1) {
                        for (int j = cn1; j <= cl1; j++) { %>
            <div class="diff-line diff-line-del"><span class="diff-line-num"><%= ++ln1 %></span><span class="diff-line-content"><%= file1[j] %></span></div><%
                        }
                    }
                    if (cn2 <= cl2) {
                        for (int j = cn2; j < cl2; j++) {
                            String anchor = (full ? "<a id=\"" + ln2 + "\"></a>" : ""); %>
            <div class="diff-line diff-line-add"><span class="diff-line-num"><%= ++ln2 %></span><span class="diff-line-content"><%= anchor %><%= file2[j] %></span></div><%
                        }
                        String anchor = (full ? "<a id=\"" + ln2 + "\"></a>" : ""); %>
            <div class="diff-line diff-line-add"><span class="diff-line-num"><%= ++ln2 %></span><span class="diff-line-content"><%= anchor %><%= file2[cl2] %></span></div><%
                    }
                    %></div><%
                }
            }
            // Dump the remaining lines (post-deltas) for SDIFF / UNIFIED in the OLD panel context.
            if (type == DiffType.SIDEBYSIDE) {
                if (full || file1.length - ln1 < 20) {
                    for (int j = ln1; j < file1.length; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= j + 1 %></span><span class="diff-line-content"><%= Util.htmlize(file1[j]) %></span></div><%
                    }
                } else {
                    for (int j = ln1; j < ln1 + 8; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= j + 1 %></span><span class="diff-line-content"><%= Util.htmlize(file1[j]) %></span></div><%
                    } %>
            <div class="diff-line"><span class="diff-line-num"></span><span class="diff-line-content"> --- <strong><%= file1.length - ln1 - 8 %> unchanged lines hidden</strong> --- </div><%
                }
            } else if (type == DiffType.UNIFIED) {
                if (full || file2.length - ln2 < 20) {
                    for (int j = ln2; j < file2.length; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= j + 1 %></span><span class="diff-line-content"><%= Util.htmlize(file2[j]) %></span></div><%
                    }
                } else { %>
            <div class="diff-line"><span class="diff-line-num"></span><span class="diff-line-content">--- <strong><%= file2.length - ln2 - 8 %> unchanged lines hidden</strong> ---</div><%
                }
            } %>
                </div>
            </div>
            <% if (type == DiffType.SIDEBYSIDE) { %>
            <div class="diff-panel diff-panel-new">
                <div class="diff-panel-header">
                    <span class="panel-tag">new</span><%= Util.htmlize(newPath) %>
                </div>
                <div class="diff-code" data-od-id="diff-code-new"><%
            /* SDIFF: render the new (added + context) lines in the right
             * panel so the user can compare both sides column-by-column. */
                int ln2s = 0;
                for (int i = 0; i < data.getRevision().size(); i++) {
                    Delta delta = data.getRevision().getDelta(i);
                    Chunk c1 = delta.getOriginal();
                    Chunk c2 = delta.getRevised();
                    int cn1 = c1.first();
                    int cl1 = c1.last();
                    int cn2 = c2.first();
                    int cl2 = c2.last();
                    %><div class="chunk"><%
                    if (cn1 > ln2s || cn2 > ln2s) {
                        if (full || cn2 - ln2s < 20) {
                            for (int j = ln2s; j < cn2; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= ++ln2s %></span><span class="diff-line-content"><%= Util.htmlize(file2[j]) %></span></div><%
                            }
                        } else {
                            for (int j = ln2s; j < ln2s + 8; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= j + 1 %></span><span class="diff-line-content"><%= Util.htmlize(file2[j]) %></span></div><%
                            }
                            int hiddenLines = cn2 - ln2s - 16; %>
            <div class="diff-line"><span class="diff-line-num"></span><span class="diff-line-content">--- <strong><%= hiddenLines %> unchanged lines hidden</strong> (<a href="<%= fullUrl %>#<%= ln2s %>">view full</a>) ---</span></div><%
                            ln2s = cn2 - 8;
                            for (int j = ln2s; j < cn2; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= ++ln2s %></span><span class="diff-line-content"><%= Util.htmlize(file2[j]) %></span></div><%
                            }
                        }
                    }
                    for (int j = cn2; j <= cl2; j++) {
                        String lineNum = String.valueOf(++ln2s);
                        String anchor = (full ? "<a id=\"" + ln2s + "\"></a>" : ""); %>
            <div class="diff-line diff-line-add"><span class="diff-line-num"><%= lineNum %></span><span class="diff-line-content"><%= anchor %><%= file2[j] %></span></div><%
                    }
                    %></div><%
                }
                /* Tail of file2 (post-deltas). */
                if (full || file2.length - ln2s < 20) {
                    for (int j = ln2s; j < file2.length; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= j + 1 %></span><span class="diff-line-content"><%= Util.htmlize(file2[j]) %></span></div><%
                    }
                } else {
                    for (int j = ln2s; j < ln2s + 8; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= j + 1 %></span><span class="diff-line-content"><%= Util.htmlize(file2[j]) %></span></div><%
                    } %>
            <div class="diff-line"><span class="diff-line-num"></span><span class="diff-line-content"> --- <strong><%= file2.length - ln2s - 8 %> unchanged lines hidden</strong> --- </div><%
                } %>
                </div>
            </div><%
            } %>
        <% } else if (type == DiffType.TEXT) {
            // Single-panel text diff
%>
            <div class="diff-panel diff-panel-old" style="grid-column: 1 / -1;">
                <div class="diff-panel-header">
                    <span class="panel-tag">text</span><%= Util.htmlize(filename) %>
                </div>
                <pre class="diff-text"><%
            for (int i = 0; i < data.getRevision().size(); i++) {
                Delta delta = data.getRevision().getDelta(i); %>
<%= Util.htmlize(delta.toString()) %><%
            } %>
</pre>
            </div><%
        } else if (type == DiffType.OLD) {
            String filePath = (project != null ? project.getName() + "/" : "") + path;
%>
            <div class="diff-panel diff-panel-old" style="grid-column: 1 / -1;">
                <div class="diff-panel-header">
                    <span class="panel-tag">old</span><%= Util.htmlize(filePath) %>
                </div>
                <div class="diff-code"><%
            for (int i = 0; i < data.getRevision().size(); i++) {
                Delta delta = data.getRevision().getDelta(i);
                Chunk c1 = delta.getOriginal();
                Chunk c2 = delta.getRevised();
                int cn1 = c1.first();
                int cl1 = c1.last();
                int cn2 = c2.first();
                int cl2 = c2.last();
                int i1 = cn1, i2 = cn2;
                StringBuilder bl1 = new StringBuilder(80);
                StringBuilder bl2 = new StringBuilder(80);
                for (; i1 <= cl1 && i2 <= cl2; i1++, i2++) {
                    String[] ss = Util.diffline(
                            new StringBuilder(file1[i1]),
                            new StringBuilder(file2[i2]));
                    file1[i1] = ss[0];
                    file2[i2] = ss[1];
                }
                for (; i1 <= cl1; i1++) {
                    bl1.setLength(0);
                    bl1.append("<span class=\"d\">");
                    Util.htmlize(file1[i1], bl1);
                    file1[i1] = bl1.append("</span>").toString();
                }
                for (; i2 <= cl2; i2++) {
                    bl2.setLength(0);
                    bl2.append("<span class=\"a\">");
                    Util.htmlize(file2[i2], bl2);
                    file2[i2] = bl2.append("</span>").toString();
                }
                %><div class="chunk"><%
                if (cn1 > ln1) {
                    if (full || cn1 - ln1 < 20) {
                        for (int j = ln1; j < cn1; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= ++ln1 %></span><span class="diff-line-content"><%= Util.htmlize(file1[j]) %></span></div><%
                        }
                    } else {
                        for (int j = ln1; j < ln1 + 8; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= j + 1 %></span><span class="diff-line-content"><%= Util.htmlize(file1[j]) %></span></div><%
                        }
                        int hiddenLines = cn1 - ln1 - 16; %>
            <div class="diff-line"><span class="diff-line-num"></span><span class="diff-line-content">--- <strong><%= hiddenLines %> unchanged lines hidden</strong> (<a href="<%= fullUrl %>#<%= ln1 %>">view full</a>) ---</div><%
                        ln1 = cn1 - 8;
                        for (int j = ln1; j < cn1; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= ++ln1 %></span><span class="diff-line-content"><%= Util.htmlize(file1[j]) %></span></div><%
                        }
                    }
                }
                for (int j = cn1; j <= cl1; j++) { %>
            <div class="diff-line diff-line-del"><span class="diff-line-num"><%= ++ln1 %></span><span class="diff-line-content"><%= file1[j] %></span></div><%
                }
                if (full) { %>
            <a id="<%= ln1 %>"></a><%
                }
                %></div><%
            }
            if (file1.length >= ln1) {
                if (full || file1.length - ln1 < 20) {
                    for (int j = ln1; j < file1.length; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= j + 1 %></span><span class="diff-line-content"><%= Util.htmlize(file1[j]) %></span></div><%
                    }
                } else {
                    for (int j = ln1; j < ln1 + 8; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= j + 1 %></span><span class="diff-line-content"><%= Util.htmlize(file1[j]) %></span></div><%
                    } %>
            <div class="diff-line"><span class="diff-line-num"></span><span class="diff-line-content"> --- <strong><%= file1.length - ln1 - 8 %> unchanged lines hidden</strong> ---</div><%
                }
            } %>
                </div>
            </div><%
        } else if (type == DiffType.NEW) {
            String filePath = (project != null ? project.getName() + "/" : "") + path;
%>
            <div class="diff-panel diff-panel-new" style="grid-column: 1 / -1;">
                <div class="diff-panel-header">
                    <span class="panel-tag">new</span><%= Util.htmlize(filePath) %>
                </div>
                <div class="diff-code"><%
            for (int i = 0; i < data.getRevision().size(); i++) {
                Delta delta = data.getRevision().getDelta(i);
                Chunk c1 = delta.getOriginal();
                Chunk c2 = delta.getRevised();
                int cn1 = c1.first();
                int cl1 = c1.last();
                int cn2 = c2.first();
                int cl2 = c2.last();
                int i1 = cn1, i2 = cn2;
                StringBuilder bl1 = new StringBuilder(80);
                StringBuilder bl2 = new StringBuilder(80);
                for (; i1 <= cl1 && i2 <= cl2; i1++, i2++) {
                    String[] ss = Util.diffline(
                            new StringBuilder(file1[i1]),
                            new StringBuilder(file2[i2]));
                    file1[i1] = ss[0];
                    file2[i2] = ss[1];
                }
                for (; i1 <= cl1; i1++) {
                    bl1.setLength(0);
                    bl1.append("<span class=\"d\">");
                    Util.htmlize(file1[i1], bl1);
                    file1[i1] = bl1.append("</span>").toString();
                }
                for (; i2 <= cl2; i2++) {
                    bl2.setLength(0);
                    bl2.append("<span class=\"a\">");
                    Util.htmlize(file2[i2], bl2);
                    file2[i2] = bl2.append("</span>").toString();
                }
                %><div class="chunk"><%
                if (cn2 > ln2) {
                    if (full || cn2 - ln2 < 20) {
                        for (int j = ln2; j < cn2; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= ++ln2 %></span><span class="diff-line-content"><%= Util.htmlize(file2[j]) %></span></div><%
                        }
                    } else {
                        for (int j = ln2; j < ln2 + 8; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= j + 1 %></span><span class="diff-line-content"><%= Util.htmlize(file2[j]) %></span></div><%
                        }
                        int hiddenLines = cn2 - ln2 - 16; %>
            <div class="diff-line"><span class="diff-line-num"></span><span class="diff-line-content">--- <strong><%= hiddenLines %> unchanged lines hidden</strong> (<a href="<%= fullUrl %>#<%= ln2 %>">view full</a>) ---</div><%
                        ln2 = cn2 - 8;
                        for (int j = ln2; j < cn2; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= ++ln2 %></span><span class="diff-line-content"><%= Util.htmlize(file2[j]) %></span></div><%
                        }
                    }
                }
                for (int j = cn2; j <= cl2; j++) {
                    String anchor = (full ? "<a id=\"" + ln2 + "\"></a>" : ""); %>
            <div class="diff-line diff-line-add"><span class="diff-line-num"><%= ++ln2 %></span><span class="diff-line-content"><%= anchor %><%= file2[j] %></span></div><%
                }
                %></div><%
            }
            if (file2.length >= ln2) {
                if (full || file2.length - ln2 < 20) {
                    for (int j = ln2; j < file2.length; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= j + 1 %></span><span class="diff-line-content"><%= Util.htmlize(file2[j]) %></span></div><%
                    }
                } else {
                    for (int j = ln2; j < ln2 + 8; j++) { %>
            <div class="diff-line diff-line-ctx"><span class="diff-line-num"><%= j + 1 %></span><span class="diff-line-content"><%= Util.htmlize(file2[j]) %></span></div><%
                    } %>
            <div class="diff-line"><span class="diff-line-num"></span><span class="diff-line-content"> --- <strong><%= file2.length - ln2 - 8 %> unchanged lines hidden</strong> ---</div><%
                }
            } %>
                </div>
            </div><%
        }
%>
        </div>
    </section>
<%
    }
}
%>
</main>
<%@ include file="/foot.jspf" %>
<%= PageConfig.get(request).getScripts() %>
<script type="text/javascript">
/* <![CDATA[ */
/* ---------------------- diff.jsp page-specific scripts ---------------------
 *
 * Diff jumper floating popup.
 *
 * The stock plugin (diff-0.0.5.js + utils-0.0.48.js's $.window) creates a
 * popup via the $.window plugin but its layout and toggle logic relies on
 * a #content element that the refactored chrome no longer renders, so
 * the popup ends up anchored against an empty jQuery set and never
 * appears when the user clicks "jumper".
 *
 * We implement the popup directly here, modelled on the stock plugin's
 * behaviour and styling (cream-yellow background + box-shadow from
 * apache_tomcat's style-1.0.4.css .diff_navigation_style). The jumper
 * finds all ".chunk" hunks inside the FIRST .diff-panel and lets the
 * user step through them with buttons or keyboard (n / b shortcuts).
 */
/* ── Diff jumper ────────────────────────────────────────────────── */
(function () {
    $(function () {
        var $btn = $('#toggle-jumper');
        if (!$btn.length) return;

        /* Stop the stock diff-0.0.5.js plugin from also binding its
         * broken click handler (it would point at an empty #content
         * and crash on .offset().top). We replace it with our own. */
        $btn.off('click');
        /* Also drop the stock plugin's phantom window + key handler so
         * the document.keypress binding doesn't fire 'n' / 'b' twice. */
        if (typeof $.diffWindow !== 'undefined' && $.diffWindow) {
            if ($.diffWindow.$window && $.diffWindow.$window.remove) {
                try { $.diffWindow.$window.remove(); } catch (e) { /* ignore */ }
            }
        }
        $(document).off('keypress.diffWindow');

        /* Scope hunks to the left/old panel only so SDIFF's visual
         * duplicate hunks in the right panel don't double-count. */
        var $chunks = $('.diff-panel:first-child .chunk');

        /* Build the popup DOM. */
        var $popup = $('<div id="diff_win" class="diff-window diff_navigation_style">' +
                '<div class="window-header">' +
                    '<div class="clearfix">' +
                        '<div class="pull-left"><b>Diff jumper</b></div>' +
                        '<div class="pull-right"><a href="#" class="minimize">x</a></div>' +
                    '</div>' +
                '</div>' +
                '<div class="window-body">' +
                    '<div class="pull-right">' +
                        '<a href="#" class="prev" title="Previous chunk (b)">&lt;&lt; Previous</a>' +
                        ' | ' +
                        '<a href="#" class="next" title="Next chunk (n)">Next &gt;&gt;</a>' +
                        '<div class="clearfix"></div>' +
                    '</div>' +
                    '<div class="summary"></div>' +
                    '<div class="progress"></div>' +
                '</div>' +
            '</div>').appendTo('body');

        var $summary = $popup.find('.summary');
        var $progress = $popup.find('.progress');
        var index = -1;
        var animating = false;

        function update() {
            var label = (index < 0 ? 0 : index + 1) + '/' + $chunks.length + ' chunks';
            $summary.text(label);
        }

        function gotoChunk(i) {
            if (i < 0 || i >= $chunks.length) {
                flash('No ' + (i < 0 ? 'previous' : 'next') + ' chunk!');
                return;
            }
            index = i;
            update();
            var $c = $chunks.eq(i);
            $('html, body').stop().animate({
                scrollTop: $c.offset().top - 80
            }, 300);
            flash('Going to chunk ' + (index + 1) + '/' + $chunks.length);
        }

        function flash(msg) {
            var $p = $('<p>' + msg + '</p>');
            $progress.html($p);
            $p.delay(800).fadeOut(200, function () { $p.remove(); });
        }

        /* Toggle on click. */
        $btn.off('click.diffJumper').on('click.diffJumper', function (e) {
            e.preventDefault();
            if (animating) return;
            animating = true;
            if ($popup.is(':visible')) {
                /* Slide back to the button and hide. */
                var btnTop = $btn.offset().top;
                $popup.stop().animate({
                    top: btnTop,
                    opacity: 0
                }, 250, function () {
                    $popup.hide();
                    animating = false;
                });
            } else {
                /* Show and slide in from the button position to top-right.
                 * We compute positions first (offset/width) while the
                 * popup is still hidden, so the initial frame is correct. */
                var startTop = $btn.offset().top;
                var startLeft = $btn.offset().left + $btn.outerWidth() + 8;
                $popup.css({
                    top: startTop,
                    left: startLeft,
                    opacity: 0,
                    display: 'block',
                    visibility: 'visible'
                });
                update();
                /* Force a layout pass before measuring, otherwise the
                 * popup's outerWidth() could read 0 if it just appeared. */
                $popup.outerWidth();
                var endLeft = $(window).width() - $popup.outerWidth() - 20;
                $popup.stop().animate({
                    top: 100,
                    left: endLeft,
                    opacity: 1
                }, 250, function () { animating = false; });
            }
            return false;
        });

        /* Minimize button. */
        $popup.find('.minimize').on('click', function (e) {
            e.preventDefault();
            $popup.stop().animate({ opacity: 0 }, 200, function () {
                $popup.hide();
                animating = false;
            });
            return false;
        });

        /* Prev / Next buttons. */
        $popup.find('.prev').on('click', function (e) {
            e.preventDefault();
            gotoChunk(index - 1);
            return false;
        });
        $popup.find('.next').on('click', function (e) {
            e.preventDefault();
            gotoChunk(index + 1);
            return false;
        });

        /* Keyboard shortcuts (n / b) — same as the stock plugin. */
        $(document).on('keydown.diffJumper', function (e) {
            var tag = (e.target && e.target.tagName) || '';
            if (/^(INPUT|TEXTAREA|SELECT)$/.test(tag)) return;
            if (e.key === 'n' || e.key === 'N') { gotoChunk(index + 1); }
            if (e.key === 'b' || e.key === 'B') { gotoChunk(index - 1); }
            if (e.key === 'Escape' && $popup.is(':visible')) {
                $popup.stop().animate({ opacity: 0 }, 200, function () {
                    $popup.hide();
                    animating = false;
                });
            }
        });
    });
})();
/* ]]> */
</script>
</body>
</html>
