import assert from "node:assert/strict";
import { delimiter } from "node:path";
import test from "node:test";
import { parseAgentArgs, repairCommand, userCliPath } from "../scripts/agent-cli.mjs";

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

test("doctor adds user CLI locations for non-login shells", () => {
  const value = userCliPath("/home/edi", "/usr/bin");
  assert.equal(value, ["/home/edi/.local/bin", "/home/edi/.npm-global/bin", "/usr/bin"].join(delimiter));
});
