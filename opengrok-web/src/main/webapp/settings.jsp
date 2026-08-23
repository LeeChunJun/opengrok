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


Copyright (c) 2021, 2026, Oracle and/or its affiliates. All rights reserved.
Portions Copyright (c) 2026, UI Refactor.
--%>

<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page session="false" errorPage="error.jsp"%>
<%@ page import="
org.opengrok.web.PageConfig,
org.opengrok.indexer.configuration.RuntimeEnvironment"%>

<style>
:root {
    --fg:        #24292f;
    --accent:    #0969da;
    --font-sans: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif;
}

.settings-page { max-width: 640px; }
.settings-page h1 { font-size: 22px; font-weight: 600; margin: 8px 0 16px; color: var(--fg); }
.settings-page h3 { font-size: 14px; font-weight: 600; margin: 18px 0 8px; color: var(--fg); }
.settings-page label { display: block; font-size: 13px; color: var(--fg); margin: 6px 0; }
.settings-page select.local-setting,
.settings-page input.local-setting[type="checkbox"] { margin-left: 6px; accent-color: var(--accent); }
.settings-page input[type="button"] {
  background: var(--accent); color: #fff; border: none;
  padding: 8px 18px; border-radius: 7px; font-size: 13px; font-weight: 500;
  font-family: var(--font-sans); cursor: pointer; transition: background 0.12s;
  margin-top: 14px;
}
.settings-page input[type="button"]:hover { background: #2563eb; }
</style>

<%-- settings.jsp start

    settings.jsp -- OpenGrok settings page (theme + suggester toggle).
    Uses pageheader.jspf + foot.jspf for the new chrome.
--%>
<%
    {
        PageConfig _chromeSettingCfg = PageConfig.get(request);
        _chromeSettingCfg.setTitle("OpenGrok Settings");

        /* Inject page-specific CSS into <head> via pageheader.jspf. */
    }
%>
<%@include file="/pageheader.jspf" %>
<main class="container">
<div class="settings-page">
    <h1>Settings</h1>

    <h3>Appearance</h3>
    <label>Theme
        <select class="local-setting" name="theme-mode" data-default-value="auto"
                onchange="onSettingsValueChange(this)">
            <option value="auto">Use operating system setting</option>
            <option value="light">Light</option>
            <option value="dark">Dark</option>
        </select>
    </label>

    <h3>Suggester</h3>
    <%
        boolean suggesterEnabled = RuntimeEnvironment.getInstance().getSuggesterConfig().isEnabled();
    %>
    <label>Enabled
        <input class="local-setting" name="suggester-enabled" type="checkbox" data-checked-value="true"
               data-unchecked-value="false" data-default-value="<%= suggesterEnabled ? "true" : "false" %>"
               <%= suggesterEnabled ? "" : "disabled" %>
               onchange="onSettingsValueChange(this)">
    </label>

    <input class="submit btn" onclick="resetAllSettings()" type="button" value="Reset to defaults"/>
</div>
</main>
<script type="text/javascript">
    /* <![CDATA[ */
    document.pageReady.push(() => initSettings());
    /* ]]> */
</script>
<%@ include file="/foot.jspf" %>
<%= PageConfig.get(request).getScripts() %>
</body>
</html>