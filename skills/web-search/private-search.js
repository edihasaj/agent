import { readFile, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

export async function loadPrivateConfig(path = process.env.AGENT_SEARCH_CONFIG || join(homedir(), ".config/agent-search/client.json")) {
  let info;
  try { info = await stat(path); }
  catch (error) { if (error.code === "ENOENT") return null; throw error; }
  if (process.platform !== "win32" && (info.mode & 0o077 || info.uid !== process.getuid())) {
    throw new Error("Private search configuration must be owner-only (0600)");
  }
  const text = await readFile(path, "utf8");
  try { return JSON.parse(text); }
  catch { throw new Error("Private search configuration must contain valid JSON"); }
}

export async function fetchPrivateResults(query, count, options = {}) {
  const config = options.config === undefined ? await loadPrivateConfig() : options.config;
  if (!config) throw new Error("Private search is not configured; install ~/.config/agent-search/client.json");
  let base;
  try { base = new URL(config.url); } catch { throw new Error("Invalid private search origin"); }
  if (base.protocol !== "https:" || base.username || base.password || base.search || base.hash || base.pathname !== "/") {
    throw new Error("Private search requires an HTTPS origin without credentials or a path");
  }
  if (typeof config.token !== "string" || !/^[A-Za-z0-9_-]{32,256}$/.test(config.token)) throw new Error("Invalid private search identity");
  const url = new URL("/search", base);
  url.searchParams.set("q", query);
  url.searchParams.set("count", String(count));
  if (options.profile) url.searchParams.set("profile", options.profile);
  if (options.engines) url.searchParams.set("engines", options.engines);
  const response = await (options.fetchImpl ?? fetch)(url, {
    headers: { Accept: "application/json", Authorization: "Bearer " + config.token, "User-Agent": "EdiAgentSearch/1.0" },
    redirect: "error", signal: AbortSignal.timeout(170_000),
  });
  if (!response.ok) {
    await response.body?.cancel();
    const retry = response.headers.get("retry-after");
    throw new Error(`Private search HTTP ${response.status}${retry ? `; retry after ${retry} seconds` : ""}. Paid search was not called.`);
  }
  const data = await response.json();
  if (!Array.isArray(data.results)) throw new Error("Private search returned an invalid response");
  return data.results.slice(0, count).map(result => ({
    title: result.title ?? "", link: result.url ?? "", snippet: result.content ?? "",
  }));
}
