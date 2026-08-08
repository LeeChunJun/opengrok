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

Copyright (c) 2005, 2022, Oracle and/or its affiliates. All rights reserved.
Portions Copyright 2011 Jens Elkner.
Portions Copyright (c) 2018, Chris Fraire <cfraire@me.com>.
Portions Copyright (c) 2026, UI Refactor.
--%>
<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page session="false" errorPage="error.jsp" %>
<%@ page import="
java.util.Date,
java.util.Locale,
java.util.Map,
java.util.Set,
java.util.SortedSet,
java.text.SimpleDateFormat,

org.opengrok.indexer.Info,
org.opengrok.indexer.configuration.Group,
org.opengrok.indexer.configuration.Project,
org.opengrok.indexer.history.RepositoryInfo,
org.opengrok.indexer.search.QueryBuilder,
org.opengrok.indexer.web.Prefix,
org.opengrok.indexer.web.QueryParameters,
org.opengrok.indexer.web.SearchHelper,
org.opengrok.indexer.web.Util,
org.opengrok.web.PageConfig,
org.opengrok.web.ProjectHelper"
%><%!
/* ---------------------- helper: render one repository card --------------------- */

/* Icons used by the meta row. Inline SVGs (Feather-style 24x24, stroke-only). */
private static final String ICON_REPO_BRANCH =
    "<svg viewBox=\"0 0 24 24\">" +
    "<line x1=\"6\" y1=\"3\" x2=\"6\" y2=\"15\"/>" +
    "<circle cx=\"18\" cy=\"6\" r=\"3\"/>" +
    "<circle cx=\"6\" cy=\"18\" r=\"3\"/>" +
    "<path d=\"M18 9a9 9 0 0 1-9 9\"/>" +
    "</svg>";
private static final String ICON_PROJECT =
    "<svg viewBox=\"0 0 24 24\">" +
    "<path d=\"M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z\"/>" +
    "<polyline points=\"14 2 14 8 20 8\"/>" +
    "</svg>";
private static final String ICON_CLOCK =
    "<svg viewBox=\"0 0 24 24\">" +
    "<circle cx=\"12\" cy=\"12\" r=\"10\"/>" +
    "<polyline points=\"12 6 12 12 16 14\"/>" +
    "</svg>";

/* Returns badgeClass for a given repo type token (git/svn/hg/cvs/...). */
private static String repoTypeBadgeClass(String repoType) {
    if (repoType == null) return "badge-default";
    String lt = repoType.toLowerCase();
    if (lt.contains("git"))                                    return "badge-git";
    if (lt.contains("svn") || lt.contains("subversion"))      return "badge-svn";
    if (lt.contains("hg")  || lt.contains("mercurial"))       return "badge-hg";
    if (lt.contains("cvs"))                                    return "badge-cvs";
    return "badge-default";
}

/* Returns true if `s` is non-null and non-blank. */
private static boolean hasText(String s) {
    return s != null && !s.isEmpty();
}

/*
 * Returns `s` if non-null, otherwise "". Use this to guard calls to
 * Util.htmlize(...) / Util.redactUri(...) which throw NullPointerException
 * on null input (Util.htmlize iterates `s.length()` without a null check).
 */
private static String nz(String s) {
    return s == null ? "" : s;
}

/*
 * Try to extract "YYYY-MM-DD HH:mm" prefix from a currentVersion string.
 * Examples of accepted inputs:
 *   "2026-02-06 11:40 +0800 34c4" -> "2026-02-06 11:40"
 *   "2026-02-06 11:40:12 +0800 a" -> "2026-02-06 11:40"  (truncate seconds)
 * Returns null if `s` does not start with that pattern.
 */
private static String extractVersionDateTime(String s) {
    if (s == null || s.length() < 16) return null;
    if (   s.charAt(4)  == '-' && s.charAt(7)  == '-'
        && s.charAt(10) == ' ' && s.charAt(13) == ':') {
        return s.substring(0, 16);
    }
    return null;
}

/*
 * Extract the short hash / revision from a currentVersion string.
 * Per GitRepository.determineCurrentVersion (and MercurialRepository, SubversionRepository),
 * the format is:  "{date} {time} {tz} {hash|revision} {author} {message}"
 * so the 4th whitespace-separated token (index 3) is the hash/revision.
 * We additionally require the candidate to look like a hex string (4-40 chars,
 * matching git short or full hash) or a decimal number (matching svn revision).
 * Otherwise we return null so the caller can fall back gracefully.
 */
private static String extractShortHash(String s) {
    if (s == null) return null;
    String[] tokens = s.trim().split("\\s+");
    if (tokens.length < 4) return null;
    String candidate = tokens[3];
    if (candidate.matches("[0-9a-fA-F]{4,40}") || candidate.matches("\\d{1,20}")) {
        return candidate;
    }
    return null;
}

private void renderRepoCard(JspWriter out, PageConfig cfg, String ctxPath,
                            ProjectHelper ph, Project p) throws java.io.IOException {
    if (!p.isIndexed() || !cfg.isAllowed(p)) return;

    String name = p.getName();
    String repoUrl = ctxPath + Prefix.XREF_P + "/" + Util.uriEncodePath(name);

    /* Pick the first (best) RepositoryInfo for this project. */
    RepositoryInfo ri = null;
    for (RepositoryInfo info : ph.getSortedRepositoryInfo(p)) {
        ri = info;
        break;
    }

    /* ── Fields (null = missing → render with placeholder space) ── */
    String repoType     = (ri == null) ? null : ri.getType();
    String remoteUrl    = (ri == null) ? null : ri.getParent();
    String branch       = (ri == null) ? null : ri.getBranch();
    String currentVer   = (ri == null) ? null : ri.getCurrentVersion();

    boolean hasRepoType = hasText(repoType);
    boolean hasUrl      = hasText(remoteUrl);
    boolean hasBranch   = hasText(branch);
    String versionDate  = extractVersionDateTime(currentVer);   /* e.g. "2026-02-06 11:40" */
    String versionHash  = extractShortHash(currentVer);         /* e.g. "34c4909" */

    /* Badge class always resolves (even if empty) so layout is stable. */
    String badgeClass = repoTypeBadgeClass(repoType);

    /* ── HTML-escape strings we plan to emit as text ── */
    /* Use nz() to guard against null — Util.htmlize throws NPE on null input. */
    String hName        = Util.htmlize(name);
    String hType        = Util.htmlize(nz(repoType));
    String hUrl         = Util.htmlize(nz(remoteUrl));
    String hBranch      = Util.htmlize(nz(branch));
    String hVersionDate = Util.htmlize(nz(versionDate));
    String hVersionHash = Util.htmlize(nz(versionHash));

    /* ── Slot ④ 仓库/工程: choose icon + label by whether SCM type exists ── */
    String slot4Icon  = hasRepoType ? ICON_REPO_BRANCH : ICON_PROJECT;
    String slot4Label = hasRepoType ? "\u4ed3\u5e93" /* 仓库 */ : "\u5de5\u7a0b" /* 工程 */;
    String slot4Cls   = "";                                  /* always shown */

    /* ── Slot ⑤ 版本时间: hidden if no parseable date ── */
    String slot5Cls   = hasText(hVersionDate) ? "" : " empty";

    /* ── Slot ⑥ 分支·最后一次提交: branch + last hash; placeholder if both absent ── */
    String branchLine;
    String slot6Cls   = "";
    if (hasBranch && hasText(hVersionHash)) {
        branchLine = hBranch + " &middot; " + hVersionHash;
    } else if (hasBranch) {
        branchLine = hBranch;
    } else if (hasText(hVersionHash)) {
        branchLine = hVersionHash;
    } else {
        branchLine = "\u6682\u65e0\u5206\u652f" /* 暂无分支 */;
        slot6Cls   = " placeholder";
    }

    /* ── Slot ② 仓库(URL): hidden if absent ── */
    String slot2Cls = hasUrl ? "" : " empty";
    /* ── Slot ③ git 标识: hidden if absent ── */
    String slot3Cls = hasRepoType ? "" : " empty";

    out.println("<a href=\"" + repoUrl + "\" class=\"repo-card\" data-od-id=\"repo-" + hName + "\">");
    out.println("  <div class=\"repo-card-header\">");
    out.println("    <span class=\"repo-card-name\">" + hName + "</span>");
    out.println("    <span class=\"repo-card-badge " + badgeClass + slot3Cls + "\">" + hType + "</span>");
    out.println("  </div>");
    out.println("  <div class=\"repo-card-url" + slot2Cls + "\" title=\"" + hUrl + "\">" + hUrl + "</div>");
    out.println("  <div class=\"repo-card-meta\">");
    out.println("    <span class=\"meta-item " + slot4Cls + "\">" + slot4Icon + "<span class=\"meta-text\">" + slot4Label + "</span></span>");
    out.println("    <span class=\"meta-item" + slot5Cls + "\">" + ICON_CLOCK + "<span class=\"meta-text\">" + hVersionDate + "</span></span>");
    out.println("  </div>");
    out.println("  <div class=\"repo-card-footer\">");
    out.println("    <span class=\"repo-card-branch" + slot6Cls + "\"><span class=\"branch-text\">" + branchLine + "</span></span>");
    out.println("    <span class=\"repo-card-link\">\u6d4f\u89c8 &rarr;</span>");
    out.println("  </div>");
    out.println("</a>");
}
%><%@ include file="/projects.jspf" %><%
/* ---------------------- index.jsp start --------------------- */
PageConfig cfg = PageConfig.get(request);
cfg.checkSourceRootExistence();
cfg.setTitle("OpenGrok Code Search");

/* Register jQuery + jquery-ui + utils + jquery-caret so the existing suggester/autocomplete works.
   utils.js's getAutocompleteMenuData() (utils-0.0.48.js:1898-1915) calls input.caret() to read the
   caret position — if jquery.caret-1.5.2.min.js is not loaded this throws "input.caret is not a
   function" and the suggestion popup silently empties. The original httpheader.jspf registers
   these in priority order, so we mirror the same set here.
   The legacy searchable-option-list widget is NOT needed: we override window.getSelectedProjectNames
   to read from our hidden <select id="project-select"> instead. */
cfg.addScript("jquery");
cfg.addScript("jquery-ui");
cfg.addScript("jquery-caret");
cfg.addScript("utils");

ProjectHelper ph = ProjectHelper.getInstance(cfg);
String ctxPath = request.getContextPath();
String styleDir = cfg.getCssDir();
QueryBuilder qb = cfg.getQueryBuilder();
boolean displayRepos = cfg.getEnv().isDisplayRepositories();

Set<Project> projects = ph.getAllProjects();
SortedSet<String> requestedProjects = cfg.getRequestedProjects();
boolean anyRequested = !requestedProjects.isEmpty();

String selectedType = qb.getType() == null ? "" : qb.getType();
Set<Map.Entry<String, String>> typeDescriptions = SearchHelper.getFileTypeDescriptions();

Date dateForLastIndexRun = cfg.getEnv().getDateForLastIndexRun();

int repoCount = 0;
if (displayRepos) {
    for (Group g : ph.getGroups()) {
        if (!(cfg.isAllowed(g) || ph.hasAllowedSubgroup(g))) {
            continue;
        }
        for (Project p : ph.getProjects(g)) {
            if (p.isIndexed() && cfg.isAllowed(p)) repoCount++;
        }
        for (Project p : ph.getRepositories(g)) {
            if (p.isIndexed() && cfg.isAllowed(p)) repoCount++;
        }
    }
    for (Project p : ph.getUngroupedProjects()) {
        if (p.isIndexed() && cfg.isAllowed(p)) repoCount++;
    }
    for (Project p : ph.getUngroupedRepositories()) {
        if (p.isIndexed() && cfg.isAllowed(p)) repoCount++;
    }
}
%><!DOCTYPE html>
<html lang="zh-CN" class="index">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<meta name="generator" content="OpenGrok <%= Info.getVersion() %> (<%= Info.getRevision() %>)">
<meta name="theme-color" media="(prefers-color-scheme: light)" content="#ffffff">
<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#1e1f22">
<link rel="icon" href="<%= styleDir %>/img/favicon.svg">
<link rel="stylesheet" type="text/css" href="<%= styleDir %>/style-1.0.6.min.css" media="all" title="Default">
<script type="text/javascript">/* <![CDATA[ */
    window.contextPath = '<%= ctxPath %>';
    document.pageReady = [];
    document.domReady = [];
/* ]]> */</script>
<title><%= cfg.getTitle() %></title>
<style>
    :root {
      --bg:        #f4f5f7;
      --surface:   #ffffff;
      --fg:        #1a1b2e;
      --muted:     #6b7280;
      --border:    #e5e7eb;
      --accent:    #3b82f6;
      --accent-dim: rgba(59,130,246,0.08);
      --green:     #22c55e;
      --green-dim: rgba(34,197,94,0.10);
      --font-sans: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, system-ui, sans-serif;
      --font-mono: 'JetBrains Mono', 'SF Mono', 'Cascadia Code', ui-monospace, Menlo, monospace;
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: var(--font-sans);
      background: var(--bg);
      color: var(--fg);
      min-height: 100vh;
      -webkit-font-smoothing: antialiased;
    }

    /* ═ Header ═══ */
    .header {
      background: var(--surface);
      border-bottom: 1px solid var(--border);
      padding: 14px 32px;
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .header-logo {
      width: 28px; height: 28px;
      background: var(--fg);
      border-radius: 7px;
      display: grid; place-items: center;
      flex-shrink: 0;
    }
    .header-logo svg {
      width: 14px; height: 14px;
      stroke: #60a5fa; fill: none; stroke-width: 2.5;
    }
    .header-title {
      font-size: 16px;
      font-weight: 600;
      letter-spacing: -0.02em;
    }
    .header-title span {
      color: var(--muted);
      font-weight: 400;
      margin-left: 4px;
    }
    .header-link {
      margin-left: auto;
      font-size: 13px;
      color: var(--muted);
      text-decoration: none;
      transition: color 0.12s;
    }
    .header-link:hover { color: var(--accent); }
    .header-link svg {
      width: 14px; height: 14px;
      stroke: currentColor; fill: none; stroke-width: 2;
      vertical-align: -1px;
      margin-right: 4px;
    }

    /* ══ Main Container ══ */
    .container {
      max-width: 960px;
      margin: 0 auto;
      padding: 36px 24px 48px;
    }

    /* ══ Search Hero ═══ */
    .search-hero {
      margin-bottom: 28px;
    }
    .search-hero h1 {
      font-size: 22px;
      font-weight: 600;
      letter-spacing: -0.02em;
      margin-bottom: 4px;
    }
    .search-hero p {
      font-size: 14px;
      color: var(--muted);
      margin-bottom: 20px;
    }

    .primary-search {
      position: relative;
      margin-bottom: 12px;
    }
    .primary-search input {
      width: 100%;
      height: 48px;
      border: 1.5px solid var(--border);
      border-radius: 10px;
      padding: 0 16px 0 44px;
      font-size: 15px;
      font-family: var(--font-sans);
      color: var(--fg);
      background: var(--surface);
      outline: none;
      transition: border-color 0.15s, box-shadow 0.15s;
    }
    .primary-search input::placeholder { color: #b0b4bc; }
    .primary-search input:focus {
      border-color: var(--accent);
      box-shadow: 0 0 0 3px var(--accent-dim);
    }
    .primary-search .ps-icon {
      position: absolute;
      left: 14px;
      top: 50%;
      transform: translateY(-50%);
      width: 18px; height: 18px;
      stroke: var(--muted);
      fill: none; stroke-width: 2;
    }
    .primary-search .ps-kbd {
      position: absolute;
      right: 14px;
      top: 50%;
      transform: translateY(-50%);
      font-size: 11px;
      color: var(--muted);
      background: #f0f1f3;
      padding: 2px 7px;
      border-radius: 4px;
      border: 1px solid var(--border);
      font-family: var(--font-sans);
      pointer-events: none;
    }

    .controls-row {
      display: flex;
      align-items: center;
      gap: 8px;
      flex-wrap: wrap;
    }
    .ctrl-btn {
      display: inline-flex;
      align-items: center;
      gap: 5px;
      padding: 6px 12px;
      border-radius: 6px;
      font-size: 12.5px;
      font-weight: 500;
      border: 1px solid var(--border);
      background: var(--surface);
      color: var(--fg);
      cursor: pointer;
      transition: background 0.12s, border-color 0.12s;
      font-family: var(--font-sans);
    }
    .ctrl-btn:hover { background: #f8f9fb; color: var(--fg); }
    .ctrl-btn:focus,
    .ctrl-btn:focus-visible { outline: none; box-shadow: 0 0 0 3px var(--accent-dim); }
    .ctrl-btn.active {
      border-color: var(--accent);
      color: var(--accent);
      background: var(--accent-dim);
    }
    .ctrl-btn.active:hover { color: var(--accent); background: var(--accent-dim); }
    .ctrl-btn svg {
      width: 13px; height: 13px;
      stroke: currentColor; fill: none; stroke-width: 2;
    }
    .ctrl-btn .arrow {
      transition: transform 0.2s;
    }
    .ctrl-btn.active .arrow {
      transform: rotate(180deg);
    }
    .ctrl-select {
      padding: 6px 10px;
      border-radius: 6px;
      border: 1px solid var(--border);
      font-size: 12.5px;
      font-family: var(--font-sans);
      color: var(--fg);
      background: var(--surface);
      outline: none;
      cursor: pointer;
      visibility: visible;       /* override legacy style-1.0.6.css's `select#type { visibility:hidden }` */
      width: auto;               /* override the legacy 30px width hack */
      height: auto;              /* override the legacy 20px height hack */
      min-width: 120px;          /* keep the dropdown readable */
    }
    .ctrl-select:focus { border-color: var(--accent); }

    .advanced-panel {
      max-height: 0;
      overflow: hidden;
      transition: max-height 0.3s ease, opacity 0.2s;
      opacity: 0;
    }
    .advanced-panel.open {
      max-height: 500px;
      opacity: 1;
      margin-top: 16px;
    }
    .advanced-inner {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 20px;
    }
    .adv-row {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 12px;
    }
    .adv-row:last-of-type { margin-bottom: 0; }
    .adv-label {
      width: 90px;
      font-size: 13px;
      font-weight: 500;
      color: var(--fg);
      flex-shrink: 0;
    }
    .adv-label.secondary {
      color: var(--muted);
      font-weight: 400;
    }
    .adv-input {
      flex: 1;
      height: 34px;
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 0 12px;
      font-size: 13px;
      font-family: var(--font-sans);
      color: var(--fg);
      background: #fff;
      outline: none;
      transition: border-color 0.15s, box-shadow 0.15s;
    }
    .adv-input:focus {
      border-color: var(--accent);
      box-shadow: 0 0 0 3px var(--accent-dim);
    }
    .adv-input::placeholder { color: #b0b4bc; }

    .adv-actions {
      display: flex;
      gap: 8px;
      margin-top: 18px;
      padding-top: 14px;
      border-top: 1px solid var(--border);
      flex-wrap: wrap;
    }

    .btn {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 8px 18px;
      border-radius: 7px;
      font-size: 13px;
      font-weight: 500;
      border: none;
      cursor: pointer;
      transition: background 0.12s, transform 0.1s;
      text-decoration: none;
      font-family: var(--font-sans);
    }
    .btn:active { transform: scale(0.97); }
    .btn-primary {
      background: var(--accent);
      color: #fff;
    }
    .btn-primary:hover { background: #2563eb; }
    .btn-secondary {
      background: #f0f1f3;
      color: var(--fg);
    }
    .btn-secondary:hover { background: #e4e5e8; }
    .btn-ghost {
      background: transparent;
      color: var(--muted);
      border: 1px solid var(--border);
    }
    .btn-ghost:hover { background: #f8f9fb; color: var(--fg); }

    .project-section {
      margin-bottom: 24px;
    }
    .project-bar {
      display: flex;
      align-items: center;
      gap: 8px;
      flex-wrap: wrap;
    }
    .project-bar label {
      font-size: 13px;
      font-weight: 500;
      color: var(--fg);
    }
    .project-chips {
      display: flex;
      gap: 6px;
      flex-wrap: wrap;
      flex: 1 1 100%;
      order: 3;
      justify-content: flex-start;
    }
    .chip-actions {
      order: 2;
      display: flex;
      gap: 4px;
    }
    .chip {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      padding: 4px 10px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 500;
      border: 1px solid var(--border);
      background: var(--surface);
      cursor: pointer;
      transition: all 0.12s;
      user-select: none;
    }
    .chip:hover { border-color: #ccc; }
    .chip.selected {
      border-color: var(--accent);
      background: var(--accent-dim);
      color: var(--accent);
    }
    .chip .chip-dot {
      width: 6px; height: 6px;
      border-radius: 50%;
      background: var(--green);
    }
    .chip-action {
      font-size: 11px;
      color: var(--muted);
      cursor: pointer;
      padding: 2px 6px;
      border-radius: 4px;
      transition: background 0.12s;
      border: none;
      background: none;
      font-family: var(--font-sans);
    }
    .chip-action:hover { background: #f0f1f3; color: var(--fg); }

    .repo-section-title {
      font-size: 13px;
      font-weight: 600;
      margin-bottom: 14px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .repo-section-title .count {
      font-weight: 400;
      color: var(--muted);
      font-size: 12px;
    }
    .repo-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
      gap: 12px;
      margin-bottom: 36px;
      align-items: start;   /* cards take natural height; no row-stretch */
    }
    .repo-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 16px;
      cursor: pointer;
      transition: border-color 0.12s, box-shadow 0.12s, transform 0.1s;
      text-decoration: none;
      color: inherit;
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .repo-card:hover {
      border-color: #c7c9d0;
      box-shadow: 0 2px 12px rgba(0,0,0,0.05);
      transform: translateY(-1px);
    }
    .repo-card-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      min-width: 0;
    }
    .repo-card-name {
      font-size: 15px;
      font-weight: 600;
      letter-spacing: -0.01em;
      color: var(--fg);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      min-width: 0;
    }
    .repo-card-badge {
      font-size: 11px;
      padding: 2px 8px;
      border-radius: 999px;
      font-weight: 500;
      flex-shrink: 0;
    }
    /* Empty badge: keep pill dimensions (so layout stays stable), just hide text. */
    .repo-card-badge.empty { visibility: hidden; }
    .badge-git     { background: #f0f1ff; color: #5b6abf; }
    .badge-svn     { background: #fef3c7; color: #92400e; }
    .badge-hg      { background: #fce7f3; color: #9d174d; }
    .badge-cvs     { background: #dbeafe; color: #1e40af; }
    .badge-mercurial { background: #fce7f3; color: #9d174d; }
    .badge-subversion { background: #fef3c7; color: #92400e; }
    .badge-default { background: #e5e7eb; color: #374151; }
    .repo-card-url {
      font-family: var(--font-mono);
      font-size: 11.5px;
      color: var(--muted);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      min-width: 0;        /* allow shrinking inside flex column */
      max-width: 100%;
    }
    /* Empty URL slot: preserve the line height but hide the text. */
    .repo-card-url.empty { visibility: hidden; }
    .repo-card-meta {
      display: flex;
      align-items: center;
      gap: 12px;
      font-size: 12px;
      color: var(--muted);
      min-width: 0;
      flex-wrap: wrap;
    }
    .repo-card-meta .meta-item {
      display: flex;
      align-items: center;
      gap: 4px;
      min-width: 0;
      max-width: 100%;
      flex: 0 1 auto;
    }
    .repo-card-meta .meta-text {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      min-width: 0;
      flex: 1 1 auto;
    }
    /* Empty meta item: keep icon + text space (no row collapse). */
    .repo-card-meta .meta-item.empty { visibility: hidden; }
    .repo-card-meta svg {
      width: 13px; height: 13px;
      stroke: currentColor; fill: none; stroke-width: 2;
      flex-shrink: 0;
    }
    .repo-card-footer {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding-top: 10px;
      border-top: 1px solid var(--border);
      gap: 8px;
      min-width: 0;
    }
    .repo-card-branch {
      font-family: var(--font-mono);
      font-size: 11.5px;
      color: var(--muted);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      min-width: 0;
      flex: 1 1 auto;
    }
    .repo-card-branch .branch-text {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      min-width: 0;
      display: inline-block;
      max-width: 100%;
    }
    /* "暂无分支" placeholder: muted italic so it reads as a fallback, not real data. */
    .repo-card-branch.placeholder { color: var(--muted); font-style: italic; }
    .repo-card-link {
      font-size: 12px;
      color: var(--accent);
      text-decoration: none;
      font-weight: 500;
      flex-shrink: 0;
    }
    .repo-card-link:hover { text-decoration: underline; }

    .footer {
      text-align: center;
      font-size: 12px;
      color: var(--muted);
      padding-top: 8px;
    }
    .footer a {
      color: var(--accent);
      text-decoration: none;
    }
    .footer a:hover { text-decoration: underline; }

    .results-section {
      display: none;
      margin-top: 24px;
      animation: fadeIn 0.3s ease;
    }
    .results-section.visible {
      display: block;
    }
    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(8px); }
      to   { opacity: 1; transform: translateY(0); }
    }
    .results-header {
      font-size: 13px;
      color: var(--muted);
      margin-bottom: 16px;
      padding-bottom: 10px;
      border-bottom: 1px solid var(--border);
    }
    .results-header strong { color: var(--fg); font-weight: 600; }
    .results-header .query-term { color: var(--accent); font-weight: 500; }

    .sort-bar {
      display: flex;
      align-items: center;
      gap: 4px;
      margin-bottom: 16px;
      font-size: 13px;
      color: var(--muted);
      padding-bottom: 10px;
      border-bottom: 1px solid var(--border);
    }
    .sort-bar .sort-label {
      font-weight: 500;
      color: var(--fg);
      margin-right: 4px;
    }
    .sort-bar .sort-option {
      padding: 4px 10px;
      border-radius: 5px;
      cursor: pointer;
      transition: background 0.12s, color 0.12s;
      border: none;
      background: none;
      font-size: 13px;
      font-family: var(--font-sans);
      color: var(--muted);
    }
    .sort-bar .sort-option:hover { background: #eef0f3; color: var(--fg); }
    .sort-bar .sort-option.active {
      background: var(--accent-dim);
      color: var(--accent);
      font-weight: 500;
    }
    .sort-bar .sort-sep { color: #d1d5db; margin: 0 2px; }

    .result-group-header {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 12px 0 8px;
      font-size: 14px;
      font-weight: 600;
      color: var(--accent);
      font-family: var(--font-mono);
      letter-spacing: -0.01em;
    }
    .result-group-header:first-child { padding-top: 0; }
    .group-count {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: 22px;
      height: 20px;
      padding: 0 6px;
      border-radius: 999px;
      font-size: 11px;
      font-weight: 600;
      font-family: var(--font-sans);
      background: var(--accent-dim);
      color: var(--accent);
    }

    .result-file-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 8px;
      margin-bottom: 10px;
      overflow: hidden;
      transition: border-color 0.12s, box-shadow 0.12s;
    }
    .result-file-card:hover {
      border-color: #c7c9d0;
      box-shadow: 0 2px 8px rgba(0,0,0,0.04);
    }

    .result-file-header {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 8px 14px;
      background: #fafbfc;
      border-bottom: 1px solid var(--border);
      flex-wrap: nowrap;
    }
    .result-file-header > a {
      display: flex;
      align-items: center;
      gap: 8px;
      flex: 1;
      min-width: 0;
      text-decoration: none;
      color: var(--muted);
      transition: color 0.12s;
    }
    .result-file-header > a:hover {
      color: var(--accent);
    }
    .result-file-header svg {
      width: 14px; height: 14px;
      stroke: #9ca3af; fill: none; stroke-width: 2;
      flex-shrink: 0;
    }
    .result-file-header .file-path {
      font-family: var(--font-mono);
      font-size: 12px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      flex: 1;
    }
    .result-file-header .file-actions {
      display: flex;
      gap: 4px;
      flex-shrink: 0;
      margin-left: auto;
    }

    .action-btn {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      padding: 4px 10px;          /* comfort hit-area, like sort-option */
      border-radius: 5px;
      font-size: 12px;
      border: 1px solid #e5e7eb;   /* keep border + bg (per user feedback) */
      background: #f9fafb;
      color: var(--muted);         /* softer gray — same token as sort-bar default */
      cursor: pointer;
      font-family: var(--font-sans);
      transition: background 0.12s, color 0.12s, border-color 0.12s;
      text-decoration: none;
      white-space: nowrap;
      flex-shrink: 0;
    }
    .action-btn:hover {
      background: #f3f4f6;         /* slightly darker gray on hover, like sort-bar */
      color: var(--fg);
      border-color: #d1d5db;
    }
    .action-btn svg {
      width: 12px; height: 12px;
      stroke: currentColor; fill: none; stroke-width: 2;
    }
    /* Result group header — bucket of file cards that share the same directory.
       One header per distinct dir, with the dir as an accent link + a hit-count badge. */
    .result-group-header {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 16px 4px 10px;
      font-size: 14px;
      font-weight: 600;
      color: var(--accent);
      font-family: var(--font-mono);
      letter-spacing: -0.01em;
      min-width: 0;
    }
    .result-group-header:first-child { padding-top: 4px; }
    .result-group-header svg {
      width: 14px; height: 14px;
      stroke: currentColor;
      fill: none;
      stroke-width: 2;
      flex-shrink: 0;
    }
    .result-group-header a, .result-group-header .group-root {
      color: var(--accent);
      text-decoration: none;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      min-width: 0;
      flex: 1 1 auto;
      transition: color 0.12s;
    }
    .result-group-header a:hover { text-decoration: underline; }
    .result-group-header .group-root { color: var(--muted); font-style: italic; }
    .group-count {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: 22px;
      height: 20px;
      padding: 0 6px;
      border-radius: 999px;
      font-size: 11px;
      font-weight: 600;
      font-family: var(--font-sans);
      background: var(--accent-dim);
      color: var(--accent);
      flex-shrink: 0;
    }
    .result-lines { padding: 4px 0; }
    .result-line {
      display: flex;
      align-items: baseline;
      padding: 2px 14px 2px 0;
      font-family: var(--font-mono);
      font-size: 12.5px;
      line-height: 1.7;
      cursor: pointer;
      text-decoration: none;
      color: inherit;
      transition: background 0.1s;
    }
    .result-line:hover {
      background: #eef2ff;
    }
    .result-line:hover .line-num {
      color: var(--accent);
    }
    .line-num {
      width: 44px; min-width: 44px;
      text-align: right;
      padding-right: 12px;
      color: #b0b4bc;
      font-size: 11.5px;
      user-select: none;
      flex-shrink: 0;
    }
    .line-code {
      flex: 1;
      min-width: 0;             /* let ellipsis kick in inside flex */
      padding-right: 14px;
      white-space: nowrap;      /* single line, ellipsis-capable */
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .line-code .match {
      background: #fef08a;
      border-bottom: 2px solid #fde047;
      padding: 0 1px;
      border-radius: 2px;
      flex-shrink: 0;          /* highlighted keyword never compressed */
    }

    /* Per card: max 10 lines shown by default; extra lines hide behind "show more" button.
       The button toggles .expanded on the parent .result-file-card. */
    .result-file-card .result-line.result-line-overflow { display: none; }
    .result-file-card.expanded .result-line.result-line-overflow { display: flex; }
    .result-expand-btn {
      display: block;
      width: 100%;
      padding: 8px 14px;
      margin-top: 2px;
      background: transparent;
      border: 0;
      border-top: 1px dashed var(--border);
      color: var(--accent);
      font-size: 12px;
      font-weight: 500;
      cursor: pointer;
      text-align: center;
      transition: background 0.12s, color 0.12s;
      font-family: var(--font-sans);
    }
    .result-expand-btn:hover {
      background: #dbeafe;          /* tailwind blue-100 — much darker than accent-dim */
      color: #1e40af;                /* tailwind blue-800 — keeps text legible on the hover bg */
    }
    .result-expand-btn .arrow {
      display: inline-block;
      transition: transform 0.2s;
    }
    .result-file-card.expanded .result-expand-btn .arrow { transform: rotate(180deg); }

    .pagination {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 4px;
      padding: 20px 0 8px;
    }
    .page-btn {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      min-width: 36px;
      height: 36px;
      padding: 0 10px;
      border-radius: 8px;
      border: none;
      background: transparent;
      font-size: 14px;
      font-family: var(--font-sans);
      font-weight: 500;
      color: var(--fg);
      cursor: pointer;
      transition: background 0.12s, color 0.12s;
      text-decoration: none;
    }
    .page-btn:hover {
      background: #f0f1f3;
    }
    .page-btn.active {
      background: var(--accent);
      color: #fff;
    }
    .page-btn.active:hover {
      background: #2563eb;
    }
    .page-btn:disabled {
      opacity: 0.4;
      cursor: default;
      pointer-events: none;
    }
    .page-btn.nav-btn {
      color: var(--muted);
      font-weight: 400;
    }
    .page-btn.nav-btn:hover {
      color: var(--accent);
    }
    .page-btn.nav-btn svg {
      width: 14px; height: 14px;
      stroke: currentColor; fill: none; stroke-width: 2;
    }
    .page-ellipsis {
      min-width: 36px;
      height: 36px;
      display: grid; place-items: center;
      font-size: 14px;
      color: var(--muted);
    }

    @media (max-width: 700px) {
      .header { padding: 12px 16px; }
      .container { padding: 24px 16px 36px; }
      .adv-row { flex-wrap: wrap; }
      .adv-label { width: 100%; margin-bottom: -4px; }
      .repo-grid { grid-template-columns: 1fr; }
      .controls-row { gap: 6px; }
      .result-line { font-size: 11.5px; }
      .line-num { width: 36px; min-width: 36px; font-size: 10.5px; }
    }
    @media (max-width: 480px) {
      .primary-search input { height: 42px; font-size: 14px; }
      .search-hero h1 { font-size: 19px; }
      .pagination .page-btn:nth-child(n+5):nth-child(-n+8) {
        display: none;
      }
    }

    /* —— jQuery UI autocomplete popup — equal-width to input + baseline alignment ——
       utils-0.0.48.js:1961-2005 renders each suggestion as:
         <li class="ui-menu-item" style="display:block">
           <div class="ui-menu-item-wrapper" style="height:20px;padding:0">
             <span style="float:left;padding-left:5px">phrase</span>
             <span style="float:right;padding-right:5px;color:#999;font-style:italic">projectName</span>
           </div>
         </li>
       jQuery UI's `.ui-autocomplete` width is set by `_width = Math.max(ul.width("").outerWidth(), ul.outerWidth(true))`,
       and with long phrase strings and floating children this pushes the popup past the input width.
       We hook `autocompleteopen` (set up in the inline IIFE further down) to pin `ul.outerWidth(input.outerWidth())`,
       so #full/#defs/#refs/#path/#hist each get a popup that matches their own input width.
       We also override the wrapper to use flex (so floats don't break the ellipsis clip) and align the right-hand
       project name to the phrase's baseline. */
    .ui-autocomplete {
      box-sizing: border-box;
      border-radius: 8px;
      overflow: hidden;
      box-shadow: 0 4px 16px rgba(0,0,0,0.08);
      font-size: 13.5px;
    }
    .ui-autocomplete .ui-menu-item {
      margin: 0;
      border: 0;
      display: block;
    }
    .ui-autocomplete .ui-menu-item-wrapper {
      height: 32px !important;
      padding: 0 12px !important;
      display: flex !important;
      align-items: baseline !important;          /* phrase + projectName share baseline (fix #2) */
      gap: 12px;
      min-width: 0;
    }
    /* Both inline spans inside the wrapper: kill the utils.js floats and let flex layout take over. */
    .ui-autocomplete .ui-menu-item-wrapper > span {
      float: none !important;
      max-height: none !important;
      padding: 0 !important;
      line-height: 1.5;
      color: var(--fg);
      font-style: normal;
    }
    .ui-autocomplete .ui-menu-item-wrapper > span:first-child {
      flex: 1 1 auto;
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .ui-autocomplete .ui-menu-item-wrapper > span:last-child {
      flex: 0 0 auto;
      color: var(--muted);
      font-style: italic;
      font-size: 12.5px;
    }
    .ui-autocomplete .ui-menu-item.ui-state-focus .ui-menu-item-wrapper,
    .ui-autocomplete .ui-menu-item:hover .ui-menu-item-wrapper {
      background: var(--accent-dim);
    }
    .ui-autocomplete .ui-menu-item.ui-state-focus .ui-menu-item-wrapper > span,
    .ui-autocomplete .ui-menu-item:hover .ui-menu-item-wrapper > span {
      color: var(--fg);
    }
    </style>
</head>
<body>

<header class="header">
  <div class="header-logo">
    <svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><line x1="16.5" y1="16.5" x2="21" y2="21"/></svg>
  </div>
  <div class="header-title">OpenGrok <span>Code Search</span></div>
  <a href="<%= ctxPath %><%= Prefix.XREF_P %>" class="header-link">
    <svg viewBox="0 0 24 24"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>
    代码浏览
  </a>
</header>

<div class="container">

  <section class="search-hero" data-od-id="search-section">
    <h1>搜索代码</h1>
    <p>在已索引的代码仓库中进行多维度检索</p>

    <form action="<%= ctxPath %>/search" id="sbox" method="get">
      <div class="primary-search">
        <svg class="ps-icon" viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><line x1="16.5" y1="16.5" x2="21" y2="21"/></svg>
        <input type="text"
               placeholder="全文搜索 — 输入关键词、类名、方法名…"
               id="full"
               name="<%= QueryParameters.FULL_SEARCH_PARAM %>"
               value="<%= Util.formQuoteEscape(qb.getFreetext()) %>" />
        <span class="ps-kbd">⌘K</span>
      </div>

      <div class="controls-row">
        <button type="button" class="ctrl-btn" id="adv-toggle">
          <svg viewBox="0 0 24 24"><line x1="4" y1="6" x2="20" y2="6"/><line x1="4" y1="12" x2="14" y2="12"/><line x1="4" y1="18" x2="18" y2="18"/></svg>
          高级搜索
          <svg class="arrow" viewBox="0 0 24 24"><polyline points="6 9 12 15 18 9"/></svg>
        </button>
        <%-- id="filetype" (not "type") so legacy style-1.0.6.css's `select#type { visibility:hidden }`
             and utils-0.0.48.js's `$('#type').searchableOptionList(...)` don't catch this element.
             name="type" is unchanged so the form still submits `type=...` for SearchController. --%>
        <select class="ctrl-select" id="filetype" name="<%= QueryParameters.TYPE_SEARCH_PARAM %>">
          <option value=""<%= selectedType.isEmpty() ? " selected" : "" %>>任意类型</option>
          <% for (Map.Entry<String, String> d : typeDescriptions) {
              String tval = d.getKey();
              String tlabel = d.getValue();
          %><option value="<%= Util.formQuoteEscape(tval) %>"<%
              if (tval.equals(selectedType)) { %> selected="selected"<% }
              %>><%= Util.htmlize(tlabel) %></option><%
          } %>
        </select>
      </div>

      <div class="advanced-panel" id="advanced-panel">
        <div class="advanced-inner">
          <div class="adv-row">
            <span class="adv-label secondary">定义</span>
            <input type="text" class="adv-input"
                   id="defs"
                   name="<%= QueryParameters.DEFS_SEARCH_PARAM %>"
                   placeholder="按定义搜索，例如类名、接口名…"
                   value="<%= Util.formQuoteEscape(qb.getDefs()) %>" />
          </div>
          <div class="adv-row">
            <span class="adv-label secondary">符号</span>
            <input type="text" class="adv-input"
                   id="refs"
                   name="<%= QueryParameters.REFS_SEARCH_PARAM %>"
                   placeholder="按符号搜索，例如变量名、方法名…"
                   value="<%= Util.formQuoteEscape(qb.getRefs()) %>" />
          </div>
          <div class="adv-row">
            <span class="adv-label secondary">文件路径</span>
            <input type="text" class="adv-input"
                   id="path"
                   name="<%= QueryParameters.PATH_SEARCH_PARAM %>"
                   placeholder="按路径过滤，例如 src/main/java…"
                   value="<%= Util.formQuoteEscape(qb.getPath()) %>" />
          </div>
          <div class="adv-row">
            <span class="adv-label secondary">历史</span>
            <input type="text" class="adv-input"
                   id="hist"
                   name="<%= QueryParameters.HIST_SEARCH_PARAM %>"
                   placeholder="搜索提交历史中的描述…"
                   value="<%= Util.formQuoteEscape(qb.getHist()) %>" />
          </div>
          <div class="adv-actions">
            <button type="submit" class="btn btn-primary">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><line x1="16.5" y1="16.5" x2="21" y2="21"/></svg>
              搜索
            </button>
            <button type="reset" class="btn btn-secondary">清除</button>
            <button type="button" class="btn btn-ghost" onclick="window.open('<%= ctxPath %>/help', '_blank')">帮助</button>
            <button type="button" class="btn btn-ghost" onclick="window.open('<%= ctxPath %>/settings', '_self')">设置</button>
          </div>
        </div>
      </div>

      <%-- Hidden multi-select for project submission; chips UI drives this list --%>
      <select id="project-select"
              name="<%= QueryParameters.PROJECT_SEARCH_PARAM %>"
              multiple="multiple"
              style="display:none">
          <% for (Project p : projects) {
              if (!p.isIndexed() || !cfg.isAllowed(p)) continue;
              String pname = p.getName();
              boolean selected = requestedProjects.contains(pname) || (!anyRequested && true);
              /* when no project requested, default-select all */
              String sel = (selected || !anyRequested) ? " selected" : "";
          %><option value="<%= Util.formQuoteEscape(pname) %>"<%= sel %>><%= Util.htmlize(pname) %></option><%
          } %>
        </select>
      <input type="hidden" id="<%= QueryParameters.NO_REDIRECT_PARAM %>" name="<%= QueryParameters.NO_REDIRECT_PARAM %>" value="" />
    </form>
  </section>

  <section class="project-section" data-od-id="project-section">
    <div class="project-bar">
      <label>项目</label>
      <div class="project-chips" id="project-chips">
        <% for (Project p : projects) {
            if (!p.isIndexed() || !cfg.isAllowed(p)) continue;
            String pname = p.getName();
            boolean selected = requestedProjects.contains(pname) || !anyRequested;
            String sel = selected ? " selected" : "";
        %><div class="chip"<%= sel %>
                 data-project="<%= Util.formQuoteEscape(pname) %>">
              <span class="chip-dot"></span>
              <%= Util.htmlize(pname) %>
            </div><%
        } %>
      </div>
      <div class="chip-actions">
        <button type="button" class="chip-action" data-action="select-all">全选</button>
        <button type="button" class="chip-action" data-action="invert-all">反选</button>
        <button type="button" class="chip-action" data-action="deselect-all">清除</button>
      </div>
    </div>
  </section>

  <section class="results-section" id="results-section" data-od-id="results-section">
    <div class="sort-bar" id="sort-bar">
      <span class="sort-label">排序：</span>
      <button class="sort-option" data-sort="modified" onclick="changeSort(this)">最后修改时间</button>
      <span class="sort-sep">|</span>
      <button class="sort-option active" data-sort="relevance" onclick="changeSort(this)">相关度</button>
      <span class="sort-sep">|</span>
      <button class="sort-option" data-sort="path" onclick="changeSort(this)">路径</button>
    </div>
    <div class="results-header" id="results-header"></div>
    <div class="results-list" id="results-list"></div>
    <div class="pagination" id="pagination">
      <button class="page-btn nav-btn" disabled>
        <svg viewBox="0 0 24 24"><polyline points="15 18 9 12 15 6"/></svg>
        Previous
      </button>
      <button class="page-btn active">1</button>
      <button class="page-btn">2</button>
      <button class="page-btn">3</button>
      <button class="page-btn">4</button>
      <button class="page-btn">5</button>
      <button class="page-btn">6</button>
      <button class="page-btn">7</button>
      <span class="page-ellipsis">…</span>
      <button class="page-btn">100</button>
      <button class="page-btn nav-btn">
        Next
        <svg viewBox="0 0 24 24"><polyline points="9 18 15 12 9 6"/></svg>
      </button>
    </div>
  </section>

  <% if (displayRepos && repoCount > 0) { %>
  <section id="repo-section" data-od-id="repo-section">
    <div class="repo-section-title">仓库列表 <span class="count"><%= repoCount %> 个仓库</span></div>
    <div class="repo-grid">
      <%
        for (Group g : ph.getGroups()) {
            if (!(cfg.isAllowed(g) || ph.hasAllowedSubgroup(g))) continue;
            for (Project p : ph.getProjects(g))          renderRepoCard(out, cfg, ctxPath, ph, p);
            for (Project p : ph.getRepositories(g))      renderRepoCard(out, cfg, ctxPath, ph, p);
        }
        for (Project p : ph.getUngroupedProjects())      renderRepoCard(out, cfg, ctxPath, ph, p);
        for (Project p : ph.getUngroupedRepositories())  renderRepoCard(out, cfg, ctxPath, ph, p);
      %>
    </div>
  </section>
  <% } %>

  <div class="footer" data-od-id="footer">
    由 <a href="https://oracle.github.io/opengrok/">OpenGrok</a> 托管
    <% if (dateForLastIndexRun != null) {
         /* Format: "2026 \u5e74 2 \u6708 15 \u65e5 15:06 CST" — 年/月/日 are literal chars in the pattern. */
         SimpleDateFormat lastIdxFmt = new SimpleDateFormat("yyyy \u5e74 M \u6708 d \u65e5 HH:mm zzz", Locale.US);
         String lastIdxText = lastIdxFmt.format(dateForLastIndexRun);
    %>
    &nbsp;·&nbsp; 最后索引更新：<%= lastIdxText %>
    <% } %>
    &nbsp;·&nbsp; <%= Info.getVersion() %> (<%= Info.getShortRevision() %>)
  </div>

</div>

<%= cfg.getEnv().getIncludeFiles().getBodyIncludeFileContent(false) %>

<script>
(function () {
    // ── DOM refs ──
    var sbox = document.getElementById('sbox');
    var fullInput = document.getElementById('full');
    var projectSelect = document.getElementById('project-select');
    var projectChips = document.getElementById('project-chips');
    var resultsSection = document.getElementById('results-section');
    var resultsHeader = document.getElementById('results-header');
    var resultsList = document.getElementById('results-list');
    var pagination = document.getElementById('pagination');
    var repoSection = document.getElementById('repo-section');
    var advPanel = document.getElementById('advanced-panel');
    var advToggleBtn = document.getElementById('adv-toggle');

    // ── Sync chips <-> hidden <select> ──
    function refreshProjectSelect() {
        if (!projectSelect) return;
        for (var i = 0; i < projectSelect.options.length; i++) {
            var name = projectSelect.options[i].value;
            var chip = projectChips ? projectChips.querySelector('[data-project="' + name.replace(/"/g, '\\"') + '"]') : null;
            projectSelect.options[i].selected = !!(chip && chip.classList.contains('selected'));
        }
    }

    // Per-chip click handler (attached via event delegation).
    function handleChipClick(ev) {
        var chip = ev.target.closest('.chip');
        if (!chip || !projectChips || !projectChips.contains(chip)) return;
        chip.classList.toggle('selected');
        refreshProjectSelect();
    }

    function selectAllProjects() {
        if (!projectChips) return;
        var chips = projectChips.querySelectorAll('.chip');
        for (var i = 0; i < chips.length; i++) chips[i].classList.add('selected');
        refreshProjectSelect();
    }

    function invertAllProjects() {
        if (!projectChips) return;
        var chips = projectChips.querySelectorAll('.chip');
        for (var i = 0; i < chips.length; i++) chips[i].classList.toggle('selected');
        refreshProjectSelect();
    }

    function deselectAllProjects() {
        if (!projectChips) return;
        var chips = projectChips.querySelectorAll('.chip');
        for (var i = 0; i < chips.length; i++) chips[i].classList.remove('selected');
        refreshProjectSelect();
    }

    // ── Wire up chips & action buttons via addEventListener (more robust than inline onclick) ──
    if (projectChips) {
        projectChips.addEventListener('click', handleChipClick);
    }
    var chipActionBtns = document.querySelectorAll('.chip-action[data-action]');
    chipActionBtns.forEach(function (btn) {
        var act = btn.getAttribute('data-action');
        var fn = ({ 'select-all': selectAllProjects,
                    'invert-all': invertAllProjects,
                    'deselect-all': deselectAllProjects })[act];
        if (fn) btn.addEventListener('click', fn);
    });
    // Also expose globally so any legacy `onclick="..."` (e.g. from cached HTML) still works.
    window.selectAllProjects  = selectAllProjects;
    window.invertAllProjects  = invertAllProjects;
    window.deselectAllProjects = deselectAllProjects;
    window.toggleChip          = handleChipClick;

    // ── Advanced panel toggle ──
    if (advToggleBtn && advPanel) {
        advToggleBtn.addEventListener('click', function () {
            advPanel.classList.toggle('open');
            advToggleBtn.classList.toggle('active');
        });
    }

    // ── Sort toggle (re-fetch /api/v1/search with new sort key) ──
    // OpenGrok's SortOrder enum names are: lastmodtime / relevancy / fullpath.
    // The data-sort attribute on each button uses short aliases; map to the API key here.
    var SORT_KEY_MAP = { 'modified': 'lastmodtime', 'relevance': 'relevancy', 'path': 'fullpath' };
    window.changeSort = function (el) {
        var sortAttr = el.getAttribute('data-sort');
        var apiSort = SORT_KEY_MAP[sortAttr] || 'relevancy';
        var opts = document.querySelectorAll('.sort-option');
        for (var i = 0; i < opts.length; i++) opts[i].classList.remove('active');
        el.classList.add('active');

        // Re-issue the same inline search as a regular submit, just with ?sort=apiSort appended.
        if (!sbox) return;
        var fd = new FormData(sbox);
        var params = new URLSearchParams();
        fd.forEach(function (v, k) {
            if (typeof v === 'string' && v.length) {
                var apiKey = FORM_TO_API_PARAM[k] || k;
                params.append(apiKey, v);
            }
        });
        var query = (fullInput && fullInput.value) ? fullInput.value.trim() : '';
        if (query) params.set('full', query);
        params.set('sort', apiSort);

        var url = (window.contextPath || '') + '/api/v1/search?' + params.toString();
        fetch(url, { headers: { 'Accept': 'application/json' } })
            .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
            .then(function (data) { renderResults(data, query); })
            .catch(function () { if (sbox) sbox.submit(); });
    };

    // Pagination is intentionally client-only for now (placeholder buttons in the static markup).
    // The real search API only returns the first page; pagination would require server-side support
    // (offset/limit params on SearchController), which is out of scope for the UI refactor.

    // ── Keyboard shortcut: Cmd/Ctrl+K to focus the primary search ──
    document.addEventListener('keydown', function (e) {
        if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
            e.preventDefault();
            if (fullInput) fullInput.focus();
        }
    });

    // ── Inline search via AJAX (uses /api/v1/search; falls back to /search) ──
    function escapeHtml(s) {
        return String(s).replace(/[&<>"']/g, function (c) {
            return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c];
        });
    }

    function renderResults(data, query) {
        if (!resultsSection || !resultsList || !resultsHeader) return;
        resultsSection.classList.add('visible');
        if (repoSection) repoSection.style.display = 'none';
        // /api/v1/search returns SearchResult{time, resultCount, results, startDocument, endDocument}
        // where `results` is a Map<String, List<SearchHit>> keyed by file path, and
        // each SearchHit has {line, lineNumber, tag}.
        var resultCount   = (data && typeof data.resultCount === 'number')   ? data.resultCount   : 0;
        var startDocument = (data && typeof data.startDocument === 'number') ? data.startDocument : 0;
        var endDocument   = (data && typeof data.endDocument === 'number')   ? data.endDocument   : startDocument;
        var resultsMap    = (data && data.results) ? data.results : {};
        var filePaths     = Object.keys(resultsMap);
        var fileCount     = filePaths.length;
        var fromIdx       = resultCount > 0 ? (startDocument + 1) : 0;
        var toIdx         = endDocument + 1;
        resultsHeader.innerHTML =
            '搜索 <strong>fulltext:<span class="query-term">' + escapeHtml(query) + '</span></strong>' +
            '（结果 ' + fromIdx + ' &mdash; ' + toIdx + ' 条，共 ' + resultCount + ' 条）按相关度排序';

        var MAX_HITS_PER_CARD = 10;
        var html = '';
        if (fileCount > 0) {
            // ── Group files by their parent directory so users see one "directory header"
            //    per group rather than a dir strip on every single file card. This matches
            //    the design: same-directory files share one accent-coloured dir link + a
            //    single hit-count badge. The dir link jumps to that directory's xref listing.
            var groups = Object.create(null);
            filePaths.forEach(function (path) {
                var lastSlash = path.lastIndexOf('/');
                var dir = lastSlash >= 0 ? path.substring(0, lastSlash) : '';
                if (!groups[dir]) groups[dir] = [];
                groups[dir].push({ path: path, hits: resultsMap[path] || [] });
            });

            Object.keys(groups).forEach(function (dir) {
                var files = groups[dir];
                var totalHits = 0;
                files.forEach(function (f) { totalHits += f.hits.length; });

                // Group header: directory path link + matches badge.
                html += '<div class="result-group-header">';
                html += '<svg viewBox="0 0 24 24"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>';
                if (dir) {
                    html += '<a href="<%= ctxPath %><%= Prefix.XREF_P %>/' + encodeURIComponent(dir) + '" title="' + escapeHtml(dir) + '">';
                    html += escapeHtml(dir);
                    html += '</a>';
                } else {
                    html += '<span class="group-root">(项目根)</span>';
                }
                html += '<span class="group-count" title="' + totalHits + ' 条匹配">' + totalHits + '</span>';
                html += '</div>';

                files.forEach(function (f) {
                    var path = f.path;
                    var hits = f.hits;
                    var name = path.split('/').pop() || path;
                    html += '<div class="result-file-card">';
                    html += '<div class="result-file-header">';
                    html += '<a href="<%= ctxPath %><%= Prefix.XREF_P %>/' + encodeURIComponent(path) + '" style="display:flex;align-items:center;gap:8px;flex:1;min-width:0;text-decoration:none;">';
                    html += '<svg viewBox="0 0 24 24"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>';
                    html += '<span class="file-path" title="' + escapeHtml(path) + '">' + escapeHtml(name) + '</span>';
                    html += '</a>';
                    html += '<div class="file-actions">';
                    html += '<a href="<%= ctxPath %><%= Prefix.HIST_L %>/' + encodeURIComponent(path) + '" class="action-btn"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>History</a>';
                    html += '<a href="<%= ctxPath %><%= Prefix.XREF_P %>/' + encodeURIComponent(path) + '?a=true" class="action-btn"><svg viewBox="0 0 24 24"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/></svg>Annotate</a>';
                    html += '<a href="<%= ctxPath %><%= Prefix.DOWNLOAD_P %>/' + encodeURIComponent(path) + '" class="action-btn"><svg viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg></a>';
                    html += '</div></div>';
                    if (hits.length) {
                        html += '<div class="result-lines">';
                        hits.forEach(function (h, i) {
                            var num  = h.lineNumber || '';
                            var code = h.line || '';
                            var tag  = h.tag || '';
                            var lineClass = (i >= MAX_HITS_PER_CARD) ? 'result-line result-line-overflow' : 'result-line';
                            html += '<a href="<%= ctxPath %><%= Prefix.XREF_P %>/' + encodeURIComponent(path) + '#L' + encodeURIComponent(num) + '" class="' + lineClass + '">';
                            html += '<span class="line-num">' + escapeHtml(num) + '</span>';
                            html += '<span class="line-code">';
                            if (tag) html += '<span class="match">' + escapeHtml(tag) + '</span> ';
                            html += escapeHtml(code) + '</span>';
                            html += '</a>';
                        });
                        html += '</div>';
                        if (hits.length > MAX_HITS_PER_CARD) {
                            var hiddenCount = hits.length - MAX_HITS_PER_CARD;
                            html += '<button type="button" class="result-expand-btn">';
                            html += '<svg class="arrow" viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>';
                            html += ' 显示剩余 <strong>' + hiddenCount + '</strong> 条匹配行';
                            html += '</button>';
                        }
                    }
                    html += '</div>';   // /result-file-card
                });
            });
        } else {
            html = '<div class="results-empty">未找到匹配项</div>';
        }
        resultsList.innerHTML = html;

        // Wire the expand buttons (delegated once per render; cheap).
        if (resultsList._expandBound) return;
        resultsList._expandBound = true;
        resultsList.addEventListener('click', function (ev) {
            var btn = ev.target.closest('.result-expand-btn');
            if (!btn) return;
            var card = btn.closest('.result-file-card');
            if (!card) return;
            var expanded = card.classList.toggle('expanded');
            var hidden  = card.querySelectorAll('.result-line-overflow').length;
            btn.innerHTML = '<svg class="arrow" viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>'
                + (expanded ? ' 收起' : (' 显示剩余 <strong>' + hidden + '</strong> 条匹配行'));
        });
    }

    // /api/v1/search expects different param names than the legacy form:
    //   form `defs`   → API `def`
    //   form `refs`   → API `symbol`
    //   form `project`→ API `projects` (List<String>)
    // See SearchController.search().
    var FORM_TO_API_PARAM = {
        'defs':    'def',
        'refs':    'symbol',
        'project': 'projects'
    };

    function performInlineSearch() {
        if (!sbox) return;
        var fd = new FormData(sbox);
        var params = new URLSearchParams();
        fd.forEach(function (v, k) {
            if (typeof v === 'string' && v.length) {
                var apiKey = FORM_TO_API_PARAM[k] || k;
                params.append(apiKey, v);
            }
        });
        var query = (fullInput && fullInput.value) ? fullInput.value.trim() : '';
        if (!query) return;
        params.set('<%= QueryParameters.FULL_SEARCH_PARAM %>', query);

        var url = (window.contextPath || '') + '/api/v1/search?' + params.toString();
        fetch(url, { headers: { 'Accept': 'application/json' } })
            .then(function (r) {
                if (!r.ok) throw new Error('HTTP ' + r.status);
                return r.json();
            })
            .then(function (data) { renderResults(data, query); })
            .catch(function () {
                // fall back to full page navigation
                if (sbox) sbox.submit();
            });
    }

    if (sbox) {
        sbox.addEventListener('submit', function (e) {
            e.preventDefault();
            performInlineSearch();
        });
    }

    // ── Initial sync: make sure hidden select matches default chip state ──
    refreshProjectSelect();

    // ── Wire up the suggester via utils.js (needs jQuery + jquery-ui + utils loaded) ──
    // domReadyMenu is provided by utils-0.0.48.js which loads AFTER this inline script,
    // so we just enqueue — do NOT use typeof check (it would be undefined here and the
    // callback would never be pushed). utils.js iterates document.domReady on
    // $(document).ready, by which time window.domReadyMenu is defined.
    if (document && Array.isArray(document.domReady)) {
        document.domReady.push(function () {
            // Override utils.js's getSelectedProjectNames (utils-0.0.48.js:2184).
            // The default reads from $("#project").searchableOptionList(), which
            // requires the legacy searchable-option-list widget mounted on
            // <select id="project"> — a structure our chip-based UI does not have.
            // If un-overridden, the suggest call goes out with projects=[] and
            // SuggesterServiceImpl.getNamedIndexReaders streams over an empty list,
            // so every autocomplete dropdown ends up empty regardless of what the
            // user types. Our chip UI keeps a hidden <select id="project-select"
            // multiple> in sync via refreshProjectSelect(), so read selected names
            // from there.
            window.getSelectedProjectNames = function () {
                var ps = document.getElementById('project-select');
                if (!ps) return [];
                var names = [];
                for (var i = 0; i < ps.options.length; i++) {
                    if (ps.options[i].selected) names.push(ps.options[i].value);
                }
                return names;
            };
            // The 5 inputs #full/#defs/#refs/#path/#hist already get jQuery UI
            // autocomplete widgets attached via initAutocompleteForField in
            // utils.js (utils-0.0.48.js:1743-1747). Each call passes the matching
            // "field" argument ("full" / "defs" / "refs" / "path" / "hist") which
            // is closed over and reached getAutocompleteMenuData() at keystroke
            // time, becoming the `field` query parameter of /api/v1/suggest —
            // i.e. typing in #defs asks for symbol definitions, typing in #refs
            // asks for symbol usages, etc. No per-input wiring needed here.
            window.domReadyMenu();

            // Pin popup width to its input width on every open. jQuery UI's default
            // _resizeMenu picks the max of widest item.outerWidth / input.outerWidth,
            // which lets long phrases stretch the popup past the input. We override
            // here so each popup exactly matches its input — and because each input
            // is bound separately, #defs / #refs / #path / #hist automatically get
            // their own correct (potentially narrower) width.
            $('#full, #defs, #refs, #path, #hist').on('autocompleteopen', function () {
                var $input = $(this);
                var $ul = $input.autocomplete('widget');
                $ul.outerWidth($input.outerWidth());
            });
        });
    }
})();
</script>
<%= PageConfig.get(request).getScripts() %>
</body>
</html><%
/* ---------------------- index.jsp end --------------------- */
%>