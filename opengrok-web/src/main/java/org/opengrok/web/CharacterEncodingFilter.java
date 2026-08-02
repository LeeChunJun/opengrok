/*
 * CDDL HEADER START
 *
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License (the "License").
 * You may not use this file except in compliance with the License.
 *
 * See LICENSE.txt included in this distribution for the specific
 * language governing permissions and limitations under the License.
 *
 * When distributing Covered Code, include this CDDL HEADER in each
 * file and include the License file at LICENSE.txt.
 * If applicable, add the following below this CDDL HEADER, with the
 * fields enclosed by brackets "[]" replaced with your own identifying
 * information: Portions Copyright [yyyy] [name of copyright owner]
 *
 * CDDL HEADER END
 */

/*
 * Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
 */
package org.opengrok.web;

import jakarta.servlet.Filter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.FilterConfig;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;

import java.io.IOException;

/**
 * Forces request and response character encoding to UTF-8.
 */
public class CharacterEncodingFilter implements Filter {
	
	private String encoding = "UTF-8";
	private boolean forceRequestEncoding = true;
	private boolean forceResponseEncoding = true;

    @Override
    public void init(FilterConfig filterConfig) {
    	String enc = filterConfig.getInitParameter("encoding");
    	if (enc != null && !enc.isBlank()) {
    		this.encoding = enc;
    	}
    	String forceReq = filterConfig.getInitParameter("forceRequestEncoding");
    	if (forceReq != null) {
    		this.forceRequestEncoding = Boolean.parseBoolean(forceReq);
    	}
    	String forceResp = filterConfig.getInitParameter("forceResponseEncoding");
    	if (forceResp != null) {
    		this.forceResponseEncoding = Boolean.parseBoolean(forceResp);
    	}
    }

    @Override
    public void doFilter(ServletRequest servletRequest, ServletResponse servletResponse, FilterChain chain)
            throws IOException, ServletException {
    	
    	if (forceRequestEncoding && servletRequest.getCharacterEncoding() == null) {
    		servletRequest.setCharacterEncoding(encoding);
    	}
    	
    	if (forceResponseEncoding && servletResponse.getCharacterEncoding() == null) {
    		servletResponse.setCharacterEncoding(encoding);
    	}
        
        chain.doFilter(servletRequest, servletResponse);
    }

    @Override
    public void destroy() {
        // Empty since there is No specific destroy configuration.
    }
}
