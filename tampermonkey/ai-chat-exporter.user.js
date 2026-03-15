// ==UserScript==
// @name         AI Chat Exporter
// @namespace    https://chat.openai.com/
// @version      2.1.0
// @description  Export ChatGPT and Claude conversations as Markdown, HTML or JSON with one click.
// @author       VpkDevs
// @match        https://chat.openai.com/*
// @match        https://chatgpt.com/*
// @match        https://claude.ai/*
// @grant        GM_addStyle
// @grant        GM_download
// @run-at       document-idle
// ==/UserScript==

(function () {
  'use strict';

  // ── Styles ──────────────────────────────────────────────────────────────────
  GM_addStyle(`
    #ai-export-btn {
      position: fixed; bottom: 24px; right: 24px; z-index: 99999;
      background: #6366f1; color: white;
      border: none; border-radius: 10px;
      padding: 10px 18px; font-size: 14px; font-weight: 600;
      cursor: pointer; box-shadow: 0 4px 16px rgba(99,102,241,0.4);
      display: flex; align-items: center; gap: 8px;
      font-family: 'Segoe UI', sans-serif;
      transition: all 0.2s;
    }
    #ai-export-btn:hover { background: #4f46e5; transform: translateY(-2px); box-shadow: 0 6px 20px rgba(99,102,241,0.5); }
    #ai-export-menu {
      position: fixed; bottom: 74px; right: 24px; z-index: 99999;
      background: #1e1e2e; border: 1px solid #30363d; border-radius: 10px;
      padding: 6px 0; box-shadow: 0 8px 32px rgba(0,0,0,0.5);
      min-width: 180px; font-family: 'Segoe UI', sans-serif;
      display: none;
    }
    #ai-export-menu.visible { display: block; }
    #ai-export-menu button {
      display: flex; align-items: center; gap: 10px; width: 100%;
      background: none; border: none; color: #e2e8f0;
      padding: 10px 16px; font-size: 13px; cursor: pointer; text-align: left;
    }
    #ai-export-menu button:hover { background: #2d2d3e; }
    #ai-export-toast {
      position: fixed; top: 20px; right: 24px; z-index: 99999;
      background: #22c55e; color: white; padding: 10px 20px;
      border-radius: 8px; font-size: 14px; font-weight: 600;
      font-family: 'Segoe UI', sans-serif;
      transform: translateY(-80px); opacity: 0;
      transition: all 0.3s; pointer-events: none;
    }
    #ai-export-toast.show { transform: translateY(0); opacity: 1; }
  `);

  // ── Detect platform ─────────────────────────────────────────────────────────
  function matchHost(domain) {
    const h = location.hostname;
    return h === domain || h.endsWith('.' + domain);
  }
  const isChatGPT = matchHost('openai.com') || matchHost('chatgpt.com');
  const isClaude  = matchHost('claude.ai');

  // ── Scrape conversation ─────────────────────────────────────────────────────
  function scrapeMessages() {
    const messages = [];

    if (isChatGPT) {
      // ChatGPT DOM structure
      const turns = document.querySelectorAll('[data-testid^="conversation-turn"]');
      turns.forEach(turn => {
        const roleEl = turn.querySelector('[data-message-author-role]');
        const role   = roleEl?.getAttribute('data-message-author-role') || 'unknown';
        const contentEl = turn.querySelector('.markdown, .whitespace-pre-wrap, [class*="prose"]');
        const content = contentEl?.innerText?.trim() || '';
        if (content) messages.push({ role, content });
      });
    } else if (isClaude) {
      // Claude DOM structure
      const humanMsgs = document.querySelectorAll('[data-testid="human-turn"], .font-claude-message');
      const aiMsgs    = document.querySelectorAll('[data-testid="ai-turn"], .font-claude-message');

      // Interleaved approach
      document.querySelectorAll('.font-claude-message, [class*="ConversationTurn"]').forEach(el => {
        const isHuman = el.closest('[data-testid="human-turn"]') !== null
                     || el.classList.contains('human-turn')
                     || el.closest('.human-turn') !== null;
        messages.push({
          role:    isHuman ? 'user' : 'assistant',
          content: el.innerText.trim()
        });
      });

      // Fallback: all visible paragraphs in chat
      if (!messages.length) {
        document.querySelectorAll('div[class*="message"] p').forEach(p => {
          messages.push({ role: 'unknown', content: p.innerText.trim() });
        });
      }
    }

    return messages;
  }

  // ── Get conversation title ───────────────────────────────────────────────────
  function getTitle() {
    const candidates = [
      document.querySelector('title'),
      document.querySelector('h1'),
      document.querySelector('[data-testid="conversation-title"]'),
      document.querySelector('nav li.active, nav [aria-current="page"]')
    ];
    for (const el of candidates) {
      const text = el?.textContent?.trim();
      if (text && text !== 'ChatGPT' && text !== 'Claude' && text.length < 100) return text;
    }
    return 'AI Conversation ' + new Date().toISOString().slice(0, 10);
  }

  // ── Formatters ──────────────────────────────────────────────────────────────
  function toMarkdown(messages, title) {
    const date = new Date().toLocaleString();
    let md = `# ${title}\n\n*Exported: ${date}*\n\n---\n\n`;
    messages.forEach(({ role, content }) => {
      const label = role === 'user' ? '**You**' : role === 'assistant' ? '**Assistant**' : `**${role}**`;
      md += `### ${label}\n\n${content}\n\n---\n\n`;
    });
    return md;
  }

  function toHTML(messages, title) {
    const date = new Date().toLocaleString();
    const rows = messages.map(({ role, content }) => {
      const isUser = role === 'user';
      const bg     = isUser ? '#1a1a2e' : '#16213e';
      const label  = isUser ? 'You' : 'Assistant';
      const color  = isUser ? '#60a5fa' : '#a78bfa';
      const htmlContent = content
        .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
        .replace(/\n/g, '<br>');
      return `
        <div style="background:${bg};border-radius:8px;padding:16px 20px;margin-bottom:12px">
          <div style="color:${color};font-weight:700;font-size:13px;margin-bottom:8px;text-transform:uppercase;letter-spacing:0.05em">${label}</div>
          <div style="color:#e2e8f0;font-size:15px;line-height:1.6">${htmlContent}</div>
        </div>`;
    }).join('\n');

    return `<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>${title}</title>
<style>
  body { font-family: 'Segoe UI', sans-serif; background: #0d1117; color: #e2e8f0;
         max-width: 800px; margin: 0 auto; padding: 32px 20px; }
  h1 { color: #60a5fa; }
  .meta { color: #6b7280; font-size: 13px; margin-bottom: 24px; }
</style>
</head><body>
<h1>${title}</h1>
<div class="meta">Exported: ${date}</div>
${rows}
</body></html>`;
  }

  function toJSON(messages, title) {
    return JSON.stringify({
      title,
      exportedAt: new Date().toISOString(),
      platform: isChatGPT ? 'ChatGPT' : 'Claude',
      messages
    }, null, 2);
  }

  // ── Download helper ─────────────────────────────────────────────────────────
  function download(content, filename, mime) {
    const blob = new Blob([content], { type: mime });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement('a');
    a.href     = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  }

  function safeFilename(title) {
    return title.replace(/[^a-z0-9\-_ ]/gi, '').replace(/\s+/g, '_').slice(0, 60);
  }

  // ── Toast ────────────────────────────────────────────────────────────────────
  function showToast(msg) {
    const toast = document.getElementById('ai-export-toast');
    toast.textContent = msg;
    toast.classList.add('show');
    setTimeout(() => toast.classList.remove('show'), 2200);
  }

  // ── Export actions ───────────────────────────────────────────────────────────
  function exportAs(format) {
    const messages = scrapeMessages();
    if (!messages.length) { showToast('No messages found'); return; }
    const title    = getTitle();
    const fname    = safeFilename(title) + '_' + new Date().toISOString().slice(0,10);

    if (format === 'markdown') {
      download(toMarkdown(messages, title), fname + '.md', 'text/markdown');
    } else if (format === 'html') {
      download(toHTML(messages, title), fname + '.html', 'text/html');
    } else if (format === 'json') {
      download(toJSON(messages, title), fname + '.json', 'application/json');
    } else if (format === 'clipboard') {
      navigator.clipboard.writeText(toMarkdown(messages, title))
        .then(() => showToast('✓ Copied to clipboard!'))
        .catch(() => showToast('Clipboard failed'));
    }
    document.getElementById('ai-export-menu').classList.remove('visible');
    if (format !== 'clipboard') showToast('✓ Exported!');
  }

  // ── Build UI ─────────────────────────────────────────────────────────────────
  function buildUI() {
    if (document.getElementById('ai-export-btn')) return;

    const toast = document.createElement('div');
    toast.id = 'ai-export-toast';
    document.body.appendChild(toast);

    const menu = document.createElement('div');
    menu.id = 'ai-export-menu';
    menu.innerHTML = `
      <button data-fmt="markdown">📝 Export as Markdown</button>
      <button data-fmt="html">🌐 Export as HTML</button>
      <button data-fmt="json">📦 Export as JSON</button>
      <button data-fmt="clipboard">📋 Copy as Markdown</button>
    `;
    menu.querySelectorAll('button').forEach(btn => {
      btn.addEventListener('click', () => exportAs(btn.dataset.fmt));
    });
    document.body.appendChild(menu);

    const btn = document.createElement('button');
    btn.id = 'ai-export-btn';
    btn.innerHTML = '⬇ Export Chat';
    btn.addEventListener('click', e => {
      e.stopPropagation();
      menu.classList.toggle('visible');
    });
    document.body.appendChild(btn);

    document.addEventListener('click', () => menu.classList.remove('visible'));
  }

  // Wait for the page to fully load
  const ready = setInterval(() => {
    if (document.body) {
      buildUI();
      clearInterval(ready);
    }
  }, 800);
})();
