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
Portions Copyright (c) 2026, UI Refactor.
--%>

<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page session="false" errorPage="error.jsp" import="
java.text.SimpleDateFormat,
java.util.Set,

org.opengrok.indexer.history.DirectoryHistoryReader,
org.opengrok.indexer.history.History,
org.opengrok.indexer.history.HistoryEntry,
org.opengrok.indexer.history.HistoryGuru,
org.opengrok.indexer.web.Util,
org.opengrok.indexer.web.Prefix,
org.opengrok.web.PageConfig,
jakarta.servlet.http.HttpServletResponse"%>

<%
/* ---------------------- rss.jsp start ---------------------
 *
 * RSS 2.0 feed for the history of a file or directory. Produces
 * raw XML — not HTML — and does not use the new chrome
 * (pageheader.jspf / foot.jspf). Authorization / redirect handling
 * must happen before any output is written, so the early-exit
 * branch is kept at the top of the body block.
 *
 * Variables are prefixed `_rss_` so the calling JSP's body block
 * (which does not exist here — this is a toplevel jsp) does not
 * collide with anything in the chrome fragments.
 */
{
    PageConfig _rssCfg = PageConfig.get(request);
    _rssCfg.checkSourceRootExistence();

    String _rssRedirectLocation = _rssCfg.canProcess();
    if (_rssRedirectLocation == null || !_rssRedirectLocation.isEmpty()) {
        if (_rssRedirectLocation != null) {
            response.sendRedirect(_rssRedirectLocation);
        } else {
            response.sendError(HttpServletResponse.SC_NOT_FOUND);
        }
        return;
    }
    String _rssPath = _rssCfg.getPath();
    response.setContentType("text/xml");
%>

<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="<%= request.getContextPath() %>/rss.xsl.xml"?>
<rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel>
    <title>Changes in <%= _rssPath.isEmpty()
        ? "Cross Reference"
        : Util.htmlize(_rssCfg.getResourceFile().getName()) %>
    </title>
    <description><%= Util.htmlize(_rssCfg.getDefineTagsIndex()) %></description>
    <language>en</language>
    <copyright>Copyright 2026</copyright>
    <generator>Java</generator>
<%
    History _rssHistory;
    if (_rssCfg.isDir()) {
        _rssHistory = new DirectoryHistoryReader(_rssCfg.getHistoryDirs()).getHistory();
    } else {
        _rssHistory = HistoryGuru.getInstance().getHistory(_rssCfg.getResourceFile());
    }
    if (_rssHistory != null) {
        int _rssI = 20;
        for (HistoryEntry _rssEntry : _rssHistory.getHistoryEntries()) {
            if (_rssI-- <= 0) {
                break;
            }
            if (_rssEntry.isActive()) {
%>
    <item>
        <title>
        <%
            /*
             * Newlines would result in HTML tags inside the 'title' which
             * causes the title to be displayed as 'null'. Print first line
             * of the message. The whole message will be printed in description.
             */
            String _rssReplaced = _rssEntry.getMessage().split("\n")[0];
        %>
        <%= Util.htmlize(_rssEntry.getRevision()) %> - <%= Util.htmlize(_rssReplaced) %>
        </title>

        <link>
        <%
            String _rssRequestUrl = request.getScheme() +
                    "://" +
                    _rssCfg.getServerName() +
                    ":" +
                    request.getLocalPort() +
                    Util.uriEncodePath(request.getContextPath()) +
                    Prefix.HIST_L +
                    Util.uriEncodePath(_rssCfg.getPath()) +
                    "#" +
                    Util.uriEncode(_rssEntry.getRevision());
        %>
        <%= _rssRequestUrl %>
        </link>

        <description>
        <%  for (String _rssE : _rssEntry.getMessage().split("\n")) { %>
            <%= Util.htmlize(_rssE) %>
        <%  } %>

            List of files:
            <%
            if (_rssCfg.isDir()) {
                Set<String> _rssFiles = _rssEntry.getFiles();
                if (_rssFiles != null) {
                    for (String _rssEntryFile : _rssFiles) {
            %>
                        <%= Util.htmlize(_rssEntryFile) %>
            <%
                    }
                }
            } else {
            %><%= Util.htmlize(_rssPath) %><%
            }
        %>
        </description>

        <pubDate>
        <% SimpleDateFormat _rssDf = new SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss Z");%>
        <%= Util.htmlize(_rssDf.format(_rssEntry.getDate())) %>
        </pubDate>
        <dc:creator><%= Util.htmlize(_rssEntry.getAuthor()) %></dc:creator>
    </item>
<%
            }
        }
    }
%>
</channel>
</rss>
<%
}
/* ---------------------- rss.jsp end --------------------- */
%>
