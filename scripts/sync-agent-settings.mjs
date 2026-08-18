#!/usr/bin/env node

// Agent CLI settings we own on every machine.
//
// The one that matters today is `includeCoAuthoredBy`. The Claude CLI adds a
// `Co-Authored-By: <model>` trailer to every commit it makes unless told not to,
// which means an unattended agent lands commits co-authored by a model even when
// the pipeline running it forbids exactly that. Prompts are the wrong place to
// fix it: they are per-repo, per-workorder, and a model can simply not follow
// one. The setting is per-machine and the CLI enforces it, so setup turns it off
// once and `--check` keeps it off.
//
// Only keys listed in `managedSettings` are touched; everything else in the file
// is read, preserved, and written back untouched.

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";

const supportedClis = ["codex", "claude", "opencode", "gemini", "copilot"];
const userHome = resolve(process.env.AGENT_SETUP_HOME || homedir());

// CLIs absent from this map have no settings we manage — either they add no
// commit trailer of their own, or they expose no switch for it.
const managedSettings = {
  claude: { file: [".claude", "settings.json"], values: { includeCoAuthoredBy: false } },
};

function usage(stream = process.stdout) {
  stream.write("usage: sync-agent-settings [--check] [--cli NAME]...\n\n");
  stream.write("Pin the agent CLI settings this repo owns (commit co-author trailers off).\n");
  stream.write("Unmanaged keys in each settings file are preserved. Re-running is safe.\n\n");
  stream.write("Options:\n");
  stream.write("  --check          report drift without changing configuration\n");
  stream.write("  --cli NAME       select a CLI; repeat for multiple CLIs\n");
  stream.write("  -h, --help       show this help\n\n");
  stream.write(`Supported CLIs: ${supportedClis.join(", ")}\n`);
}

function parseArgs(argv) {
  const options = { check: false, clis: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--check") options.check = true;
    else if (argument === "--cli") {
      const cli = argv[index + 1];
      if (!cli) throw new Error("--cli requires a value");
      if (!supportedClis.includes(cli)) throw new Error(`unsupported CLI: ${cli}`);
      if (!options.clis.includes(cli)) options.clis.push(cli);
      index += 1;
    } else if (argument === "-h" || argument === "--help") {
      usage();
      process.exit(0);
    } else throw new Error(`unknown argument: ${argument}`);
  }
  return options;
}

function readSettings(path) {
  if (!existsSync(path)) return {};
  const raw = readFileSync(path, "utf8").trim();
  if (raw === "") return {};
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    // Never overwrite a file we cannot read: a hand-edited settings.json with a
    // stray comma holds real configuration, and clobbering it to set one key is
    // a worse outcome than reporting the drift.
    throw new Error(`unreadable settings, fix by hand: ${path}: ${error.message}`);
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`settings is not a JSON object: ${path}`);
  }
  return parsed;
}

function writeSettings(path, data) {
  const temporary = `${path}.tmp-agent-settings`;
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(temporary, `${JSON.stringify(data, null, 2)}\n`, { mode: 0o600 });
  renameSync(temporary, path);
}

function driftedKeys(current, values) {
  return Object.entries(values)
    .filter(([key, value]) => JSON.stringify(current[key]) !== JSON.stringify(value))
    .map(([key]) => key);
}

function main(argv) {
  const options = parseArgs(argv);
  const clis = options.clis.length > 0 ? options.clis : supportedClis;
  let matched = 0;
  let changed = 0;
  const failures = [];

  for (const cli of clis) {
    const managed = managedSettings[cli];
    if (!managed) continue;
    const path = join(userHome, ...managed.file);
    let current;
    try {
      current = readSettings(path);
    } catch (error) {
      failures.push(error.message);
      continue;
    }
    const drifted = driftedKeys(current, managed.values);
    if (drifted.length === 0) {
      matched += 1;
      continue;
    }
    const summary = drifted.map((key) => `${key}=${JSON.stringify(managed.values[key])}`).join(", ");
    if (options.check) {
      failures.push(`${path}: expected ${summary}`);
      continue;
    }
    writeSettings(path, { ...current, ...managed.values });
    process.stdout.write(`updated: ${path} (${summary})\n`);
    changed += 1;
  }

  for (const failure of failures) process.stderr.write(`${failure}\n`);
  process.stdout.write(
    `settings ${options.check ? "check" : "sync"} complete: matched=${matched} changed=${changed} failures=${failures.length}\n`,
  );
  return failures.length > 0 ? 1 : 0;
}

try {
  process.exit(main(process.argv.slice(2)));
} catch (error) {
  process.stderr.write(`error: ${error.message}\n`);
  usage(process.stderr);
  process.exit(2);
}
