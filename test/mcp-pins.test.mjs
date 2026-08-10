import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

test("public managed MCP runtimes use reviewed exact versions", () => {
  const launcher = readFileSync("scripts/agent-mcp", "utf8");
  const manifest = readFileSync("config/mcps.json", "utf8");
  assert.doesNotMatch(launcher, /@latest/);
  assert.doesNotMatch(manifest, /@latest/);
  assert.match(launcher, /chrome-devtools-mcp@1\.7\.0/);
  assert.match(launcher, /mcp-remote@0\.1\.38/);
});
