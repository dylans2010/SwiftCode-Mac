'use strict';
// Ycode extension host (specs/ide/extensions-platform.md §4.4).
//
// One Node process per VS Code extension. Speaks NDJSON JSON-RPC v1
// over stdin/stdout: one JSON object per line, `jsonrpc: "2.0"`,
// `protocolVersion: 1`. Intercepts only `require('vscode')`; every
// other `require` resolves normally from the extension's own
// directory / node_modules.
//
// D-9 (recorded disagreement, fixed here): `workspace.applyEdit`
// sends `host.applyEdit` as `{path, edits: [...]}` — the shape the
// Swift handler requires — not the `{edit}` shape Legacy's shim
// sent, which the handler could never serve.
//
// `vscode.version` is '1.85.0'. Unsupported APIs throw a descriptive
// error, never fake success.
const fs = require('fs');
const path = require('path');

const PROTOCOL_VERSION = 1;
const HOST_REQUEST_TIMEOUT_MS = 30_000;

function entryPathFromArgv() {
  const index = process.argv.indexOf('--extension-entry');
  if (index === -1 || !process.argv[index + 1]) {
    process.stderr.write('extension-host: missing --extension-entry\n');
    process.exit(2);
  }
  return process.argv[index + 1];
}

const entryPath = entryPathFromArgv();

// ---- NDJSON transport -------------------------------------------------
let inputBuffer = '';
let nextHostRequestId = 1;
const pendingHostRequests = new Map(); // id -> {resolve, reject, timer}

function send(message) {
  process.stdout.write(JSON.stringify(message) + '\n');
}

function sendRequestToSwift(method, params) {
  const id = `host-${nextHostRequestId++}`;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pendingHostRequests.delete(id);
      reject(new Error(`Host request '${method}' timed out after 30s`));
    }, HOST_REQUEST_TIMEOUT_MS);
    pendingHostRequests.set(id, { resolve, reject, timer });
    send({ jsonrpc: '2.0', protocolVersion: PROTOCOL_VERSION, id, method, params });
  });
}

function toPlain(value) {
  if (value === undefined) return null;
  if (value === null || typeof value !== 'object') {
    try { JSON.stringify(value); return value; } catch { return String(value); }
  }
  try {
    return JSON.parse(JSON.stringify(value));
  } catch {
    return String(value);
  }
}

function unsupported(api) {
  return new Error(`SwiftCode does not support ${api} (see Docs/Extensions-v2.md API matrix).`);
}

// ---- Host state --------------------------------------------------------
const state = {
  messages: [],
  outputLines: [],
  statusBar: null,
  completionLanguages: new Set(),
  hoverLanguages: new Set(),
  treeProviders: new Map(), // viewId -> provider
  commands: new Map(), // commandId -> handler
  diagnostics: new Map(), // uri -> diagnostics
};

let extensionExports = null;
let activated = false;

// ---- The vscode shim ---------------------------------------------------
class Position {
  constructor(line, character) { this.line = line; this.character = character; }
}
class Range {
  constructor(start, end) {
    if (start instanceof Position) { this.start = start; this.end = end; }
    else { this.start = new Position(start, arguments[1]); this.end = new Position(arguments[2], arguments[3]); }
  }
}
class Selection extends Range {
  constructor(anchor, active) { super(anchor, active); this.anchor = anchor; this.active = active; }
}
class Uri {
  constructor(scheme, p) { this.scheme = scheme; this.path = p; this.fsPath = p; }
  static file(p) { return new Uri('file', p); }
  static parse(value) {
    const match = /^([a-zA-Z][a-zA-Z0-9+.-]*):(.*)$/.exec(value);
    return match ? new Uri(match[1], match[2]) : new Uri('file', value);
  }
  toString() { return `${this.scheme}:${this.path}`; }
}
class Diagnostic {
  constructor(range, message, severity) { this.range = range; this.message = message; this.severity = severity; }
}
const DiagnosticSeverity = { Error: 0, Warning: 1, Information: 2, Hint: 3 };
class TreeItem {
  constructor(label, collapsibleState) { this.label = label; this.collapsibleState = collapsibleState; }
}
class EventEmitter {
  constructor() { this._listeners = []; this.event = (listener) => { this._listeners.push(listener); return new Disposable(() => {}); }; }
  fire(data) { for (const l of this._listeners) { try { l(data); } catch {} } }
  dispose() { this._listeners = []; }
}
class Disposable {
  constructor(dispose) { this._dispose = dispose; }
  dispose() { if (this._dispose) { this._dispose(); this._dispose = null; } }
  static from(...disposables) { return new Disposable(() => { for (const d of disposables) d.dispose(); }); }
}

function recordMessage(kind, message) {
  state.messages.push({ kind, message });
  return undefined;
}

const vscode = {
  version: '1.85.0',
  Position, Range, Selection, Uri, Diagnostic, DiagnosticSeverity, TreeItem, EventEmitter, Disposable,
  commands: {
    registerCommand(id, handler) {
      state.commands.set(id, handler);
      return new Disposable(() => { state.commands.delete(id); });
    },
    async executeCommand(id, ...args) {
      const handler = state.commands.get(id);
      if (!handler) throw new Error(`Command not registered in this host: ${id}`);
      return toPlain(await handler(...args));
    },
    getCommands() { return Promise.resolve([...state.commands.keys()]); },
  },
  window: {
    showInformationMessage: (m) => { recordMessage('information', m); return Promise.resolve(undefined); },
    showWarningMessage: (m) => { recordMessage('warning', m); return Promise.resolve(undefined); },
    showErrorMessage: (m) => { recordMessage('error', m); return Promise.resolve(undefined); },
    createOutputChannel(name) {
      return {
        name,
        appendLine: (line) => { state.outputLines.push(line); },
        append: (value) => { state.outputLines.push(value); },
        show: () => {}, hide: () => {}, clear: () => {}, dispose: () => {},
      };
    },
    createStatusBarItem() {
      const item = { text: '', tooltip: undefined, command: undefined, show() {}, hide() {}, dispose() {} };
      Object.defineProperty(item, 'text', {
        get() { return state.statusBar; },
        set(value) { state.statusBar = value; },
      });
      return item;
    },
    showQuickPick: () => Promise.resolve(undefined),
    showInputBox: () => Promise.resolve(undefined),
    withProgress: () => Promise.reject(unsupported('window.withProgress')),
  },
  workspace: {
    getConfiguration() {
      return {
        get: (_key, fallback) => fallback,
        has: () => false,
        inspect: () => undefined,
      };
    },
    async openTextDocument(filePath) {
      const p = typeof filePath === 'string' ? filePath : filePath.fsPath;
      const content = await sendRequestToSwift('host.readFile', { path: p });
      return { uri: Uri.file(p), fileName: p, getText: () => (typeof content === 'string' ? content : '') };
    },
    // D-9: the Swift handler requires {path, edits: [...]}.
    async applyEdit(edit) {
      const params = { path: edit.path, edits: edit.edits || [] };
      return sendRequestToSwift('host.applyEdit', params);
    },
    fs: {
      readFile: (uri) => sendRequestToSwift('host.readFile', { path: uri.fsPath || uri.path }),
      writeFile: (uri, content) => sendRequestToSwift('host.writeFile', {
        path: uri.fsPath || uri.path,
        content: Buffer.isBuffer(content) ? content.toString('utf8') : String(content),
      }),
    },
    onDidChangeTextDocument: () => new Disposable(() => {}),
  },
  languages: {
    registerCompletionItemProvider(language, _provider) {
      state.completionLanguages.add(typeof language === 'string' ? language : language.language);
      return new Disposable(() => {});
    },
    registerHoverProvider(language, _provider) {
      state.hoverLanguages.add(typeof language === 'string' ? language : language.language);
      return new Disposable(() => {});
    },
    registerDefinitionProvider: () => new Disposable(() => {}),
    registerReferenceProvider: () => new Disposable(() => {}),
    registerRenameProvider: () => new Disposable(() => {}),
    registerDocumentFormattingEditProvider: () => new Disposable(() => {}),
    registerCodeActionProvider: () => new Disposable(() => {}),
    createDiagnosticCollection(name) {
      return {
        name,
        set(uri, diagnostics) {
          const uriString = typeof uri === 'string' ? uri : uri.toString();
          state.diagnostics.set(uriString, diagnostics || []);
          sendRequestToSwift('host.publishDiagnostics', {
            path: uriString, diagnostics: toPlain(diagnostics || []),
          }).catch(() => {});
        },
        delete(uri) {
          const uriString = typeof uri === 'string' ? uri : uri.toString();
          state.diagnostics.delete(uriString);
        },
        clear() { state.diagnostics.clear(); },
        dispose() {},
      };
    },
  },
  extensions: {
    getExtension(id) {
      if (!activated) return undefined;
      return { id, exports: extensionExports, isActive: true };
    },
  },
  debug: { get activeDebugSession() { throw unsupported('vscode.debug'); } },
  notebooks: { get activeNotebookEditor() { throw unsupported('vscode.notebooks'); } },
  authentication: { getSession: () => { throw unsupported('vscode.authentication'); } },
};

// Intercept only require('vscode').
const Module = require('module');
const originalResolveFilename = Module._resolveFilename;
Module._resolveFilename = function (request, ...args) {
  if (request === 'vscode') return request;
  return originalResolveFilename.call(this, request, ...args);
};
const originalLoad = Module._load;
Module._load = function (request, ...args) {
  if (request === 'vscode') return vscode;
  return originalLoad.call(this, request, ...args);
};

// ---- Contribution collection ------------------------------------------
async function collectContribution() {
  const treeItems = [];
  for (const [viewId, provider] of state.treeProviders) {
    try {
      const children = (await provider.getChildren()) || [];
      for (const child of children) {
        const label = typeof child.label === 'string' ? child.label : String(child.label || '');
        treeItems.push({
          id: `${viewId}:${label}`,
          label,
          description: child.description || null,
          command: child.command ? child.command.command || null : null,
        });
      }
    } catch (error) {
      state.outputLines.push(`Tree provider '${viewId}' failed: ${error.message}`);
    }
  }
  return {
    commands: [...state.commands.keys()].map((id) => ({ command: id, title: id })),
    views: [...state.treeProviders.keys()].map((id) => ({ id, name: id })),
    treeItems,
    statusBarText: state.statusBar,
    outputLines: state.outputLines,
    messages: state.messages,
    completionLanguages: [...state.completionLanguages],
    hoverLanguages: [...state.hoverLanguages],
  };
}

// ---- Requests from Swift -------------------------------------------------
async function handleSwiftRequest(message) {
  const { id, method, params } = message;
  try {
    switch (method) {
      case 'activate': {
        if (activated) return { result: toPlain(await collectContribution()) };
        const mod = require(entryPath);
        extensionExports = mod;
        if (mod && typeof mod.activate === 'function') {
          await mod.activate({
            subscriptions: [],
            extensionPath: path.dirname(entryPath),
          });
        }
        activated = true;
        return { result: toPlain(await collectContribution()) };
      }
      case 'executeCommand': {
        const handler = state.commands.get(params.command);
        if (!handler) throw new Error(`Command not registered in this host: ${params.command}`);
        const result = await handler(...(params.args || []));
        return { result: toPlain(result) };
      }
      case 'shutdown': {
        try {
          if (extensionExports && typeof extensionExports.deactivate === 'function') {
            await extensionExports.deactivate();
          }
        } catch {}
        return { result: { ok: true } };
      }
      case 'deactivate': {
        try {
          if (extensionExports && typeof extensionExports.deactivate === 'function') {
            await extensionExports.deactivate();
          }
        } catch {}
        return { result: { ok: true } };
      }
      case 'didChangeTextDocument':
      case 'didChangeConfiguration':
        // Reserved methods (spec §4.3): accepted, no sender yet.
        return { result: null };
      default:
        throw new Error(`Unknown method: ${method}`);
    }
  } catch (error) {
    return { error: { code: -32000, message: error.message || String(error) } };
  }
}

process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  inputBuffer += chunk;
  let newline;
  while ((newline = inputBuffer.indexOf('\n')) !== -1) {
    const line = inputBuffer.slice(0, newline);
    inputBuffer = inputBuffer.slice(newline + 1);
    if (!line.trim()) continue;
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      continue; // A line that is neither a response nor a parseable request is ignored.
    }
    if (message.id !== undefined && (message.result !== undefined || message.error !== undefined)) {
      // Response to one of our host-initiated requests.
      const pending = pendingHostRequests.get(message.id);
      if (!pending) continue;
      pendingHostRequests.delete(message.id);
      clearTimeout(pending.timer);
      if (message.error) pending.reject(new Error(message.error.message || 'Host request failed'));
      else pending.resolve(message.result);
    } else if (message.method) {
      handleSwiftRequest(message).then((outcome) => {
        send({ jsonrpc: '2.0', protocolVersion: PROTOCOL_VERSION, id: message.id, ...outcome });
      });
    }
    // Anything else is ignored.
  }
});

process.on('uncaughtException', (error) => {
  try {
    send({ jsonrpc: '2.0', protocolVersion: PROTOCOL_VERSION, id: 'fatal',
           error: { code: -32001, message: `Host crashed: ${error.message}` } });
  } catch {}
  process.exit(1);
});
