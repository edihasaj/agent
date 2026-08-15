#!/usr/bin/env node

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const supportedClis = ["codex", "claude", "opencode", "gemini", "copilot"];
const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = resolve(dirname(scriptPath), "..");
const userHome = resolve(process.env.AGENT_SETUP_HOME || homedir());
const platform = process.env.AGENT_SETUP_PLATFORM || (process.platform === "win32" ? "windows" : "posix");

function usage(stream = process.stdout) {
  stream.write(`usage: sync-agent-mcps [--check] [--public-only] [--exclude NAME] [--cli NAME]...\n\n`);
  stream.write(`Register managed private MCPs in installed agent CLIs.\n`);
  stream.write(`Existing unmanaged MCPs are preserved. Re-running is safe.\n\n`);
  stream.write(`Options:\n`);
  stream.write(`  --check          report drift without changing configuration\n`);
  stream.write(`  --public-only    ignore ../manager/configs/mcps.json\n`);
  stream.write(`  --exclude NAME   remove and skip one managed MCP; repeat as needed\n`);
  stream.write(`  --cli NAME       select a CLI; repeat for multiple CLIs\n`);
  stream.write(`  -h, --help       show this help\n\n`);
  stream.write(`Supported CLIs: ${supportedClis.join(", ")}\n`);
}

function parseArgs(argv) {
  const options = { check: false, publicOnly: false, clis: [], excluded: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--check") options.check = true;
    else if (argument === "--public-only") options.publicOnly = true;
    else if (argument === "--exclude") {
      const name = argv[index + 1];
      if (!name) throw new Error("--exclude requires a value");
      if (!options.excluded.includes(name)) options.excluded.push(name);
      index += 1;
    }
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

function executableExists(command) {
  if (command.includes("/") || command.includes("\\")) return existsSync(command);
  if (platform === "windows" && /\.[a-z0-9]+$/i.test(command)) {
    return (process.env.PATH || "").split(delimiter).some((directory) => existsSync(join(directory, command)));
  }
  const extensions = platform === "windows"
    ? (process.env.PATHEXT || ".COM;.EXE;.BAT;.CMD").split(";")
    : [""];
  return (process.env.PATH || "").split(delimiter).some((directory) =>
    extensions.some((extension) => existsSync(join(directory, command + extension.toLowerCase())) ||
      existsSync(join(directory, command + extension.toUpperCase()))),
  );
}

function loadManifest(path, required) {
  if (!existsSync(path)) {
    if (required) throw new Error(`MCP manifest not found: ${path}`);
    return [];
  }
  const parsed = JSON.parse(readFileSync(path, "utf8"));
  if (parsed.version !== 1 || !Array.isArray(parsed.servers)) {
    throw new Error(`invalid MCP manifest: ${path}`);
  }
  const names = new Set();
  for (const server of parsed.servers) {
    if (!server || typeof server.name !== "string" || !server.name) {
      throw new Error(`MCP manifest entry missing name: ${path}`);
    }
    if (names.has(server.name)) throw new Error(`duplicate MCP name in ${path}: ${server.name}`);
    if (server.replaces && (!Array.isArray(server.replaces) ||
      server.replaces.some((name) => typeof name !== "string" || !name || name === server.name))) {
      throw new Error(`invalid replaces list for ${server.name}: ${path}`);
    }
    names.add(server.name);
  }
  return parsed.servers;
}

function expand(value) {
  return value.replaceAll("{repo}", repoRoot).replaceAll("{home}", userHome);
}

function desiredConfig(server) {
  if (server.transport === "http") {
    if (typeof server.url !== "string") throw new Error(`${server.name}: HTTP server missing url`);
    return { transport: "http", url: expand(server.url) };
  }
  const commandSpec = server.command?.[platform];
  if (!Array.isArray(commandSpec) || commandSpec.length === 0) {
    throw new Error(`${server.name}: missing ${platform} command`);
  }
  const [command, ...args] = commandSpec.map(expand);
  return { transport: "stdio", command, args };
}

function readJson(path) {
  if (!existsSync(path)) return {};
  return JSON.parse(readFileSync(path, "utf8"));
}

function run(command, args, allowFailure = false) {
  const result = spawnSync(command, args, { encoding: "utf8", env: process.env });
  if (result.error) {
    if (allowFailure) return result;
    throw new Error(`${command}: ${result.error.message}`);
  }
  if (result.status !== 0 && !allowFailure) {
    const detail = (result.stderr || result.stdout || "command failed").trim().split("\n").at(-1);
    throw new Error(`${command} ${args.join(" ")}: ${detail}`);
  }
  return result;
}

function normalize(server) {
  if (!server || typeof server !== "object") return null;
  if (server.transport && typeof server.transport === "object") {
    const transport = server.transport;
    if (transport.type === "stdio") {
      return { transport: "stdio", command: transport.command, args: transport.args || [] };
    }
    return { transport: "http", url: transport.url };
  }
  const type = server.type || server.transport;
  if (type === "local" || type === "stdio" || server.command) {
    if (Array.isArray(server.command)) {
      return { transport: "stdio", command: server.command[0], args: server.command.slice(1) };
    }
    return { transport: "stdio", command: server.command, args: server.args || [] };
  }
  if (type === "remote" || type === "http" || type === "sse" || server.url) {
    return { transport: "http", url: server.url };
  }
  return null;
}

function sameConfig(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function currentCliConfig(cli, name) {
  if (cli === "codex") {
    const result = run("codex", ["mcp", "get", name, "--json"], true);
    return result.status === 0 ? normalize(JSON.parse(result.stdout)) : null;
  }
  if (cli === "copilot") {
    const result = run("copilot", ["mcp", "get", name, "--json"], true);
    if (result.status !== 0) return null;
    const parsed = JSON.parse(result.stdout);
    return normalize(parsed[name]);
  }
  if (cli === "claude") {
    return normalize(readJson(join(userHome, ".claude.json")).mcpServers?.[name]);
  }
  if (cli === "gemini") {
    return normalize(readJson(join(userHome, ".gemini", "settings.json")).mcpServers?.[name]);
  }
  if (cli === "opencode") {
    const jsonPath = join(userHome, ".config", "opencode", "opencode.json");
    const jsoncPath = join(userHome, ".config", "opencode", "opencode.jsonc");
    if (existsSync(jsoncPath)) {
      throw new Error(`OpenCode JSONC requires manual merge: ${jsoncPath}`);
    }
    return normalize(readJson(jsonPath).mcp?.[name]);
  }
  throw new Error(`unsupported CLI: ${cli}`);
}

function removeCliConfig(cli, name) {
  if (cli === "codex") run("codex", ["mcp", "remove", name]);
  else if (cli === "claude") run("claude", ["mcp", "remove", "-s", "user", name]);
  else if (cli === "gemini") run("gemini", ["mcp", "remove", "-s", "user", name]);
  else if (cli === "copilot") run("copilot", ["mcp", "remove", name]);
}

function addCliConfig(cli, name, desired) {
  let args;
  if (desired.transport === "stdio") {
    if (cli === "codex") args = ["mcp", "add", name, "--", desired.command, ...desired.args];
    else if (cli === "claude") args = ["mcp", "add", "-s", "user", name, "--", desired.command, ...desired.args];
    else if (cli === "gemini") args = ["mcp", "add", "-s", "user", name, desired.command, ...desired.args];
    else if (cli === "copilot") args = ["mcp", "add", name, "--", desired.command, ...desired.args];
  } else {
    if (cli === "codex") args = ["mcp", "add", name, "--url", desired.url];
    else if (cli === "claude") args = ["mcp", "add", "-s", "user", "--transport", "http", name, desired.url];
    else if (cli === "gemini") args = ["mcp", "add", "-s", "user", "-t", "http", name, desired.url];
    else if (cli === "copilot") args = ["mcp", "add", "--transport", "http", name, desired.url];
  }
  run(cli, args);
}

function writeOpenCodeConfig(name, desired) {
  const path = join(userHome, ".config", "opencode", "opencode.json");
  const data = readJson(path);
  data.$schema ||= "https://opencode.ai/config.json";
  data.mcp ||= {};
  data.mcp[name] = desired.transport === "stdio"
    ? { type: "local", command: [desired.command, ...desired.args], enabled: true }
    : { type: "remote", url: desired.url, enabled: true };
  const temporary = `${path}.tmp-agent-mcp`;
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(temporary, `${JSON.stringify(data, null, 2)}\n`, { mode: 0o600 });
  renameSync(temporary, path);
}

function removeOpenCodeConfig(name) {
  const path = join(userHome, ".config", "opencode", "opencode.json");
  const data = readJson(path);
  if (!data.mcp?.[name]) return;
  delete data.mcp[name];
  const temporary = `${path}.tmp-agent-mcp`;
  writeFileSync(temporary, `${JSON.stringify(data, null, 2)}\n`, { mode: 0o600 });
  renameSync(temporary, path);
}

function main() {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`error: ${error.message}\n`);
    usage(process.stderr);
    process.exit(2);
  }

  const privatePath = process.env.PRIVATE_MCPS_CONFIG || resolve(repoRoot, "..", "manager", "configs", "mcps.json");
  const servers = options.publicOnly ? [] : loadManifest(privatePath, false);
  const managedNames = new Set(servers.map((server) => server.name));
  for (const name of options.excluded) {
    if (!managedNames.has(name)) throw new Error(`cannot exclude unmanaged MCP: ${name}`);
  }
  const selectedClis = options.clis.length > 0
    ? options.clis
    : supportedClis.filter(executableExists);
  let failures = 0;
  let matched = 0;
  let changed = 0;
  let skipped = 0;

  for (const cli of selectedClis) {
    if (!executableExists(cli)) {
      process.stdout.write(`skip: ${cli} executable missing\n`);
      skipped += 1;
      continue;
    }
    for (const server of servers) {
      if (server.enabled === false || !server.clis?.includes(cli)) continue;
      if (options.excluded.includes(server.name)) {
        try {
          const current = currentCliConfig(cli, server.name);
          if (!current) {
            matched += 1;
            continue;
          }
          if (options.check) {
            process.stderr.write(`unexpected: ${cli}/${server.name} is excluded\n`);
            failures += 1;
            continue;
          }
          if (cli === "opencode") removeOpenCodeConfig(server.name);
          else removeCliConfig(cli, server.name);
          process.stdout.write(`removed excluded: ${cli}/${server.name}\n`);
          changed += 1;
        } catch (error) {
          process.stderr.write(`error: ${cli}/${server.name}: ${error.message}\n`);
          failures += 1;
        }
        continue;
      }
      const missing = (server.requires || []).filter((command) => !executableExists(command));
      if (missing.length > 0) {
        process.stdout.write(`skip: ${cli}/${server.name} missing ${missing.join(",")}\n`);
        skipped += 1;
        continue;
      }
      try {
        const desired = desiredConfig(server);
        const legacyNames = server.replaces || [];
        for (const legacyName of legacyNames) {
          const legacy = currentCliConfig(cli, legacyName);
          if (!legacy) continue;
          if (options.check) {
            process.stderr.write(`legacy: ${cli}/${legacyName} -> ${server.name}\n`);
            failures += 1;
            continue;
          }
          if (cli === "opencode") removeOpenCodeConfig(legacyName);
          else removeCliConfig(cli, legacyName);
          process.stdout.write(`removed legacy: ${cli}/${legacyName}\n`);
          changed += 1;
        }
        const current = currentCliConfig(cli, server.name);
        if (sameConfig(current, desired)) {
          matched += 1;
          continue;
        }
        if (options.check) {
          process.stderr.write(`mismatch: ${cli}/${server.name}\n`);
          failures += 1;
          continue;
        }
        if (cli === "opencode") writeOpenCodeConfig(server.name, desired);
        else {
          if (current) removeCliConfig(cli, server.name);
          addCliConfig(cli, server.name, desired);
        }
        process.stdout.write(`${current ? "updated" : "added"}: ${cli}/${server.name}\n`);
        changed += 1;
      } catch (error) {
        process.stderr.write(`error: ${cli}/${server.name}: ${error.message}\n`);
        failures += 1;
      }
    }
  }

  const mode = options.check ? "check" : "sync";
  process.stdout.write(`MCP ${mode} complete: matched=${matched} changed=${changed} skipped=${skipped} clis=${selectedClis.join(",") || "none"}\n`);
  if (failures > 0) {
    process.stderr.write(`MCP ${mode} failed: ${failures} issue(s)\n`);
    process.exit(1);
  }
}

try {
  main();
} catch (error) {
  process.stderr.write(`error: ${error.message}\n`);
  process.exit(1);
}
