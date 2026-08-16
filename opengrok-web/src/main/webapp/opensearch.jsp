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
Portions Copyright (c) 2018, 2020, Chris Fraire <cfraire@me.com>.
Portions Copyright (c) 2026, UI Refactor.
--%>

<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page  session="false" errorPage="error.jsp" import="
java.util.Set,

org.opengrok.indexer.web.Prefix,
org.opengrok.indexer.web.QueryParameters,
org.opengrok.indexer.web.Util"
%>

<%
{
    /* ---------------------- opensearch.jsp start ---------------------
     *
     * OpenSearch description (XML). The browser reads this when the
     * user installs OpenGrok as a search engine. This page produces
     * raw XML — not HTML — and does not use the new chrome
     * (pageheader.jspf / foot.jspf).
     */
    PageConfig _osCfg = PageConfig.get(request);
    _osCfg.checkSourceRootExistence();
}
%>
<%@include file="/projects.jspf"%>
<%
{
    StringBuilder _osUrl = new StringBuilder(128);

    /* 协议头：http/https/file */
    final String _osScheme = request.getScheme();
    _osUrl.append(_osScheme).append("://");

    /* 主机名 */
    PageConfig _osCfg = PageConfig.get(request);
    _osUrl.append(_osCfg.getServerName());

    /* 端口：Append port if needed. */
    int _osPort = request.getServerPort();
    if ((_osPort != 80 && _osScheme.equals("http")) || (_osPort != 443 && _osScheme.equals("https"))) {
        _osUrl.append(':').append(_osPort);
    }

    /* 搜索内容 */
    /* TODO  Bug 11749 ??? */
    StringBuilder _osText = new StringBuilder();
    _osUrl.append(request.getContextPath()).append(Prefix.SEARCH_P).append('?');
    Set<String> _osProjects = _osCfg.getRequestedProjects();
    for (String _osName : _osProjects) {
        _osText.append(_osName).append(',');
        Util.appendQuery(_osUrl, QueryParameters.PROJECT_SEARCH_PARAM, _osName);
    }
    if (!_osText.isEmpty()) {
        _osText.setLength(_osText.length() - 1);
    }
%>

<?xml version="1.0" encoding="UTF-8"?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
    <ShortName>OpenGrok <%= _osText.toString() %></ShortName>
    <Description>Search in OpenGrok <%= _osText.toString() %></Description>
    <InputEncoding>UTF-8</InputEncoding>
    <Image height="16" width="16" type="image/png"><%= _osUrl + _osCfg.getCssDir() + "/img/icon.png" %></Image>

    <%-- <Url type="application/x-suggestions+json" template="suggestionURL"/>--%>
    <Url type="text/html" template="<%= _osUrl.toString() %>&amp;<%= QueryParameters.FULL_SEARCH_PARAM_EQ %>{searchTerms}"/>
</OpenSearchDescription>
<%
}
/* ---------------------- opensearch.jsp end --------------------- */
%>
