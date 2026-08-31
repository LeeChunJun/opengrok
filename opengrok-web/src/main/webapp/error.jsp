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
Portions Copyright (c) 2018, Chris Fraire <cfraire@me.com>.
Portions Copyright (c) 2026, UI Refactor.
--%>

<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page session="false" isErrorPage="true" import="
java.io.PrintWriter,
java.io.StringWriter,

org.opengrok.indexer.web.Util,
jakarta.servlet.http.HttpServletResponse"%>

<style>
:root {
    /* Theme colours are fragment-local. Font variables (--font-sans / --font-mono)
     * live in httpheader.jspf :root and are inherited from there. */
    --fg:        #24292f;
    --bg:        #f6f8fa;
    --border:    #d0d7de;
    --border-light: #eaeef2;
}

.error-page { max-width: 920px; font-size: 14px; color: var(--fg); line-height: 1.6; }
.error-page h3 { font-size: 18px; font-weight: 600; margin: 8px 0 12px; color: #cf222e; }
.error-page p { margin: 8px 0; }
.error-page p.error { color: #cf222e; }
.error-page pre {
  background: var(--bg); border: 1px solid var(--border); border-radius: 6px;
  padding: 12px 14px; font-size: 12.5px; font-family: var(--font-mono);
  overflow-x: auto; line-height: 1.55; color: var(--fg); white-space: pre-wrap;
}
</style>

<%-- error.jspf start

    error.jsp -- generic 500 error page (isErrorPage=true). Uses
    pageheader.jspf + foot.jspf for the new chrome.
--%>
<%
/* ---------------------- error.jsp start --------------------- */
{
    PageConfig _chromeErrorCfg = PageConfig.get(request);
    _chromeErrorCfg.setTitle("OpenGrok Error!");

    // Set status to Internal error. This should help to avoid caching
    // the page by some proxies.
    response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
}
%>
<%@include file="/pageheader.jspf" %>
<main class="container">
<div class="error-page">
<%
{
    PageConfig _chromeErrorCfg = PageConfig.get(request);
    String configError = "";
    if (_chromeErrorCfg.getSourceRootPath() == null || _chromeErrorCfg.getSourceRootPath().isEmpty()) {
        configError = "The source root path has not been configured! "
            + "Please configure your webapp.";
    } else if (!_chromeErrorCfg.getEnv().getSourceRootFile().isDirectory()) {
        configError = "The source root " +  _chromeErrorCfg.getEnv().getSourceRootPath()
            + " specified in your configuration does "
            + "not point to a valid directory! Please configure your webapp.";
    }
%>
    <h3>There was an error!</h3>
    <p><%= configError %></p>

    <% if (exception != null) { %>
    <p><%= exception.getMessage() %></p>
    <pre>
    <%
        StringWriter wrt = new StringWriter();
        PrintWriter prt = new PrintWriter(wrt);
        exception.printStackTrace(prt);
        prt.close();
        out.write(Util.htmlize(wrt.toString()));
    %>
    </pre>
    <% } else { %>
    <p>Unknown Error</p>
    <% } %>
<%
}
%>
</div>
</main>
<%@ include file="/foot.jspf" %>
<%= PageConfig.get(request).getScripts() %>
</body>
</html>