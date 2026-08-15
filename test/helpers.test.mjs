import assert from "node:assert/strict";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readlinkSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const script = resolve("scripts/sync-agent-helpers.sh");
const committer = resolve("scripts/committer");

function run(home, ...args) {
  return spawnSync("bash", [script, ...args], { encoding: "utf8", env: { ...process.env, HOME: home } });
}

test("helper sync installs committer into the user executable directory", (context) => {
  const home = mkdtempSync(join(tmpdir(), "agent-helpers-"));
  context.after(() => rmSync(home, { recursive: true, force: true }));
  const target = join(home, ".local", "bin", "committer");

  assert.equal(run(home).status, 0);
  assert.equal(lstatSync(target).isSymbolicLink(), true);
  assert.equal(readlinkSync(target), committer);
  assert.equal(run(home, "--check").status, 0);
});

test("helper sync preserves an existing user-owned committer", (context) => {
  const home = mkdtempSync(join(tmpdir(), "agent-helpers-owned-"));
  context.after(() => rmSync(home, { recursive: true, force: true }));
  const target = join(home, ".local", "bin", "committer");
  mkdirSync(join(home, ".local", "bin"), { recursive: true });
  writeFileSync(target, "user owned\n");

  const result = run(home);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /preserving user-owned file/);
  assert.equal(existsSync(target), true);
});
