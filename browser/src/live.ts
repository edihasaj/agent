/**
 * Live mode: drive the user's real Chrome over CDP instead of abx's
 * own headless Chromium.
 *
 * Requires Chrome to be running with --remote-debugging-port=9222
 * (use scripts/chrome-debug to launch).
 *
 * Each call connects fresh, runs the command, disconnects. No daemon.
 */

import { chromium, type Browser, type BrowserContext, type Page } from 'playwright';
import * as fs from 'fs';
import { wrapUntrustedContent } from './commands';

const CDP_URL = process.env.ABX_LIVE_CDP_URL || 'http://127.0.0.1:9222';

interface ResolvedTab {
  browser: Browser;
  context: BrowserContext;
  page: Page;
}

async function connect(): Promise<Browser> {
  try {
    return await chromium.connectOverCDP(CDP_URL, { timeout: 3000 });
  } catch (err: any) {
    const detail = process.env.ABX_LIVE_DEBUG ? `\n[abx] underlying: ${err.message}` : '';
    const msg =
      `[abx] Cannot reach Chrome at ${CDP_URL}.${detail}\n` +
      `[abx] Run scripts/chrome-debug to relaunch Chrome with the debug port.`;
    throw new Error(msg);
  }
}

async function activeTab(browser: Browser): Promise<ResolvedTab> {
  const contexts = browser.contexts();
  if (contexts.length === 0) {
    throw new Error('[abx] Chrome is reachable but has no open windows.');
  }
  const context = contexts[contexts.length - 1];
  const pages = context.pages();
  if (pages.length === 0) {
    const page = await context.newPage();
    return { browser, context, page };
  }
  return { browser, context, page: pages[pages.length - 1] };
}

function shouldWrap(cmd: string): boolean {
  return cmd === 'text' || cmd === 'html' || cmd === 'snapshot';
}

async function runCommand(tab: ResolvedTab, cmd: string, args: string[]): Promise<void> {
  const { page } = tab;
  let output = '';
  let raw = false;

  switch (cmd) {
    case 'status':
    case undefined:
    case '': {
      const contexts = tab.browser.contexts();
      const tabCount = contexts.reduce((n, c) => n + c.pages().length, 0);
      output =
        `Connected: ${CDP_URL}\n` +
        `Contexts: ${contexts.length}\n` +
        `Tabs: ${tabCount}\n` +
        `Active URL: ${page.url()}`;
      raw = true;
      break;
    }
    case 'url': {
      output = page.url();
      raw = true;
      break;
    }
    case 'goto': {
      const url = args[0];
      if (!url) throw new Error('Usage: abx live goto <url>');
      const resp = await page.goto(url, { waitUntil: 'domcontentloaded' });
      output = `Navigated to ${url} (${resp?.status() ?? 'no response'})`;
      raw = true;
      break;
    }
    case 'reload': {
      await page.reload({ waitUntil: 'domcontentloaded' });
      output = `Reloaded ${page.url()}`;
      raw = true;
      break;
    }
    case 'back': {
      await page.goBack({ waitUntil: 'domcontentloaded' });
      output = `Back → ${page.url()}`;
      raw = true;
      break;
    }
    case 'forward': {
      await page.goForward({ waitUntil: 'domcontentloaded' });
      output = `Forward → ${page.url()}`;
      raw = true;
      break;
    }
    case 'text': {
      output = (await page.locator('body').innerText()).trim();
      break;
    }
    case 'html': {
      const sel = args[0];
      output = sel ? await page.locator(sel).first().innerHTML() : await page.content();
      break;
    }
    case 'snapshot': {
      output = await page.locator('body').ariaSnapshot();
      break;
    }
    case 'click': {
      const sel = args[0];
      if (!sel) throw new Error('Usage: abx live click <selector>');
      if (sel.startsWith('@e')) throw new Error('[abx] @e refs are not yet supported in live mode — use a CSS selector.');
      await page.locator(sel).first().click();
      output = `Clicked ${sel}`;
      raw = true;
      break;
    }
    case 'fill': {
      const sel = args[0];
      const value = args.slice(1).join(' ');
      if (!sel) throw new Error('Usage: abx live fill <selector> <value>');
      if (sel.startsWith('@e')) throw new Error('[abx] @e refs are not yet supported in live mode — use a CSS selector.');
      await page.locator(sel).first().fill(value);
      output = `Filled ${sel}`;
      raw = true;
      break;
    }
    case 'press': {
      const key = args[0];
      if (!key) throw new Error('Usage: abx live press <key>');
      await page.keyboard.press(key);
      output = `Pressed ${key}`;
      raw = true;
      break;
    }
    case 'type': {
      const text = args.join(' ');
      if (!text) throw new Error('Usage: abx live type <text>');
      await page.keyboard.type(text);
      output = `Typed ${text.length} chars`;
      raw = true;
      break;
    }
    case 'js': {
      const expr = args.join(' ');
      if (!expr) throw new Error('Usage: abx live js <expression>');
      const result = await page.evaluate(expr);
      output = typeof result === 'string' ? result : JSON.stringify(result, null, 2);
      raw = true;
      break;
    }
    case 'screenshot': {
      const path = args[0] || `/tmp/abx-live-${Date.now()}.png`;
      await page.screenshot({ path });
      output = `Screenshot saved: ${path}`;
      raw = true;
      break;
    }
    case 'tabs': {
      const lines: string[] = [];
      let i = 0;
      for (const ctx of tab.browser.contexts()) {
        for (const p of ctx.pages()) {
          lines.push(`${i++}\t${p.url()}\t${await p.title()}`);
        }
      }
      output = lines.join('\n');
      raw = true;
      break;
    }
    case 'cookies': {
      const cookies = await tab.context.cookies();
      output = JSON.stringify(cookies, null, 2);
      raw = true;
      break;
    }
    default: {
      throw new Error(
        `[abx] Live mode does not yet support: ${cmd}\n` +
        `Available: status, url, goto, reload, back, forward, text, html, snapshot, click, fill, press, type, js, screenshot, tabs, cookies`,
      );
    }
  }

  if (!raw && shouldWrap(cmd)) {
    process.stdout.write(wrapUntrustedContent(output, page.url()) + '\n');
  } else {
    process.stdout.write(output + '\n');
  }
}

export async function runLive(argv: string[]): Promise<number> {
  const cmd = argv[0] ?? '';
  const args = argv.slice(1);
  let browser: Browser | null = null;
  try {
    browser = await connect();
    const tab = await activeTab(browser);
    await runCommand(tab, cmd, args);
    return 0;
  } catch (err: any) {
    process.stderr.write((err.message ?? String(err)) + '\n');
    return 1;
  } finally {
    try {
      await browser?.close();
    } catch {}
  }
}

if (import.meta.main) {
  process.exit(await runLive(process.argv.slice(2)));
}
