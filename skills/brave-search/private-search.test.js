import assert from "node:assert/strict";
import test from "node:test";
import { fetchPrivateResults } from "./private-search.js";
import { fetchSearchResults } from "./search.js";
import { loadPrivateConfig } from "./private-search.js";
import { mkdtemp, writeFile, rm } from "node:fs/promises";

const config = { url: "https://search.example.org", token: "test-token-".repeat(8) };

test("private search maps results and confines bearer credentials to the configured origin", async () => {
  let request;
  const results = await fetchPrivateResults("swift actors", 2, {
    config, profile: "code", fetchImpl: async (url, options) => {
      request = { url, options };
      return Response.json({ results: [{ title: "One", url: "https://example.org/1", content: "Snippet" }] });
    },
  });
  assert.equal(request.url.origin, config.url);
  assert.equal(request.url.pathname, "/search");
  assert.equal(request.url.searchParams.get("profile"), "code");
  assert.equal(request.options.headers.Authorization, "Bearer " + config.token);
  assert.equal(request.options.headers["X-Subscription-Token"], undefined);
  assert.equal(request.options.redirect, "error");
  assert.deepEqual(results, [{ title: "One", link: "https://example.org/1", snippet: "Snippet" }]);
});

test("configured private search takes precedence over an available paid key", async () => {
  let calls = 0;
  await fetchSearchResults("hello", 1, { config, apiKey: "paid-key", fetchImpl: async url => {
    calls++;
    assert.equal(url.origin, config.url);
    return Response.json({ results: [] });
  } });
  assert.equal(calls, 1);
});

test("missing private configuration never defaults to paid search or another config file", async () => {
  for (const options of [{ config: null }, { configPath: new URL('./nonexistent-client.json', import.meta.url) }]) {
    let calls = 0;
    await assert.rejects(fetchSearchResults('hello', 1, { ...options, apiKey: 'paid-key', fetchImpl: async () => { calls++; } }), /Private search is not configured/);
    assert.equal(calls, 0);
  }
});

test("private errors never call the paid provider or expose the body", async () => {
  let calls = 0;
  await assert.rejects(fetchSearchResults("hello", 1, { config, apiKey: "paid-key", fetchImpl: async () => {
    calls++;
    return new Response("private response detail", { status: 429, headers: { "Retry-After": "60" } });
  } }), /HTTP 429; retry after 60 seconds\. Paid search was not called/);
  assert.equal(calls, 1);
});

test("an explicit paid request retains the original Brave API behavior", async () => {
  await fetchSearchResults("hello", 1, { provider: "brave", configPath: new URL('./package.json', import.meta.url), apiKey: "test-key", fetchImpl: async (url, options) => {
    assert.equal(url.origin, "https://api.search.brave.com");
    assert.equal(options.headers.Authorization, undefined);
    assert.equal(options.headers["X-Subscription-Token"], "test-key");
    return Response.json({ web: { results: [] } });
  } });
});

test("malformed bearer tokens cannot leak through header validation errors", async () => {
  for (const suffix of ['\rX', '\nX', '\u0000', ' ']) {
    const token = config.token + suffix;
    let calls = 0;
    await assert.rejects(fetchPrivateResults('hello', 1, { config: { ...config, token }, fetchImpl: async () => { calls++; } }), error => {
      assert.equal(error.message, 'Invalid private search identity');
      assert.ok(!error.message.includes(config.token));
      return true;
    });
    assert.equal(calls, 0);
  }
});

test("private origins reject insecure transports, embedded credentials and paths", async () => {
  for (const url of ["http://search.example.org", "https://user:pass@search.example.org", "https://search.example.org/path", "https://search.example.org/?token=x"]) {
    await assert.rejects(fetchPrivateResults("hello", 1, { config: { ...config, url } }), /HTTPS origin/);
  }
});

test("malformed configuration errors do not echo private file contents", async t => {
  const directory = await mkdtemp('/tmp/agent-search-client-test-');
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = directory + '/client.json';
  await writeFile(path, '{"token":"synthetic-private-value" BROKEN}', { mode: 0o600 });
  await assert.rejects(loadPrivateConfig(path), error => {
    assert.equal(error.message, 'Private search configuration must contain valid JSON');
    assert.ok(!error.message.includes('synthetic-private-value'));
    return true;
  });
});
