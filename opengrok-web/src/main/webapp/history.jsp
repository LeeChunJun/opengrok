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

<%-- history.jsp — directory / file history (per docs/ui/directory-history.html).

The chrome (header / compact-nav / breadcrumb / footer) is provided by
mast.jsp + foot.jspf; only the page-specific styles live here.
--%>

<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page errorPage="error.jsp" import="
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

<%
/* ---------------------- history.jsp setup (before chrome) ---------------------
 * Stay in a block so the chrome variables that mast.jsp declares do not collide
 * with anything we set here.
 */
{
    final Logger LOGGER = LoggerFactory.getLogger(getClass());
    PageConfig _historyCfg = PageConfig.get(request);
    _historyCfg.checkSourceRootExistence();

    /* Title is set here (before mast.jsp includes httpheader.jspf). */
    _historyCfg.setTitle(_historyCfg.getHistoryTitle());

    String path = _historyCfg.getPath();
    if (!path.isEmpty()) {
        String primePath = path;
        Project project = _historyCfg.getProject();
        if (project != null) {
            SearchHelper searchHelper = _historyCfg.prepareInternalSearch(SortOrder.RELEVANCY);
            request.setAttribute(SearchHelper.REQUEST_ATTR, searchHelper);
            searchHelper.prepareExec(project);
            try {
                primePath = searchHelper.getPrimeRelativePath(project.getName(), path);
            } catch (IOException | ForbiddenSymlinkException ex) {
                LOGGER.log(Level.WARNING, String.format("Error getting prime relative for '%s'", path), ex);
            }
        }
        File file = _historyCfg.getResourceFile(primePath);
        History hist;
        try {
            hist = HistoryGuru.getInstance().getHistoryUI(file);
        } catch (Exception e) {
            response.sendError(HttpServletResponse.SC_NOT_FOUND, e.getMessage());
            return;
        }
        if (hist == null) {
            response.sendError(HttpServletResponse.SC_NOT_FOUND);
            return;
        }
        request.setAttribute(_historyCfg.getHistoryAttrName(), hist);
    }
}
%>
<%-- Mark the History pill as active for this page. --%>
<% pageContext.setAttribute("activeNav", "history"); %>
<%@ include file="pageheader.jspf" %>
<main class="container">
<style>
/* ── history.jsp page-specific styles ── */
/* Page background + container centering — matches index.jsp / design.
 * httpheader.jspf declares the theme variables; we just pin body background
 * to --bg (same as the home page) and center the 1200px content column so
 * this page does not look pinned to the left edge against a white body. */
body { background: var(--bg); }
main.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 24px;
}
@media (max-width: 768px) {
    main.container { padding: 16px; }
}
@media (max-width: 600px) {
    main.container { padding: 12px; }
}

/* By default the modified-files block per revision is collapsed (hidden).
 * The shared utils-0.0.48.js toggle_filelist() only flips display/classes;
 * it does not toggle the anchor text. We override the click handler inline
 * on the anchor so the label flips between ">>> Show modified files" and
 * "<<< Hide modified files" in lockstep with the visibility change. */
.filelist-hidden { display: none; }
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
.history-title .path { font-family: var(--font-mono); font-size: 13px; color: var(--accent); }
.history-title .revtags-toggle-anchor {
    margin-left: auto;
    font-size: 12px;
    color: var(--accent);
    text-decoration: none;
    white-space: nowrap;
}
.history-title .revtags-toggle-anchor:hover { text-decoration: underline; }

.history-table-wrapper {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
}
.history-table { width: 100%; border-collapse: collapse; font-size: 13px; }
.history-table thead th {
    text-align: left;
    padding: 10px 12px;
    font-weight: 600;
    color: var(--fg);
    border-bottom: 2px solid var(--border);
    font-size: 12.5px;
    white-space: nowrap;
    vertical-align: bottom;
    background: #e0d9ac;
}
.history-table thead th .filelist-toggle-anchor {
    float: right;
    font-size: 12px;
    color: var(--accent);
    text-decoration: none;
    font-weight: 400;
}
.history-table thead th .filelist-toggle-anchor:hover { text-decoration: underline; }
.history-table td { padding: 10px 12px; border-bottom: 1px solid var(--border-light); vertical-align: top; }
.history-table tbody tr:hover { background: #f6f8fa; }
.history-table tbody tr:last-child td { border-bottom: none; }
.col-revision { width: 130px; }
.col-compare { width: 140px; text-align: center; }
.col-date { width: 90px; }
.col-author { width: 240px; }
.col-comments { width: auto; }

.revision-hash { font-family: var(--font-mono); font-size: 12.5px; color: var(--accent); text-decoration: none; cursor: pointer; }
.revision-hash:hover { text-decoration: underline; }
.revision-anchor { color: var(--muted); text-decoration: none; margin-right: 4px; font-family: var(--font-mono); font-size: 12.5px; }
.revision-anchor:hover { color: var(--accent); }
.revision-radio { display: flex; gap: 8px; align-items: center; justify-content: center; font-size: 11.5px; color: var(--muted); }
.revision-radio label { display: inline-flex; align-items: center; gap: 3px; cursor: pointer; }
.revision-radio input[type="radio"] { margin: 0; accent-color: var(--accent); cursor: pointer; }

.compare-btn {
    display: inline-block;
    padding: 4px 14px;
    border: 1px solid var(--border);
    background: #f6f8fa;
    border-radius: 6px;
    font-size: 12px;
    font-weight: 600;
    color: var(--fg);
    font-family: var(--font-sans);
    cursor: pointer;
    text-decoration: none;
    transition: background 0.12s, border-color 0.12s, color 0.12s;
}
.compare-btn:hover { background: #eaeef2; border-color: var(--accent); color: var(--accent); }
.compare-btn:disabled { opacity: 0.5; cursor: not-allowed; }

.date-day { font-size: 13px; color: var(--fg); font-family: var(--font-mono); font-variant-numeric: tabular-nums; white-space: nowrap; }
.date-year { font-size: 11px; color: var(--muted); font-family: var(--font-mono); font-variant-numeric: tabular-nums; white-space: nowrap; margin-top: 2px; }

.author-name { font-size: 13px; font-weight: 500; word-break: break-word; }
.author-name a { color: var(--fg); text-decoration: none; }
.author-name a:hover { color: var(--accent); text-decoration: underline; }
.author-email { font-size: 11.5px; color: var(--muted); word-break: break-all; margin-top: 2px; font-family: var(--font-mono); }

.comment-entry { margin-bottom: 4px; font-size: 13px; line-height: 1.5; word-break: break-word; }
.comment-entry::before { content: '\2022  '; color: var(--muted); }
.comment-entry.bullet::before { content: '*  '; color: var(--muted); }
.comment-separator { font-size: 11px; color: var(--muted); margin: 4px 0; font-family: var(--font-mono); }
.co-authored { font-size: 11.5px; color: var(--muted); margin-top: 6px; margin-bottom: 4px; word-break: break-word; }
.rev-message-summary, .rev-message-full { font-size: 13px; line-height: 1.5; word-break: break-word; margin: 0 0 4px; }
.rev-message-hidden { display: none; }
.rev-message-toggle { margin: 4px 0; font-size: 12px; }
.rev-message-toggle a { color: var(--accent); text-decoration: none; }
.rev-message-toggle a:hover { text-decoration: underline; }

.filelist, .filelist-hidden { margin-top: 6px; }
.filelist > a, .filelist-hidden > a {
    display: block;
    font-family: var(--font-mono);
    font-size: 11.5px;
    color: var(--accent);
    text-decoration: none;
    line-height: 1.7;
    word-break: break-all;
}
.filelist > a:hover, .filelist-hidden > a:hover { text-decoration: underline; }

tr.revtags td { background: var(--accent-dim); border-bottom: 1px solid var(--border-light); font-size: 12.5px; color: var(--fg); }
tr.revtags .bold { font-weight: 600; }
tr.revtags-hidden { display: none; }

.pagination {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 4px;
    padding: 20px 0 8px;
    flex-wrap: wrap;
}
.pagination a, .pagination span {
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
.pagination a:hover { background: #f3f4f6; border-color: #ccc; }
.pagination span.sel { background: var(--accent); color: #fff; border-color: var(--accent); cursor: default; }
.pagination span:not(.sel) { border-color: transparent; background: transparent; cursor: default; }

.strike-note { font-size: 12.5px; color: var(--muted); margin: 16px 0 0; }
.strike-note del { color: var(--muted); }

.rssbadge { margin: 16px 0 0; font-size: 12.5px; }
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

@media (max-width: 600px) {
    .history-table-wrapper { border-radius: 8px; overflow-x: auto; -webkit-overflow-scrolling: touch; }
    .history-table { min-width: 700px; font-size: 13px; }
    .col-author { width: 200px; }
    .col-date { width: 70px; }
    .col-revision { width: 110px; }
    .col-compare { width: 130px; }
}
</style>
<%
/* ---------------------- history.jsp body --------------------- */
{
    PageConfig _historyCfg = PageConfig.get(request);
    String context = request.getContextPath();
    String path = _historyCfg.getPath();
    History hist;

    if ((hist = (History) request.getAttribute(_historyCfg.getHistoryAttrName())) != null) {
        int startIndex = _historyCfg.getStartIndex();
        int max = _historyCfg.getMaxItems();
        long totalHits = hist.getHistoryEntries().size();
        long thisPageIndex = Math.min(totalHits - startIndex, max);

        request.setAttribute("history.jsp-slider", Util.createSlider(startIndex, max, totalHits, request));

        RuntimeEnvironment env = _historyCfg.getEnv();
        String uriEncodedName = _historyCfg.getUriEncodedPath();
        Project project = _historyCfg.getProject();

        boolean striked = false;
        String userPage = env.getUserPage();
        String userPageSuffix = env.getUserPageSuffix();
        String bugPage = project != null ? project.getBugPage() : env.getBugPage();
        String bugRegex = project != null ? project.getBugPattern() : env.getBugPattern();
        Pattern bugPattern = null;
        if (bugRegex != null) { bugPattern = Pattern.compile(bugRegex); }
        String reviewPage = project != null ? project.getReviewPage() : env.getReviewPage();
        String reviewRegex = project != null ? project.getReviewPattern() : env.getReviewPattern();
        Pattern reviewPattern = null;
        if (reviewRegex != null) { reviewPattern = Pattern.compile(reviewRegex); }

        Format dayFmt = new SimpleDateFormat("M\u6708d\u65e5", Locale.CHINA);
        Format yearFmt = new SimpleDateFormat("yyyy\u5e74", Locale.CHINA);

        int revision2Index = Math.max(_historyCfg.getIntParam(QueryParameters.REVISION_2_PARAM, -1), 0);
        int revision1Index = _historyCfg.getIntParam(QueryParameters.REVISION_1_PARAM, -1) < revision2Index ?
                revision2Index + 1 : _historyCfg.getIntParam(QueryParameters.REVISION_1_PARAM, -1);
        revision2Index = revision2Index >= hist.getHistoryEntries().size() ? hist.getHistoryEntries().size() - 1 : revision2Index;

        String subPath = path;
        if (project != null) {
            String prefix = "/" + project.getName();
            if (subPath.startsWith(prefix)) subPath = subPath.substring(prefix.length());
        }
        if (subPath.startsWith("/")) subPath = subPath.substring(1);
        while (subPath.endsWith("/")) subPath = subPath.substring(0, subPath.length() - 1);
        String titlePathStr;
        if (project != null) {
            titlePathStr = "/" + project.getName()
                    + (subPath.isEmpty() ? "/" : "/" + subPath + (_historyCfg.isDir() ? "/" : ""));
        } else {
            titlePathStr = subPath.isEmpty() ? "/" : ("/" + subPath + (_historyCfg.isDir() ? "/" : ""));
        }
%>
    <div class="history-title">
        History log of <span class="path"><%= Util.htmlize(titlePathStr) %></span>
        (Results <strong> <%= totalHits != 0 ? startIndex + 1 : 0 %> &#8211; <%= startIndex + thisPageIndex %></strong> of <strong><%= totalHits %></strong>)
        <% if (hist.hasTags()) { %>
        <a href="#" class="revtags-toggle-anchor" onclick="toggle_revtags(); return false;">&lt;&lt;&lt; Hide revision tags</a>
        <% } %>
    </div>
    <div class="history-table-wrapper">
        <form action="<%= context + Prefix.DIFF_P + uriEncodedName %>" id="compare-form" data-od-id="compare-form">
        <input type="hidden" id="input_r1" name="r1" value="<%= revision1Index < hist.getHistoryEntries().size() ? (path + "@" + hist.getHistoryEntries().get(revision1Index).getRevision()) : "" %>" />
        <input type="hidden" id="input_r2" name="r2" value="<%= revision2Index < hist.getHistoryEntries().size() ? (path + "@" + hist.getHistoryEntries().get(revision2Index).getRevision()) : "" %>" />
        <table class="history-table" aria-label="table of revisions">
            <thead>
                <tr>
                    <th class="col-revision">Revision</th>
                    <% if (!_historyCfg.isDir()) { %>
                    <th class="col-compare"><button type="submit" class="compare-btn" id="compare-submit" data-od-id="compare-submit">Compare</button></th>
                    <% } %>
                    <th class="col-date">Date</th>
                    <th class="col-author">Author</th>
                    <th class="col-comments">Comments
                        <% if (hist.hasFileList()) { %>
                        <a href="#" class="filelist-toggle-anchor"
                           data-default-label="&gt;&gt;&gt; Show modified files"
                           onclick="return toggleFilelistLabel(this);">&gt;&gt;&gt; Show modified files</a>
                        <% } %>
                    </th>
                </tr>
            </thead>
            <tbody>
                <%
                java.util.Map<String, String> tagsMap = hist.getTags();
                for (java.util.Map.Entry<String, String> tagEntry : tagsMap.entrySet()) {
                    String tags = tagEntry.getValue();
                    if (tags != null && !tags.isEmpty()) { %>
                <tr class="revtags-hidden">
                    <td colspan="<%= _historyCfg.isDir() ? 4 : 5 %>">
                        <span class="bold">Revision tags:</span> <%= Util.htmlize(tags) %>
                    </td>
                </tr>
                <%      }
                }
                int count=0;
                for (HistoryEntry entry : hist.getHistoryEntries(max, startIndex)) {
                    if (Objects.isNull(entry)) continue;

                    final String htmlEncodedDisplayRevision = Optional.ofNullable(entry.getDisplayRevision()).
                            map(Util::htmlize).
                            orElse("");
                    final String rev = Optional.ofNullable(entry.getRevision()).
                            orElse("");
                %>
                <tr>
                    <td class="col-revision"><%
                        if (_historyCfg.isDir()) { %>
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
                        <%      } else {
                                striked = true;
                        %>
                        <del><%= htmlEncodedDisplayRevision %></del>
                        <%      }
                        } %>
                    </td>
                    <% if (!_historyCfg.isDir()) { %>
                    <td class="col-compare"><%
                        if (entry.isActive()) { %>
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
                                    %> <%
                                } else if (count + startIndex == revision1Index) {
                                    %> checked="checked"<%
                                } else if (count + startIndex <= revision2Index) {
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
                                    %> <%
                                } else if (count + startIndex == revision2Index) {
                                    %> checked="checked" <%
                                } else if (count + startIndex >= revision1Index) {
                                    %> disabled="disabled" <%
                                }
                                %>/>
                                <span>To</span>
                            </label>
                        </div>
                        <% } %>
                    </td>
                    <% } %>
                    <td class="col-date"><%
                        Date date = entry.getDate();
                        if (date != null) { %>
                        <div class="date-day"><%= dayFmt.format(date) %></div>
                        <div class="date-year"><%= yearFmt.format(date) %></div><%
                        } %>
                    </td>
                    <td class="col-author"><%
                        String author = entry.getAuthor();
                        if (author == null) { %>
                        <div class="author-name">(no author)</div><%
                        } else if (userPage != null && !userPage.isEmpty()) {
                            String alink = Util.getEmail(author); %>
                        <div class="author-name"><a href="<%= userPage + Util.htmlize(alink) + userPageSuffix %>"><%= Util.htmlize(author)%></a></div>
                        <div class="author-email">&lt;<%= Util.htmlize(alink) %>&gt;</div><%
                        } else { %>
                        <div class="author-name"><%= Util.htmlize(author) %></div><%
                        } %>
                    </td>
                    <td class="col-comments"><a id="<%= htmlEncodedDisplayRevision %>"></a><%
                        int summaryLength = Math.max(10, _historyCfg.getRevisionMessageCollapseThreshold());
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

                        if (showSummary) { %>
                        <p class="rev-message-summary"><%= coutSummary %></p>
                        <p class="rev-message-full rev-message-hidden"><%= cout %></p>
                        <p class="rev-message-toggle" data-toggle-state="less"><a class="rev-toggle-a" href="#">show more ... </a></p><%
                        } else { %>
                        <p class="rev-message-full"><%= cout %></p><%
                        }

                        Set<String> files = entry.getFiles();
                        if (files != null) { %>
                        <div class="filelist-hidden"><%
                            for (String ifile : files) {
                                ifile = Util.fixPathIfWindows(ifile);
                                String jfile = Util.stripPathPrefix(path, ifile);
                                if (Objects.equals(rev, "")) { %>
                            <a href="<%= context + Prefix.XREF_P + Util.uriEncodePath(ifile) %>"><%= Util.htmlize(jfile) %></a><%
                                } else { %>
                            <a href="<%= context + Prefix.XREF_P + Util.uriEncodePath(ifile) + "?" + QueryParameters.REVISION_PARAM_EQ + Util.uriEncode(rev) %>"><%= Util.htmlize(jfile) %></a><%
                                }
                            } %>
                        </div><%
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
<%
        if (hist.hasFileList()) {
%>
<script>
/* Local override of the shared utils-0.0.48.js toggle_filelist():
 * the shared helper only flips div visibility/classes — it does not
 * touch the anchor label. Per the design (docs/ui/directory-history.html)
 * the "Hide/Show modified files" anchor text must move in lockstep
 * with the visibility change. We keep the shared helper for the actual
 * div toggle and only manage the label here.
 *
 * Initial state: every <div class="filelist-hidden">…</div> block per
 * revision is rendered with class "filelist-hidden", and the CSS rule
 * `.filelist-hidden { display: none; }` collapses them by default. The
 * anchor therefore starts with the ">>> Show modified files" label. */
function toggleFilelistLabel(anchor) {
    if (typeof toggle_filelist === 'function') {
        toggle_filelist();
    }
    /* Detect post-toggle visibility by looking at the first .filelist
     * block on the page (after toggle_filelist, all blocks now share
     * the same class — either all visible or all hidden). */
    var anyVisible = document.querySelector('div.filelist') !== null;
    anchor.textContent = anyVisible
        ? '\u00AB\u00AB\u00AB Hide modified files'
        : '\u00BB\u00BB\u00BB Show modified files';
    return false;
}
</script>
<%
        }
    }
}
%>
</main>
<%@ include file="foot.jspf" %>
<%= PageConfig.get(request).getScripts() %>
</body>
</html>
