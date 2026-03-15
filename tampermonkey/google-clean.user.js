// ==UserScript==
// @name         Google Search Cleaner
// @namespace    https://www.google.com/
// @version      2.0.0
// @description  Remove sponsored results, tracking from links, add DuckDuckGo and other engine shortcuts, and clean up the Google search UI.
// @author       VpkDevs
// @match        https://www.google.com/search*
// @match        https://www.google.co.uk/search*
// @match        https://www.google.ca/search*
// @match        https://www.google.com.au/search*
// @match        https://www.google.*/search*
// @grant        GM_addStyle
// @grant        GM_getValue
// @grant        GM_setValue
// @run-at       document-end
// ==/UserScript==

(function () {
  'use strict';

  // ── Config ──────────────────────────────────────────────────────────────────
  const CFG = {
    removeSponsored:     GM_getValue('removeSponsored',  true),
    removeTracking:      GM_getValue('removeTracking',   true),
    showAltEngines:      GM_getValue('showAltEngines',   true),
    highlightDomains:    GM_getValue('highlightDomains', true),
    compactResults:      GM_getValue('compactResults',   false),
    blacklistDomains:    GM_getValue('blacklistDomains', 'pinterest.com,w3schools.com'),
  };

  // ── Styles ──────────────────────────────────────────────────────────────────
  GM_addStyle(`
    /* Engine switcher bar */
    #gs-engine-bar {
      display: flex; align-items: center; gap: 8px;
      padding: 8px 16px; background: #1a1a2e;
      border-bottom: 1px solid #30363d; flex-wrap: wrap;
    }
    #gs-engine-bar span { color: #6b7280; font-size: 12px; }
    .gs-engine-link {
      display: inline-flex; align-items: center; gap: 4px;
      background: #1e1e2e; color: #94a3b8; text-decoration: none;
      padding: 4px 12px; border-radius: 6px; font-size: 12px;
      border: 1px solid #374151; transition: all 0.15s;
    }
    .gs-engine-link:hover { background: #2d2d3e; color: #e2e8f0; border-color: #4b5563; }

    /* Sponsored label */
    .gs-sponsored-badge {
      display: inline-block; background: #7c2d12; color: #fed7aa;
      font-size: 10px; padding: 1px 6px; border-radius: 3px;
      margin-left: 6px; vertical-align: middle; font-weight: 600;
    }

    /* Blacklisted domains */
    .gs-blacklisted { opacity: 0.35; border-left: 3px solid #ef4444 !important; }

    /* Trusted domain highlight */
    .gs-trusted cite::after {
      content: ' ✓'; color: #22c55e; font-size: 11px; font-weight: bold;
    }

    /* Compact mode */
    body.gs-compact .g { margin-bottom: 8px !important; }
    body.gs-compact .g .tF2Cxc { padding: 8px 0 !important; }

    /* Clean up some Google UI noise */
    #tpd, .M8OgIe, .ULSxyf, [data-ved][data-cad] { opacity: 0.8; }
  `);

  // ── Trusted domains (show checkmark) ────────────────────────────────────────
  const TRUSTED_DOMAINS = [
    'github.com', 'stackoverflow.com', 'developer.mozilla.org',
    'docs.microsoft.com', 'learn.microsoft.com', 'npmjs.com',
    'pypi.org', 'rust-lang.org', 'go.dev', 'php.net',
    'reactjs.org', 'react.dev', 'vuejs.org', 'svelte.dev',
    'nodejs.org', 'typescriptlang.org', 'python.org',
    'wikipedia.org', 'arxiv.org', 'medium.com',
  ];

  // ── Get query from URL ───────────────────────────────────────────────────────
  function getQuery() {
    return new URLSearchParams(location.search).get('q') || '';
  }

  function encQ() { return encodeURIComponent(getQuery()); }

  // ── 1. Remove sponsored / ad results ────────────────────────────────────────
  function removeSponsored() {
    if (!CFG.removeSponsored) return;
    let removed = 0;

    // Various ways Google marks ads
    const adSelectors = [
      '[data-text-ad]', '.commercial-unit-desktop-top',
      '.commercial-unit-desktop-rhs', '.uEierd',
      'div[data-sokoban-container]', '[data-hveid][data-ved] [aria-label*="Ad"]',
      '#tads', '#tadsb', '#bottomads', '.x54gtf',
      '[data-rw]', '.ads-visurl', '[class*="commercial"]',
    ];

    adSelectors.forEach(sel => {
      document.querySelectorAll(sel).forEach(el => {
        const container = el.closest('.g, [data-hveid]') || el;
        container.style.display = 'none';
        removed++;
      });
    });

    // Heuristic: look for "Sponsored" text in result headers
    document.querySelectorAll('.g .yuRUbf, .g h3').forEach(el => {
      const parent = el.closest('.g');
      if (!parent) return;
      const text = parent.textContent;
      if (/Sponsored|Anzeige|Annonce|Patrocinado/i.test(text)) {
        parent.style.display = 'none';
        removed++;
      }
    });

    if (removed) console.debug(`[GS Cleaner] Removed ${removed} sponsored results`);
  }

  // ── 2. Strip tracking from result URLs ──────────────────────────────────────
  function cleanLinks() {
    if (!CFG.removeTracking) return;
    document.querySelectorAll('a[href*="google.com/url"], a[href*="/url?"]').forEach(a => {
      try {
        const url  = new URL(a.href);
        const real = url.searchParams.get('q') || url.searchParams.get('url') || '';
        if (real && real.startsWith('http')) {
          a.href = real;
        }
      } catch {}
    });

    // Also clean data-href / ping attributes
    document.querySelectorAll('a[ping]').forEach(a => a.removeAttribute('ping'));
    document.querySelectorAll('a[data-href]').forEach(a => {
      const dh = a.getAttribute('data-href');
      if (dh && dh.startsWith('http')) a.href = dh;
    });
  }

  // ── 3. Engine switcher ───────────────────────────────────────────────────────
  function addEngineSwitcher() {
    if (!CFG.showAltEngines || document.getElementById('gs-engine-bar')) return;

    const q = encQ();
    const engines = [
      { name: '🦆 DuckDuckGo', url: `https://duckduckgo.com/?q=${q}` },
      { name: '🔍 Bing',       url: `https://www.bing.com/search?q=${q}` },
      { name: '🦊 Brave',      url: `https://search.brave.com/search?q=${q}` },
      { name: '📚 Kagi',       url: `https://kagi.com/search?q=${q}` },
      { name: '🧅 Searx',      url: `https://searx.be/search?q=${q}` },
      { name: '📖 Phind',      url: `https://phind.com/search?q=${q}` },
      { name: '🤖 Perplexity', url: `https://www.perplexity.ai/search?q=${q}` },
    ];

    const bar = document.createElement('div');
    bar.id = 'gs-engine-bar';
    bar.innerHTML = `<span>Also search:</span>` +
      engines.map(e => `<a class="gs-engine-link" href="${e.url}" target="_blank" rel="noreferrer">${e.name}</a>`).join('');

    // Insert after the search bar
    const resultStats = document.getElementById('result-stats')
                     || document.getElementById('appbar');
    if (resultStats) resultStats.after(bar);
    else document.body.insertBefore(bar, document.body.firstChild);
  }

  // ── 4. Highlight / dim domains ───────────────────────────────────────────────
  function processDomains() {
    if (!CFG.highlightDomains) return;
    const blacklist = CFG.blacklistDomains.split(',').map(s => s.trim()).filter(Boolean);

    document.querySelectorAll('.g').forEach(result => {
      if (result.dataset.gsCleaned) return;
      result.dataset.gsCleaned = '1';

      const cite = result.querySelector('cite');
      if (!cite) return;
      const domainText = cite.textContent.toLowerCase();

      if (blacklist.some(d => domainText.includes(d))) {
        result.classList.add('gs-blacklisted');
        result.title = 'Domain is on your blocked list';
      } else if (TRUSTED_DOMAINS.some(d => domainText.includes(d))) {
        result.classList.add('gs-trusted');
      }
    });
  }

  // ── 5. Keyboard shortcuts ────────────────────────────────────────────────────
  document.addEventListener('keydown', e => {
    if (e.target.matches('input, textarea')) return;
    // Alt+D  →  search DuckDuckGo
    if (e.altKey && e.key === 'd') {
      window.open(`https://duckduckgo.com/?q=${encQ()}`, '_blank');
    }
    // Alt+P  →  search Perplexity
    if (e.altKey && e.key === 'p') {
      window.open(`https://www.perplexity.ai/search?q=${encQ()}`, '_blank');
    }
  });

  // ── 6. Compact mode toggle ────────────────────────────────────────────────────
  if (CFG.compactResults) document.body.classList.add('gs-compact');

  // ── Run ─────────────────────────────────────────────────────────────────────
  function run() {
    removeSponsored();
    cleanLinks();
    addEngineSwitcher();
    processDomains();
  }

  run();

  // Re-run on lazy-loaded results
  const observer = new MutationObserver(() => {
    removeSponsored();
    cleanLinks();
    processDomains();
  });
  observer.observe(document.getElementById('search') || document.body, {
    childList: true, subtree: true
  });
})();
