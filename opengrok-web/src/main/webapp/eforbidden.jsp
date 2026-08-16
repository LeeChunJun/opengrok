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

Copyright (c) 2017, 2026, Oracle and/or its affiliates. All rights reserved.
Portions Copyright (c) 2018, Chris Fraire <cfraire@me.com>.
Portions Copyright (c) 2026, UI Refactor.
--%>

<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page session="false" import="
org.opengrok.web.PageConfig,
jakarta.servlet.http.HttpServletResponse"%>

<style>
:root {
    --fg:        #24292f;
}

.eforbidden-page { max-width: 920px; font-size: 14px; color: var(--fg); line-height: 1.6; }
.eforbidden-page h3 { font-size: 18px; font-weight: 600; margin: 8px 0 12px; color: #cf222e; }
.eforbidden-page p { margin: 8px 0; }
</style>

<%-- eforbidden.jspf start

    eforbidden.jsp -- 403 access forbidden page. Uses pageheader.jspf +
    foot.jspf for the new chrome.
--%>
<%
/* ---------------------- eforbidden.jsp start --------------------- */
{
    response.setStatus(HttpServletResponse.SC_FORBIDDEN);

    PageConfig _chromeEForbiddenCfg = PageConfig.get(request);
    _chromeEForbiddenCfg.setTitle("OpenGrok Forbidden!");
}
%>
<%@include file="/pageheader.jspf" %>
<main class="container">
<div class="eforbidden-page">
    <h3>Error: access forbidden</h3>
    <p>The request was forbidden. This can be either file/directory permissions problem or insufficient authorization.</p>
    <%= PageConfig.get(request).getEnv().getIncludeFiles().getForbiddenIncludeFileContent(false) %>
</div>
</main>
<%@ include file="/foot.jspf" %>
<%= PageConfig.get(request).getScripts() %>
</body>
</html>