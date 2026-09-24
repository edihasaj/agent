import assert from "node:assert/strict";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readlinkSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const script = resolve("scripts/sync-agent-helpers.sh");
const committer = resolve("bin/committer");
const docsList = resolve("bin/docs-list");

function run(home, ...args) {
  return spawnSync("bash", [script, ...args], { encoding: "utf8", env: { ...process.env, HOME: home } });
}

test("helper sync installs committer into the user executable directory", (context) => {
  const home = mkdtempSync(join(tmpdir(), "agent-helpers-"));
  context.after(() => rmSync(home, { recursive: true, force: true }));
  const target = join(home, ".local", "bin", "committer");

  assert.equal(existsSync(committer), true);
  assert.equal(run(home).status, 0);
  assert.equal(lstatSync(target).isSymbolicLink(), true);
  assert.equal(readlinkSync(target), committer);
  assert.equal(readlinkSync(join(home, ".local", "bin", "docs-list")), docsList);
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

function repo(files) {
  const dir = mkdtempSync(join(tmpdir(), "agent-docs-list-"));
  spawnSync("git", ["init", "-q"], { cwd: dir });
  for (const [name, body] of Object.entries(files)) {
    mkdirSync(join(dir, name, ".."), { recursive: true });
    writeFileSync(join(dir, name), body);
  }
  return dir;
}

function docs(cwd) {
  return spawnSync("bash", [docsList], { cwd, encoding: "utf8" });
}

test("docs-list says so when a repo has no docs and exits cleanly", (context) => {
  const dir = repo({ "README.md": "# x\n" });
  context.after(() => rmSync(dir, { recursive: true, force: true }));
  const result = docs(dir);
  assert.equal(result.status, 0);
  assert.match(result.stdout, /no docs\/ directory/);
});

test("docs-list lists docs with read_when hints", (context) => {
  const dir = repo({ "docs/deploy.md": "---\nsummary: Deploy steps\nread_when: deploying\n---\n# Deploy\n" });
  context.after(() => rmSync(dir, { recursive: true, force: true }));
  const result = docs(dir);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /deploy\.md/);
});

test("docs-list prefers the repository's own docs:list script", (context) => {
  const dir = repo({
    "package.json": JSON.stringify({ name: "x", scripts: { "docs:list": "echo repo-owned-lister" } }),
    "package-lock.json": "{}",
    "docs/a.md": "# a\n",
  });
  context.after(() => rmSync(dir, { recursive: true, force: true }));
  const result = docs(dir);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /repo-owned-lister/);
});
