import assert from "node:assert/strict";
import test from "node:test";

import { fetchBraveResults } from "./search.js";

function response(body, init = {}) {
	return new Response(JSON.stringify(body), {
		status: 200,
		headers: { "content-type": "application/json" },
		...init,
	});
}

test("calls the official API with the subscription key and maps results", async () => {
	let request;
	const results = await fetchBraveResults("swift actors", 2, {
		apiKey: "test-key",
		fetchImpl: async (url, options) => {
			request = { url, options };
			return response({
				web: {
					results: [
						{ title: "One", url: "https://example.com/1", description: "First" },
						{ title: "Two", url: "https://example.com/2", description: "Second" },
					],
				},
			});
		},
	});

	const url = new URL(request.url);
	assert.equal(url.origin + url.pathname, "https://api.search.brave.com/res/v1/web/search");
	assert.equal(url.searchParams.get("q"), "swift actors");
	assert.equal(url.searchParams.get("count"), "2");
	assert.equal(request.options.headers["X-Subscription-Token"], "test-key");
	assert.deepEqual(results, [
		{ title: "One", link: "https://example.com/1", snippet: "First" },
		{ title: "Two", link: "https://example.com/2", snippet: "Second" },
	]);
});

test("retries a rate-limited request using the reset header", async () => {
	let calls = 0;
	const delays = [];
	const results = await fetchBraveResults("retry", 1, {
		apiKey: "test-key",
		fetchImpl: async () => {
			calls++;
			if (calls === 1) {
				return response(
					{ message: "rate limited" },
					{ status: 429, headers: { "x-ratelimit-reset": "2, 100" } },
				);
			}
			return response({ web: { results: [] } });
		},
		sleep: async (milliseconds) => delays.push(milliseconds),
	});

	assert.equal(calls, 2);
	assert.deepEqual(delays, [2000]);
	assert.deepEqual(results, []);
});

test("requires an API key", async () => {
	await assert.rejects(
		fetchBraveResults("missing key", 1, { apiKey: "" }),
		/BRAVE_API_KEY is not set/,
	);
});
