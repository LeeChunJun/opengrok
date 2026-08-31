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

Copyright (c) 2009, 2026, Oracle and/or its affiliates. All rights reserved.
Portions Copyright 2011 Jens Elkner.
Portions Copyright (c) 2018, Chris Fraire <cfraire@me.com>.
Portions Copyright (c) 2026, UI Refactor.
--%>

<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page session="false" errorPage="error.jsp"%>
<%@ page import="
org.opengrok.indexer.web.Util"%>

<style>
:root {
    /* Theme colours are fragment-local. Font variables (--font-sans / --font-mono)
     * live in httpheader.jspf :root and are inherited from there. */
    --fg:        #24292f;
    --accent:    #0969da;
    --bg:        #f6f8fa;
    --border:    #d0d7de;
    --border-light: #eaeef2;
}

.status-page { max-width: 920px; font-size: 14px; color: var(--fg); line-height: 1.6; }
.status-page h1 { font-size: 22px; font-weight: 600; margin: 8px 0 12px; }
.status-page p { margin: 8px 0; }
.status-page code { background: var(--bg); padding: 1px 5px; border-radius: 3px;
    font-family: var(--font-mono); font-size: 12.5px; color: var(--accent); }
.status-page pre { background: var(--bg); border: 1px solid var(--border); border-radius: 6px;
    padding: 12px 14px; font-size: 12.5px; font-family: var(--font-mono);
    overflow-x: auto; line-height: 1.55; }
</style>

<%-- status.jsp start

    status.jsp -- OpenGrok status / diagnostics page. Uses pageheader.jspf +
    foot.jspf for the new chrome (no mast.jsp, since status is a static
    diagnostics page).
--%>
<%
{
    PageConfig _chromeStatusCfg = PageConfig.get(request);
    _chromeStatusCfg.setTitle("OpenGrok Status");
    _chromeStatusCfg.checkSourceRootExistence();
}
%>
<%@include file="/projects.jspf"%>
<%@include file="/pageheader.jspf" %>
<main class="container">
<div class="status-page">
    <h1>OpenGrok status page</h1>
    <p>This page is only used for testing purposes to dump some internal settings on your OpenGrok server.</p>
<%
{
    if (PageConfig.get(request).getEnv().isChattyStatusPage()) {
        Util.dumpConfiguration(out);
    } else {
%>
        <p>For security reasons, printing of internal settings is not enabled by default. To enable, set the property <code>chattyStatusPage</code> to <code>true</code> in <code>configuration.xml</code>.</p>
<%
    }
}
%>
</div>
</main>
<%@ include file="/foot.jspf" %>
<%= PageConfig.get(request).getScripts() %>
</body>
</html>