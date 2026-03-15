// ==UserScript==
// @name         Stack Overflow Enhancer
// @namespace    https://stackoverflow.com/
// @version      1.5.0
// @description  Better code copying, syntax-highlighted copy buttons, jump to accepted answer, collapse noise, and question age warnings.
// @author       VpkDevs
// @match        https://stackoverflow.com/*
// @match        https://superuser.com/*
// @match        https://serverfault.com/*
// @match        https://*.stackexchange.com/*
// @grant        GM_addStyle
// @run-at       document-idle
// ==/UserScript==

(function () {
  'use strict';

  GM_addStyle(`
    .so-enh-copy-btn {
      position: absolute; top: 6px; right: 6px;
      background: #2d2d3e; color: #94a3b8;
      border: 1px solid #374151; border-radius: 5px;
      padding: 3px 10px; font-size: 11px; cursor: pointer;
      font-family: 'Segoe UI', sans-serif; transition: all 0.15s;
      z-index: 10;
    }
    .so-enh-copy-btn:hover { background: #3f3f5a; color: #e2e8f0; }
    .so-enh-copy-btn.copied { background: #166534; color: #86efac; border-color: #166534; }
    .so-enh-jump-btn {
      display: inline-flex; align-items: center; gap: 6px;
      background: #1e3a5f; color: #93c5fd; border: 1px solid #1d4ed8;
      border-radius: 6px; padding: 6px 14px; font-size: 13px;
      cursor: pointer; text-decoration: none; margin: 10px 0 4px;
      font-family: 'Segoe UI', sans-serif;
      transition: background 0.15s;
    }
    .so-enh-jump-btn:hover { background: #1d4ed8; color: white; }
    .so-enh-age-warning {
      display: inline-flex; align-items: center; gap: 6px;
      background: #451a03; color: #fed7aa; border: 1px solid #c2410c;
      border-radius: 6px; padding: 6px 12px; font-size: 12px; margin: 8px 0;
    }
    .so-enh-vote-bar {
      display: inline-block; height: 4px; border-radius: 2px;
      vertical-align: middle; margin-left: 6px;
    }
    pre { position: relative !important; }
    .so-enh-line-count {
      position: absolute; top: 6px; left: 10px;
      background: rgba(0,0,0,0.3); color: #6b7280;
      font-size: 10px; padding: 1px 6px; border-radius: 3px;
    }
    .so-enh-collapse-btn {
      cursor: pointer; font-size: 11px; color: #6b7280;
      background: none; border: none; padding: 0 4px;
      text-decoration: underline;
    }
    .so-enh-toolbar {
      display: flex; align-items: center; gap: 8px;
      padding: 8px 0; border-bottom: 1px solid #374151;
      margin-bottom: 12px;
    }
    .so-enh-toolbar a {
      font-size: 13px; color: #60a5fa; text-decoration: none; padding: 4px 8px;
      border-radius: 4px; background: rgba(96,165,250,0.1);
    }
    .so-enh-toolbar a:hover { background: rgba(96,165,250,0.2); }
  `);

  // ── Helpers ─────────────────────────────────────────────────────────────────
  const $ = s => document.querySelector(s);
  const $$ = s => [...document.querySelectorAll(s)];
  const on = (el, ev, fn) => el?.addEventListener(ev, fn);

  function copyText(text, btn) {
    navigator.clipboard.writeText(text).then(() => {
      btn.textContent = '✓ Copied';
      btn.classList.add('copied');
      setTimeout(() => {
        btn.textContent = '⎘ Copy';
        btn.classList.remove('copied');
      }, 1500);
    });
  }

  // ── 1. Copy buttons on code blocks ──────────────────────────────────────────
  function addCopyButtons() {
    $$('pre code, pre.s-code-block').forEach(codeEl => {
      const pre = codeEl.tagName === 'PRE' ? codeEl : codeEl.parentElement;
      if (!pre || pre.dataset.soEnh) return;
      pre.dataset.soEnh = '1';
      pre.style.position = 'relative';

      const lines = codeEl.textContent.split('\n').length;

      const btn = document.createElement('button');
      btn.className   = 'so-enh-copy-btn';
      btn.textContent = '⎘ Copy';
      on(btn, 'click', () => copyText(codeEl.textContent, btn));
      pre.appendChild(btn);

      if (lines > 5) {
        const lineLbl = document.createElement('span');
        lineLbl.className   = 'so-enh-line-count';
        lineLbl.textContent = `${lines} lines`;
        pre.appendChild(lineLbl);
      }
    });
  }

  // ── 2. Jump to accepted answer ───────────────────────────────────────────────
  function addJumpToAccepted() {
    const accepted = $('.accepted-answer');
    if (!accepted || $('#so-enh-jump')) return;

    const container = $('.post-text, .question, .s-post-summary');
    if (!container) return;

    const btn = document.createElement('a');
    btn.id        = 'so-enh-jump';
    btn.className = 'so-enh-jump-btn';
    btn.href      = '#' + accepted.id;
    btn.innerHTML = '✓ Jump to Accepted Answer';
    btn.addEventListener('click', e => {
      e.preventDefault();
      accepted.scrollIntoView({ behavior: 'smooth', block: 'start' });
      accepted.style.outline = '2px solid #22c55e';
      setTimeout(() => { accepted.style.outline = ''; }, 2000);
    });

    // Insert near the question header
    const questionTitle = $('.question-header, h1[itemprop="name"]');
    if (questionTitle) questionTitle.after(btn);
  }

  // ── 3. Age warning for old questions ────────────────────────────────────────
  function addAgeWarning() {
    const dateEl = $('[itemprop="dateCreated"], .question-header time, .asked time');
    if (!dateEl || dateEl.dataset.soAgeWarn) return;
    dateEl.dataset.soAgeWarn = '1';

    const dateStr = dateEl.getAttribute('datetime') || dateEl.textContent;
    const date    = new Date(dateStr);
    if (isNaN(date)) return;

    const ageYears = (Date.now() - date) / (365.25 * 24 * 3600 * 1000);
    if (ageYears < 3) return;

    const warn = document.createElement('div');
    warn.className   = 'so-enh-age-warning';
    warn.textContent = `⚠ This question is ${Math.floor(ageYears)} years old — some answers may be outdated.`;
    const header = $('.question-header, h1[itemprop="name"]')?.parentElement;
    if (header) header.insertBefore(warn, header.children[1]);
  }

  // ── 4. Keyboard shortcut: Alt+A = jump to accepted answer ───────────────────
  document.addEventListener('keydown', e => {
    if (e.altKey && e.key === 'a') {
      const accepted = $('.accepted-answer');
      if (accepted) accepted.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
    if (e.altKey && e.key === 'q') {
      const question = $('#question');
      if (question) question.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  });

  // ── 5. Toolbar for question page ─────────────────────────────────────────────
  function addToolbar() {
    if ($('#so-enh-toolbar') || !location.pathname.match(/\/questions\/\d+/)) return;

    const answerCount = $$('.answer').length;
    const accepted    = $('.accepted-answer');

    const bar = document.createElement('div');
    bar.id = 'so-enh-toolbar';
    bar.className = 'so-enh-toolbar';
    bar.innerHTML = `
      <span style="font-size:12px;color:#6b7280">SO Enhancer:</span>
      ${accepted ? `<a href="#${accepted.id}">✓ Accepted answer</a>` : ''}
      <a href="#answers">⬇ ${answerCount} answers</a>
      <a href="javascript:void(0)" id="so-enh-copy-q">📋 Copy question</a>
    `;
    const qHeader = $('.question-header');
    if (qHeader) qHeader.before(bar);

    document.getElementById('so-enh-copy-q')?.addEventListener('click', () => {
      const title = $('h1[itemprop="name"]')?.textContent?.trim() || '';
      const body  = $('.question .s-prose, .question .post-text')?.innerText?.trim() || '';
      navigator.clipboard.writeText(`## ${title}\n\n${body}`).then(() => {
        const el = document.getElementById('so-enh-copy-q');
        if (el) { el.textContent = '✓ Copied'; setTimeout(() => { el.textContent = '📋 Copy question'; }, 1500); }
      });
    });
  }

  // ── 6. Show vote count bar next to score ────────────────────────────────────
  function addVoteBars() {
    $$('.js-vote-count[data-value]').forEach(el => {
      if (el.dataset.soVoteBar) return;
      el.dataset.soVoteBar = '1';
      const v = parseInt(el.dataset.value || el.textContent);
      if (isNaN(v)) return;

      const bar = document.createElement('span');
      const width  = Math.min(Math.abs(v) * 2, 60);
      const color  = v >= 0 ? '#22c55e' : '#ef4444';
      bar.className = 'so-enh-vote-bar';
      bar.style.cssText = `width:${width}px;background:${color}`;
      el.after(bar);
    });
  }

  // ── Run ─────────────────────────────────────────────────────────────────────
  function run() {
    addCopyButtons();
    addJumpToAccepted();
    addAgeWarning();
    addToolbar();
    addVoteBars();
  }

  run();

  const obs = new MutationObserver(run);
  obs.observe(document.body, { childList: true, subtree: true });
})();
