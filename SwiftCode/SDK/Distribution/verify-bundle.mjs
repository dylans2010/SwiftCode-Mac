#!/usr/bin/env node
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, symlinkSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const toolkit = resolve(process.argv[2] ?? '');
assert.ok(process.argv[2], 'Usage: node verify-bundle.mjs <SwiftCodeSDK resource directory>');
const root = mkdtempSync(join(tmpdir(), 'swiftcode-bundle-'));
const cli = join(toolkit, 'TypeScript/cli/swiftcode.mjs');
const project = join(root, 'project');
const extensions = join(root, 'extensions');
const env = { ...process.env, SWIFTCODE_EXTENSIONS_DIR: extensions };
function command(executable, args, cwd) {
  const result = spawnSync(executable, args, { cwd, env, encoding: 'utf8', timeout: 60000 });
  assert.equal(result.status, 0, `${args.join(' ')}: ${result.error ?? result.stderr}\n${result.stdout}`);
  return result.stdout;
}
function runCLI(args) {
  const result = JSON.parse(command(process.execPath, [cli, ...args, '--json']));
  assert.equal(result.ok, true, JSON.stringify(result));
  return result.data;
}
try {
  runCLI(['create', '--type', 'extension', '--language', 'typescript', '--id', 'com.example.bundle-smoke', '--name', 'Bundle Smoke', '--outDir', project]);
  command('npm', ['install', '--ignore-scripts', '--no-audit', '--no-fund'], project);
  runCLI(['build', project]);
  const packaged = runCLI(['package', project, '--out', join(root, 'packages')]);
  const installed = runCLI(['install', packaged.path]);
  assert.equal(installed.id, 'com.example.bundle-smoke');
  const installedDir = join(extensions, installed.id, '0.1.0');
  assert.equal(JSON.parse(readFileSync(join(installedDir, 'swiftcode.json'))).id, installed.id);
  // The host supplies the SDK to installed extensions; mirror its run tree.
  const run = join(root, 'run');
  mkdirSync(join(run, 'node_modules/@swiftcode'), { recursive: true });
  symlinkSync(join(toolkit, 'TypeScript/package'), join(run, 'node_modules/@swiftcode/sdk'));
  symlinkSync(join(installedDir, 'dist'), join(run, 'dist'));
  const child = spawn(process.execPath, [join(toolkit, 'TypeScript/runtime-adapter/dist/adapter.js'),
    '--entrypoint', join(run, 'dist/index.js'), '--manifest', join(installedDir, 'swiftcode.json')],
    { env, stdio: ['pipe', 'pipe', 'pipe'] });
  let stdout = '', stderr = '', ready = false;
  const code = await new Promise((resolveExit, reject) => {
    const timer = setTimeout(() => { child.kill(); reject(new Error(`Adapter timeout: ${stderr}`)); }, 20000);
    child.on('error', reject);
    child.stdout.on('data', data => { stdout += data; });
    child.stderr.on('data', data => {
      stderr += data;
      if (!ready && stderr.includes('active; awaiting host events')) {
        ready = true;
        child.stdin.end();
      }
    });
    child.on('close', status => { clearTimeout(timer); resolveExit(status); });
  });
  assert.equal(code, 0, stderr);
  assert.ok(ready, stderr);
  assert.match(stdout, /"event":"extension\.ready"/);
  assert.match(stdout, /"method":"commands\.register"/);
  console.log('Bundled toolkit create → build → package → install → activate → shutdown: passed');
} finally {
  rmSync(root, { recursive: true, force: true });
}
