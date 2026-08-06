#!/usr/bin/env node
// Deterministically extract JavaScript/TypeScript structure without executing target modules.

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import childProcess from "node:child_process";
import { pathToFileURL } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const SCHEMA_VERSION = "1.0.0";
const REGISTER_NAMES = new Set(["get", "post", "put", "patch", "delete", "use", "route", "on", "subscribe", "consume", "command"]);

class UsageError extends Error {}
class CapabilityError extends Error {}

function parseArgs(argv) {
  const args = { command: argv[0], root: null, entry: null, profile: "auto", maxDepth: 4, maxNodes: 80, output: null, typescriptPath: null };
  if (!new Set(["discover", "trace"]).has(args.command)) throw new UsageError("첫 인자는 discover 또는 trace여야 합니다.");
  for (let index = 1; index < argv.length; index += 1) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key.startsWith("--") || value === undefined) throw new UsageError(`잘못된 인자: ${key}`);
    index += 1;
    if (key === "--root") args.root = value;
    else if (key === "--entry") args.entry = value;
    else if (key === "--profile") args.profile = value;
    else if (key === "--max-depth") args.maxDepth = Number(value);
    else if (key === "--max-nodes") args.maxNodes = Number(value);
    else if (key === "--output") args.output = value;
    else if (key === "--typescript-path") args.typescriptPath = value;
    else throw new UsageError(`지원하지 않는 인자: ${key}`);
  }
  if (!args.root || !args.output) throw new UsageError("--root와 --output이 필요합니다.");
  if (args.command === "trace" && !args.entry) throw new UsageError("trace에는 --entry가 필요합니다.");
  if (!Number.isInteger(args.maxDepth) || args.maxDepth < 0 || !Number.isInteger(args.maxNodes) || args.maxNodes < 1) throw new UsageError("max-depth는 0 이상, max-nodes는 1 이상이어야 합니다.");
  return args;
}

function posixRel(root, file) {
  const relative = path.relative(root, path.resolve(file)).split(path.sep).join("/");
  if (relative.startsWith("../") || relative === "..") throw new UsageError(`root 밖의 경로입니다: ${file}`);
  return relative;
}

function git(root, args) {
  try { return childProcess.execFileSync("git", ["-C", root, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 5000 }).trim(); }
  catch { return null; }
}

function fileDigest(files) {
  const hash = crypto.createHash("sha256");
  [...files].sort((a, b) => a.relative.localeCompare(b.relative)).forEach(({ relative, content }) => {
    hash.update(relative); hash.update("\0"); hash.update(content); hash.update("\0");
  });
  return hash.digest("hex");
}

function uniqueSorted(items, keys) {
  const seen = new Set();
  return [...items].sort((a, b) => {
    for (const key of keys) {
      const compared = String(a[key] ?? "").localeCompare(String(b[key] ?? ""));
      if (compared) return compared;
    }
    return 0;
  }).filter((item) => {
    const marker = JSON.stringify(item);
    if (seen.has(marker)) return false;
    seen.add(marker); return true;
  });
}

function moduleId(file) { return `module:${file}`; }
function symbolId(file, name) { return `symbol:${file}#${name}`; }
function makeEdge(from, to, type, resolution, line = null) { return { from, to, type, resolution, line }; }

function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, "utf8")); } catch { return null; }
}

function collectPackageJson(root) {
  const found = [];
  const visit = (directory, depth) => {
    if (depth > 5) return;
    for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      if (entry.isDirectory() && !new Set(["node_modules", ".git", "dist", "build", ".next", "coverage"]).has(entry.name) && !entry.name.startsWith(".")) visit(path.join(directory, entry.name), depth + 1);
      else if (entry.isFile() && entry.name === "package.json") found.push(path.join(directory, entry.name));
    }
  };
  visit(root, 0);
  return found;
}

function extractManifestEntries(root, manifests) {
  const entries = [];
  const candidate = (manifestFile, target, kind, evidence) => {
    if (typeof target !== "string" || target.includes("*")) return;
    const absolute = path.resolve(path.dirname(manifestFile), target);
    entries.push({ id: `entry:${posixRel(root, absolute)}`, path: posixRel(root, absolute), symbol: null, kind, evidence, resolution: fs.existsSync(absolute) ? "resolved" : "candidate" });
  };
  const exportTargets = (value) => {
    if (typeof value === "string") return [value];
    if (!value || typeof value !== "object") return [];
    return Object.keys(value).sort().flatMap((key) => exportTargets(value[key]));
  };
  manifests.forEach((file) => {
    const data = readJson(file);
    if (!data) return;
    candidate(file, data.main, "module", "package.json:main");
    candidate(file, data.module, "module", "package.json:module");
    for (const target of exportTargets(data.exports)) candidate(file, target, "module", "package.json:exports");
    if (typeof data.bin === "string") candidate(file, data.bin, "cli", "package.json:bin");
    else if (data.bin && typeof data.bin === "object") for (const name of Object.keys(data.bin).sort()) candidate(file, data.bin[name], "cli", `package.json:bin:${name}`);
  });
  return entries;
}

async function loadTypeScript(args, root) {
  const candidates = [];
  if (args.typescriptPath) candidates.push(path.resolve(args.typescriptPath));
  try {
    const resolved = require.resolve("typescript", { paths: [root] });
    const relative = path.relative(root, resolved);
    if (relative !== ".." && !relative.startsWith(`..${path.sep}`)) candidates.push(resolved);
  } catch {}
  for (const candidate of candidates) {
    try { return { ts: await import(pathToFileURL(candidate).href), source: candidate }; } catch {}
  }
  return null;
}

function executableVersion(name) {
  try { return childProcess.execFileSync(name, ["--version"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 3000 }).trim().split(/\r?\n/)[0]; }
  catch { return null; }
}

function locateOptional(root) {
  const capabilities = [];
  const tools = [];
  let dependencyCruiser = null;
  const packageFile = path.join(root, "node_modules", "dependency-cruiser", "package.json");
  const packageData = readJson(packageFile);
  if (packageData) {
    const binValue = typeof packageData.bin === "string" ? packageData.bin : packageData.bin?.depcruise ?? packageData.bin?.[Object.keys(packageData.bin ?? {})[0]];
    if (binValue) {
      dependencyCruiser = { bin: path.resolve(path.dirname(packageFile), binValue), version: packageData.version ?? "unknown" };
      capabilities.push("dependency-cruiser-module-graph"); tools.push({ name: "dependency-cruiser", version: dependencyCruiser.version });
    }
  }
  const astGrep = executableVersion("ast-grep") ?? executableVersion("sg");
  if (astGrep) { capabilities.push("ast-grep-available"); tools.push({ name: "ast-grep", version: astGrep }); }
  return { capabilities, tools, dependencyCruiser };
}

function analyzeWithDependencyCruiser(root, executable) {
  let raw;
  try {
    raw = childProcess.execFileSync(process.execPath, [executable, "--output-type", "json", "--no-config", "--no-progress", "--no-cache", "."], {
      cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], timeout: 120000, maxBuffer: 64 * 1024 * 1024,
    });
  } catch (error) {
    throw new CapabilityError(`dependency-cruiser 실행에 실패했습니다: exit=${error.status ?? "unknown"}`);
  }
  let cruise;
  try { cruise = JSON.parse(raw); } catch { throw new CapabilityError("dependency-cruiser JSON을 해석하지 못했습니다."); }
  const modules = [], edges = [], contents = [];
  for (const item of cruise.modules ?? []) {
    const absolute = path.resolve(root, item.source);
    const rawRelative = path.relative(root, absolute);
    if (rawRelative === ".." || rawRelative.startsWith(`..${path.sep}`) || rawRelative.split(path.sep).includes("node_modules")) continue;
    const relative = posixRel(root, absolute);
    if (!/\.[cm]?[jt]sx?$/.test(relative) || !fs.statSync(absolute, { throwIfNoEntry: false })?.isFile()) continue;
    modules.push({ id: moduleId(relative), path: relative, language: /\.tsx?$/.test(relative) ? "typescript" : "javascript" });
    contents.push({ relative, content: fs.readFileSync(absolute) });
    for (const dependency of item.dependencies ?? []) {
      let target, resolution;
      const resolved = dependency.resolved ? path.resolve(root, dependency.resolved) : null;
      const relativeTarget = resolved ? path.relative(root, resolved) : "..";
      if (resolved && relativeTarget !== ".." && !relativeTarget.startsWith(`..${path.sep}`) && !relativeTarget.split(path.sep).includes("node_modules") && fs.existsSync(resolved)) {
        target = moduleId(posixRel(root, resolved)); resolution = "resolved";
      } else {
        target = `external:${dependency.module ?? "<unresolved>"}`;
        resolution = dependency.couldNotResolve ? "candidate" : "external";
      }
      edges.push(makeEdge(moduleId(relative), target, "imports", resolution, null));
    }
  }
  return { modules, edges, contents };
}

function createProgram(ts, root) {
  const configName = ts.findConfigFile(root, ts.sys.fileExists, "tsconfig.json");
  if (configName) {
    const configFile = ts.readConfigFile(configName, ts.sys.readFile);
    if (configFile.error) throw new Error("tsconfig를 읽지 못했습니다.");
    const parsed = ts.parseJsonConfigFileContent(configFile.config, ts.sys, path.dirname(configName), { noEmit: true, allowJs: true }, configName);
    if (parsed.errors.length) throw new Error("tsconfig를 해석하지 못했습니다.");
    return ts.createProgram({ rootNames: parsed.fileNames, options: parsed.options, projectReferences: parsed.projectReferences });
  }
  const files = [];
  const visit = (directory) => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      if (entry.isDirectory() && !new Set(["node_modules", ".git", "dist", "build", ".next", "coverage"]).has(entry.name) && !entry.name.startsWith(".")) visit(path.join(directory, entry.name));
      else if (entry.isFile() && /\.[cm]?[jt]sx?$/.test(entry.name) && !entry.name.endsWith(".d.ts")) files.push(path.join(directory, entry.name));
    }
  };
  visit(root);
  return ts.createProgram(files, { allowJs: true, checkJs: false, noEmit: true, moduleResolution: ts.ModuleResolutionKind.Node10, target: ts.ScriptTarget.ES2020 });
}

function nameOf(ts, node, source) {
  if (!node) return null;
  if (ts.isIdentifier(node) || ts.isPrivateIdentifier(node)) return node.text;
  if (ts.isStringLiteral(node) || ts.isNumericLiteral(node)) return node.text;
  try { return node.getText(source).replace(/\s+/g, " ").slice(0, 120); } catch { return null; }
}

function analyzeProgram(ts, program, root) {
  const checker = program.getTypeChecker();
  const modules = [], symbols = [], edges = [], entrypoints = [], contents = [], declarationIds = new Map();
  const sources = program.getSourceFiles().filter((source) => !source.isDeclarationFile && !source.fileName.includes(`${path.sep}node_modules${path.sep}`) && !posixRel(root, source.fileName).startsWith("../"));
  const line = (source, position) => source.getLineAndCharacterOfPosition(position).line + 1;
  const symbolForDeclaration = (source, node, qualified, kind) => {
    const file = posixRel(root, source.fileName);
    const item = { id: symbolId(file, qualified), path: file, name: qualified, kind, start_line: line(source, node.getStart(source)), end_line: line(source, node.getEnd()) };
    symbols.push(item);
    const semantic = node.name ? checker.getSymbolAtLocation(node.name) : null;
    if (semantic) declarationIds.set(semantic, item.id);
    return item;
  };
  for (const source of sources.sort((a, b) => a.fileName.localeCompare(b.fileName))) {
    const file = posixRel(root, source.fileName);
    modules.push({ id: moduleId(file), path: file, language: /\.tsx?$/.test(file) ? "typescript" : "javascript" });
    contents.push({ relative: file, content: fs.readFileSync(source.fileName) });
    const scopes = [];
    const visit = (node) => {
      let pushed = false;
      const nodeName = nameOf(ts, node.name, source);
      let kind = null;
      if (ts.isFunctionDeclaration(node) || ts.isFunctionExpression(node) || ts.isArrowFunction(node)) kind = "function";
      else if (ts.isClassDeclaration(node)) kind = "class";
      else if (ts.isMethodDeclaration(node)) kind = "method";
      else if (ts.isInterfaceDeclaration(node)) kind = "interface";
      else if (ts.isTypeAliasDeclaration(node)) kind = "type";
      else if (ts.isVariableDeclaration(node) && node.initializer && (ts.isArrowFunction(node.initializer) || ts.isFunctionExpression(node.initializer))) kind = "function";
      if (kind && nodeName) {
        const qualified = [...scopes, nodeName].join(".");
        const item = symbolForDeclaration(source, node, qualified, kind);
        edges.push(makeEdge(scopes.length ? symbolId(file, scopes.join(".")) : moduleId(file), item.id, "contains", "resolved", item.start_line));
        scopes.push(nodeName); pushed = true;
      }
      const owner = scopes.length ? symbolId(file, scopes.join(".")) : moduleId(file);
      if (ts.isImportDeclaration(node) && ts.isStringLiteral(node.moduleSpecifier)) {
        const semantic = checker.getSymbolAtLocation(node.moduleSpecifier);
        const declaration = semantic?.declarations?.[0];
        const target = declaration && !declaration.getSourceFile().isDeclarationFile ? moduleId(posixRel(root, declaration.getSourceFile().fileName)) : `external:${node.moduleSpecifier.text}`;
        edges.push(makeEdge(owner, target, "imports", target.startsWith("module:") ? "resolved" : "external", line(source, node.getStart(source))));
      }
      if (ts.isExportDeclaration(node)) {
        let target = "external:<re-export>";
        let resolution = "external";
        if (node.moduleSpecifier && ts.isStringLiteral(node.moduleSpecifier)) {
          const semantic = checker.getSymbolAtLocation(node.moduleSpecifier);
          const declaration = semantic?.declarations?.[0];
          if (declaration && !declaration.getSourceFile().isDeclarationFile) { target = moduleId(posixRel(root, declaration.getSourceFile().fileName)); resolution = "resolved"; }
          else target = `external:${node.moduleSpecifier.text}`;
        }
        edges.push(makeEdge(owner, target, "exports", resolution, line(source, node.getStart(source))));
      }
      if (ts.isCallExpression(node)) {
        const expressionName = nameOf(ts, node.expression, source) ?? "<dynamic>";
        const signature = checker.getResolvedSignature(node);
        const declaration = signature?.declaration;
        let target = null, resolution = "candidate";
        if (declaration) {
          let semantic = declaration.name ? checker.getSymbolAtLocation(declaration.name) : null;
          if (semantic?.flags & ts.SymbolFlags.Alias) semantic = checker.getAliasedSymbol(semantic);
          target = semantic ? declarationIds.get(semantic) : null;
          if (!target && !declaration.getSourceFile().isDeclarationFile) {
            const targetFile = posixRel(root, declaration.getSourceFile().fileName);
            const targetName = nameOf(ts, declaration.name, declaration.getSourceFile());
            if (targetName) target = symbolId(targetFile, targetName);
          }
          resolution = target ? "resolved" : declaration.getSourceFile().isDeclarationFile ? "external" : "candidate";
        }
        if (!target) target = expressionName === "import" ? "call:<dynamic-import>" : `call:${expressionName}`;
        if (expressionName === "import" || node.expression.kind === ts.SyntaxKind.ElementAccessExpression) resolution = "dynamic";
        edges.push(makeEdge(owner, target, "calls", resolution, line(source, node.getStart(source))));
        const tail = expressionName.split(".").at(-1);
        if (REGISTER_NAMES.has(tail)) {
          const handler = node.arguments.at(-1);
          let handlerTarget = handler ? `call:${nameOf(ts, handler, source) ?? "<dynamic-handler>"}` : "call:<dynamic-handler>";
          if (handler) {
            let semantic = checker.getSymbolAtLocation(handler);
            if (semantic?.flags & ts.SymbolFlags.Alias) semantic = checker.getAliasedSymbol(semantic);
            if (semantic && declarationIds.has(semantic)) handlerTarget = declarationIds.get(semantic);
          }
          edges.push(makeEdge(owner, handlerTarget, "registers", handlerTarget.startsWith("symbol:") ? "resolved" : "candidate", line(source, node.getStart(source))));
          entrypoints.push({ id: `entry:${file}:${line(source, node.getStart(source))}`, path: file, symbol: scopes.join(".") || null, kind: new Set(["on", "subscribe", "consume"]).has(tail) ? "worker" : tail === "command" ? "cli" : "http", evidence: `registration:${tail}`, resolution: "candidate" });
        }
      }
      ts.forEachChild(node, visit);
      if (pushed) scopes.pop();
    };
    visit(source);
  }
  return { modules, symbols, edges, entrypoints, contents };
}

function parseEntry(value, root, symbols, modules) {
  let rawPath = value, symbol = null, wantedLine = null;
  if (value.includes("#")) [rawPath, symbol] = value.split(/#(?=[^#]*$)/);
  else {
    const match = value.match(/^(.*):(\d+)$/);
    if (match) { rawPath = match[1]; wantedLine = Number(match[2]); }
  }
  const file = posixRel(root, path.resolve(root, rawPath));
  if (symbol) {
    const wanted = symbolId(file, symbol);
    if (symbols.some((item) => item.id === wanted)) return wanted;
    throw new UsageError(`entry symbol을 찾을 수 없습니다: ${value}`);
  }
  if (wantedLine !== null) {
    const candidates = symbols.filter((item) => item.path === file && item.start_line <= wantedLine && wantedLine <= item.end_line).sort((a, b) => (a.end_line - a.start_line) - (b.end_line - b.start_line));
    if (candidates.length) return candidates[0].id;
  }
  if (modules.some((item) => item.path === file)) return moduleId(file);
  throw new UsageError(`entry 파일을 찾을 수 없습니다: ${value}`);
}

function traceGraph(start, allEdges, maxDepth, maxNodes) {
  const outgoing = new Map();
  allEdges.filter((item) => new Set(["calls", "imports", "registers", "contains"]).has(item.type)).forEach((item) => outgoing.set(item.from, [...(outgoing.get(item.from) ?? []), item]));
  const visited = new Set([start]), selected = [], queue = [[start, 0]];
  let truncated = false;
  while (queue.length) {
    const [current, depth] = queue.shift();
    const candidates = (outgoing.get(current) ?? []).sort((a, b) => `${a.type}:${a.to}:${a.line ?? 0}`.localeCompare(`${b.type}:${b.to}:${b.line ?? 0}`));
    if (depth >= maxDepth) { if (candidates.length) truncated = true; continue; }
    for (const item of candidates) {
      selected.push(item);
      if (!visited.has(item.to)) {
        if (visited.size >= maxNodes) { truncated = true; continue; }
        visited.add(item.to); queue.push([item.to, depth + 1]);
      }
    }
  }
  return { visited, edges: selected, truncated };
}

async function analyze(args) {
  const root = path.resolve(args.root);
  if (!fs.statSync(root, { throwIfNoEntry: false })?.isDirectory()) throw new UsageError(`root 디렉터리를 찾을 수 없습니다: ${root}`);
  const manifests = collectPackageJson(root);
  const manifestFiles = manifests.map((file) => ({ relative: posixRel(root, file), content: fs.readFileSync(file) }));
  const manifestEntries = extractManifestEntries(root, manifests);
  const optional = locateOptional(root);
  const loaded = await loadTypeScript(args, root);
  const commit = git(root, ["rev-parse", "HEAD"]), status = git(root, ["status", "--porcelain"]);
  if (!loaded) {
    if (optional.dependencyCruiser) {
      const cruised = analyzeWithDependencyCruiser(root, optional.dependencyCruiser.bin);
      let modules = cruised.modules, edges = cruised.edges, readSet = [];
      const diagnostics = [{ level: "warning", code: "module-only-trace", message: "dependency-cruiser 모듈 그래프이며 symbol/call 관계는 포함하지 않습니다." }];
      if (args.command === "trace") {
        if (args.entry.includes("#")) throw new CapabilityError("dependency-cruiser fallback은 symbol entry를 지원하지 않습니다. TypeScript Compiler API를 사용하십시오.");
        const rawPath = args.entry.replace(/:\d+$/, "");
        const start = moduleId(posixRel(root, path.resolve(root, rawPath)));
        if (!modules.some((item) => item.id === start)) throw new UsageError(`entry 파일을 찾을 수 없습니다: ${args.entry}`);
        const traced = traceGraph(start, edges, args.maxDepth, args.maxNodes);
        edges = traced.edges; modules = modules.filter((item) => traced.visited.has(item.id));
        readSet = modules.map((item) => ({ path: item.path, start_line: 1, end_line: Math.max(1, fs.readFileSync(path.join(root, item.path), "utf8").split(/\r?\n/).length), reason: "module-trace" }));
        if (traced.truncated) diagnostics.push({ level: "warning", code: "trace-truncated", message: `--max-depth ${args.maxDepth} 또는 --max-nodes ${args.maxNodes} 제한에 도달했습니다.` });
      }
      return {
        schema_version: SCHEMA_VERSION,
        snapshot: { git_commit: commit, dirty: status === null ? null : Boolean(status), source_digest: fileDigest([...manifestFiles, ...cruised.contents]) },
        tools: uniqueSorted([{ name: "node", version: process.versions.node }, ...optional.tools], ["name", "version"]),
        capabilities: [...new Set(["dependency-cruiser-module-graph", "entrypoint-discovery", ...optional.capabilities])].sort(),
        entrypoints: uniqueSorted(manifestEntries, ["path", "symbol", "kind", "evidence"]), modules: uniqueSorted(modules, ["path"]), symbols: [],
        edges: uniqueSorted(edges, ["from", "type", "to", "line"]), read_set: uniqueSorted(readSet, ["path", "start_line", "end_line", "reason"]), diagnostics,
      };
    }
    if (args.command === "trace") throw new CapabilityError("TypeScript Compiler API 또는 dependency-cruiser를 찾지 못해 trace를 수행할 수 없습니다.");
    return {
      schema_version: SCHEMA_VERSION,
      snapshot: { git_commit: commit, dirty: status === null ? null : Boolean(status), source_digest: fileDigest(manifestFiles) },
      tools: uniqueSorted([{ name: "node", version: process.versions.node }, ...optional.tools], ["name", "version"]),
      capabilities: [...new Set(["manifest-only", "entrypoint-discovery", ...optional.capabilities])].sort(),
      entrypoints: uniqueSorted(manifestEntries, ["path", "symbol", "kind", "evidence"]), modules: [], symbols: [], edges: [], read_set: [],
      diagnostics: [{ level: "warning", code: "typescript-unavailable", message: "manifest-only discover를 수행했습니다." }],
    };
  }
  const ts = loaded.ts.default ?? loaded.ts;
  const analyzed = analyzeProgram(ts, createProgram(ts, root), root);
  let { modules, symbols, edges } = analyzed;
  const diagnostics = [];
  let readSet = [];
  if (args.command === "trace") {
    const start = parseEntry(args.entry, root, symbols, modules);
    const traced = traceGraph(start, edges, args.maxDepth, args.maxNodes);
    edges = traced.edges;
    symbols = symbols.filter((item) => traced.visited.has(item.id));
    const paths = new Set(symbols.map((item) => item.path));
    if (start.startsWith("module:")) paths.add(start.slice("module:".length));
    modules = modules.filter((item) => traced.visited.has(item.id) || paths.has(item.path));
    readSet = symbols.map((item) => ({ path: item.path, start_line: item.start_line, end_line: item.end_line, reason: "trace-symbol" }));
    if (start.startsWith("module:")) {
      const file = start.slice("module:".length), lines = fs.readFileSync(path.join(root, file), "utf8").split(/\r?\n/).length;
      readSet.push({ path: file, start_line: 1, end_line: Math.max(1, lines), reason: "trace-entry" });
    }
    if (traced.truncated) diagnostics.push({ level: "warning", code: "trace-truncated", message: `--max-depth ${args.maxDepth} 또는 --max-nodes ${args.maxNodes} 제한에 도달했습니다.` });
  }
  return {
    schema_version: SCHEMA_VERSION,
    snapshot: { git_commit: commit, dirty: status === null ? null : Boolean(status), source_digest: fileDigest([...manifestFiles, ...analyzed.contents]) },
    tools: uniqueSorted([{ name: "node", version: process.versions.node }, { name: "typescript", version: ts.version }, ...optional.tools], ["name", "version"]),
    capabilities: [...new Set(["typescript-compiler-api", "module-graph", "symbol-index", "call-candidates", "entrypoint-discovery", ...optional.capabilities])].sort(),
    entrypoints: uniqueSorted([...manifestEntries, ...analyzed.entrypoints], ["path", "symbol", "kind", "evidence"]),
    modules: uniqueSorted(modules, ["path"]), symbols: uniqueSorted(symbols, ["path", "start_line", "name"]), edges: uniqueSorted(edges, ["from", "type", "to", "line"]),
    read_set: uniqueSorted(readSet, ["path", "start_line", "end_line", "reason"]), diagnostics: uniqueSorted(diagnostics, ["level", "code", "message"]),
  };
}

async function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const result = await analyze(args);
    fs.mkdirSync(path.dirname(path.resolve(args.output)), { recursive: true });
    fs.writeFileSync(path.resolve(args.output), `${JSON.stringify(result, null, 2)}\n`, "utf8");
    console.log(`js-ts ${args.command}: entrypoints=${result.entrypoints.length} modules=${result.modules.length} symbols=${result.symbols.length} edges=${result.edges.length} read_set=${result.read_set.length}`);
    result.read_set.forEach((item) => console.log(`  ${item.path}:${item.start_line}-${item.end_line} (${item.reason})`));
    process.exitCode = result.diagnostics.some((item) => item.level === "error") ? 4 : 0;
  } catch (error) {
    console.error(error.message);
    process.exitCode = error instanceof UsageError ? 2 : error instanceof CapabilityError ? 3 : 4;
  }
}

await main();
