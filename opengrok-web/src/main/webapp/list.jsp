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
    /* Sticky toolbar — match the legacy OpenGrok behaviour where
     * the file-toolbar (Annotate / Line / Scopes / Navigate / Raw /
     * Download / Line:) sticks to the top of the viewport while
     * the user scrolls through the dumped xref. Without this the
     * toolbar scrolls out of view and the user has to scroll back
     * to the top of the file just to toggle the Scopes / Navigate
     * popups.
     *
     * Implementation notes:
     *   - `position: sticky` requires NO `overflow: hidden|auto|scroll`
     *     on any ancestor between the toolbar and the viewport. The
     *     .code-area below is `overflow: auto`, but it is a SIBLING
     *     of .code-toolbar, not an ancestor, so sticky is free to
     *     stick to the viewport.
     *   - `top: 0` makes it stick to the viewport top once the
     *     pageheader.jspf chrome scrolls out of view. If you want
     *     a small breathing gap, change to e.g. `top: 4px`.
     *   - `z-index: 5` puts the toolbar above the code content
     *     (z-index auto) but BELOW the floating Scopes / Navigate /
     *     Intelligence popups (z-index 10 in the .window rules).
     *     That ordering matches the user's mental model: popups
     *     should never be hidden behind the toolbar they belong to. */
    position: sticky;
    top: 0;
    z-index: 5;
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
/* Line-number gutter — mirror style-1.0.6.css .l / .hl so the gutter
 * reads as a fixed-width muted column on the left of every line, with
 * every 10th line highlighted (.hl). Without the gutter background the
 * anchors just look like big blue links floating in space (see the
 * "before" screenshot). Match original specificity (`.l, .hl`) so that
 * the original rule from style-1.0.6.css also wins when both are
 * loaded; the scoped overrides below restore the gutter look on top
 * of any rule that would otherwise turn `.l` into a blue link. */
.code-area pre a.l,
.code-area pre a.hl {
    display: inline-block;
    width: 3.5em;
    min-width: 3.5em;
    text-align: right;
    padding: 0 .4em 0 .4em;
    margin-right: .5em;
    background-color: #f6f8fa;
    color: #8b949e;
    user-select: none;
    text-decoration: none;
    font-size: 11px;
    font-family: var(--font-mono);
    border: 0;
}
.code-area pre a.l:hover { color: var(--accent); }
.code-area pre a.hl { color: var(--accent); font-weight: 600; }
/* Goto-line target highlight — when URL has #N, light up that row's
 * gutter anchor (matches original style-1.0.6.css rule). */
.code-area div[id^='src'] a.l:target,
.code-area div[id^='src'] a.hl:target {
    background: var(--accent-dim);
    color: var(--accent);
}
/* Symbol/link highlighting inside the dumped xref. Scoped to a.l /
 * a.hl above so that the gutter anchors don't pick up the blue
 * accent colour. */
.code-area pre a:not(.l):not(.hl) { color: var(--accent); text-decoration: none; }
.code-area pre a:not(.l):not(.hl):hover { text-decoration: underline; }
/* Scope fold anchors inside the dumped xref — emit at end of each
 * scope-head line; keep them inline-block so the layout doesn't
 * break onto a new line. */
.code-area pre span.scope-head { display: inline; }
.code-area pre span.scope-body { display: inline; }
/* Annotate mode ("blame" column). The xref dump emits, for each
 * annotated line, after the line-number anchor:
 *   <span class="blame">
 *       <a class="r title-tooltip" ...>rev</a>
 *       <a class="search" ...></a>
 *       <span class="a">author</span>
 *   </span>
 * In the original style-1.0.6.css all three classes share a single
 * rule with `.l, .hl` (display: inline-block, 6ex wide, gutter
 * background). Without those rules the author/revision text breaks
 * out of the gutter and overlaps the line-number column. */
.code-area pre a.r,
.code-area pre span.a {
    display: inline-block;
    width: 6em;
    text-align: right;
    padding: 0 .4em 0 .4em;
    margin-right: .5em;
    background-color: #f6f8fa;
    color: #6e7681;
    font-size: 11px;
    font-family: var(--font-mono);
    user-select: none;
    text-decoration: none;
    vertical-align: top;
}
.code-area pre a.r:hover { color: var(--accent); text-decoration: underline; }
.code-area pre a.search {
    display: inline-block;
    width: 1.4em;
    background-color: #f6f8fa;
    color: #6e7681;
    font-size: 11px;
    text-align: center;
    margin-right: .5em;
    text-decoration: none;
}
.code-area pre a.search:hover { color: var(--accent); text-decoration: none; }
.code-area pre span.most_recent_revision { font-weight: 600; color: var(--accent); }
/* Hide the scope-signature span (it lives between the line-number anchor
 * and the rest of the line; original style-1.0.6.css hides it via
 * display: none and the JS shows it again when the scope is folded).
 * Without this rule the signature text leaks back into the gutter area
 * on every scope-start line. */
.code-area pre span.scope-signature { display: none; }
.code-area pre span.fold-icon,
.code-area pre span.unfold-icon,
.code-area pre span.fold-space {
    display: inline-block;
    width: 11px; height: 11px;
    margin: 0 .2em;
}
.code-area pre span.fold-icon { background-image: url('<%= request.getContextPath() %>/default/img/folding.png'); background-repeat: no-repeat; }
.code-area pre span.unfold-icon { background-image: url('<%= request.getContextPath() %>/default/img/unfolding.png'); background-repeat: no-repeat; }
.code-area.raw-mode pre { color: var(--fg) !important; }
.code-area.raw-mode pre * { color: inherit !important; font-weight: normal !important; font-style: normal !important; }
.code-area.raw-mode pre a { text-decoration: none; }

/* `body.lines-hidden` (toggled by utils.js lntoggle()) must beat the
 * `.code-area pre a.l { display: inline-block }` rule above so the
 * Line button can hide the gutter. Same for `.hl`. The original
 * CSS rule lives in style-1.0.6.css but is overridden by specificity,
 * so we reproduce it here at higher specificity. */
body.lines-hidden .code-area pre a.l,
body.lines-hidden .code-area pre a.hl {
    display: none !important;
}
body.lines-hidden .code-area pre a.r,
body.lines-hidden .code-area pre a.search,
body.lines-hidden .code-area pre span.a {
    display: none !important;
}
body.lines-hidden .code-area pre span.fold-space,
body.lines-hidden .code-area pre span.fold-icon,
body.lines-hidden .code-area pre span.unfold-icon {
    display: none !important;
}

/* The comprehensive IntelliScence / Scopes / Navigate floating-window
 * styles live further down (immediately after the symbol-colour
 * rules). Nothing extra to add here. */

/* Symbol-colour classes used by the xref dump. The CSS class comes
 * from XrefStyle.ssClass — different colours per definition type
 * (class vs method vs field vs …). Without explicit rules the
 * generic `a:not(.l):not(.hl)` rule painted every definition in the
 * single accent colour. We mirror the per-class colours from the
 * original style-1.0.4.css (apache_tomcat/webapps/source) so the
 * type distinction is preserved.
 *
 * Specificity note: the generic rule above is
 *   `.code-area pre a:not(.l):not(.hl)`
 * whose specificity is (0, 3, 2) — `:not(.l)` and `:not(.hl)`
 * contribute the specificity of their argument, not zero. A bare
 * `.code-area a.xm` is only (0, 2, 1) and loses. The fix is to add
 * the same `:not(.l):not(.hl)` chain to every symbol rule so the
 * specificity is (0, 4, 2); with our rules placed AFTER the generic
 * rule in source order, they win for matching anchors. The chain
 * still excludes line-number / highlighted anchors (.l / .hl) so the
 * gutter styling stays intact. */
.code-area pre a:not(.l):not(.hl).xm   { color: #c66;      font-weight: 700; }
.code-area pre a:not(.l):not(.hl).xa   { color: #60c;      font-weight: 700; }
.code-area pre a:not(.l):not(.hl).xl   { color: #963;      font-weight: 700; }
.code-area pre a:not(.l):not(.hl).xv   { color: #c30;      font-weight: 700; }
.code-area pre a:not(.l):not(.hl).xc   { color: #909;      font-weight: 700; font-style: italic; }
.code-area pre a:not(.l):not(.hl).xp   { color: #909;      font-weight: 700; font-style: italic; }
.code-area pre a:not(.l):not(.hl).xi   { color: #909;      font-weight: 700; font-style: italic; }
.code-area pre a:not(.l):not(.hl).xn   { color: #909;      font-weight: 700; font-style: italic; }
.code-area pre a:not(.l):not(.hl).xe   { color: #909;      font-weight: 700; font-style: italic; }
.code-area pre a:not(.l):not(.hl).xer  { color: #909;      font-weight: 700; font-style: italic; }
.code-area pre a:not(.l):not(.hl).xs   { color: #909;      font-weight: 700; font-style: italic; }
.code-area pre a:not(.l):not(.hl).xt   { color: #909;      font-weight: 700; font-style: italic; }
.code-area pre a:not(.l):not(.hl).xts  { color: #909;      font-weight: 700; font-style: italic; }
.code-area pre a:not(.l):not(.hl).xu   { color: #909;      font-weight: 700; font-style: italic; }
.code-area pre a:not(.l):not(.hl).xfld { color: #090;      font-weight: 700; }
.code-area pre a:not(.l):not(.hl).xmb  { color: #090;      font-weight: 700; }
.code-area pre a:not(.l):not(.hl).xf   { color: #00f;      font-weight: 700; }
.code-area pre a:not(.l):not(.hl).xmt  { color: #00f;      font-weight: 700; }
.code-area pre a:not(.l):not(.hl).xsr  { color: #00f;      font-weight: 700; }
.code-area pre a:not(.l):not(.hl).xlbl { color: red;       font-weight: 700; background-color: yellow; }
.code-area pre a:not(.l):not(.hl).xr   { color: #909;      font-weight: 700; }
.code-area pre a:not(.l):not(.hl).d    { color: #909;      font-weight: 700; }
.code-area pre a:not(.l):not(.hl).scope{ color: steelblue; font-weight: 700; padding-left: 1ex;  }

/* ── Floating windows created by utils.js (Intelligence, Scopes,
 * Navigate) ──
 *
 * The original OpenGrok stylesheet default/style-1.0.6.css carries
 * the rules for these windows, but the refactored chrome no longer
 * references that file (we render an inline theme above). We inline
 * the minimum subset of those rules here so the three jQuery-UI
 * floating windows still look and behave like the upstream deployment:
 * opaque cream background, fixed positioning above the code area,
 * proper inner-element layout, and the six symbol-highlight colours
 * used by the IntelliScence window's Highlight/Search/Prev/Next
 * controls. */
.window {
    position: fixed;
    font-size: 12px;
    font-family: var(--font-mono);
    overflow: hidden;
    z-index: 10;
}
.window-header {
    padding: 5px 10px;
    min-height: 20px;
    border-bottom: 1px solid #c0c0c0;
    background: #eeeebb;
    background-color: #eeeebb;
}
.window-header .pull-left {
    float: left;
    font-family: var(--font-mono);
    font-size: 13px;
    font-weight: 600;
    color: #333;
}
.window-header .pull-right {
    float: right;
}
.window-header .clearfix::after {
    content: "";
    display: table;
    clear: both;
}
.window-body {
    overflow: auto;
    height: calc(100% - 40px - 1px - 20px);
    padding: 10px 10px 10px 10px;
    width: calc(100% - 20px);
}
.intelli-window {
    width: 504px;
    max-height: 400px;
}
.scopes-window {
    min-width: 150px;
    max-width: 40%;
    max-height: 400px;
}
.navigate-window {
    min-width: 200px;
    max-width: 300px;
    max-height: 480px;
}
.diff_navigation_style {
    border: solid 1px var(--og-border, #dddddd);
    border-radius: 5px;
    box-shadow: 10px 10px 5px var(--og-popup-shadow, #888888);
    /* Solid cream background so the code area never bleeds through.
     * Use `background` (shorthand) AND `background-color` so any later
     * `background: transparent` reset (e.g. jQuery-UI's `.ui-front`
     * rule) cannot override us — `background:` resets every layer,
     * including color, while `background-color:` only resets the color
     * layer. Both together cover either order. */
    background: rgb(255, 255, 204);
    background-color: rgb(255, 255, 204);
}
/* Symbol highlight colours used by the IntelliScence window's
 * "Highlight" / "Unhighlight" buttons. Same six colours as the
 * upstream default/style-1.0.6.css. */
.symbol-highlighted.hightlight-color-1 { background-color: #ffd700; }
.symbol-highlighted.hightlight-color-2 { background-color: #00ff00; }
.symbol-highlighted.hightlight-color-3 { background-color: #00ccff; }
.symbol-highlighted.hightlight-color-4 { background-color: #F653F8; }
.symbol-highlighted.hightlight-color-5 { background-color: rgb(242, 132, 34); }
.symbol-highlighted.hightlight-color-6 { background-color: #B6EBB5; }
/* Inner content of the IntelliScence floating window — pinned to the
 * window's cream background so the code area never bleeds through,
 * and styled to match the upstream print-friendly rendering.
 *
 * Belt-and-suspenders: the popup is appended to <body> by utils.js
 * line 724, and jQuery-UI's `.ui-front` class (from the
 * jquery-ui-1.12.1-custom theme stylesheet) would normally not
 * apply here, but the IntelliScence popup adds `class="window
 * diff_navigation_style intelli-window"` only — no `ui-*` classes.
 * The cream `background-color` is set on every layer (the window
 * container, the header, the body) so the .code-area's `#fbfcfd`
 * xref-paper background never shows through, even if the user
 * scrolls the code area while the popup is open. */
#intelli_win,
#scopes_win,
#navigate_win {
    background: rgb(255, 255, 204);
    background-color: rgb(255, 255, 204);
}
#intelli_win .window-header,
#scopes_win .window-header,
#navigate_win .window-header {
    background: #eeeebb;
    background-color: #eeeebb;
}
#intelli_win .window-body,
#scopes_win .window-body,
#navigate_win .window-body {
    background: rgb(255, 255, 204);
    background-color: rgb(255, 255, 204);
}
/* Per-symbol colour rules for the Navigate window.
 *
 * The Navigate window renders each definition as
 *   <a class="xc|xm|xv|…" href="#line">name</a>
 * inside <h4>Variable / Function / …</h4> groups. The class name on
 * each <a> is the same XrefStyle.ssClass used by the xref dump, so
 * the colour rules below mirror the per-class colours defined
 * elsewhere (`.code-area pre a.xm`, `.xref-paper a.xm`, …) and
 * restore the orange/red/purple/green/blue distinction the original
 * deployment showed.
 *
 * Specificity: `#navigate_win a.xc` is (0, 2, 2) and beats the
 * generic `a` selector (0, 0, 1), so per-class colour wins on every
 * link with a symbol class. For links without one (e.g. the
 * IntelliScence window's "Search" / "Google" controls, the Scopes
 * window's enclosing-scope link) the fallback `a` rule below kicks
 * in and paints them in the OpenGrok default link blue (#0000ee). */
#navigate_win a.xm   { color: #c66; font-weight: 700; }
#navigate_win a.xa   { color: #60c; font-weight: 700; }
#navigate_win a.xl   { color: #963; font-weight: 700; }
#navigate_win a.xv   { color: #c30; font-weight: 700; }
#navigate_win a.xc   { color: #909; font-weight: 700; font-style: italic; }
#navigate_win a.xp   { color: #909; font-weight: 700; font-style: italic; }
#navigate_win a.xi   { color: #909; font-weight: 700; font-style: italic; }
#navigate_win a.xn   { color: #909; font-weight: 700; font-style: italic; }
#navigate_win a.xe   { color: #909; font-weight: 700; font-style: italic; }
#navigate_win a.xer  { color: #909; font-weight: 700; font-style: italic; }
#navigate_win a.xs   { color: #909; font-weight: 700; font-style: italic; }
#navigate_win a.xt   { color: #909; font-weight: 700; font-style: italic; }
#navigate_win a.xts  { color: #909; font-weight: 700; font-style: italic; }
#navigate_win a.xu   { color: #909; font-weight: 700; font-style: italic; }
#navigate_win a.xfld { color: #090; font-weight: 700; }
#navigate_win a.xmb  { color: #090; font-weight: 700; }
#navigate_win a.xf   { color: #00f; font-weight: 700; }
#navigate_win a.xmt  { color: #00f; font-weight: 700; }
#navigate_win a.xsr  { color: #00f; font-weight: 700; }
#navigate_win a.xlbl { color: red;  font-weight: 700; background-color: yellow; }
#navigate_win a.xr   { color: #909; font-weight: 700; }
#navigate_win a.d    { color: #909; font-weight: 700; }
#navigate_win a.scope{ color: steelblue; font-weight: 700; padding-left: 1ex; }
/* Generic link styling for the IntelliScence window's action links
 * and any Navigate link without a symbol class. The per-class rules
 * above have higher specificity and override this for symbols.
 *
 * We deliberately DO NOT include `#scopes_win a` here: in the
 * original OpenGrok chrome (and the legacy Apache-tomcat
 * deployment) the scopes popup's single scope-link was rendered
 * without an underline. Mirroring that style. The `:not(.minimize)`
 * guard below keeps the close button (utils.js appends
 * `<a href="#" class="minimize">x</a>`) from being pulled into the
 * generic IntelliScence rule.
 *
 * Belt-and-suspenders: redeclare `color: #0000ee` for `:focus` and
 * `:active` so the IntelliScence action links (Highlight /
 * Unhighlight / Search / Google) don't drop to the browser's
 * default focus colour when the user tabs onto them. The default
 * focus colour is usually a slightly different shade (or, on some
 * Chromium themes, plain black) which makes the link look broken
 * next to the un-focused ones above it. */
#intelli_win a,
#intelli_win a:focus,
#intelli_win a:active,
#navigate_win a:not(.xm):not(.xa):not(.xl):not(.xv):not(.xc):not(.xp):not(.xi):not(.xn):not(.xe):not(.xer):not(.xs):not(.xt):not(.xts):not(.xu):not(.xfld):not(.xmb):not(.xf):not(.xmt):not(.xsr):not(.xlbl):not(.xr):not(.d):not(.scope),
#navigate_win a:not(.xm):not(.xa):not(.xl):not(.xv):not(.xc):not(.xp):not(.xi):not(.xn):not(.xe):not(.xer):not(.xs):not(.xt):not(.xts):not(.xu):not(.xfld):not(.xmb):not(.xf):not(.xmt):not(.xsr):not(.xlbl):not(.xr):not(.d):not(.scope):focus,
#navigate_win a:not(.xm):not(.xa):not(.xl):not(.xv):not(.xc):not(.xp):not(.xi):not(.xn):not(.xe):not(.xer):not(.xs):not(.xt):not(.xts):not(.xu):not(.xfld):not(.xmb):not(.xf):not(.xmt):not(.xsr):not(.xlbl):not(.xr):not(.d):not(.scope):active {
    color: #0000ee;
    text-decoration: underline;
    display: inline-block;
}
/* Scopes window: the body contains a single `<a>` built by utils.js's
 * buildLink(id, name) — that link is the only thing the user sees
 * inside the popup. Make sure it is a proper clickable target — but
 * the `.minimize` close button is ALSO an `<a>` inside this window,
 * so we exclude it via `:not(.minimize)` to keep its dimensions
 * untouched (the close button is styled by utils.js's window plugin
 * and should look like the title-bar × that the user expects). */
#scopes_win a:not(.minimize) {
    min-height: 1.5em;
    padding: 4px 0;
    word-break: break-word;
}
#intelli_win a:hover,
#scopes_win a:hover,
#navigate_win a:hover {
    color: #ff5500;
}
#intelli_win b.symbol-name,
#scopes_win b.symbol-name,
#navigate_win b.symbol-name {
    font-weight: 700;
    color: inherit;
}
#intelli_win h2,
#intelli_win h4,
#intelli_win h5,
#scopes_win h2,
#scopes_win h4,
#scopes_win h5,
#navigate_win h2,
#navigate_win h4,
#navigate_win h5 {
    color: #333;
    margin: 6px 0 4px;
    font-size: 12px;
    font-weight: 700;
}
#intelli_win h2 {
    font-size: 16px;
    font-weight: 700;
    font-family: var(--font-mono);
}

/* ── Window close button (×) ──
 *
 * utils.js's window plugin appends
 *   <a href="#" class="minimize">x</a>
 * as the close button on every floating window. By default the
 * browser's `<a>` styling leaks in (underline, focus ring, default
 * link colour). Reset that so the × button looks like a plain
 * clickable label, matching the legacy OpenGrok chrome and the
 * upstream apache_tomcat deployment.
 *
 * - `text-decoration: none` removes the underline that would
 *   otherwise appear under the "x" (the `:not(.minimize)` guard
 *   above on `#scopes_win a` doesn't help here because the generic
 *   IntelliScence rule further up still matches if the close
 *   button's parent is, say, the intelli window — same selector
 *   chain as the link list items).
 * - `color: inherit` keeps the "x" the same colour as the title-bar
 *   text instead of inheriting the IntelliScence `#0000ee`.
 * - `outline: none` silences the focus ring that browsers draw on
 *   `<a>` elements after a click (the legacy table-based chrome
 *   didn't have this issue; in the refactored chrome the focus
 *   ring is a small black rectangle around the "x").
 * - `font-weight: bold` makes the "x" readable against the cream
 *   title-bar background without being huge. */
.diff_navigation_style .minimize:focus,
.diff_navigation_style .minimize:active,
.diff_navigation_style .minimize {
    outline: none;
    text-decoration: none;
    color: #333;
    background: #fff;
    background-color: #fff;
    border: 1px solid #999;
    border-radius: 3px;
    padding: 0 6px;
    font-weight: bold;
    font-size: 12px;
    line-height: 1.4;
    cursor: pointer;
}
.diff_navigation_style .minimize:hover {
    background: #ffebe9;
    background-color: #ffebe9;
}
#intelli_win ul,
#scopes_win ul,
#navigate_win ul {
    margin: 0 0 8px;
    padding-left: 20px;
    list-style: disc;
}
#intelli_win li,
#scopes_win li,
#navigate_win li {
    line-height: 1.7;
}
#intelli_win hr,
#scopes_win hr,
#navigate_win hr {
    border: 0;
    border-top: 1px solid #c0c0c0;
    margin: 6px 0;
}
#intelli_win .pull-right,
#scopes_win .pull-right,
#navigate_win .pull-right {
    float: right;
}
#intelli_win .clearfix,
#scopes_win .clearfix,
#navigate_win .clearfix {
    clear: both;
}

@media (max-width: 900px) {
    .code-toolbar { padding: 6px 16px; }
    .code-toolbar-left .toolbar-btn span { display: none; }
    .code-toolbar-left .toolbar-btn { padding: 5px 8px; }
    .goto-line-group { margin-left: 4px; padding-left: 8px; }
    .goto-line-group label { display: none; }
}
@media (max-width: 600px) {
    .code-area pre { padding: 0 12px; font-size: 12px; }
    .code-area pre a.l,
    .code-area pre a.hl { width: 3em; min-width: 3em; padding-right: .3em; margin-right: .3em; }
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
            <button class="toolbar-btn" id="btn-raw" data-raw-href="<%= rawHref %>"><svg viewBox="0 0 24 24"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg><span>Raw</span></button>
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
            /* Decide once whether xref is going to be rendered by us
             * directly (in which case we wrap with <div id="src">) or
             * delegated to xref.jspf (which emits its own <div id="src">).
             * Avoids duplicate ids — invalid HTML and only the first
             * match would be picked up by $('#src'). */
            File _codeViewXrefFile = null;
            boolean _codeViewRenderDirect = false;
            if (!rev.isEmpty()) {
                if (_chromeListCfg.isLatestRevision(rev)) {
                    _codeViewXrefFile = _chromeListCfg.findDataFile();
                    _codeViewRenderDirect = _codeViewXrefFile != null;
                }
            } else {
                _codeViewXrefFile = _chromeListCfg.findDataFile();
                _codeViewRenderDirect = _codeViewXrefFile != null;
            }
            if (_codeViewRenderDirect) { %>
            <div id="src" data-navigate-window-enabled="<%= navigateWindowEnabled %>"><%
            }
            if (!rev.isEmpty()) {
                if (_codeViewRenderDirect) {
                    File xrefFile = _codeViewXrefFile;
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
                            } else if (g == AbstractAnalyzer.Genre.PLAIN) { %>
            <pre><%
                                Definitions defs = IndexDatabase.getDefinitions(resourceFile);
                                Annotation annotationX = _chromeListCfg.getAnnotation();
                                r = IOUtils.createBOMStrippedReader(bin, StandardCharsets.UTF_8.name());
                                AnalyzerGuru.writeDumpedXref(ctxPath, a, r, out, defs, annotationX, project, resourceFile); %>
            </pre><%
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
            } else if (_codeViewRenderDirect) {
                File xrefFile = _codeViewXrefFile; %>
            <pre><% Util.dumpXref(out, xrefFile, xrefFile.getName().endsWith(".gz"), ctxPath); %></pre><% out.flush(); %><%
            } else { %>
            <%@ include file="/xref.jspf" %><% out.flush(); %><%
            }
            if (_codeViewRenderDirect) { %>
            </div><%
            }
        %>
        </div>
    </main>
    <%-- utils-0.0.48.js (line 1553) keys the IntelliScence window init
         off the presence of #contextpath, and pageReadyList() (line
         2054) binds click on #navigate. Render the empty stubs the
         plugin expects. --%>
    <input type="hidden" id="contextpath" value="<%= ctxPath %>" />
    <a href="#" id="navigate" style="display:none"></a>
<script type="text/javascript">
/* <![CDATA[ */
/* ---------------------- list.jsp page-specific scripts ---------------------
 *
 * Restore the toolbar/popup interactivity that was lost when list.jsp
 * was refactored to the new chrome (header / breadcrumb / footer).
 * The button styles are intentionally kept as-is; only behaviour is
 * wired up here.
 *
 * The original (apache_tomcat/webapps/source) uses utils.js to manage
 * three jQuery-UI floating windows:
 *   • $.intelliWindow  – hovers with `a.intelliWindow-symbol` and shows
 *                       Highlight / Unhighlight / Search / Google links.
 *                       Initialised when #contextpath is on the page.
 *   • $.scopesWindow   – shows the enclosing scope of the line at the
 *                       top of the viewport. Initialised by init_scopes()
 *                       when #src is on the page.
 *   • $.navigateWindow – standalone window with the symbol list.
 *                       Initialised by pageReadyList().
 *
 * pageReadyList() (utils-0.0.47.js / utils-0.0.48.js) wires up
 *   $.navigateWindow.init();
 *   $.navigateWindow.update(get_sym_list());
 *   $('#navigate').click(...).toggle();
 * and also binds the keyboard shortcuts (1 → toggle IntelliScence,
 * 2-7 → highlight colors, 8 → unhighlight all, n/b → next/prev symbol)
 * inside $.intelliWindow's load callback.
 *
 * We delegate to the plugin wherever possible: the toolbar buttons just
 * invoke the same toggle() / show() / hide() methods that pageReadyList
 * would invoke through `#navigate`. We DO call pageReadyList() so the
 * plugin also wires up the IntelliScence keypress listener, the
 * mouseover handler on `a.intelliWindow-symbol`, and the `$('#navigate')`
 * click binding that the rest of the code base relies on.
 *
 * The Scopes / Navigate toolbar buttons intentionally do NOT keep a
 * mirrored `.active` class — the popup's own close (x) button hides
 * it without going through the toolbar, so any `.active` class on
 * the button would drift the moment the user dismisses the popup via
 * its built-in close control. The popup owns its own show/hide state
 * and the toolbar acts as a plain toggle, matching the original
 * OpenGrok chrome's behaviour.
 */
/* ── Legacy anchor shims (#content / #whole_header) — MUST run
 * before utils.js's $(document).ready() callback fires.
 *
 * utils-0.0.48.js hardcodes two element ids that only existed in
 * the OLD OpenGrok chrome and are NOT rendered by the refactored
 * chrome (pageheader.jspf emits <header class="common-page-header">
 * and list.jsp emits <main class="code-area">):
 *
 *   • `#content`      — used by scopesWindow.load()   (line 1159)
 *                       as `$("#content").offset().top`.
 *                       On a page with no #content, jQuery returns
 *                       an EMPTY set, `.offset()` yields undefined,
 *                       and `undefined.top` throws a TypeError. That
 *                       exception escapes from inside the plugin's
 *                       `load` callback and the popup never reaches
 *                       the show/hide hooks we want to bypass.
 *
 *   • `#whole_header` — used by scope_on_scroll() (line 2221) to
 *                       compute the y coordinate to hit-test with
 *                       document.elementFromPoint(15, y + 1).
 *
 * Both shims run here, in the global scope, synchronously, at the
 * top of the only <script> block — BEFORE any $(document).ready()
 * callback (utils.js's ready callback calls init_scopes() which
 * immediately creates #scopes_win and fires the load callback,
 * and that load callback depends on #content existing).
 *
 * If we instead put this shim inside a document.pageReady.push()
 * callback (the previous location), we'd be too late: utils.js
 * has already fired init_scopes() inside its own ready handler,
 * which runs before window.onload (where pageReady callbacks
 * fire — utils.js line 1525-1529).
 *
 * Both are only added when absent, so an upstream page that still
 * has them is left untouched. */
(function _installLegacyAnchorsImmediate() {
    if (!document.getElementById('whole_header')) {
        /* The original Apache-tomcat deployment put EVERYTHING
         * (logo + compact-nav + breadcrumb) under one element
         * with id="whole_header", and utils.js's scope_on_scroll()
         * reads `$('#whole_header').outerHeight() + 2` to compute
         * the y-coordinate for `elementFromPoint(15, y + 1)`. The
         * outerHeight() therefore needed to include the full
         * stacked header — logo + nav + breadcrumb — so that the
         * hit-test landed INSIDE the dumped-xref area below.
         *
         * The refactored chrome splits those three blocks into
         * separate siblings (<header.common-page-header>,
         * mast.jsp's <div class="compact-nav">, breadcrumb.jspf's
         * <nav class="dir-path">). Tagging only the logo header
         * leaves the hit-test pointing at the compact-nav (which
         * has no `.l` line anchors), so scope_on_scroll() exits
         * early and the Scopes window is never populated.
         *
         * Fix: walk down through every chrome sibling until we
         * find a sibling that actually contains a `#code-area` /
         * `#src` descendant, and tag the one JUST BEFORE it. That
         * way `outerHeight()` spans the full chrome stack and
         * `y + 1` lands inside the dumped xref. Falls back to the
         * logo header on pages with no code area (e.g. directory
         * listings). */
        var code = document.getElementById('code-area') ||
                   document.getElementById('content') ||
                   document.getElementById('src');
        var tag = document.querySelector('header.common-page-header');
        if (code && tag) {
            var n = tag.nextElementSibling;
            while (n && !n.contains(code) && n !== code) {
                tag = n;
                n = n.nextElementSibling;
            }
        }
        if (tag) {
            tag.id = 'whole_header';
        }
    }
    if (!document.getElementById('content')) {
        var area = document.getElementById('code-area');
        if (area) {
            area.id = 'content';
            /* keep the old id working for our own selectors below */
            area.classList.add('code-area');
            area.setAttribute('data-alias-of', 'code-area');
        }
    }
})();

document.pageReady.push(function() {
    /* ── Legacy anchor shims (#content / #whole_header) — moved to
     * the synchronous IIFE _installLegacyAnchorsImmediate() at the
     * very top of this <script> block. utils.js's $(document).ready()
     * callback (which calls init_scopes() and immediately fires
     * scopesWindow.load()) runs BEFORE window.onload (which is
     * where the pageReady callbacks fire), so any shim registered
     * here would be too late for `$("#content").offset().top`. */

    /* Delegate the heavy lifting to the upstream pageReadyList(). It
     * already does everything the original Apache-tomcat deployment
     * did: initialises $.navigateWindow, populates it from
     * get_sym_list(), binds the #navigate click, and (through the
     * intelliWindow load callback) wires up the 1-8/n/b keyboard
     * shortcuts and the hover handler on a.intelliWindow-symbol.
     *
     * Wrapped in try/catch: if any single plugin still throws, the
     * remaining toolbar bindings below must still be installed. */
    try {
        if (typeof pageReadyList === 'function') {
            pageReadyList();
        } else if (document.highlight_count === undefined) {
            document.highlight_count = 0;
        }
    } catch (err) {
        console.error('[opengrok] pageReadyList() failed', err);
        if (document.highlight_count === undefined) {
            document.highlight_count = 0;
        }
    }

    /* ── Populate the Navigate window explicitly ──
     *
     * SECOND ROOT CAUSE. pageReadyList() only fills the Navigate body
     * when `get_sym_list` is a function. That function is emitted by
     * the indexer INSIDE the dumped xref
     * (JFlexXrefUtils.writeSymbolTable → "function get_sym_list(){…}"),
     * i.e. it arrives as an inline <script> in the middle of the
     * page. Two ways it goes missing here:
     *
     *   1. The xref is dumped through Util.dumpXref() from a stored
     *      .gz xref file. Scripts injected via innerHTML-style DOM
     *      writes are not executed, and even for a plain server-side
     *      dump the definition only exists if the file HAS ctags
     *      definitions.
     *   2. `writeSymbolTable` is skipped entirely when the analyzer
     *      produced no Definitions (economy mode / no ctags), in which
     *      case get_sym_list never exists at all.
     *
     * When get_sym_list is missing the Navigate window is initialised
     * but never receives an update() call → empty body. We therefore
     * build the symbol list from the DOM itself as a fallback: every
     * definition anchor in the xref carries `class="xf|xmt|xc|…"` plus
     * a `name` attribute, which is exactly the data get_sym_list would
     * have returned. */
    function _symListFromDom() {
        /* class → human readable group title, mirrors XrefStyle. */
        var TITLES = {
            xc:  'Class',      xi: 'Interface', xs: 'Struct',
            xe:  'Enum',       xn: 'Namespace', xp: 'Package',
            xf:  'Function',   xmt:'Method',    xm: 'Macro',
            xv:  'Variable',   xfld:'Field',    xmb:'Member',
            xt:  'Typedef',    xts:'Typedefs',  xu: 'Union',
            xa:  'Annotation', xl: 'Label',     xsr:'Subroutine',
            xer: 'Error',      xr: 'Reference'
        };
        var groups = {};
        /* Definition anchors are emitted as <a class="xf" name="sym"/>
         * immediately before the clickable reference anchor. Pick the
         * ones that carry a name attribute — those are the defs. */
        var nodes = document.querySelectorAll('#src a[name], #content a[name]');
        for (var i = 0; i < nodes.length; i++) {
            var a = nodes[i];
            var nm = a.getAttribute('name');
            if (!nm || /^\d+$/.test(nm)) {
                continue;   // line-number anchor, not a definition
            }
            var cls = null;
            for (var k = 0; k < a.classList.length; k++) {
                if (TITLES[a.classList[k]]) { cls = a.classList[k]; break; }
            }
            if (!cls) {
                continue;
            }
            /* Line number = the nearest preceding line anchor. */
            var line = 0;
            var prev = a;
            while ((prev = prev.previousElementSibling)) {
                if (prev.classList &&
                        (prev.classList.contains('l') || prev.classList.contains('hl'))) {
                    line = parseInt(prev.getAttribute('name'), 10) || 0;
                    break;
                }
            }
            (groups[cls] = groups[cls] || []).push([nm, line]);
        }
        var out = [];
        Object.keys(groups).forEach(function (cls) {
            groups[cls].sort(function (a, b) { return a[0] < b[0] ? -1 : (a[0] > b[0] ? 1 : 0); });
            out.push([TITLES[cls], cls, groups[cls]]);
        });
        return out;
    }

    /* Fill Navigate if pageReadyList() left it empty. */
    try {
        if (window.jQuery && jQuery.navigateWindow && jQuery.navigateWindow.initialized) {
            var list = (typeof get_sym_list === 'function') ? get_sym_list() : [];
            if (!list || !list.length) {
                list = _symListFromDom();
            }
            if (list && list.length) {
                jQuery.navigateWindow.update(list);
            } else {
                /* Genuinely no symbols (plain text, JSON, no ctags data):
                 * say so instead of showing a blank cream box. */
                jQuery.navigateWindow.$content
                    .empty()
                    .append($('<h4>').text('No symbols for this file'));
            }
        }
    } catch (err) {
        console.error('[opengrok] navigate window population failed', err);
    }

    /* ── Silence utils.js's vendored scope_on_scroll() ──
     *
     * utils-0.0.48.js ships `scope_on_scroll()` at module scope. Its
     * `show` / `hide` hooks on $.scopesWindow call it directly. In
     * the new chrome it crashes inside `elementFromPoint(outerHeight+2)`
     * because the 16px top padding on `.code-content` shifts the first
     * `.l/.hl` anchor out of the y-coordinate; `elementFromPoint` then
     * returns null and `$(c).is('.l, .hl')` throws
     *     TypeError: Cannot read properties of undefined (reading 'top')
     * On Chrome 113+ the browser also flags `unload` handlers as a
     * permissions policy violation — that's a separate, unrelated
     * warning.
     *
     * By the time our pageReady callback runs, utils.js has bound
     * `window.scope_on_scroll` and `init_scopes()` has already wired
     * it into the scopesWindow show/hide hooks. We replace it with a
     * stub that defers to our own layout-agnostic
     * `_scopeAtViewportTop()` helper, which already uses
     * `getBoundingClientRect()` and never throws.
     *
     * Why not just delete scope_on_scroll entirely? Because utils.js's
     * `$(window).scroll(scope_on_scroll)` (line 1337) would then call
     * `undefined()` on every scroll and throw. Defining a no-op
     * keeps the scroll listener harmless. */
    window.scope_on_scroll = function _opengrokScopeOnScroll() {
        try {
            if (typeof _scopeAtViewportTop === 'function') {
                _scopeAtViewportTop();
            }
        } catch (err) {
            console.error('[opengrok] scope_on_scroll replacement failed', err);
        }
    };

    /* ── Locate the Scopes popup body and write scope links directly ──
     *
     * Earlier revisions patched `jQuery.scopesWindow.update()` to
     * suppress its auto-show side effect (utils-0.0.48.js line
     * 1182-1189 sets `data-shown-once` and calls `show()`), but the
     * patch was fighting the vendored plugin on its own turf and
     * turned out to be fragile: depending on the timing of
     * `init_scopes()` (which re-creates the wrapper) the patch
     * either ran before the real update() was attached, or got
     * overwritten by a later re-init.
     *
     * Simpler, more robust approach: BYPASS `update()` entirely and
     * write to the popup's body div directly. utils.js's window
     * plugin builds #scopes_win as:
     *   .window .scopes-window .diff_navigation_style
     *     .window-header  (title strip with × close button)
     *     .window-body
     *       <div> ($errors container, transient error messages)
     *       <div> ($scopes container — THIS is what we want)
     * We locate the $scopes container with `_scopesBody()` and write
     * <a href="#id">name</a> into it ourselves. The vendored
     * `update()` is left alone, but our path never calls it, so
     * its side-effects cannot leak into our state. If the user
     * closes the popup via its × button, utils.js just hides the
     * wrapper — the body content survives, so the next show is
     * non-empty automatically.
    /* Locate the body div inside #scopes_win that utils.js stores
     * scope links in. utils.js's window plugin builds the structure
     * as:
     *   #scopes_win (.window .scopes-window .diff_navigation_style)
     *     .window-header
     *       …
     *     .window-body
     *       <div> (utils.js's $errors container, set by window plugin)
     *       <div> (utils.js's $scopes container — THIS is what we want)
     *
     * The $scopes container is the only direct child of .window-body
     * that is NOT a script/error element. We pick it dynamically
     * instead of relying on `jQuery.scopesWindow.$scopes` because
     * that property may not be exposed on the wrapper, or may be a
     * stale reference after the plugin is re-initialised by
     * `init_scopes()` later in the lifecycle.
     *
     * Returns a jQuery wrapper for the body div, or an empty wrapper
     * (length=0) if #scopes_win isn't there yet. The caller decides
     * what to do with the empty result. */
    function _scopesBody() {
        var $win = $('#scopes_win');
        if (!$win.length) return $();
        var $body = $win.children('.window-body').first();
        if (!$body.length) return $();
        /* Walk all direct children of $body and return the FIRST one
         * that does not look like the errors container. utils.js's
         * window plugin inserts the errors div first (see line 595
         * `append(self.$errors = $('<div>').css('text-align', 'center'))`)
         * and then appends the user's $scopes via `body().append(...)`
         * (line 1154-1156). So the LAST direct child of $body is the
         * $scopes container in normal operation; the FIRST non-errors
         * one is safer if the plugin ever reorders. */
        var kids = $body.children();
        for (var i = 0; i < kids.length; i++) {
            var k = kids[i];
            /* The errors container has inline text-align:center and
             * is reserved for transient error messages; skip it. */
            if (k.style && k.style.textAlign === 'center') continue;
            return $(k);
        }
        /* Fallback: no non-errors child yet. Use the last child, or
         * if $body is empty create one. */
        if (kids.length) return $(kids[kids.length - 1]);
        return $('<div>').appendTo($body);
    }

    /* Direct DOM writer. Does NOT call jQuery.scopesWindow.update()
     * (whose vendored implementation triggers a no-op scope_on_scroll
     * that drops the body in the new chrome and clears our write in
     * some versions). Writes to the DOM directly so the popup body
     * is whatever we put there. */
    function _fillScopesDom(id, link) {
        try {
            var $body = _scopesBody();
            if (!$body.length) return false;
            $body.empty();
            if (id && link) {
                var $a = $('<a>')
                    .attr('href', '#' + id)
                    .attr('title', link)
                    .text(link);
                $body.append($a);
            } else if (link) {
                /* "No scope at top of view" placeholder. */
                $body.append($('<span>').text(link));
            }
            return true;
        } catch (err) {
            console.error('[opengrok] _fillScopesDom failed', err);
            return false;
        }
    }

    function _seedScopes() {
        try {
            if (!window.jQuery || !jQuery('#scopes_win').length) {
                return;
            }
            /* Skip if already populated (avoid clobbering a working
             * fill from a previous scroll / show). */
            var $body = _scopesBody();
            if (!$body.length) return;
            if ($body.children().length) return;

            /* Look for .scope-head under #src (the refactored chrome
             * emits it), then fall back to #content (alias), then to
             * #code-area (the real id before the shim ran). Picking
             * the FIRST .scope-head matches the original deployment,
             * which shows the outermost enclosing scope. */
            var $head = $('#src .scope-head, #content .scope-head, #code-area .scope-head').first();
            if ($head.length) {
                /* The xref dump emits the scope-signature <span> as
                 * the first child of each .scope-head; reading its
                 * html() is what the original utils.js code did
                 * inside scope_on_scroll() (see utils-0.0.47.js line
                 * 2232).
                 *
                 * The scope-signature content is the FULL signature
                 * (name + parameters), e.g.
                 *   "sample_hbp_handler(struct perf_event * bp, …)"
                 * which is wider than the scopes-window's max-width
                 * and forces a wrap that makes the popup look
                 * broken. Strip it down to just the leading
                 * identifier (the function name) by taking the text
                 * up to the first opening paren, matching what the
                 * original OpenGrok toolbar showed in the legacy
                 * chrome. If the signature has no parentheses, fall
                 * back to the first 80 chars. */
                var rawHtml = ($head.children().first().html() || $head.text() || '').trim();
                var parenIdx = rawHtml.indexOf('(');
                var shortName = (parenIdx > 0 ? rawHtml.substring(0, parenIdx) : rawHtml.substring(0, 80)).trim();
                _fillScopesDom($head.attr('id'), shortName);
            } else {
                _fillScopesDom(null, 'No scope at the top of the view');
            }
        } catch (err) {
            console.error('[opengrok] scopes seed failed', err);
        }
    }
    /* Update the Scopes window to show the scope that contains the
     * line currently at the top of the code viewport. This mirrors
     * what the original `scope_on_scroll()` does in utils-0.0.47.js,
     * but uses `getBoundingClientRect()` instead of
     * `document.elementFromPoint()` because the refactored chrome
     * has a 16px top padding on `.code-content` that shifts the first
     * line anchor out of the `outerHeight() + 2` y coordinate the
     * vendored function tests. As a result, in the new chrome
     * `elementFromPoint()` returns `.code-content` itself (the padded
     * wrapper) instead of a `.l`/`.hl` line anchor, the `.is('.l,
     * .hl')` check fails, and the popup never updates to the current
     * scroll position — which is exactly the "Scopes shows the wrong
     * scope" bug the user reported.
     *
     * Iteration over `.l`/`.hl` `getBoundingClientRect()` is robust
     * to any future padding/border changes between the chrome and
     * the code area, and walks DOM siblings (a line is a sibling of
     * its enclosing scope, NOT a descendant in the xref dump — the
     * scope spans are inline `<span>`s that wrap line anchors) so
     * `closest('.scope-body, .scope-head')` still resolves to the
     * correct scope. */
    function _scopeAtViewportTop() {
        try {
            if (!window.jQuery || !jQuery('#scopes_win').length) {
                return;
            }
            /* Pick the uppermost VISIBLE line. This avoids two
             * failure modes:
             *
             *  1. Using #whole_header.outerHeight() misses the
             *     sticky toolbar (once the chrome scrolls past, the
             *     toolbar stops being a document-flow element so
             *     .outerHeight() of #whole_header no longer reflects
             *     the visible chrome stack).
             *
             *  2. Using #code-area.offset().top is fragile: the
             *     area has internal padding / borders / sticky
             *     overlap. The exact offset shifts with each
             *     refactor and Chrome version.
             *
             * "Uppermost visible line" is what the user actually
             * wants: "the line the user is reading right now". Any
             * line with rect.top ≥ 0 is on-screen; we pick the
             * SMALLEST such top so the uppermost visible line
             * wins. Lines with rect.top < 0 are above the viewport
             * and must not be picked — otherwise we show the
             * PREVIOUS function's body for the current viewport.
             *
             * Performance: the dump emits thousands of .l anchors.
             * Once we find a line whose rect.top >= innerHeight we
             * can break early (later lines are off-screen below).
             */
            var $lines = $('#src .l, #src .hl, #content .l, #content .hl');
            var target = null;
            var bestTop = Infinity;
            var viewportH = window.innerHeight || 0;
            for (var i = 0; i < $lines.length; i++) {
                var el = $lines[i];
                var rect = el.getBoundingClientRect();
                /* Skip lines above the viewport (scrolled past). */
                if (rect.bottom <= 0) continue;
                /* Lines at or below the viewport bottom are out of
                 * reach; subsequent lines are even further down so
                 * we can break. */
                if (rect.top >= viewportH) break;
                /* Pick the line with the smallest (closest-to-top)
                 * rect.top among those still on-screen. */
                if (rect.top < bestTop) {
                    bestTop = rect.top;
                    target = el;
                }
            }
            if (!target) {
                /* No line is yet visible (very first paint, before
                 * layout settles). Defer to the seed as a graceful
                 * fallback so the user sees SOMETHING rather than
                 * a blank cream box. */
                _seedScopes();
                return;
            }
            var $par = $(target).closest('.scope-body, .scope-head');
            if (!$par.length) {
                /* Line is outside any scope (top of the file, before
                 * the first function). Show the first scope-head as
                 * a sensible default — same fallback as
                 * _seedScopes(). */
                _seedScopes();
                return;
            }
            var $head = $par.hasClass('scope-body') ? $par.prev() : $par;
            var $sig = $head.children().first();
            var rawHtml = ($sig.html() || $head.text() || '').trim();
            var parenIdx = rawHtml.indexOf('(');
            var shortName = (parenIdx > 0 ? rawHtml.substring(0, parenIdx) : rawHtml.substring(0, 80)).trim();
            _fillScopesDom($head.attr('id'), shortName);
        } catch (err) {
            console.error('[opengrok] scope-at-viewport-top failed', err);
            _seedScopes();
        }
    }
    /* Pre-populate the Scopes window so the first click on the
     * toolbar button already shows content rather than a blank cream
     * box. Without this initial call the user would see an empty
     * Scopes window until the page scrolls (utils.js's scope_on_scroll
     * is the only path that updates the body). Calling it now puts
     * the data in place before the user opens the window; the
     * `if (jQuery.scopesWindow.$scopes.children().length)` guard
     * inside _seedScopes() short-circuits any later update from
     * scope_on_scroll(). */
    _seedScopes();

    /* ── Debug helper exposed on window ──
     *
     * `window._opengrokDebugScopes()` returns a snapshot of the
     * current Scopes state so the user can paste it into a bug
     * report. Cheap to leave in production — the function is only
     * called manually from devtools. Also re-runs _scopeAtViewportTop
     * synchronously to give an immediate "what should the popup be
     * showing right now?" answer.
     *
     * Output keys:
     *   patchInstalled    – did our update() patch survive utils.js's
     *                      own init?
     *   popupVisible      – is $.scopesWindow.is(':visible') true?
     *   popupDisplay      – raw inline style.display
     *   $scopesChildren   – count of children currently inside $scopes
     *   $scopesHtml       – first 200 chars of the popup body
     *   chromeBottom      – y-coordinate where chrome ends
     *   wholeHeaderFound  – did our `#whole_header` shim find a target?
     *   scopeHeadCount    – total .scope-head elements in the document
     *   firstLineRect     – bounding rect of the first .l/.hl
     *   updateBeforeAfter – child count delta after one re-population */
    window._opengrokDebugScopes = function () {
        var info = {};
        try {
            var $win = jQuery('#scopes_win');
            info.scopesWinFound = $win.length;
            info.popupVisible = $win.is(':visible');
            info.popupDisplay = $win[0] && $win[0].style.display;
            var $body = _scopesBody();
            info.bodyFound = $body.length;
            if ($body.length) {
                info.bodyChildren = $body.children().length;
                var html = $body.html() || '';
                info.bodyHtml = html.length > 200 ?
                    html.substring(0, 200) + '…' : html;
            }
            info.wholeHeaderFound = $('#whole_header').length > 0;
            info.scopeHeadCount = $('#src .scope-head, #content .scope-head').length;
            var $firstLine = $('#src .l, #content .l').first();
            if ($firstLine.length) {
                var r = $firstLine[0].getBoundingClientRect();
                info.firstLineRect = { top: r.top, height: r.height };
            }
            var $wh = $('#whole_header');
            if ($wh.length) {
                info.chromeBottom =
                    $wh.offset().top + $wh.outerHeight();
            }
            if ($win.length) {
                var before = $body.length ? $body.children().length : 0;
                _scopeAtViewportTop();
                var $b2 = _scopesBody();
                var after = $b2.length ? $b2.children().length : 0;
                info.fillBeforeAfter = { before: before, after: after };
                if ($b2.length) {
                    var h2 = $b2.html() || '';
                    info.bodyHtmlAfter = h2.length > 200 ?
                        h2.substring(0, 200) + '…' : h2;
                }
            }
        } catch (err) {
            info.error = String(err);
        }
        try { console.info('[opengrok-debug] scopes', info); } catch (e) {}
        return info;
    };

    /* After pageReadyList() runs, both $.navigateWindow and
     * $.scopesWindow exist (scopesWindow was created earlier by the
     * utils.js `init_scopes()` call inside `$(document).ready`,
     * navigateWindow was created by pageReadyList). Re-park them to
     * the layout our `_layoutPopups()` helper expects so the very
     * first click on either button already starts from the right
     * default position rather than from utils.js's hardcoded
     * `top: 150px`. */
    if (typeof _layoutPopups === 'function') {
        _layoutPopups();
    }

    /* No popup-overlay suppression: utils.js needs to create the
     * scopesWindow / navigateWindow / intelliWindow jQuery-UI floating
     * windows itself. Removing the previous no-op shims here lets
     * init_scopes() and pageReadyList() do their job. */

    /* ── Fold ──
     *
     * The xref dump emits <a onclick="fold(this.parentNode.id)"
     * id="X_fold_icon"> with a global `fold(id)` function from
     * utils-0.0.48.js. That inline handler is enough on its own, but
     * utils.js loads *after* the dumped onclick is parsed and *before*
     * this pageReady callback runs (utils.js installs its own
     * `window.fold` synchronously), so by the time the user clicks the
     * fold icon, `window.fold` is utils.js's fold().
     *
     * We still install a `_fold` fallback here in case utils.js fails
     * to load. We deliberately do NOT add a delegated click handler —
     * that would cause the inline onclick AND the delegated handler
     * to both fire and cancel each other out (toggle twice = no
     * visible change).
     *
     * NOTE: the previous revision registered this in `domReady.push`,
     * but utils-0.0.48.js line 1532 has `for (let i in this.domReady)`
     * (note `this`, not `document`) — that loop iterates over an
     * undefined object's properties and the domReady callbacks never
     * fire. pageReady callbacks DO fire (utils-0.0.48.js line 1525–1528
     * iterates `document.pageReady` correctly), so all of the toolbar
     * click bindings live here now. */
    function _fold(id) {
        $('#' + id + '_fold_icon')
            .children()
            .first()
            .toggleClass('unfold-icon')
            .toggleClass('fold-icon');
        $('#' + id + '_fold').toggle('fold');
    }
    window.fold = _fold;

    /* ── Toolbar button handlers ──
     *
     * Each button is a thin wrapper around the utils.js plugin it
     * controls. The Line button still toggles an `.active` class to
     * mirror the gutter's `lines-hidden` body class (the user has no
     * other way to tell from the toolbar that the gutter is hidden);
     * the Scopes / Navigate buttons intentionally do NOT, since the
     * popup's own close (x) button can hide the window out-of-band
     * and the mirrored class would drift immediately. */

    /* Annotate: mirrors utils.js `get_annotations()`. When the JSP
     * has already computed a href (annotHref / xannotateHref), the
     * <a> tag itself navigates; otherwise we call get_annotations(). */
    $('#btn-annotate').on('click', function(e) {
        if ($(this).is('[disabled]') || $(this).attr('aria-disabled') === 'true') {
            e.preventDefault();
            return false;
        }
        const $a = $(this);
        if ($a.attr('href')) {
            return true;
        }
        e.preventDefault();
        if (typeof get_annotations === 'function') {
            get_annotations();
        }
        return false;
    });

    /* Line: toggle the line-number gutter. Mirrors lntoggle(). */
    $('#btn-line').on('click', function() {
        if (typeof lntoggle === 'function') lntoggle();
        $(this).toggleClass('active', $('body').hasClass('lines-hidden'));
        return false;
    });

    /* Scopes: toggle the jQuery-UI scopesWindow that utils.js creates
     * in init_scopes(). The window's `toggle()` method is installed
     * by the jQuery-UI Window plugin's `init` callback (utils-0.0.48.js
     * line 664) — once the plugin has run, `$.scopesWindow.toggle()`
     * works regardless of any internal `initialized` flag. We therefore
     * call it as long as the object exists.
     *
     * The vendored utils.js's `load` callback overrides the popup's
     * `show` method to also call `scope_on_scroll()` (utils-0.0.48.js
     * line 1166-1174). `scope_on_scroll()` uses
     * `document.elementFromPoint(15, y + 1)` where `y` is computed
     * from `#whole_header.outerHeight() + 2`. In the refactored chrome
     * the first 16px under the chrome is the `.code-content` padding
     * (line 329: `padding: 16px 0;`), so `elementFromPoint` returns
     * the `.code-content` wrapper, NOT a `.l/.hl` line anchor, and
     * `$(c).is('.l, .hl')` evaluates to false — the vendored update
     * is a no-op. We therefore MUST refresh the body ourselves on
     * every show, with our own layout-agnostic implementation.
     *
     * Visibility tracking: rather than `jQuery.scopesWindow.is(':visible')`
     * (which can give wrong answers in some edge cases — see the
     * ROOT-CAUSE block above) we read the popup's own inline `display`
     * style. The vendored `init` callback always sets the popup to
     * `display: none` at startup, and every `show()` call clears the
     * `display: none` (jQuery's `show` stores and removes the prior
     * `display` value). So a popup that is currently visible has
     * `style.display` !== 'none'. This is unambiguous and matches
     * what the user sees on screen, so the refresh logic below
     * fires on every "popup just opened" click and stays quiet on
     * "popup just closed" clicks.
     *
     * NOTE: the button itself intentionally does NOT keep an `.active`
     * class in sync with the popup's visibility. utils.js installs
     * its own popup-control and the close (x) link on the floating
     * window hides it without going through the toolbar button, so a
     * button-side `.active` mirror would drift out of sync as soon as
     * the user closes the popup via its own close button. The toolbar
     * therefore behaves as a plain toggle (like "Raw" and "Download"
     * in the original OpenGrok chrome) and lets the popup own its own
     * show/hide state. */
    document.getElementById('btn-scopes').addEventListener('click', function(e) {
        e.preventDefault();
        try {
            if (window.jQuery && jQuery.scopesWindow) {
                /* Snapshot the popup's `display` style BEFORE the
                 * toggle so we can tell which direction the click
                 * moved. The vendored `show` override clears
                 * `display: none` synchronously (it does NOT animate),
                 * so reading the new state right after `toggle()` is
                 * also fine, but a before/after diff is more obvious
                 * in the source and matches the original behaviour of
                 * the legacy `if (is(':visible'))` guard.
                 *
                 * We deliberately use the raw `style.display` here
                 * instead of jQuery's `is(':visible')` because the
                 * latter can give a wrong answer in two important
                 * edge cases: (1) when the popup is animated to/from
                 * `display: none` — the animation is over in real life
                 * but jQuery's heuristic still sees the inline
                 * `display: none`; (2) when our CSS specifies the
                 * popup as `position: fixed` with no explicit width
                 * and a child of `<body>`, jQuery's parent-chain check
                 * can flag a freshly shown popup as "not visible" if
                 * an ancestor of the popup happens to have a
                 * `display: none` style applied via a CSS variable
                 * that is missing on first paint. Reading the raw
                 * `style.display` is unambiguous and matches what the
                 * user actually sees on screen. */
                const wasHidden = jQuery.scopesWindow[0].style.display === 'none';
                jQuery.scopesWindow.toggle();
                const isShown = jQuery.scopesWindow[0].style.display !== 'none';
                if (isShown) {
                    /* Show the scope that contains the line currently
                     * at the top of the code viewport — i.e. whichever
                     * function the user is looking at. We use our own
                     * `_scopeAtViewportTop()` rather than relying on
                     * the vendored `scope_on_scroll()` (which is also
                     * auto-called by the overridden `show` method)
                     * because the new chrome's 16px top padding on
                     * `.code-content` makes the vendored function's
                     * `elementFromPoint(outerHeight() + 2)` miss every
                     * line anchor. Walking the `.l`/`.hl` rects is
                     * layout-agnostic and runs synchronously, so the
                     * popup updates in the same frame as the click
                     * and overwrites whatever the (failed) vendored
                     * update left behind. */
                    _scopeAtViewportTop();
                    /* Belt-and-suspenders: re-run on the next frame so
                     * the very first paint after a freshly-shown popup
                     * is computed against the actual post-show layout.
                     * Without this, a popup whose `.l`/`.hl` line
                     * anchors were below the viewport at click time
                     * (e.g. page just loaded, no scroll yet) ends up
                     * with the "No scope at the top of the view"
                     * placeholder even though on the very next tick
                     * the chrome has settled and a line is visible. */
                    requestAnimationFrame(function () {
                        try { _scopeAtViewportTop(); }
                        catch (e) { console.error('[opengrok] btn-scopes rAF refresh failed', e); }
                    });
                }
                _layoutPopups();
            } else {
                console.warn('[opengrok] scopesWindow not initialised yet');
            }
        } catch (err) {
            console.error('[opengrok] btn-scopes error', err);
        }
        return false;
    });

    /* Navigate: toggle the jQuery-UI navigateWindow that pageReadyList
     * creates (it also binds $('\#navigate').click → toggle, so the
     * hidden <a id="navigate"> we render above also works).
     *
     * NOTE: same rationale as btn-scopes — the button intentionally
     * does NOT keep an `.active` class in sync. The popup's own close
     * (x) button hides it without going through the toolbar, so a
     * mirrored `.active` class would drift the moment the user
     * dismisses the popup via its built-in close control. */
    document.getElementById('btn-navigate').addEventListener('click', function(e) {
        e.preventDefault();
        try {
            if (window.jQuery && jQuery.navigateWindow) {
                jQuery.navigateWindow.toggle();
                if (jQuery.navigateWindow.is(':visible') &&
                        jQuery.navigateWindow.$content &&
                        jQuery.navigateWindow.$content.children().length === 0) {
                    /* Late fill: the xref's inline get_sym_list() may
                     * only have become available after pageReady ran. */
                    const late = (typeof get_sym_list === 'function')
                        ? get_sym_list() : _symListFromDom();
                    if (late && late.length) {
                        jQuery.navigateWindow.update(late);
                    } else {
                        jQuery.navigateWindow.$content
                            .empty()
                            .append($('<h4>').text('No symbols for this file'));
                    }
                }
                _layoutPopups();
            } else if (window.jQuery && jQuery.intelliWindow) {
                jQuery.intelliWindow.toggleAndMove();
            } else {
                console.warn('[opengrok] navigateWindow not initialised yet');
            }
        } catch (err) {
            console.error('[opengrok] btn-navigate error', err);
        }
        return false;
    });

    /* ── Scopes / Navigate co-layout ──
     *
     * utils-0.0.48.js initialises BOTH windows with the same inline
     * `css({ top: '150px', right: '20px' })`, so they land in the exact
     * same corner. utils.js only dodges this one way (when scopes opens
     * first it nudges navigate below it); opening navigate first left
     * scopes stacked directly on top of it.
     *
     * `_layoutPopups()` enforces "scopes above navigate" on every
     * toggle: whichever is alone sits at DEFAULT_TOP, and when both are
     * up navigate is pinned below scopes' outerHeight + GAP. We animate
     * with .stop() so rapid clicks don't queue fighting animations. */
    function _layoutPopups() {
        if (!window.jQuery) return;
        const $scopes  = jQuery.scopesWindow;
        const $nav     = jQuery.navigateWindow;
        if (!$scopes || !$scopes.length || !$nav || !$nav.length) return;

        const scopesVisible  = $scopes.is(':visible');
        const navigateVisible = $nav.is(':visible');
        if (!scopesVisible && !navigateVisible) return;

        const DEFAULT_TOP = 80;     // px from viewport top
        const GAP         = 20;     // px gap between the two windows

        if (scopesVisible && navigateVisible) {
            // Both up: scopes at the default, navigate pinned just
            // under scopes. We measure scopes' outerHeight for the
            // offset; if the float isn't yet rendered the helper
            // returns 0 and the two stack — user will see that as
            // a one-frame flicker, which is acceptable.
            $scopes.stop(true, false).animate({ top: DEFAULT_TOP });
            const scopesBottom = $scopes.position().top + $scopes.outerHeight();
            $nav.stop(true, false).animate({ top: scopesBottom + GAP });
        } else if (scopesVisible) {
            $scopes.stop(true, false).animate({ top: DEFAULT_TOP });
        } else {
            $nav.stop(true, false).animate({ top: DEFAULT_TOP });
        }
    }
    // Expose for utils.js's own update() listeners (e.g. when scopes
    // auto-shows on first scroll) so the navigate window follows.
    window._layoutPopups = _layoutPopups;

    /* Wire _layoutPopups() to the jQuery show/hide events that
     * utils.js fires on the scopesWindow / navigateWindow elements.
     * utils.js itself registers internal listeners on the SAME
     * events for its own updatePosition bookkeeping; our listener
     * chains off them and only re-pins the top offsets so the two
     * windows never overlap. Without this, the
     * scopesWindow.update() helper (utils-0.0.48.js line 1182-1188)
     * can auto-show the scopes window as the user scrolls past the
     * first scope-head, leaving navigate out of sync. */
    if (window.jQuery && jQuery.scopesWindow && jQuery.scopesWindow.length) {
        jQuery.scopesWindow.on('show', _layoutPopups)
                          .on('hide', _layoutPopups);
    }
    if (window.jQuery && jQuery.navigateWindow && jQuery.navigateWindow.length) {
        jQuery.navigateWindow.on('show', _layoutPopups)
                            .on('hide', _layoutPopups);
    }

    /* ── Scopes popup scroll sync via IntersectionObserver ──
     *
     * Why IntersectionObserver and not scroll listeners?
     *
     * The previous revisions bound `scroll` listeners on
     * `#code-area` AND `window` and throttled with rAF. That still
     * fails to update the popup as the user scrolls past a function
     * boundary, for one or more of these reasons:
     *
     *   - The page may scroll on `document.documentElement` (the
     *     default scrollingElement in standards mode) rather than
     *     `window`, so neither `window.addEventListener('scroll', …)`
     *     nor `$area.addEventListener('scroll', …)` fires.
     *
     *   - A sticky .code-toolbar in front of #code-area can cause
     *     `getBoundingClientRect()` to report coordinates that don't
     *     match the scroll position the browser actually rendered.
     *
     *   - rAF throttling drops events when the user flings the
     *     trackpad and the page hits the scroll-end; the popup is
     *     left showing the scope from BEFORE the fling.
     *
     * IntersectionObserver sidesteps all of these: it watches the
     * line anchors themselves and the browser fires a callback
     * whenever any of them enters or leaves the viewport. We
     * observe the .l/.hl anchors under #src with a single root
     * (the actual scrolling container, or null = viewport) and an
     * 8-pixel top "shrinking band" so a line is "visible" only
     * when its top is at most 8px below the viewport's top edge.
     * That band approximates the "current line" the user is reading.
     *
     * Performance: thousands of `.l` anchors in a 50k-line file
     * could be expensive, but IntersectionObserver batches its
     * callbacks across a frame, so even an 8k-anchor dump observes
     * cleanly. We also debounce the callback's actual
     * `_fillScopesDom()` write — once per frame is enough; multiple
     * `.l` crossings in the same frame collapse into one update.
     *
     * Fallback: if IntersectionObserver is not available (very old
     * browsers, very rare sandboxed contexts), we fall back to a
     * window scroll listener + rAF. */
    (function _wireScopesScrollSync() {
        var _scopesObserverScheduled = false;
        if (!('IntersectionObserver' in window)) {
            /* Legacy fallback — duplicate of the previous revision's
             * strategy. */
            var rafScheduled = false;
            function _onScroll() {
                if (rafScheduled) return;
                rafScheduled = true;
                requestAnimationFrame(function () {
                    rafScheduled = false;
                    try { _scopeAtViewportTop(); }
                    catch (e) { console.error('[opengrok] scopes scroll sync failed', e); }
                });
            }
            window.addEventListener('scroll', _onScroll, { passive: true });
            return;
        }
        var $lines = jQuery('#src .l, #src .hl, #content .l, #content .hl');
        if (!$lines.length) return;
        /* Shrink the observation root from the bottom by a large
         * amount so a line is reported intersecting only when its
         * top edge has reached the viewport top — i.e. it just
         * crossed into view as the user scrolls DOWN. Lines whose
         * top is anywhere between the viewport top and 8px below
         * it count as "the current line". We do NOT shrink the top
         * because we want EVERY line that enters the viewport to
         * trigger us, even if only 1px of it is visible (so the
         * very first line of the file still triggers when the page
         * is at scrollY=0). */
        var viewportH = window.innerHeight || 800;
        var observer = new IntersectionObserver(function (entries) {
            /* Throttle the actual fill to one per frame: multiple
             * .l crossings within the same frame collapse into a
             * single _scopeAtViewportTop() call, which then picks
             * the uppermost visible line. */
            if (_scopesObserverScheduled) return;
            _scopesObserverScheduled = true;
            requestAnimationFrame(function () {
                _scopesObserverScheduled = false;
                try {
                    if (!window.jQuery || !jQuery.scopesWindow ||
                            !jQuery.scopesWindow.initialized) { return; }
                    if (!jQuery.scopesWindow.is(':visible')) { return; }
                    /* Walk every newly-intersecting entry (this frame
                     * may contain several if the user scrolled past a
                     * whole block of lines in one go). The first one
                     * whose isIntersecting=true AND boundingClientRect.top
                     * is closest to 0 is the current top-of-viewport
                     * line. */
                    var best = null;
                    var bestTop = Infinity;
                    for (var k = 0; k < entries.length; k++) {
                        var e = entries[k];
                        if (!e.isIntersecting) continue;
                        var t = e.boundingClientRect.top;
                        if (t >= 0 && t < bestTop) {
                            bestTop = t;
                            best = e.target;
                        }
                    }
                    if (best) {
                        /* Direct write — bypass _scopeAtViewportTop
                         * entirely. We know `best` is the uppermost
                         * line the observer just fired on, which by
                         * definition sits in the top 8px of the
                         * viewport. */
                        var $par = jQuery(best).closest('.scope-body, .scope-head');
                        if ($par.length) {
                            var $head = $par.hasClass('scope-body') ?
                                $par.prev() : $par;
                            var $sig = $head.children().first();
                            var rawHtml = ($sig.html() || $head.text() || '').trim();
                            var parenIdx = rawHtml.indexOf('(');
                            var shortName = (parenIdx > 0 ?
                                rawHtml.substring(0, parenIdx) :
                                rawHtml.substring(0, 80)).trim();
                            _fillScopesDom($head.attr('id'), shortName);
                        } else {
                            /* Line is outside any scope (file-level
                             * code). Show the first scope-head as a
                             * sensible default. */
                            _seedScopes();
                        }
                    } else {
                        /* No intersecting entry yet (e.g. user
                         * scrolled fast past all observed lines —
                         * shouldn't happen, but degrade gracefully). */
                        _scopeAtViewportTop();
                    }
                } catch (e) {
                    console.error('[opengrok] scopes observer failed', e);
                }
            });
        }, {
            /* root: null → use the viewport. */
            root: null,
            /* Shrink the root's bottom by everything below the top
             * 8px. A line anchor's rect must overlap the uppermost
             * 8px of the viewport to be considered intersecting.
             * That's the visual definition of "the line at the top
             * of the code view". */
            rootMargin: '0px 0px -' + Math.max(0, viewportH - 8) + 'px 0px',
            /* Even a single pixel of intersection counts — when the
             * line just barely scrolls into the top 8px, fire. */
            threshold: 0
        });
        /* Observe every .l / .hl. The IntersectionObserver batch
         * callback already coalesces entries, so observing thousands
         * of elements is fine. */
        for (var i = 0; i < $lines.length; i++) {
            observer.observe($lines[i]);
        }
        /* Stash for the debug helper. */
        window._opengrokScopesObserver = observer;
    })();

    /* The Scopes / Navigate buttons intentionally do NOT carry a
     * mirrored `.active` class. The popup's own close (x) link can
     * hide the window out-of-band (without going through the toolbar
     * button), so a button-side `.active` mirror would drift as soon
     * as the user dismissed the popup that way. The toolbar therefore
     * acts as a plain toggle and lets the popup own its own show/hide
     * state — matching the original OpenGrok chrome's behaviour. */

    /* Raw: navigate to the /raw/ URL of the current file so the browser
     * renders the plain file contents directly. The OpenGrok Raw
     * servlet (mapped under /raw/* by web.xml) serves the source
     * without any xref decoration. Clicking the toolbar button a
     * second time on the raw page navigates BACK to the xref view by
     * stripping the /raw/ prefix off the current URL.
     *
     * This matches the behaviour of the original OpenGrok deployment,
     * where the "Raw" menu entry was a plain `<a href="/raw/...">`
     * link and the only way to come back was the browser's back
     * button or a manual navigation — here we additionally offer a
     * one-click toggle so the toolbar button doubles as a round-trip
     * switch.
     *
     * The button stores the destination URL on data-raw-href (set in
     * the JSP above) so we don't have to recompute the path/revision
     * pair from the DOM — that recomputation would also be brittle if
     * someone renamed or moved the file between requests. */
    $('#btn-raw').on('click', function(e) {
        e.preventDefault();
        const btn = this;
        const rawHref = btn.getAttribute('data-raw-href');
        if (!rawHref) {
            console.warn('[opengrok] btn-raw: missing data-raw-href');
            return false;
        }
        const currentPath = window.location.pathname;
        /* The /raw/ prefix maps 1:1 to /xref/ via OpenGrok's
         * URL routing (web.xml mounts both servlets under the same
         * path scheme: /raw/foo.c ↔ /xref/foo.c). Detect a raw URL
         * by checking for the /raw/ segment and swapping it for
         * /xref/ on click to toggle back. */
        const isOnRaw = currentPath.indexOf('/raw/') !== -1;
        if (isOnRaw) {
            /* On the raw page — toggle back to xref. Strip the
             * /raw/ segment from the current URL, keep the query
             * string (which may carry ?r=<rev>) intact, and
             * navigate. */
            const xrefPath = currentPath.replace('/raw/', '/xref/');
            const target = xrefPath + (window.location.search || '') +
                           (window.location.hash || '');
            window.location.href = target;
        } else {
            /* On the xref page — toggle to raw. The data-raw-href
             * attribute is built from the same UriEncodedPath +
             * revision params we used for the breadcrumb so it stays
             * in sync with whatever the page rendered. */
            window.location.href = rawHref;
        }
        return false;
    });

    /* Goto Line: scroll the code area so the requested line is at the
     * top (anchor format `#<line>` matches the anchors emitted by the
     * dumped xref).
     *
     * We use the browser's native scrollIntoView() first — it walks up
     * to the anchor's nearest scrolling ancestor, which works across
     * the nested `overflow: auto` wrappers (.code-area > .code-content)
     * that a manual jQuery scrollTop calculation got wrong. The
     * explicit scrollTop() write afterwards is a fallback for browsers
     * without options-object support.
     *
     * Formula note: `offset().top` is document-absolute, so
     * `anchorTop - areaTop` already yields the in-content offset. Do
     * NOT add the current scrollTop — doing so double-counts the
     * existing scroll and the browser silently clamps the result
     * (the old "URL changes but the view doesn't move" bug). */
    function _gotoLine() {
        const $input = $('#goto-line-input');
        const n = parseInt($input.val(), 10);
        if (!n || n < 1) return false;
        const $anchor = $('#src').find('a[name="' + n + '"]');
        if (!$anchor.length) return false;

        // Native scrollIntoView first: lets the browser pick the
        // right scroll container (the nearest scrolling ancestor of
        // the anchor). behaviour: 'smooth' gives the same 250ms-ish
        // glide the old jQuery animate did, but works across nested
        // overflow: auto wrappers that the jQuery formula did not.
        try {
            $anchor[0].scrollIntoView({ block: 'start', behavior: 'smooth' });
        } catch (_) {
            try {
                $anchor[0].scrollIntoView();
            } catch (_) {
                /* Old browsers with no scrollIntoView at all — fall
                 * through to the explicit scrollTop write below. */
            }
        }

        // Belt-and-suspenders for browsers / edge cases where
        // scrollIntoView doesn't move #code-area (e.g. the anchor's
        // nearest scrolling ancestor is the inner .code-content
        // rather than the outer .code-area).
        //
        // Formula: anchor's document-absolute top minus the area
        // container's document-absolute top gives the anchor's
        // in-content offset. That IS the scrollTop we want — no
        // current-scroll addition, no over-counting.
        const $area = $('#code-area, #content').first();
        const anchorTop = $anchor.offset().top;
        const areaTop = $area.offset().top;
        if (Number.isFinite(anchorTop) && Number.isFinite(areaTop)) {
            const target = (anchorTop - areaTop) - 16;
            if (Number.isFinite(target)) {
                $area.scrollTop(Math.max(0, target));
            }
        }

        if (history.replaceState) {
            history.replaceState(null, '', '#' + n);
        } else {
            location.hash = '#' + n;
        }
        return false;
    }
    $('#goto-line-btn').on('click', _gotoLine);
    $('#goto-line-input').on('keydown', function(e) {
        if (e.key === 'Enter' || e.keyCode === 13) {
            return _gotoLine();
        }
    });
});
/* ]]> */
</script>
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
