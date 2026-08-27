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
    font-family: monospace;
    overflow: hidden;
    z-index: 10;
}
.window-header {
    padding: 10px;
    min-height: 20px;
    border-bottom: 1px solid black;
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
    background: rgb(255, 255, 204);
    background-color: rgb(255, 255, 204);
}
#intelli_win .window-body,
#scopes_win .window-body,
#navigate_win .window-body {
    background: rgb(255, 255, 204);
    background-color: rgb(255, 255, 204);
}
#intelli_win a,
#scopes_win a,
#navigate_win a {
    color: #0000ee;
    text-decoration: underline;
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
#intelli_win h5,
#scopes_win h2,
#scopes_win h5,
#navigate_win h2,
#navigate_win h5 {
    color: #333;
    margin: 6px 0 4px;
    font-size: 12px;
}
#intelli_win h2 {
    font-size: 16px;
    font-weight: 700;
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
 * The `.active` class on a toolbar button is synced to its window's
 * `:visible` state via the `show`/`hide` jQuery events the plugin
 * fires — no manual bookkeeping needed.
 */
document.pageReady.push(function() {
    /* Delegate the heavy lifting to the upstream pageReadyList(). It
     * already does everything the original Apache-tomcat deployment
     * did: initialises $.navigateWindow, populates it from
     * get_sym_list(), binds the #navigate click, and (through the
     * intelliWindow load callback) wires up the 1-8/n/b keyboard
     * shortcuts and the hover handler on a.intelliWindow-symbol. */
    if (typeof pageReadyList === 'function') {
        pageReadyList();
    } else if (document.highlight_count === undefined) {
        document.highlight_count = 0;
    }

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
     * controls. We sync the `.active` class with the window's
     * `:visible` state via the `show`/`hide` events utils.js fires. */

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
     * call it as long as the object exists. We also flip the button's
     * `.active` class synchronously so the visual stays in sync even
     * if the `show`/`hide` events are silenced for some reason. */
    document.getElementById('btn-scopes').addEventListener('click', function(e) {
        e.preventDefault();
        const $btn = document.getElementById('btn-scopes');
        try {
            if (window.jQuery && jQuery.scopesWindow) {
                jQuery.scopesWindow.toggle();
                const visible = jQuery.scopesWindow.is(':visible');
                $btn.classList.toggle('active', visible);
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
     * hidden <a id="navigate"> we render above also works). */
    document.getElementById('btn-navigate').addEventListener('click', function(e) {
        e.preventDefault();
        const $btn = document.getElementById('btn-navigate');
        try {
            if (window.jQuery && jQuery.navigateWindow) {
                jQuery.navigateWindow.toggle();
                const visible = jQuery.navigateWindow.is(':visible');
                $btn.classList.toggle('active', visible);
                _layoutPopups();
            } else if (window.jQuery && jQuery.intelliWindow) {
                jQuery.intelliWindow.toggleAndMove();
                const visible = jQuery.intelliWindow.is(':visible');
                $btn.classList.toggle('active', visible);
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
     * utils-0.0.48.js (lines 1153, 1224) initialises both
     * `$.scopesWindow` and `$.navigateWindow` with the SAME inline
     * `css({ top: '150px', right: '20px' })`. The two jQuery-UI
     * floating windows therefore live in the exact same corner of
     * the viewport — opening the second one stacks on top of the
     * first and the lower one disappears behind the upper one.
     *
     * utils-0.0.48.js attempts to dodge this for navigateWindow only
     * (lines 1234-1248 + 1307-1310): when scopesWindow's `show`
     * event fires, navigateWindow re-runs `updatePosition()` which
     * moves navigate to `scopes.position().top + scopes.outerHeight()
     * + 20`. That logic only works ONE WAY:
     *
     *   1. scopes opens FIRST, then navigate opens → updatePosition
     *      correctly parks navigate below scopes. Works.
     *   2. navigate opens FIRST, then scopes opens → utils.js never
     *      nudges scopes, so scopes pops up at (150, 20) directly on
     *      top of navigate. Both buttons show "active" but only one
     *      popup is visible. Broken — matches the original report.
     *
     * Our fix: every time the user clicks Scopes or Navigate, run
     * `_layoutPopups()` to enforce the rule "scopes above navigate".
     * - scopes visible alone: park scopes at the default top.
     * - navigate visible alone: park navigate at the default top.
     * - both visible:           scopes at default top, navigate pinned
     *                           just below scopes' outerHeight + 20px
     *                           gap so they don't overlap.
     * - neither visible:        leave them alone (the previous hide
     *                           animation has already parked them off
     *                           whatever position they had).
     *
     * We always pin via `.stop().animate({ top })` to match the
     * behaviour utils.js uses elsewhere; .stop() prevents queues of
     * pending animations from fighting each other when the user
     * clicks the buttons quickly. */
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

    /* The Scopes/Navigate .active class is now toggled directly inside
     * each button's click handler (synchronous with the show()/hide()
     * call), so we don't need any deferred sync code. */

    /* Raw: replace the rendered xref with the plain file contents. The
     * original utility toggled a "raw mode" class on the <pre> so all
     * syntax colouring is dropped; we replicate that on `.code-area`
     * (which is the wrapper that holds the dumped xref) and re-trigger
     * the spaces plugin so line numbers stay in sync. */
    $('#btn-raw').on('click', function() {
        const $area = $('#code-area');
        const goingRaw = !$area.hasClass('raw-mode');
        $area.toggleClass('raw-mode', goingRaw);
        $(this).toggleClass('active', goingRaw);
        return false;
    });

    /* Goto Line: scroll the code area so the requested line is at the
     * top, and highlight it (anchor format `#<line>` matches the
     * anchors emitted by the dumped xref).
     *
     * Implementation note: the previous implementation used
     *     $area.animate({ scrollTop: $area.scrollTop()
     *                      + ($anchor.offset().top - $area.offset().top)
     *                      - 16 }, 250);
     * Two bugs combined to make it silently fail:
     *
     *   1. The new chrome wraps the xref in
     *      `<main class="code-area" id="code-area">
     *         <div class="code-content" id="code-content"> … </div>
     *       </main>`
     *      where `.code-content` carries its own `overflow: auto`
     *      (rule ".code-area .code-content"). When that inner wrapper
     *      is shorter than its child it doesn't actually scroll, so
     *      the jQuery animate fires but the visible scrollTop of
     *      #code-area never moves.
     *
     *   2. The formula added `$area.scrollTop()` to the delta, which
     *      double-counted the existing scroll. `offset().top` is in
     *      document-absolute coordinates, so subtracting
     *      `$area.offset().top` already gives the in-content offset —
     *      the current scroll position must NOT be added again.
     *      When the user had scrolled into a long file, the result
     *      was over `scrollHeight - clientHeight`, the browser
     *      silently clamped it, and the view didn't move.
     *
     * We delegate to the browser's native
     * scrollIntoView({ block: 'start' }) first — it walks up to the
     * nearest scrolling ancestor of the anchor itself, which is
     * #code-area, regardless of any intermediate wrapper. We then
     * fall back to a direct scrollTop() write on #code-area using
     * the corrected formula (anchorTop - areaTop - 16) so any older
     * browser without options-object support still lands on the
     * right line. */
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
        const $area = $('#code-area');
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
    function _gotoLine() {
        const $input = $('#goto-line-input');
        const n = parseInt($input.val(), 10);
        if (!n || n < 1) return false;
        const $anchor = $('#src').find('a[name="' + n + '"]');
        if (!$anchor.length) return false;

        // Native scrollIntoView: lets the browser pick the right
        // scroll container. behaviour:'smooth' gives the same 250ms-ish
        // glide the old jQuery animate did, but works across nested
        // overflow:auto wrappers that the jQuery formula did not.
        try {
            $anchor[0].scrollIntoView({ block: 'start', behavior: 'smooth' });
        } catch (_) {
            // Old browsers that don't accept the options object —
            // fall back to the legacy signature.
            $anchor[0].scrollIntoView();
        }

        // Belt-and-suspenders: also push #code-area itself so its
        // scrollTop matches the anchor position, in case the inner
        // .code-content wrapper absorbed some of the scroll instead.
        //
        // The previous formula added $area.scrollTop() to the delta,
        // which double-counted the existing scroll (the offset of an
        // element is already in document-absolute coords, so subtracting
        // $area's offset.top gives the in-content offset directly).
        // That double-counting was harmless when the area was at
        // scrollTop 0, but if the user had already scrolled, it
        // pushed the view off-screen (and silently failed when the
        // result overflowed the scrollable range, which is why the
        // symptom was "URL changes, view doesn't move").
        const $area = $('#code-area');
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
