import assert from "node:assert/strict";
import test from "node:test";
import { mergeServers, parseAgentArgs, repairCommand } from "../scripts/agent-cli.mjs";

test("agent doctor supports human, JSON, and quiet output modes", () => {
  assert.deepEqual(parseAgentArgs(["doctor"]), {
    help: false,
    command: "doctor",
    json: false,
    quiet: false,
  });
  assert.equal(parseAgentArgs(["doctor", "--json"]).json, true);
  assert.equal(parseAgentArgs(["doctor", "--quiet"]).quiet, true);
  assert.throws(() => parseAgentArgs(["doctor", "--json", "--quiet"]), /cannot be used together/);
  assert.throws(() => parseAgentArgs(["unknown"]), /unknown command/);
});

test("doctor repair commands preserve the stored machine policy", () => {
  const profile = {
    publicOnly: true,
    headless: true,
    cliMode: "explicit",
    clis: ["codex", "claude"],
  };
  assert.match(repairCommand(profile, "linux"), /setup-linux\.sh --public-only --headless --cli codex --cli claude$/);
  assert.match(repairCommand(profile, "win32"), /setup-windows\.ps1 -PublicOnly -Headless -Cli codex,claude$/);
});

test("private MCP entries add and shallowly override public entries by name", () => {
  assert.deepEqual(
    mergeServers(
      [{ name: "browser", enabled: true, clis: ["codex"] }],
      [
        { name: "browser", enabled: false },
        { name: "private-errors", enabled: true },
      ],
    ),
    [
      { name: "browser", enabled: false, clis: ["codex"] },
      { name: "private-errors", enabled: true },
    ],
  );
});
