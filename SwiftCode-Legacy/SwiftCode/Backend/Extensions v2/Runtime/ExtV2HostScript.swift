import Foundation

// MARK: - Embedded Node.js extension-host script
//
// This is a real host, not a fixture: it runs a VS Code extension's
// declared `main` entry in Node, with `require('vscode')` intercepted
// and replaced by a shim that talks NDJSON RPC back to SwiftCode.
// The shim implements the supported surface from ExtV2VSCodeAPI.matrix
// and throws a descriptive error for the unsupported surface — it never
// returns fake success. The extension runs out-of-process, so a crash
// kills the host process, not SwiftCode.
//
// Protocol (one JSON object per line, both directions):
//   SwiftCode -> host: {"jsonrpc":"2.0","protocolVersion":1,"id":"..",
//                        "method":"activate"|"executeCommand"|"shutdown",
//                        "params":{...}}
//   host -> SwiftCode: a response {"jsonrpc":"2.0","id":"..","result":...}
//     or a host-initiated request {"jsonrpc":"2.0","protocolVersion":1,
//                        "id":"..","method":"host.*","params":{...}}
//   SwiftCode replies to host-initiated requests with a response object.
// Host-initiated requests are how an extension reads files, publishes
// diagnostics, or registers providers mid-command.

public enum ExtV2HostScript {
    public static let source: String = #"""
'use strict';
// SwiftCode extension host. Usage:
//   node extension-host.js --extension-entry <path-to-main.js>
const fs = require('fs');
const readline = require('readline');
const Module = require('module');

function argValue(flag) {
  const i = process.argv.indexOf(flag);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : null;
}
const entryPath = argValue('--extension-entry');
if (!entryPath) { console.error('extension-host: missing --extension-entry'); process.exit(2); }

let nextId = 1;
const pendingHostRequests = new Map();
function send(obj) { process.stdout.write(JSON.stringify(obj) + '\n'); }
function hostRequest(method, params) {
  return new Promise((resolve, reject) => {
    const id = 'host-' + (nextId++);
    pendingHostRequests.set(id, { resolve, reject });
    send({ jsonrpc: '2.0', protocolVersion: 1, id, method, params: params || {} });
    setTimeout(() => {
      if (pendingHostRequests.has(id)) {
        pendingHostRequests.delete(id);
        reject(new Error('SwiftCode did not answer host request ' + method));
      }
    }, 30000);
  });
}

const state = {
  commands: new Map(),          // id -> fn
  outputLines: [],
  messages: [],
  statusBar: null,
  treeProviders: new Map(),     // viewId -> provider
  completionLanguages: [],
  hoverLanguages: [],
  diagnostics: [],              // {path, diagnostics}
  activated: false,
  extension: null,
};

function unsupported(api) {
  return new Error('SwiftCode does not support ' + api + ' (see Docs/Extensions-v2.md API matrix).');
}
function toPlain(value) {
  try { return JSON.parse(JSON.stringify(value === undefined ? null : value)); }
  catch { return String(value); }
}

class Position {
  constructor(line, character) { this.line = line; this.character = character; }
}
class Range {
  constructor(a, b, c, d) {
    if (a instanceof Position) { this.start = a; this.end = b; }
    else { this.start = new Position(a, b); this.end = new Position(c, d); }
  }
}
class Selection extends Range {
  constructor(a, b, c, d) {
    super(a, b, c, d);
    this.anchor = this.start; this.active = this.end;
  }
}
class Uri {
  constructor(scheme, path) { this.scheme = scheme; this.path = path; this.fsPath = path; }
  static file(p) { return new Uri('file', p); }
  static parse(s) { try { const u = new URL(s); return new Uri(u.protocol.replace(':', ''), u.pathname); } catch { return new Uri('file', s); } }
  toString() { return this.scheme + '://' + this.path; }
}
class Diagnostic {
  constructor(range, message, severity) { this.range = range; this.message = message; this.severity = severity; }
}

const vscode = {
  Position, Range, Selection, Uri, Diagnostic,
  DiagnosticSeverity: { Error: 0, Warning: 1, Information: 2, Hint: 3 },
  commands: {
    registerCommand(id, fn) {
      state.commands.set(id, fn);
      return { dispose() { state.commands.delete(id); } };
    },
    async executeCommand(id, ...args) {
      const fn = state.commands.get(id);
      if (!fn) throw new Error('Command not found: ' + id);
      return fn(...args);
    },
    getCommands() { return Promise.resolve([...state.commands.keys()]); },
  },
  window: {
    showInformationMessage(m) { state.messages.push('info: ' + m); return Promise.resolve(undefined); },
    showWarningMessage(m) { state.messages.push('warning: ' + m); return Promise.resolve(undefined); },
    showErrorMessage(m) { state.messages.push('error: ' + m); return Promise.resolve(undefined); },
    createOutputChannel(name) {
      return {
        name,
        append(v) { state.outputLines.push(String(v)); },
        appendLine(v) { state.outputLines.push(String(v)); },
        show() {},
        dispose() {},
      };
    },
    createStatusBarItem() {
      return {
        set text(v) { state.statusBar = v; },
        show() {}, hide() {}, dispose() {},
      };
    },
    showQuickPick() { return Promise.resolve(undefined); },
    showInputBox() { return Promise.resolve(undefined); },
    withProgress() { return Promise.reject(unsupported('window.withProgress (full progress UI)')); },
  },
  workspace: {
    getConfiguration() {
      return {
        get(key, fallback) { return fallback; },
        has() { return false; },
        inspect() { return undefined; },
      };
    },
    async openTextDocument(path) {
      const content = await hostRequest('host.readFile', { path });
      return { uri: Uri.file(path), getText: () => content, fileName: path, languageId: '', lineCount: String(content).split('\n').length };
    },
    applyEdit(edit) {
      return hostRequest('host.applyEdit', { edit: toPlain(edit) }).then(() => true);
    },
    fs: {
      readFile(uri) { return hostRequest('host.readFile', { path: uri.fsPath || uri.path }).then((t) => Buffer.from(String(t))); },
      writeFile(uri, content) { return hostRequest('host.writeFile', { path: uri.fsPath || uri.path, content: Buffer.from(content).toString('utf8') }); },
    },
    onDidChangeTextDocument() { return { dispose() {} }; },
  },
  languages: {
    registerCompletionItemProvider(lang, provider) {
      state.completionLanguages.push(typeof lang === 'string' ? lang : lang.language);
      return { dispose() {} };
    },
    registerHoverProvider(lang) {
      state.hoverLanguages.push(typeof lang === 'string' ? lang : lang.language);
      return { dispose() {} };
    },
    registerDefinitionProvider() { return { dispose() {} }; },
    registerReferenceProvider() { return { dispose() {} }; },
    registerDocumentFormattingEditProvider() { return { dispose() {} }; },
    registerCodeActionProvider() { return { dispose() {} }; },
    createDiagnosticCollection(name) {
      return {
        set(uri, diagnostics) {
          state.diagnostics.push({ path: uri.fsPath || uri.path, diagnostics: toPlain(diagnostics) });
          return hostRequest('host.publishDiagnostics', { path: uri.fsPath || uri.path, diagnostics: toPlain(diagnostics) }).catch(() => {});
        },
        clear() {}, dispose() {},
      };
    },
  },
  extensions: {
    getExtension(id) {
      if (state.extension && state.extension.id === id) return { id, isActive: true, exports: state.extension.exports };
      return undefined;
    },
  },
  TreeItem: class { constructor(label) { this.label = label; } },
  EventEmitter: class { constructor() { this.event = () => {}; } fire() {} dispose() {} },
  Disposable: class { static from() { return { dispose() {} }; } },
  debug: { registerDebugAdapterDescriptorFactory() { throw unsupported('vscode.debug'); } },
  notebooks: { registerNotebookSerializer() { throw unsupported('vscode.notebooks'); } },
  authentication: { getSession() { return Promise.reject(unsupported('vscode.authentication')); } },
  version: '1.85.0',
};

// Intercept only 'vscode'; every other require resolves normally from the
// extension's own directory / node_modules.
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
  if (request === 'vscode') return vscode;
  return originalLoad.apply(this, arguments);
};

async function collectContribution() {
  const treeItems = [];
  for (const [viewId, provider] of state.treeProviders) {
    try {
      const children = await provider.getChildren();
      for (const child of (children || [])) {
        treeItems.push({ id: viewId + ':' + String(child.label), label: String(child.label), description: child.description || null, command: child.command ? child.command.command : null });
      }
    } catch (e) { state.outputLines.push('Tree provider ' + viewId + ' failed: ' + e.message); }
  }
  return {
    commands: [...state.commands.keys()].map((id) => ({ command: id, title: id })),
    views: [...state.treeProviders.keys()].map((id) => ({ id, name: id })),
    treeItems,
    statusBarText: state.statusBar,
    outputLines: state.outputLines,
    messages: state.messages,
    completionLanguages: state.completionLanguages,
    hoverLanguages: state.hoverLanguages,
  };
}

async function handleRequest(req) {
  if (req.method === 'activate') {
    if (state.activated) return { contribution: await collectContribution() };
    const mod = require(entryPath);
    const context = { subscriptions: [], extensionPath: require('path').dirname(entryPath) };
    if (typeof mod.activate === 'function') {
      const exports = await mod.activate(context);
      state.extension = { id: req.params && req.params.extensionId, exports: toPlain(exports) };
    }
    state.activated = true;
    return { contribution: await collectContribution() };
  }
  if (req.method === 'executeCommand') {
    const fn = state.commands.get(req.params.command);
    if (!fn) throw new Error('Command not registered in this host: ' + req.params.command);
    const result = await fn(...(req.params.args || []));
    return { result: toPlain(result) };
  }
  if (req.method === 'shutdown') {
    if (state.extension && state.extension.exports && typeof state.extension.exports.deactivate === 'function') {
      try { await state.extension.exports.deactivate(); } catch {}
    }
    return { ok: true };
  }
  throw new Error('Unknown host method: ' + req.method);
}

const rl = readline.createInterface({ input: process.stdin, terminal: false });
rl.on('line', async (line) => {
  if (!line.trim()) return;
  let msg;
  try { msg = JSON.parse(line); } catch { return; }
  // Response to a host-initiated request.
  if (msg.result !== undefined || msg.error !== undefined) {
    const pending = pendingHostRequests.get(msg.id);
    if (pending) {
      pendingHostRequests.delete(msg.id);
      if (msg.error) pending.reject(new Error(msg.error.message || 'host request failed'));
      else pending.resolve(msg.result);
    }
    return;
  }
  // Request from SwiftCode.
  try {
    const result = await handleRequest(msg);
    send({ jsonrpc: '2.0', id: msg.id, result });
  } catch (e) {
    send({ jsonrpc: '2.0', id: msg.id, error: { code: -32000, message: e && e.message ? e.message : String(e) } });
  }
});
process.on('uncaughtException', (e) => {
  try { send({ jsonrpc: '2.0', id: 'fatal', error: { code: -32001, message: 'Host crashed: ' + e.message } }); } catch {}
  process.exit(1);
});
"""#

    /// The script file SwiftCode writes (and refreshes when it changes) so
    /// the Node process has a real file to execute.
    public static func hostScriptURL(storage: ExtV2Storage) -> URL {
        storage.root.appendingPathComponent("host/extension-host.js")
    }

    public static func ensureHostScript(storage: ExtV2Storage) throws -> URL {
        let url = hostScriptURL(storage: storage)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == source {
            return url
        }
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
