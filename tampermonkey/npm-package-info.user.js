// ==UserScript==
// @name         NPM & PyPI Package Info
// @namespace    https://github.com/VpkDevs
// @version      1.3.0
// @description  Hover over package names on npm, PyPI, GitHub dependency files and other pages to get an instant inline info card.
// @author       VpkDevs
// @match        https://www.npmjs.com/*
// @match        https://pypi.org/*
// @match        https://github.com/*
// @match        https://stackoverflow.com/*
// @match        https://*.stackexchange.com/*
// @connect      registry.npmjs.org
// @connect      pypi.org
// @grant        GM_xmlhttpRequest
// @grant        GM_addStyle
// @grant        GM_getValue
// @grant        GM_setValue
// @run-at       document-idle
// ==/UserScript==

(function () {
  'use strict';

  // ── Cache ────────────────────────────────────────────────────────────────────
  const cache = {};
  function getCache(key) { return cache[key]; }
  function setCache(key, val) { cache[key] = val; }

  // ── Styles ──────────────────────────────────────────────────────────────────
  GM_addStyle(`
    #pkg-info-card {
      position: fixed; z-index: 99999; pointer-events: none;
      background: #0d1117; border: 1px solid #30363d; border-radius: 10px;
      padding: 14px 18px; font-family: 'Segoe UI', sans-serif;
      color: #e2e8f0; font-size: 13px; max-width: 340px; min-width: 240px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.7);
      opacity: 0; transition: opacity 0.15s;
    }
    #pkg-info-card.visible { opacity: 1; pointer-events: auto; }
    #pkg-info-card .pkg-name  { font-size: 16px; font-weight: 700; color: #60a5fa; }
    #pkg-info-card .pkg-ver   { font-size: 12px; color: #6b7280; margin-bottom: 8px; }
    #pkg-info-card .pkg-desc  { color: #94a3b8; font-size: 13px; margin-bottom: 10px; line-height: 1.5; }
    #pkg-info-card .pkg-meta  { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 10px; }
    #pkg-info-card .pkg-chip  {
      background: #1e293b; border: 1px solid #334155; border-radius: 4px;
      padding: 2px 8px; font-size: 11px; color: #94a3b8;
    }
    #pkg-info-card .pkg-chip.green  { border-color: #166534; background: #052e16; color: #86efac; }
    #pkg-info-card .pkg-chip.yellow { border-color: #854d0e; background: #1c1400; color: #fef08a; }
    #pkg-info-card .pkg-chip.red    { border-color: #7f1d1d; background: #1c0000; color: #fca5a5; }
    #pkg-info-card .pkg-links a {
      color: #388bfd; text-decoration: none; font-size: 12px; margin-right: 10px;
    }
    #pkg-info-card .pkg-links a:hover { text-decoration: underline; }
    #pkg-info-card .pkg-loading { color: #6b7280; font-style: italic; }
    .pkg-hover-target { border-bottom: 1px dashed #388bfd; cursor: help; }
  `);

  // ── Card element ─────────────────────────────────────────────────────────────
  const card = document.createElement('div');
  card.id = 'pkg-info-card';
  document.body.appendChild(card);

  let hideTimer;

  function showCard(x, y, html) {
    card.innerHTML = html;
    const vw = window.innerWidth, vh = window.innerHeight;
    let cx = x + 16, cy = y + 16;
    if (cx + 360 > vw) cx = vw - 370;
    if (cy + 260 > vh) cy = y - 260;
    card.style.left = cx + 'px';
    card.style.top  = cy + 'px';
    card.classList.add('visible');
  }

  function hideCard() {
    card.classList.remove('visible');
  }

  // ── Fetch npm info ────────────────────────────────────────────────────────────
  function fetchNpm(pkg, x, y) {
    const key = 'npm:' + pkg;
    if (getCache(key)) { showCard(x, y, getCache(key)); return; }

    showCard(x, y, `<div class="pkg-loading">Loading ${pkg}…</div>`);

    GM_xmlhttpRequest({
      method: 'GET',
      url:    `https://registry.npmjs.org/${encodeURIComponent(pkg)}/latest`,
      onload: res => {
        if (res.status !== 200) {
          setCache(key, `<div class="pkg-loading">Not found: ${pkg}</div>`);
          showCard(x, y, getCache(key));
          return;
        }
        try {
          const d = JSON.parse(res.responseText);
          const stars = formatNum(d.github?.stars);
          const dlTrend = d.dist?.integrity ? '✓' : '';
          const ageMonths = d.date ? Math.round((Date.now() - new Date(d.date)) / (30*24*3600*1000)) : null;
          const ageColor  = ageMonths === null ? '' : ageMonths < 6 ? 'green' : ageMonths < 24 ? 'yellow' : 'red';
          const ageLabel  = ageMonths === null ? '' : ageMonths < 1 ? '< 1 month ago' : `${ageMonths}mo ago`;

          const html = `
            <div class="pkg-name">📦 ${escHtml(d.name)}</div>
            <div class="pkg-ver">v${escHtml(d.version || '?')} · npm</div>
            <div class="pkg-desc">${escHtml((d.description || 'No description').slice(0, 120))}</div>
            <div class="pkg-meta">
              ${d.license ? `<span class="pkg-chip">${escHtml(d.license)}</span>` : ''}
              ${ageLabel   ? `<span class="pkg-chip ${ageColor}">📅 ${ageLabel}</span>` : ''}
              ${d.engines?.node ? `<span class="pkg-chip">Node ${escHtml(d.engines.node)}</span>` : ''}
            </div>
            <div class="pkg-links">
              <a href="https://www.npmjs.com/package/${encodeURIComponent(pkg)}" target="_blank">npm page →</a>
              ${d.homepage ? `<a href="${escHtml(d.homepage)}" target="_blank">Homepage →</a>` : ''}
              ${d.repository?.url ? `<a href="${escHtml(cleanRepoUrl(d.repository.url))}" target="_blank">Repo →</a>` : ''}
            </div>`;
          setCache(key, html);
          showCard(x, y, html);
        } catch {
          showCard(x, y, `<div class="pkg-loading">Parse error for ${pkg}</div>`);
        }
      },
      onerror: () => showCard(x, y, `<div class="pkg-loading">Error fetching ${pkg}</div>`)
    });
  }

  // ── Fetch PyPI info ───────────────────────────────────────────────────────────
  function fetchPypi(pkg, x, y) {
    const key = 'pypi:' + pkg;
    if (getCache(key)) { showCard(x, y, getCache(key)); return; }

    showCard(x, y, `<div class="pkg-loading">Loading ${pkg}…</div>`);

    GM_xmlhttpRequest({
      method: 'GET',
      url:    `https://pypi.org/pypi/${encodeURIComponent(pkg)}/json`,
      onload: res => {
        if (res.status !== 200) {
          setCache(key, `<div class="pkg-loading">Not found: ${pkg}</div>`);
          showCard(x, y, getCache(key));
          return;
        }
        try {
          const d = JSON.parse(res.responseText).info;
          const html = `
            <div class="pkg-name">🐍 ${escHtml(d.name)}</div>
            <div class="pkg-ver">v${escHtml(d.version || '?')} · PyPI</div>
            <div class="pkg-desc">${escHtml((d.summary || 'No description').slice(0, 120))}</div>
            <div class="pkg-meta">
              ${d.license ? `<span class="pkg-chip">${escHtml(d.license.slice(0,30))}</span>` : ''}
              ${d.requires_python ? `<span class="pkg-chip">Python ${escHtml(d.requires_python)}</span>` : ''}
            </div>
            <div class="pkg-links">
              <a href="https://pypi.org/project/${encodeURIComponent(pkg)}" target="_blank">PyPI page →</a>
              ${d.home_page ? `<a href="${escHtml(d.home_page)}" target="_blank">Homepage →</a>` : ''}
              ${d.project_urls?.Source ? `<a href="${escHtml(d.project_urls.Source)}" target="_blank">Source →</a>` : ''}
            </div>`;
          setCache(key, html);
          showCard(x, y, html);
        } catch {
          showCard(x, y, `<div class="pkg-loading">Parse error for ${pkg}</div>`);
        }
      },
      onerror: () => showCard(x, y, `<div class="pkg-loading">Error fetching ${pkg}</div>`)
    });
  }

  function cleanRepoUrl(url) {
    return url.replace(/^git\+/, '').replace(/\.git$/, '').replace(/^git:\/\//, 'https://');
  }
  function escHtml(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
  function formatNum(n) { return n ? Number(n).toLocaleString() : ''; }

  // ── Host matching helper ──────────────────────────────────────────────────────
  function matchHost(domain) {
    const h = location.hostname;
    return h === domain || h.endsWith('.' + domain);
  }

  // ── Detect package refs in the page ──────────────────────────────────────────
  // package.json on GitHub
  function instrumentPackageJson() {
    if (!location.pathname.endsWith('package.json')) return;
    document.querySelectorAll('.blob-code-inner .pl-s').forEach(el => {
      if (el.dataset.pkgDone) return;
      const text = el.textContent.trim().replace(/^["']|["']$/g, '');
      if (!text || text.startsWith('.') || text.includes('/')) return;
      el.dataset.pkgDone = '1';
      el.classList.add('pkg-hover-target');
      el.addEventListener('mouseenter', e => { clearTimeout(hideTimer); fetchNpm(text, e.clientX, e.clientY); });
      el.addEventListener('mouseleave', () => { hideTimer = setTimeout(hideCard, 300); });
    });
  }

  // requirements.txt / Pipfile on GitHub
  function instrumentRequirementsTxt() {
    if (!location.pathname.match(/requirements.*\.txt$|Pipfile$/)) return;
    document.querySelectorAll('.blob-code-inner').forEach(line => {
      const text = line.textContent.trim().split(/[>=<!\[;\s]/)[0];
      if (!text || text.startsWith('#')) return;
      if (line.dataset.pkgDone) return;
      line.dataset.pkgDone = '1';
      line.classList.add('pkg-hover-target');
      line.addEventListener('mouseenter', e => { clearTimeout(hideTimer); fetchPypi(text, e.clientX, e.clientY); });
      line.addEventListener('mouseleave', () => { hideTimer = setTimeout(hideCard, 300); });
    });
  }

  // npm page itself — package name in header
  function instrumentNpmPage() {
    if (!matchHost('npmjs.com')) return;
    const heading = document.querySelector('h1, [data-testid="package-name"]');
    if (!heading || heading.dataset.pkgDone) return;
    heading.dataset.pkgDone = '1';
    const name = heading.textContent.trim();
    // Auto-show card for the current package page
    setTimeout(() => fetchNpm(name, 60, 140), 800);
  }

  // PyPI page itself
  function instrumentPypiPage() {
    if (!matchHost('pypi.org')) return;
    const m = location.pathname.match(/\/project\/([^/]+)/);
    if (!m) return;
    setTimeout(() => fetchPypi(m[1], 60, 140), 800);
  }

  // Inline code blocks on Stack Overflow mentioning package-like names
  function instrumentCodeBlocks() {
    if (!matchHost('stackoverflow.com') && !matchHost('stackexchange.com')) return;
    document.querySelectorAll('code').forEach(el => {
      if (el.dataset.pkgDone) return;
      const text = el.textContent.trim();
      // Heuristic: short lowercase names without spaces or special chars = possible package
      if (!text || text.length < 2 || text.length > 60 || /\s|[<>(){}[\]]/.test(text)) return;
      const isNpmLike   = /^[@a-z0-9][a-z0-9\-._/]*$/i.test(text) && !text.includes(' ');
      const isPypiLike  = /^[a-zA-Z0-9][a-zA-Z0-9\-_.]*$/.test(text);
      if (!isNpmLike && !isPypiLike) return;
      el.dataset.pkgDone = '1';
      el.style.cursor = 'help';
      el.addEventListener('mouseenter', e => {
        clearTimeout(hideTimer);
        // Guess: if it looks npm-ish try npm first, else pypi
        if (text.startsWith('@') || text.includes('/'))
          fetchNpm(text, e.clientX, e.clientY);
        else if (matchHost('pypi.org'))
          fetchPypi(text, e.clientX, e.clientY);
        else
          fetchNpm(text, e.clientX, e.clientY);
      });
      el.addEventListener('mouseleave', () => { hideTimer = setTimeout(hideCard, 350); });
    });
  }

  // Keep card visible while hovered
  card.addEventListener('mouseenter', () => clearTimeout(hideTimer));
  card.addEventListener('mouseleave', () => { hideTimer = setTimeout(hideCard, 300); });

  // ── Run ─────────────────────────────────────────────────────────────────────
  function run() {
    instrumentPackageJson();
    instrumentRequirementsTxt();
    instrumentNpmPage();
    instrumentPypiPage();
    instrumentCodeBlocks();
  }

  run();
  const obs = new MutationObserver(run);
  obs.observe(document.body, { childList: true, subtree: true });
})();
