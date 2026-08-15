import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

test("MCP launchers use reviewed exact versions", () => {
  const launcher = readFileSync("scripts/agent-mcp", "utf8");
  assert.doesNotMatch(launcher, /@latest/);
  assert.match(launcher, /chrome-devtools-mcp@1\.7\.0/);
  assert.match(launcher, /mcp-remote@0\.1\.38/);
});

test("public agent setup has no duplicate MCP manifest", () => {
  assert.equal(existsSync("configs"), false);
  assert.equal(existsSync("config"), false);

  const mappedSources = [
    "scripts/agent-cli.mjs",
    "scripts/agent-mcp",
    "scripts/setup-windows.ps1",
    "scripts/sync-agent-mcps.mjs",
  ].map((path) => readFileSync(path, "utf8")).join("\n");
  assert.doesNotMatch(mappedSources, /agent[\\/]configs[\\/]mcps\.json/);
  assert.doesNotMatch(mappedSources, /manager[\\/]config[\\/]/);
  assert.match(mappedSources, /manager[\\/]configs[\\/]/);
});
