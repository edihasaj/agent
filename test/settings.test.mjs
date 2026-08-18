import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const script = resolve("scripts/sync-agent-settings.mjs");

function runSync(home, args = []) {
  return spawnSync(process.execPath, [script, ...args], {
    encoding: "utf8",
    env: { ...process.env, AGENT_SETUP_HOME: home },
  });
}

function makeHome(context, settings) {
  const home = mkdtempSync(join(tmpdir(), "agent-settings-"));
  context.after(() => rmSync(home, { recursive: true, force: true }));
  if (settings !== undefined) {
    mkdirSync(join(home, ".claude"), { recursive: true });
    writeFileSync(join(home, ".claude", "settings.json"), `${JSON.stringify(settings, null, 2)}\n`);
  }
  return home;
}

function readClaudeSettings(home) {
  return JSON.parse(readFileSync(join(home, ".claude", "settings.json"), "utf8"));
}

test("sync turns off co-author trailers when the setting is missing", (context) => {
  const home = makeHome(context, { model: "opus", permissions: { allow: ["Bash"] } });

  const result = runSync(home, ["--cli", "claude"]);

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /settings sync complete: matched=0 changed=1 failures=0/);
  assert.deepEqual(readClaudeSettings(home), {
    model: "opus",
    permissions: { allow: ["Bash"] },
    includeCoAuthoredBy: false,
  });
});

test("sync creates the settings file when the CLI has never been configured", (context) => {
  const home = makeHome(context);

  const result = runSync(home, ["--cli", "claude"]);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(readClaudeSettings(home), { includeCoAuthoredBy: false });
});

test("sync overrides an explicit true rather than leaving the trailer on", (context) => {
  const home = makeHome(context, { includeCoAuthoredBy: true });

  const result = runSync(home, ["--cli", "claude"]);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(readClaudeSettings(home).includeCoAuthoredBy, false);
});

test("sync is idempotent once the setting is pinned", (context) => {
  const home = makeHome(context, { includeCoAuthoredBy: false, model: "sonnet" });

  const result = runSync(home, ["--cli", "claude"]);

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /settings sync complete: matched=1 changed=0 failures=0/);
});

test("check reports drift without writing", (context) => {
  const home = makeHome(context, { model: "opus" });

  const result = runSync(home, ["--check", "--cli", "claude"]);

  assert.equal(result.status, 1);
  assert.match(result.stderr, /expected includeCoAuthoredBy=false/);
  assert.deepEqual(readClaudeSettings(home), { model: "opus" });
});

test("unreadable settings fail loudly instead of being clobbered", (context) => {
  const home = makeHome(context);
  mkdirSync(join(home, ".claude"), { recursive: true });
  const path = join(home, ".claude", "settings.json");
  writeFileSync(path, '{"model": "opus",}\n');

  const result = runSync(home, ["--cli", "claude"]);

  assert.equal(result.status, 1);
  assert.match(result.stderr, /unreadable settings, fix by hand/);
  assert.equal(readFileSync(path, "utf8"), '{"model": "opus",}\n');
});

test("a CLI with no managed settings is a no-op", (context) => {
  const home = makeHome(context);

  const result = runSync(home, ["--cli", "codex"]);

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /settings sync complete: matched=0 changed=0 failures=0/);
});
