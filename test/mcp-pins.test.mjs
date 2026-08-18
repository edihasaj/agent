import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

// The pins live in two files: agent-mcp for per-profile packages, and the
// shared mcp-exec.sh for ones the private overlay also launches. Read both, or
// moving a pin into the shared lib silently "passes" as a missing pin.
const LAUNCHER_SOURCES = ["scripts/agent-mcp", "scripts/lib/mcp-exec.sh"];

test("MCP launchers use reviewed exact versions", () => {
  const sources = LAUNCHER_SOURCES.map((path) => readFileSync(path, "utf8")).join("\n");
  assert.doesNotMatch(sources, /@latest/);
  assert.match(sources, /chrome-devtools-mcp@1\.7\.0/);
  assert.match(sources, /mcp-remote@0\.1\.38/);
});

test("every npm package a launcher runs carries an exact version", () => {
  for (const path of LAUNCHER_SOURCES) {
    const lines = readFileSync(path, "utf8").split("\n")
      // Skip the helper's own definition and its usage comment.
      .filter((line) => !line.trimStart().startsWith("#") && !/^exec_npm_bin\(\)/.test(line.trimStart()));
    for (const [, spec] of lines.join("\n").matchAll(/exec_npm_bin\s+"?([^\s"]+)"?/g)) {
      // A shell variable is pinned where it is defined; this file checks literals.
      if (spec.startsWith("$")) continue;
      assert.match(spec, /@\d+\.\d+\.\d+$/, `${path}: unpinned package ${spec}`);
    }
  }
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
