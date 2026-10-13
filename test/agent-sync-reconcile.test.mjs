import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const script = resolve("scripts/agent-sync.mjs");

function git(root, args) {
  const result = spawnSync("git", ["-c", "core.hooksPath=/dev/null", "-C", root, ...args], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
}

function commit(root, path, contents) {
  writeFileSync(join(root, path), contents);
  git(root, ["add", path]);
  git(root, ["-c", "commit.gpgsign=false", "commit", "-m", `update ${path}`]);
}

function fixture(context) {
  const root = mkdtempSync(join(tmpdir(), "agent-sync-reconcile-"));
  context.after(() => rmSync(root, { recursive: true, force: true }));
  const home = join(root, "home");
  const repos = {};
  mkdirSync(home);
  for (const name of ["agent", "manager"]) {
    const origin = join(root, `${name}.git`);
    const local = join(root, name);
    git(root, ["init", "--bare", "--initial-branch=main", origin]);
    git(root, ["clone", origin, local]);
    git(local, ["config", "user.name", "Test"]);
    git(local, ["config", "user.email", "test@example.com"]);
    writeFileSync(join(local, "README.md"), "initial\n");
    writeFileSync(join(local, "configuration.txt"), `${name} configuration\n`);
    if (name === "agent") {
      mkdirSync(join(local, "scripts"));
      const setup = join(local, "scripts", "setup-linux.sh");
      writeFileSync(setup, `#!/bin/sh
set -eu
printf 'setup\\n' >> "$AGENT_SETUP_HOME/calls.txt"
cat "$AGENT_REPO_ROOT/configuration.txt" "$MANAGER_REPO_ROOT/configuration.txt" > "$AGENT_SETUP_HOME/AGENTS.md"
`);
      chmodSync(setup, 0o755);
      writeFileSync(join(local, "scripts", "agent-cli.mjs"), `import { appendFileSync, readFileSync } from "node:fs";
import { join } from "node:path";
if (process.argv.slice(2).join(" ") !== "doctor --quiet") throw new Error("unexpected doctor arguments");
readFileSync(join(process.env.AGENT_SETUP_HOME, "AGENTS.md"));
appendFileSync(join(process.env.AGENT_SETUP_HOME, "calls.txt"), "doctor\\n");
`);
    }
    git(local, ["add", "."]);
    git(local, ["-c", "commit.gpgsign=false", "commit", "-m", "initial"]);
    git(local, ["push", "-u", "origin", "main"]);
    git(local, ["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main"]);
    repos[name] = { local, origin };
  }
  const setupState = join(home, "setup.json");
  writeFileSync(setupState, JSON.stringify({ platform: "linux", publicOnly: false, cliMode: "detected" }));
  const environment = {
    ...process.env,
    AGENT_SETUP_HOME: home,
    AGENT_SETUP_STATE: setupState,
    AGENT_REPO_ROOT: repos.agent.local,
    MANAGER_REPO_ROOT: repos.manager.local,
    AGENT_SYNC_STATE: join(home, "last-run.json"),
    AGENT_SYNC_LOCK: join(home, "lock"),
  };
  return { root, home, environment, ...repos };
}

function advanceOrigin(f, name, contents) {
  const { local, origin } = f[name];
  const peer = join(f.root, `${name}-peer`);
  if (!existsSync(peer)) {
    git(f.root, ["clone", origin, peer]);
    git(peer, ["config", "user.name", "Test"]);
    git(peer, ["config", "user.email", "test@example.com"]);
  }
  commit(peer, "remote.txt", contents);
  git(peer, ["push", "origin", "main"]);
  assert.notEqual(git(local, ["rev-parse", "HEAD"]), git(peer, ["rev-parse", "HEAD"]));
}

function files(root) {
  const contents = {};
  function walk(directory, prefix = "") {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      if (entry.name === ".git") continue;
      const path = join(prefix, entry.name);
      if (entry.isDirectory()) walk(join(directory, entry.name), path);
      else contents[path] = readFileSync(join(directory, entry.name), "base64");
    }
  }
  walk(root);
  return contents;
}

function snapshot(root) {
  return {
    head: git(root, ["rev-parse", "HEAD"]),
    branch: git(root, ["branch", "--show-current"]),
    index: git(root, ["ls-files", "--stage", "-z"]),
    status: git(root, ["status", "--porcelain", "--untracked-files=all", "-z"]),
    refs: git(root, ["for-each-ref", "--format=%(refname) %(objectname)"]),
    contents: files(root),
  };
}

function sync(f, args = []) {
  return spawnSync(process.execPath, [script, ...args], { env: f.environment, encoding: "utf8" });
}

function state(f) {
  return JSON.parse(readFileSync(f.environment.AGENT_SYNC_STATE, "utf8"));
}

function assertNotApplied(f) {
  assert.equal(existsSync(join(f.home, "calls.txt")), false);
  assert.equal(existsSync(join(f.home, "AGENTS.md")), false);
  assert.equal(state(f).status, "blocked");
  assert.equal(existsSync(f.environment.AGENT_SYNC_LOCK), false);
}

test("reconciliation applies checked-out configuration without fetching or altering dirty and ahead repositories", (context) => {
  const f = fixture(context);
  advanceOrigin(f, "agent", "known remote update\n");
  git(f.agent.local, ["fetch", "origin"]);
  advanceOrigin(f, "agent", "unfetched remote update\n");
  commit(f.manager.local, "local-commit.txt", "local commit\n");
  advanceOrigin(f, "manager", "unfetched manager update\n");
  for (const name of ["agent", "manager"]) {
    const local = f[name].local;
    writeFileSync(join(local, "configuration.txt"), `${name} staged configuration\n`);
    git(local, ["add", "configuration.txt"]);
    writeFileSync(join(local, "configuration.txt"), `${name} working configuration\n`);
    mkdirSync(join(local, "untracked"));
    writeFileSync(join(local, "untracked", "evidence.txt"), `${name} ongoing work\n`);
  }
  const before = { agent: snapshot(f.agent.local), manager: snapshot(f.manager.local) };

  const result = sync(f, ["--reconcile-only"]);

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /agent-sync complete/);
  assert.equal(readFileSync(join(f.home, "calls.txt"), "utf8"), "setup\ndoctor\n");
  assert.equal(readFileSync(join(f.home, "AGENTS.md"), "utf8"), "agent working configuration\nmanager working configuration\n");
  assert.deepEqual(snapshot(f.agent.local), before.agent);
  assert.deepEqual(snapshot(f.manager.local), before.manager);
  const recorded = state(f);
  assert.equal(recorded.status, "ok");
  assert.equal(recorded.trigger, "reconcile");
  assert.deepEqual(recorded.repos, [
    { root: f.agent.local, branch: "main", commit: before.agent.head.trim(), dirty: true, ahead: 0, behind: 1 },
    { root: f.manager.local, branch: "main", commit: before.manager.head.trim(), dirty: true, ahead: 1, behind: 0 },
  ]);
  assert.equal(existsSync(f.environment.AGENT_SYNC_LOCK), false);
});

for (const blocker of ["dirty", "ahead"]) {
  test(`normal sync blocks ${blocker} manager work before merging a behind agent`, (context) => {
    const f = fixture(context);
    advanceOrigin(f, "agent", "remote agent update\n");
    if (blocker === "dirty") writeFileSync(join(f.manager.local, "README.md"), "ongoing manager work\n");
    else commit(f.manager.local, "local.txt", "unpublished manager work\n");
    const beforeAgent = snapshot(f.agent.local);
    const beforeManager = snapshot(f.manager.local);

    const result = sync(f);

    assert.equal(result.status, 3, result.stderr);
    assert.match(result.stderr, blocker === "dirty" ? /dirty worktree/ : /1 unpushed commit\(s\)/);
    const afterAgent = snapshot(f.agent.local);
    assert.notEqual(afterAgent.refs, beforeAgent.refs, "normal sync should fetch the remote update");
    assert.deepEqual({ ...afterAgent, refs: beforeAgent.refs }, beforeAgent);
    assert.deepEqual(snapshot(f.manager.local), beforeManager);
    assertNotApplied(f);
  });
}

for (const branch of ["feature", "detached"]) {
  test(`reconciliation refuses a ${branch} manager before applying configuration`, (context) => {
    const f = fixture(context);
    git(f.manager.local, branch === "feature" ? ["switch", "-c", "feature"] : ["checkout", "--detach"]);
    const beforeAgent = snapshot(f.agent.local);
    const beforeManager = snapshot(f.manager.local);

    const result = sync(f, ["--reconcile-only"]);

    assert.equal(result.status, 3, result.stderr);
    assert.match(result.stderr, new RegExp(`branch=${branch}, expected=main`));
    assert.deepEqual(snapshot(f.agent.local), beforeAgent);
    assert.deepEqual(snapshot(f.manager.local), beforeManager);
    assertNotApplied(f);
  });
}
