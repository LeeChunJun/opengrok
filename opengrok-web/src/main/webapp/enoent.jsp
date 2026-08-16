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
<%@ page session="false" errorPage="error.jsp" isErrorPage="true"%>

<style>
:root {
    --fg:        #24292f;
}

.enoent-page { max-width: 920px; font-size: 14px; color: var(--fg); line-height: 1.6; }
.enoent-page h3 { font-size: 18px; font-weight: 600; margin: 8px 0 12px; color: #cf222e; }
.enoent-page p { margin: 8px 0; }
</style>

<%-- enoent.jsp start

    enoent.jsp -- 404 file not found page. Uses pageheader.jspf +
    foot.jspf for the new chrome.
--%>
<%
/* ---------------------- enoent.jsp start --------------------- */
{
    PageConfig _chromeEnoentCfg = PageConfig.get(request);
    _chromeEnoentCfg.checkSourceRootExistence();
    _chromeEnoentCfg.setTitle("OpenGrok File not found");
}
%>
<%@include file="pageheader.jspf" %>
<main class="container">
<div class="enoent-page">
<%
{
    PageConfig _chromeEnoentCfg = PageConfig.get(request);
    String configError = "";
    if (!_chromeEnoentCfg.hasHistory()) {
        configError = "Resource lacks history info.";
    }
%>
    <h3>Error: File not found!</h3>
    <p>The requested resource is not available. </p>
    <p> <%= configError %> </p>
</div>
</main>
<%
}
%>
<%@ include file="/foot.jspf" %>
<%= PageConfig.get(request).getScripts() %>
</body>
</html>