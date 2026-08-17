#!/usr/bin/env node

import { Readability } from "@mozilla/readability";
import { JSDOM } from "jsdom";
import { pathToFileURL } from "node:url";
import TurndownService from "turndown";
import { gfm } from "turndown-plugin-gfm";

const DEFAULT_API_URL = "https://api.search.brave.com/res/v1/web/search";
const MAX_RETRIES = 3;

function parseResetDelay(value) {
	const seconds = Number.parseFloat(value?.split(",")[0] ?? "");
	return Number.isFinite(seconds) ? Math.max(seconds * 1000, 100) : 1000;
}

export async function fetchBraveResults(query, numResults, options = {}) {
	const apiKey = options.apiKey ?? process.env.BRAVE_API_KEY;
	if (!apiKey) throw new Error("BRAVE_API_KEY is not set");

	const apiUrl = options.apiUrl ?? process.env.BRAVE_API_URL ?? DEFAULT_API_URL;
	const fetchImpl = options.fetchImpl ?? fetch;
	const sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
	const url = new URL(apiUrl);
	url.searchParams.set("q", query);
	url.searchParams.set("count", String(numResults));

	let response;
	for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
		response = await fetchImpl(url, {
			headers: {
				Accept: "application/json",
				"Accept-Encoding": "gzip",
				"X-Subscription-Token": apiKey,
			},
			signal: AbortSignal.timeout(15000),
		});

		if (response.status !== 429 || attempt === MAX_RETRIES) break;
		await sleep(parseResetDelay(response.headers.get("x-ratelimit-reset")));
	}

	if (!response.ok) {
		const detail = await response.text();
		throw new Error(`Brave API HTTP ${response.status}: ${detail || response.statusText}`);
	}

	const data = await response.json();
	return (data.web?.results ?? []).slice(0, numResults).map((result) => ({
		title: result.title ?? "",
		link: result.url ?? "",
		snippet: result.description ?? "",
	}));
}

function htmlToMarkdown(html) {
	const turndown = new TurndownService({ headingStyle: "atx", codeBlockStyle: "fenced" });
	turndown.use(gfm);
	turndown.addRule("removeEmptyLinks", {
		filter: (node) => node.nodeName === "A" && !node.textContent?.trim(),
		replacement: () => "",
	});
	return turndown
		.turndown(html)
		.replace(/\[\\?\[\s*\\?\]\]\([^)]*\)/g, "")
		.replace(/ +/g, " ")
		.replace(/\s+,/g, ",")
		.replace(/\s+\./g, ".")
		.replace(/\n{3,}/g, "\n\n")
		.trim();
}

async function fetchPageContent(url) {
	try {
		const response = await fetch(url, {
			headers: {
				"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
				"Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
			},
			signal: AbortSignal.timeout(10000),
		});
		
		if (!response.ok) {
			return `(HTTP ${response.status})`;
		}
		
		const html = await response.text();
		const dom = new JSDOM(html, { url });
		const reader = new Readability(dom.window.document);
		const article = reader.parse();
		
		if (article && article.content) {
			return htmlToMarkdown(article.content).substring(0, 5000);
		}
		
		// Fallback: try to get main content
		const fallbackDoc = new JSDOM(html, { url });
		const body = fallbackDoc.window.document;
		body.querySelectorAll("script, style, noscript, nav, header, footer, aside").forEach(el => el.remove());
		const main = body.querySelector("main, article, [role='main'], .content, #content") || body.body;
		const text = main?.textContent || "";
		
		if (text.trim().length > 100) {
			return text.trim().substring(0, 5000);
		}
		
		return "(Could not extract content)";
	} catch (e) {
		return `(Error: ${e.message})`;
	}
}

async function main() {
	const args = process.argv.slice(2);
	const contentIndex = args.indexOf("--content");
	const fetchContent = contentIndex !== -1;
	if (fetchContent) args.splice(contentIndex, 1);

	let numResults = 5;
	const nIndex = args.indexOf("-n");
	if (nIndex !== -1 && args[nIndex + 1]) {
		numResults = Number.parseInt(args[nIndex + 1], 10);
		args.splice(nIndex, 2);
	}

	const query = args.join(" ");
	if (!query || !Number.isInteger(numResults) || numResults < 1 || numResults > 20) {
		console.log("Usage: search.js <query> [-n <1-20>] [--content]");
		console.log("\nOptions:");
		console.log("  -n <num>    Number of results, 1-20 (default: 5)");
		console.log("  --content   Fetch readable content as markdown");
		process.exitCode = 1;
		return;
	}

	const results = await fetchBraveResults(query, numResults);
	
	if (results.length === 0) {
		console.error("No results found.");
		return;
	}
	
	if (fetchContent) {
		for (const result of results) {
			result.content = await fetchPageContent(result.link);
		}
	}
	
	for (let i = 0; i < results.length; i++) {
		const r = results[i];
		console.log(`--- Result ${i + 1} ---`);
		console.log(`Title: ${r.title}`);
		console.log(`Link: ${r.link}`);
		console.log(`Snippet: ${r.snippet}`);
		if (r.content) {
			console.log(`Content:\n${r.content}`);
		}
		console.log("");
	}
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		console.error(`Error: ${error.message}`);
		process.exitCode = 1;
	});
}
