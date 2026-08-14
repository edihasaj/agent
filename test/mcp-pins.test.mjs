import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

test("public managed MCP runtimes use reviewed exact versions", () => {
  const launcher = readFileSync("scripts/agent-mcp", "utf8");
  const manifest = readFileSync("configs/mcps.json", "utf8");
  assert.doesNotMatch(launcher, /@latest/);
  assert.doesNotMatch(manifest, /@latest/);
  assert.match(launcher, /chrome-devtools-mcp@1\.7\.0/);
  assert.match(launcher, /mcp-remote@0\.1\.38/);
});

test("agent configuration uses the canonical configs directory", () => {
  assert.equal(existsSync("configs/mcps.json"), true);
  assert.equal(existsSync("config"), false);

  const mappedSources = [
    "scripts/agent-cli.mjs",
    "scripts/agent-mcp",
    "scripts/setup-windows.ps1",
    "scripts/sync-agent-mcps.mjs",
  ].map((path) => readFileSync(path, "utf8")).join("\n");
  assert.doesNotMatch(mappedSources, /manager[\\/]config[\\/]/);
  assert.match(mappedSources, /manager[\\/]configs[\\/]/);
});
