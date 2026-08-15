import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const installer = resolve("scripts/install/abx.sh");

test("abx installer check accepts a standalone CLI and Chromium runtime", (context) => {
  const root = mkdtempSync(join(tmpdir(), "agent-abx-install-"));
  context.after(() => rmSync(root, { recursive: true, force: true }));
  const bin = join(root, "bin");
  const browsers = join(root, "browsers");
  mkdirSync(join(browsers, "chromium-test"), { recursive: true });
  mkdirSync(bin, { recursive: true });
  const fakeAbx = join(bin, "abx");
  writeFileSync(fakeAbx, "#!/usr/bin/env bash\necho 9.9.9\n");
  chmodSync(fakeAbx, 0o755);

  const result = spawnSync("/bin/bash", [installer, "--check", "--platform", "linux"], {
    encoding: "utf8",
    env: {
      HOME: root,
      PATH: [bin, "/usr/bin", "/bin"].join(delimiter),
      PLAYWRIGHT_BROWSERS_PATH: browsers,
    },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /abx check complete: 9\.9\.9/);
});

test("abx installer check reports a missing standalone CLI", () => {
  const result = spawnSync("/bin/bash", [installer, "--check", "--platform", "linux"], {
    encoding: "utf8",
    env: { HOME: tmpdir(), PATH: "/usr/bin:/bin" },
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /missing: standalone abx/);
});
