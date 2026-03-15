// ==UserScript==
// @name         Cookie Banner Killer
// @namespace    https://github.com/VpkDevs
// @version      3.2.0
// @description  Aggressively auto-dismiss cookie consent banners, GDPR pop-ups and overlay modals across the web.
// @author       VpkDevs
// @match        *://*/*
// @grant        none
// @run-at       document-end
// ==/UserScript==

(function () {
  'use strict';

  // ── Button text patterns to auto-click ──────────────────────────────────────
  const ACCEPT_PATTERNS = [
    /^accept all$/i,
    /^accept cookies$/i,
    /^i accept$/i,
    /^allow all$/i,
    /^allow cookies$/i,
    /^agree to all$/i,
    /^got it$/i,
    /^ok,? i understand$/i,
    /^continue$/i,
    /^close$/i,
    /^dismiss$/i,
    /^consent$/i,
    /^agree$/i,
    /^yes,? agree$/i,
    /^accept$/i,
    /^confirm$/i,
    /^understood$/i,
    /^proceed$/i,
    /^continue without consent$/i,
    /^no thanks$/i,
    /^reject all$/i,       // preferring "reject all" over "accept all"
    /^refuse all$/i,
  ];

  // ── CSS selectors for the banner containers ──────────────────────────────────
  const CONTAINER_SELECTORS = [
    '#cookie-banner', '#cookiebanner', '#cookie-notice', '#cookie-law-info-bar',
    '#cookie-consent', '#cookie-message', '#cookie-bar', '#cookies-bar',
    '#onetrust-banner-sdk', '#onetrust-consent-sdk', '#gdpr-cookie-notice',
    '#gdpr-banner', '#gdpr-consent-tool-wrapper', '#gdpr-overlay',
    '#CybotCookiebotDialog', '#usercentrics-root', '#Cookiebot',
    '#ccc', '#ccc-notify', '#ccc-module', '#cookie-widget',
    '[id*="cookie-consent"]', '[id*="cookieBanner"]', '[id*="cookie_banner"]',
    '[class*="cookie-banner"]', '[class*="cookieBanner"]',
    '[class*="cookie-notice"]', '[class*="cookieNotice"]',
    '[class*="cookie-popup"]', '[class*="cookiePopup"]',
    '[class*="cookie-consent"]', '[class*="gdpr"]',
    '[class*="consent-banner"]', '[class*="consentBanner"]',
    '[data-nosnippet][class*="cookie"]',
    '.cookie-banner', '.cookies-banner', '.cookie-notice',
    '.gdpr-banner', '.gdpr-notice', '.consent-banner',
    // Floating overlays
    '[style*="z-index: 9999"][class*="cookie"]',
    '[style*="z-index:9999"][class*="cookie"]',
    // Common third-party widgets
    '.qc-cmp2-container', '.sp_choice_type_11', '#sp-cc',
    '#truste-consent-track', '.truste_popframe',
    '.evidon-banner', '#evidon-banner',
    '.ot-sdk-container', '#onetrust-accept-btn-handler',
    '#cc-window', '#cc-nb', '.cc-window', '.cc-banner',
  ];

  // ── CSS selectors for overlay / backdrop elements ────────────────────────────
  const OVERLAY_SELECTORS = [
    '.cookie-overlay', '.gdpr-overlay', '.consent-overlay',
    '[class*="cookie-overlay"]', '[class*="cookieOverlay"]',
    '.modal-backdrop[data-cookie]', '#cookiefirst-root + .overlay',
    '.fancybox-overlay', '.cboxOverlay',
    'body > div[style*="position: fixed"][style*="z-index: 9"][style*="background"]',
  ];

  const log = msg => console.debug('[Cookie Killer]', msg);

  // ── Try to click an accept/reject button inside a container ─────────────────
  function tryClickButton(container) {
    const btns = [...container.querySelectorAll('button, a[role="button"], [class*="btn"], input[type="button"], input[type="submit"]')];
    // Prefer "reject all" first (privacy-friendly), then "accept"
    const sorted = btns.sort((a, b) => {
      const aReject = /reject|refuse|decline|no thanks/i.test(a.textContent);
      const bReject = /reject|refuse|decline|no thanks/i.test(b.textContent);
      return (bReject ? 1 : 0) - (aReject ? 1 : 0);
    });

    for (const btn of sorted) {
      const text = btn.textContent.trim();
      for (const pat of ACCEPT_PATTERNS) {
        if (pat.test(text)) {
          log(`Clicking: "${text}"`);
          btn.click();
          return true;
        }
      }
    }
    return false;
  }

  // ── Try to remove banner container from DOM ──────────────────────────────────
  function removeBanner(el) {
    try {
      // First try clicking a button
      if (tryClickButton(el)) return;
      // Then hide/remove
      el.style.setProperty('display', 'none', 'important');
      el.style.setProperty('visibility', 'hidden', 'important');
      el.style.setProperty('opacity', '0', 'important');
      setTimeout(() => { try { el.remove(); } catch {} }, 300);
      log(`Removed: ${el.id || el.className.toString().slice(0,40)}`);
    } catch (e) {}
  }

  // ── Unfreeze body scroll (banners often lock scrolling) ──────────────────────
  function unfreezeBody() {
    const b = document.body;
    const h = document.documentElement;
    const styles = ['overflow', 'overflow-x', 'overflow-y', 'position', 'height'];
    let changed = false;
    [b, h].forEach(el => {
      const cs = getComputedStyle(el);
      if (cs.overflow === 'hidden' || cs.overflowY === 'hidden') {
        el.style.setProperty('overflow', 'auto', 'important');
        el.style.setProperty('overflow-y', 'auto', 'important');
        changed = true;
      }
      if (cs.position === 'fixed' && el === b) {
        el.style.setProperty('position', 'static', 'important');
        changed = true;
      }
    });
    if (changed) log('Unfreezed body scroll');
  }

  // ── Main scan ────────────────────────────────────────────────────────────────
  function scan() {
    let found = 0;

    // Targeted selectors
    CONTAINER_SELECTORS.forEach(sel => {
      document.querySelectorAll(sel).forEach(el => {
        const style = getComputedStyle(el);
        const isVisible = style.display !== 'none' && style.visibility !== 'hidden' && el.offsetParent !== null;
        if (isVisible) {
          removeBanner(el);
          found++;
        }
      });
    });

    // Heuristic: any fixed/sticky element in the bottom quarter of the screen
    // with "cookie" / "consent" / "privacy" / "GDPR" in its text
    const cookieKeywords = /cookie|consent|gdpr|privacy|tracking|personal data/i;
    document.querySelectorAll('div, section, aside, footer').forEach(el => {
      if (el.dataset.cbkDone) return;
      const style = getComputedStyle(el);
      if ((style.position === 'fixed' || style.position === 'sticky')
          && parseInt(style.zIndex) > 100
          && el.offsetHeight < window.innerHeight * 0.6
          && cookieKeywords.test(el.textContent)) {
        el.dataset.cbkDone = '1';
        removeBanner(el);
        found++;
      }
    });

    // Remove overlay backdrops
    OVERLAY_SELECTORS.forEach(sel => {
      document.querySelectorAll(sel).forEach(el => {
        el.style.setProperty('display', 'none', 'important');
        el.remove();
      });
    });

    if (found) unfreezeBody();
  }

  // ── CSS nuke as last resort ──────────────────────────────────────────────────
  function nukeWithCSS() {
    const style = document.createElement('style');
    style.textContent = CONTAINER_SELECTORS.map(s => `${s} { display: none !important; }`).join('\n');
    document.head?.appendChild(style);
  }

  // ── Run ─────────────────────────────────────────────────────────────────────
  scan();
  setTimeout(scan, 800);
  setTimeout(scan, 2000);
  nukeWithCSS();

  // Watch for dynamically injected banners
  const observer = new MutationObserver(muts => {
    for (const mut of muts) {
      for (const node of mut.addedNodes) {
        if (node.nodeType !== 1) continue;
        const text = node.textContent || '';
        if (/cookie|consent|gdpr/i.test(text) || /cookie|consent|gdpr/i.test(node.id + ' ' + node.className)) {
          setTimeout(scan, 100);
          break;
        }
      }
    }
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });
})();
