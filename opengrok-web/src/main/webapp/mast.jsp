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

Copyright (c) 2007, 2026, Oracle and/or its affiliates. All rights reserved.
Portions Copyright 2011 Jens Elkner.
Portions Copyright (c) 2026, UI Refactor.
--%>

<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page session="false" import="
org.opengrok.web.PageConfig,
org.opengrok.indexer.web.Prefix,
org.opengrok.indexer.configuration.Project"%>

<style>
/* Theme variables come from httpheader.jspf (<head>); this fragment
 * (rendered inside <body>) only contributes chrome-specific rules. */

.compact-nav {
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  padding: 8px 24px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 13px;
  gap: 12px;
}

.compact-nav-left {
  display: flex;
  align-items: center;
  gap: 2px;
  flex-wrap: wrap;
}

.nav-pill {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 5px 14px;
  border-radius: 6px;
  color: var(--fg);
  text-decoration: none;
  font-weight: 500;
  font-size: 13px;
  transition: background 0.12s, color 0.12s;
}

.nav-pill:hover {
  background: var(--accent-dim);
  color: var(--accent);
}

.nav-pill.active {
  background: var(--accent);
  color: #fff;
}

.nav-pill.active:hover {
  background: #0860c7;
}

.nav-pill svg {
  width: 14px;
  height: 14px;
  stroke: currentColor;
  fill: none;
  stroke-width: 2;
}

.nav-sep {
  color: var(--border);
  font-size: 13px;
  user-select: none;
  padding: 0 2px;
}

.compact-nav-right {
  display: flex;
  align-items: center;
  gap: 8px;
}

@media(max-width: 900px) {
 .compact-nav {
   padding: 8px 16px;
 }
}

@media(max-width: 600px) {
 .nav-label {
   display: none;
 }

 .compact-nav {
   padding: 6px 12px;
   gap: 6px;
   flex-wrap: nowrap;
 }

 .compact-nav-left {
   gap: 2px;
   flex-shrink: 0;
 }

 .nav-pill {
   padding: 6px;
   border-radius: 6px;
   gap: 0;
  }

 .nav-pill svg {
   width: 16px;
   height: 16px;
 }

 .compact-nav-right {
   gap: 6px;
   flex-shrink: 0;
 }
}

@media (max-width: 768px) {
 .compact-nav { padding: 8px 16px; font-size: 12px; }
}
</style>

<%-- mast.jsp start

  mast.jsp - compact-nav sub-fragment of the unified chrome.

  Invoked from pageheader.jspf (the single include point) inside the
  `_chromeShowFullChrome` branch. After include you are here:
    <body><header>...</header><div class="compact-nav">...</div>
  i.e. one self-contained, fully-matched root element — <main> is NOT
  opened here anymore; the calling page is responsible for its own
  <main class="container"> … </main> pair.

  Responsibilities kept here:
    * set page title from cfg.getPathTitle() (was here pre-refactor)
    * resolve _chromeCtxPath / _chromeProject / _chromePath /
      _chromeHomeHref / _chromeHistoryHref and publish them to nested
      static includes (minisearch.jspf) via pageContext.setAttribute
    * render the compact-nav block:
        <div class="compact-nav">
          <div class="compact-nav-left"> Home / History nav-pills
          <div class="compact-nav-right"> minisearch.jspf
        </div>

  Moved out of this file (UI Refactor):
    * isUnreadable / canProcess / isNotModified short-circuits
        → chrome-guards.jspf (called by the calling page before any
          HTML output; runs `return` from the caller's _jspService)
    * <main class="container"> opener
        → now owned by the calling page (every page that needs one
          opens and closes it itself, matching foot.jspf's pattern)

  All chrome variables are prefixed `_chrome_` so the calling JSP's
  body block (which may also declare `cfg`, `ctxPath`, `project`, etc.)
  does not collide. pageheader.jspf (caller) and minisearch.jspf
  (nested here) share the same scope and can read `_chromeCtxPath` /
  `_chromeProject` / etc.
--%>
<%
{
    PageConfig _chromeMastCfg = PageConfig.get(request);

    /* The guards (403 / redirect / 304) used to live here. They moved
     * to chrome-guards.jspf so this file is now a pure renderer with
     * no early-exit paths of its own. */
    _chromeMastCfg.setTitle(_chromeMastCfg.getPathTitle());

    String _chromeCtxPath = (String) pageContext.getAttribute("ctxPath");
    if (_chromeCtxPath == null) {
        _chromeCtxPath = request.getContextPath();
    }
    String _chromeActiveNav = (String) pageContext.getAttribute("activeNav");
    Project _chromeProject = _chromeMastCfg.getProject();
    String _chromePath = _chromeMastCfg.getPath();

    /* Expose chrome variables to nested static includes
     * (pageheader.jspf, minisearch.jspf). They read these via
     * pageContext.getAttribute, defaulting to request.getContextPath(). */
    pageContext.setAttribute("_chromeCtxPath", _chromeCtxPath);
    pageContext.setAttribute("_chromeProject", _chromeProject);
    pageContext.setAttribute("_chromePath", _chromePath);

    String _chromeHomeHref = _chromeCtxPath + "/";
    String _chromeHistoryHref = null;
    if (_chromeProject != null && _chromeMastCfg.hasHistory()) {
        _chromeHistoryHref = _chromeCtxPath + Prefix.HIST_L + _chromeMastCfg.getUriEncodedPath();
    }
%>
<script type="text/javascript">
/* <![CDATA[ */
    document.rev = function() { return getParameter("r"); };
    document.annotate = <%= _chromeMastCfg.annotate() %>;
    document.domReady.push(function() { domReadyMast(); });
    document.pageReady.push(function() { pageReadyMast(); });
/* ]]> */
</script>
<div class="compact-nav">
    <div class="compact-nav-left">
        <% if ("home".equals(_chromeActiveNav)) { %>
        <span class="nav-pill active">
            <svg viewBox="0 0 24 24"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>
            <span class="nav-label">Home</span>
        </span>
        <% } else { %>
        <a href="<%= _chromeHomeHref %>" class="nav-pill">
            <svg viewBox="0 0 24 24"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>
            <span class="nav-label">Home</span>
        </a>
        <% } %>

        <% if (_chromeHistoryHref != null && !"history".equals(_chromeActiveNav)) { %>
        <a href="<%= _chromeHistoryHref %>" class="nav-pill">
            <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
            <span class="nav-label">History</span>
        </a>
        <% } else if (_chromeHistoryHref != null) { %>
        <span class="nav-pill active">
            <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
            <span class="nav-label">History</span>
        </span>
        <% } %>
    </div>
    <div class="compact-nav-right">
        <%@ include file="minisearch.jspf" %>
    </div>
</div>
<%
}
/* mast.jsp now emits one complete <div class="compact-nav>...</div>
 * and nothing else. No half-tags cross file boundaries anymore. */
%>