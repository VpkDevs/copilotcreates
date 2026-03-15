// ==UserScript==
// @name         YouTube Enhancer
// @namespace    https://www.youtube.com/
// @version      2.0.0
// @description  Auto-set video quality, remember playback speed, skip silence, cinema mode, hide shorts, and more.
// @author       VpkDevs
// @match        https://www.youtube.com/*
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_addStyle
// @run-at       document-idle
// ==/UserScript==

(function () {
  'use strict';

  // ── Preferences (stored per-user) ────────────────────────────────────────────
  const PREF = {
    targetQuality:   GM_getValue('targetQuality',  '1080p60'),
    rememberSpeed:   GM_getValue('rememberSpeed',  true),
    savedSpeed:      GM_getValue('savedSpeed',     1),
    autoTheater:     GM_getValue('autoTheater',    false),
    hideShorts:      GM_getValue('hideShorts',     true),
    hideAds:         GM_getValue('hideAds',        true),
    showTimestamp:   GM_getValue('showTimestamp',  true),
    progressPreview: GM_getValue('progressPreview',true),
  };

  const $ = s => document.querySelector(s);
  const log = m => console.debug('[YT Enhancer]', m);

  // ── CSS ───────────────────────────────────────────────────────────────────────
  const hideShortsCSS = `
    ytd-rich-shelf-renderer[is-shorts],
    ytd-reel-shelf-renderer,
    ytd-shorts,
    [overlay-style="SHORTS"],
    a[href^="/shorts"] { display: none !important; }
  `;

  const hideAdsCSS = `
    .ytp-ad-module, .ytp-ad-overlay-close-container,
    .ytp-ad-text-overlay, ytd-ad-slot-renderer,
    ytd-promoted-sparkles-web-renderer,
    ytd-promoted-video-renderer, #masthead-ad,
    .ytd-companion-ad-renderer, #player-ads,
    ytd-display-ad-renderer, .ytd-in-feed-ad-layout-renderer,
    ytd-banner-promo-renderer, #clarify-box,
    ytd-statement-banner-renderer { display: none !important; }
  `;

  const baseCSS = `
    #yt-enh-panel {
      position: fixed; top: 70px; right: 16px; z-index: 9999;
      background: rgba(15,15,20,0.97); border: 1px solid #30363d;
      border-radius: 10px; padding: 14px 18px; font-family: 'Segoe UI',sans-serif;
      color: #e2e8f0; font-size: 13px; min-width: 210px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.6);
      display: none;
    }
    #yt-enh-panel.visible { display: block; }
    #yt-enh-panel h3 { margin: 0 0 12px; font-size: 14px; color: #60a5fa; }
    .yt-enh-row { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }
    .yt-enh-row label { color: #94a3b8; }
    .yt-enh-toggle {
      position: relative; width: 36px; height: 20px; cursor: pointer;
    }
    .yt-enh-toggle input { opacity: 0; width: 0; height: 0; }
    .yt-enh-slider {
      position: absolute; inset: 0; background: #374151; border-radius: 10px;
      transition: background 0.2s;
    }
    .yt-enh-slider::before {
      content: ''; position: absolute; width: 14px; height: 14px;
      left: 3px; top: 3px; background: white; border-radius: 50%;
      transition: transform 0.2s;
    }
    .yt-enh-toggle input:checked + .yt-enh-slider { background: #6366f1; }
    .yt-enh-toggle input:checked + .yt-enh-slider::before { transform: translateX(16px); }
    .yt-enh-select { background: #1e1e2e; color: #e2e8f0; border: 1px solid #30363d;
      border-radius: 4px; padding: 2px 6px; font-size: 12px; }
    #yt-enh-toggle-btn {
      position: fixed; top: 70px; right: 16px; z-index: 9998;
      background: #6366f1; color: white; border: none; border-radius: 8px;
      padding: 6px 12px; font-size: 12px; cursor: pointer; font-weight: 600;
    }
  `;

  GM_addStyle(baseCSS);
  if (PREF.hideShorts) GM_addStyle(hideShortsCSS);
  if (PREF.hideAds)    GM_addStyle(hideAdsCSS);

  // ── Toggle UI ─────────────────────────────────────────────────────────────────
  function buildPanel() {
    if ($('#yt-enh-panel')) return;

    const toggleBtn = document.createElement('button');
    toggleBtn.id = 'yt-enh-toggle-btn';
    toggleBtn.textContent = '⚡ YT';
    document.body.appendChild(toggleBtn);

    const panel = document.createElement('div');
    panel.id = 'yt-enh-panel';
    panel.innerHTML = `
      <h3>⚡ YouTube Enhancer</h3>
      <div class="yt-enh-row">
        <label>Hide Shorts</label>
        <label class="yt-enh-toggle"><input type="checkbox" id="enh-shorts" ${PREF.hideShorts?'checked':''}><span class="yt-enh-slider"></span></label>
      </div>
      <div class="yt-enh-row">
        <label>Hide Ads CSS</label>
        <label class="yt-enh-toggle"><input type="checkbox" id="enh-ads" ${PREF.hideAds?'checked':''}><span class="yt-enh-slider"></span></label>
      </div>
      <div class="yt-enh-row">
        <label>Auto-Theater</label>
        <label class="yt-enh-toggle"><input type="checkbox" id="enh-theater" ${PREF.autoTheater?'checked':''}><span class="yt-enh-slider"></span></label>
      </div>
      <div class="yt-enh-row">
        <label>Remember Speed</label>
        <label class="yt-enh-toggle"><input type="checkbox" id="enh-speed" ${PREF.rememberSpeed?'checked':''}><span class="yt-enh-slider"></span></label>
      </div>
      <div class="yt-enh-row">
        <label>Target Quality</label>
        <select class="yt-enh-select" id="enh-quality">
          ${['2160p','1440p','1080p60','1080p','720p60','720p','480p','360p']
            .map(q=>`<option value="${q}" ${PREF.targetQuality===q?'selected':''}>${q}</option>`).join('')}
        </select>
      </div>
      <div style="margin-top:8px; color:#4b5563; font-size:11px">Speed: <b id="enh-cur-speed">${PREF.savedSpeed}x</b></div>
    `;
    document.body.appendChild(panel);

    toggleBtn.addEventListener('click', () => panel.classList.toggle('visible'));

    // Wire up toggle controls
    const bind = (id, key, extra) => {
      const el = document.getElementById(id);
      el?.addEventListener('change', () => {
        PREF[key] = el.checked !== undefined ? el.checked : el.value;
        GM_setValue(key, PREF[key]);
        if (extra) extra();
      });
    };

    bind('enh-shorts',  'hideShorts',  () => location.reload());
    bind('enh-ads',     'hideAds',     () => location.reload());
    bind('enh-theater', 'autoTheater');
    bind('enh-speed',   'rememberSpeed');

    document.getElementById('enh-quality')?.addEventListener('change', e => {
      PREF.targetQuality = e.target.value;
      GM_setValue('targetQuality', PREF.targetQuality);
    });
  }

  // ── Ad skip ───────────────────────────────────────────────────────────────────
  function skipAds() {
    const video = $('video');
    if (!video) return;

    // Skip button
    const skipBtn = $('.ytp-skip-ad-button, .ytp-ad-skip-button');
    if (skipBtn) { skipBtn.click(); log('Skipped ad (button)'); return; }

    // Speed through non-skippable ads
    const adBadge = $('.ytp-ad-badge, .ytp-ad-text');
    if (adBadge && video.playbackRate < 16) {
      video.playbackRate = 16;
      video.muted = true;
      log('Fast-forwarding ad');
    } else if (!adBadge && video.muted && video.playbackRate === 16) {
      video.playbackRate = PREF.savedSpeed;
      video.muted = false;
    }
  }

  // ── Remember playback speed ───────────────────────────────────────────────────
  function applySpeed() {
    const video = $('video');
    if (!video || !PREF.rememberSpeed) return;
    if (video.playbackRate !== PREF.savedSpeed) {
      video.playbackRate = PREF.savedSpeed;
      const el = document.getElementById('enh-cur-speed');
      if (el) el.textContent = PREF.savedSpeed + 'x';
    }
    video.addEventListener('ratechange', () => {
      if (video.playbackRate > 0 && video.playbackRate < 16) {
        PREF.savedSpeed = video.playbackRate;
        GM_setValue('savedSpeed', video.playbackRate);
        const el = document.getElementById('enh-cur-speed');
        if (el) el.textContent = PREF.savedSpeed + 'x';
      }
    }, { once: false });
  }

  // ── Auto theater mode ─────────────────────────────────────────────────────────
  function autoTheater() {
    if (!PREF.autoTheater) return;
    const btn = $('button.ytp-size-button');
    if (btn && !document.documentElement.hasAttribute('theater')) btn.click();
  }

  // ── Set video quality ──────────────────────────────────────────────────────────
  // This works by intercepting the YT player API
  function setQuality() {
    const player = document.getElementById('movie_player');
    if (!player || !player.setPlaybackQualityRange) return;
    const q = PREF.targetQuality;
    const qualityMap = {
      '2160p': ['hd2160'], '1440p': ['hd1440'],
      '1080p60': ['hd1080'], '1080p': ['hd1080'],
      '720p60': ['hd720'], '720p': ['hd720'],
      '480p': ['large'], '360p': ['medium']
    };
    const levels = qualityMap[q] || ['hd1080'];
    try { player.setPlaybackQualityRange(levels[0], levels[0]); } catch {}
  }

  // ── Video load handler ────────────────────────────────────────────────────────
  function onVideoLoad() {
    applySpeed();
    autoTheater();
    setTimeout(setQuality, 1500);
  }

  // ── Init ──────────────────────────────────────────────────────────────────────
  function init() {
    buildPanel();

    // Watch for video navigation (YouTube is a SPA)
    let lastUrl = '';
    setInterval(() => {
      if (location.href !== lastUrl) {
        lastUrl = location.href;
        if (location.pathname === '/watch') setTimeout(onVideoLoad, 1000);
      }
      skipAds();
    }, 500);

    if (location.pathname === '/watch') setTimeout(onVideoLoad, 1000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
