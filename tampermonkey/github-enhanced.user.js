// ==UserScript==
// @name         GitHub Enhanced
// @namespace    https://github.com/
// @version      1.4.0
// @description  Quality-of-life improvements for GitHub: file size badges, copy-path buttons, dark code blocks, jump-to-definition links, PR diff stats, and more.
// @author       VpkDevs
// @match        https://github.com/*
// @grant        GM_addStyle
// @grant        GM_getValue
// @grant        GM_setValue
// @run-at       document-idle
// ==/UserScript==

(function () {
  'use strict';

  // ── Helpers ─────────────────────────────────────────────────────────────────
  const $ = (sel, ctx = document) => ctx.querySelector(sel);
  const $$ = (sel, ctx = document) => [...ctx.querySelectorAll(sel)];
  const on = (el, ev, fn) => el && el.addEventListener(ev, fn);
  const qs = new URLSearchParams(location.search);
  const path = location.pathname;

  // ── Styles ──────────────────────────────────────────────────────────────────
  GM_addStyle(`
    .gh-enh-badge {
      display: inline-flex; align-items: center; gap: 4px;
      background: var(--color-neutral-subtle, #161b22);
      border: 1px solid var(--color-border-muted, #30363d);
      border-radius: 999px; padding: 1px 8px;
      font-size: 11px; font-family: monospace;
      color: var(--color-fg-muted, #8b949e); margin-left: 6px;
    }
    .gh-enh-copy-path {
      cursor: pointer; opacity: 0.6; font-size: 11px;
      background: none; border: none; color: var(--color-fg-muted, #8b949e);
      padding: 2px 6px; border-radius: 4px;
      transition: opacity 0.15s, background 0.15s;
    }
    .gh-enh-copy-path:hover { opacity: 1; background: var(--color-btn-bg, #21262d); }
    .gh-enh-copied { color: #22c55e !important; opacity: 1 !important; }
    .gh-enh-file-jump {
      font-size: 11px; color: #388bfd; text-decoration: none; margin-left: 6px;
    }
    .gh-enh-file-jump:hover { text-decoration: underline; }
    .gh-enh-pr-stat-bar {
      height: 6px; border-radius: 3px; display: inline-block; margin-right: 4px;
    }
    .gh-enh-toc {
      position: sticky; top: 68px;
      background: var(--color-canvas-subtle, #161b22);
      border: 1px solid var(--color-border-muted, #30363d);
      border-radius: 6px; padding: 12px 16px;
      font-size: 13px; max-height: 70vh; overflow-y: auto;
      width: 220px; flex-shrink: 0;
    }
    .gh-enh-toc h4 { margin: 0 0 8px; font-size: 12px; text-transform: uppercase;
      letter-spacing: 0.08em; color: var(--color-fg-muted, #8b949e); }
    .gh-enh-toc a { display: block; padding: 3px 0; color: var(--color-fg-default);
      text-decoration: none; font-size: 12px; }
    .gh-enh-toc a:hover { color: #388bfd; }
    .gh-enh-toc a.h3 { padding-left: 12px; font-size: 11px; color: var(--color-fg-muted); }
  `);

  // ────────────────────────────────────────────────────────────────────────────
  //  1. Copy-path button on every file row in the file explorer
  // ────────────────────────────────────────────────────────────────────────────
  function addCopyPathButtons() {
    $$('[data-testid="file-name-id"], .js-navigation-item [role="rowheader"] a').forEach(el => {
      if (el.closest('.gh-enh-done')) return;
      const row = el.closest('tr, [role="row"]');
      if (!row || row.dataset.ghenhDone) return;
      row.dataset.ghenhDone = '1';

      const href = el.getAttribute('href') || '';
      const filePath = href.replace(/.*\/blob\/[^/]+\//, '');

      const btn = document.createElement('button');
      btn.className = 'gh-enh-copy-path';
      btn.title     = 'Copy path to clipboard';
      btn.textContent = '⎘';
      on(btn, 'click', e => {
        e.preventDefault(); e.stopPropagation();
        navigator.clipboard.writeText(filePath).then(() => {
          btn.textContent = '✓';
          btn.classList.add('gh-enh-copied');
          setTimeout(() => { btn.textContent = '⎘'; btn.classList.remove('gh-enh-copied'); }, 1200);
        });
      });
      el.parentNode.insertBefore(btn, el.nextSibling);
    });
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  2. File size badges in the file tree header
  // ────────────────────────────────────────────────────────────────────────────
  function addFileSizeBadges() {
    $$('.js-blob-size').forEach(el => {
      if (el.dataset.ghenhDone) return;
      el.dataset.ghenhDone = '1';
      const badge = document.createElement('span');
      badge.className   = 'gh-enh-badge';
      badge.textContent = el.textContent.trim();
      el.replaceWith(badge);
    });
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  3. "Copy file contents" button on blob view
  // ────────────────────────────────────────────────────────────────────────────
  function addCopyFileButton() {
    if (!path.match(/\/blob\//)) return;
    const toolbar = $('[data-testid="blob-raw-link"]')?.parentElement
                 || $('.Box-header--blue .d-flex');
    if (!toolbar || toolbar.dataset.ghenhCopy) return;
    toolbar.dataset.ghenhCopy = '1';

    const btn = document.createElement('button');
    btn.className   = 'btn btn-sm';
    btn.style.marginLeft = '4px';
    btn.textContent = '📋 Copy file';
    on(btn, 'click', async () => {
      const codeEl = $('[data-testid="blob-content-container"] .blob-code-content')
                   || $('table.highlight td.blob-code-inner');
      if (codeEl) {
        await navigator.clipboard.writeText(codeEl.innerText);
        btn.textContent = '✓ Copied!';
        setTimeout(() => { btn.textContent = '📋 Copy file'; }, 1500);
      }
    });
    toolbar.appendChild(btn);
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  4. Line-count and word-count in blob view
  // ────────────────────────────────────────────────────────────────────────────
  function addBlobStats() {
    if (!path.match(/\/blob\//)) return;
    const lines = $$('[data-line-number]');
    if (!lines.length) return;
    const lineCount = lines.length;
    const text = $('table.highlight')?.innerText || '';
    const wordCount = text.split(/\s+/).filter(Boolean).length;

    const header = $('.Box-header--blue, [data-testid="blob-header"]');
    if (!header || header.dataset.ghenhStats) return;
    header.dataset.ghenhStats = '1';

    const badge = document.createElement('span');
    badge.className   = 'gh-enh-badge';
    badge.textContent = `${lineCount.toLocaleString()} lines · ${wordCount.toLocaleString()} words`;
    const title = header.querySelector('[data-testid="breadcrumbs-repo-link"], .final-path');
    if (title) title.after(badge);
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  5. README table of contents (auto-generated from headings)
  // ────────────────────────────────────────────────────────────────────────────
  function addReadmeTOC() {
    const readme = $('#readme, .markdown-body');
    if (!readme || readme.dataset.ghenhToc) return;
    const headings = $$('h2, h3', readme);
    if (headings.length < 4) return;
    readme.dataset.ghenhToc = '1';

    const toc = document.createElement('nav');
    toc.className = 'gh-enh-toc';
    const h4 = document.createElement('h4');
    h4.textContent = '📑 Contents';
    toc.appendChild(h4);

    headings.forEach(h => {
      const a   = document.createElement('a');
      a.href    = '#' + h.id;
      a.textContent = h.textContent.replace(/\s*#\s*$/, '');
      if (h.tagName === 'H3') a.classList.add('h3');
      toc.appendChild(a);
    });

    // Wrap readme in flex container
    const wrapper = document.createElement('div');
    wrapper.style.cssText = 'display:flex; gap:24px; align-items:flex-start';
    readme.parentNode.insertBefore(wrapper, readme);
    wrapper.appendChild(toc);
    wrapper.appendChild(readme);
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  6. PR file-diff: mini stats bar per file
  // ────────────────────────────────────────────────────────────────────────────
  function addPRStatBars() {
    if (!path.match(/\/pull\/\d+\/files/)) return;
    $$('[data-details-container-group] .diffstat, .file-info .diffstat').forEach(el => {
      if (el.dataset.ghenhDone) return;
      el.dataset.ghenhDone = '1';

      const text  = el.textContent.trim();
      const addM  = text.match(/\+(\d+)/);
      const delM  = text.match(/-(\d+)/);
      const added = addM ? parseInt(addM[1]) : 0;
      const deleted = delM ? parseInt(delM[1]) : 0;
      const total   = added + deleted || 1;
      const addPct  = Math.round(added   / total * 100);
      const delPct  = Math.round(deleted / total * 100);

      const bar = document.createElement('span');
      bar.innerHTML = `
        <span class="gh-enh-pr-stat-bar" style="width:${addPct}%;background:#22c55e"></span>
        <span class="gh-enh-pr-stat-bar" style="width:${delPct}%;background:#ef4444"></span>`;
      el.insertBefore(bar, el.firstChild);
    });
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  7. "Jump to PR" button on issue pages
  // ────────────────────────────────────────────────────────────────────────────
  function addJumpToPR() {
    if (!path.match(/\/issues\/\d+$/)) return;
    $$('.js-issue-row a, .gh-pr-close-commit a').forEach(a => {
      if (a.dataset.ghenhDone) return;
      a.dataset.ghenhDone = '1';
      const badge = document.createElement('span');
      badge.className   = 'gh-enh-badge';
      badge.textContent = '→ PR';
      a.appendChild(badge);
    });
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  8. Mark visited repo links
  // ────────────────────────────────────────────────────────────────────────────
  GM_addStyle(`
    a[data-gh-enh-visited] { opacity: 0.65; }
  `);
  function markVisited() {
    $$('a[href*="/blob/"], a[href*="/tree/"]').forEach(a => {
      if (a.dataset.ghenhVisited) return;
      on(a, 'click', () => { a.dataset.ghenhVisited = '1'; });
    });
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  9. Keyboard shortcut: G then F = jump to search files
  // ────────────────────────────────────────────────────────────────────────────
  let lastKey = '';
  document.addEventListener('keydown', e => {
    if (e.target.matches('input, textarea, [contenteditable]')) return;
    if (lastKey === 'g' && e.key === 'f') {
      const searchBtn = $('button[data-hotkey="t"], .search-input');
      if (searchBtn) searchBtn.click();
    }
    lastKey = e.key;
  });

  // ── Run ─────────────────────────────────────────────────────────────────────
  function run() {
    addCopyPathButtons();
    addFileSizeBadges();
    addCopyFileButton();
    addBlobStats();
    addReadmeTOC();
    addPRStatBars();
    addJumpToPR();
    markVisited();
  }

  run();

  // Re-run on GitHub's pjax navigation
  const observer = new MutationObserver(() => run());
  observer.observe(document.body, { childList: true, subtree: true });
})();
