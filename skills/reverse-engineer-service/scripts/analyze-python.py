#!/usr/bin/env python3
"""Deterministically extract Python structure without importing target code."""

from __future__ import annotations

import argparse
import ast
import configparser
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

SCHEMA_VERSION = "1.0.0"
SKIP_DIRS = {".git", ".hg", ".mypy_cache", ".pytest_cache", ".tox", ".venv", "venv", "__pycache__", "node_modules", "dist", "build"}
REGISTER_NAMES = {"get", "post", "put", "patch", "delete", "route", "websocket", "task", "command", "callback"}


class UsageError(Exception):
    pass


def rel(root: Path, path: Path) -> str:
    return path.resolve().relative_to(root).as_posix()


def run_git(root: Path, *args: str) -> str | None:
    try:
        result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, timeout=5, check=False)
        return result.stdout.strip() if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def python_files(root: Path) -> list[Path]:
    result: list[Path] = []
    for current, directories, files in os.walk(root):
        directories[:] = sorted(d for d in directories if d not in SKIP_DIRS and not d.startswith("."))
        for name in sorted(files):
            if name.endswith(".py"):
                result.append(Path(current, name))
    return result


def module_name(root: Path, path: Path) -> str:
    relative = path.resolve().relative_to(root)
    parts = list(relative.with_suffix("").parts)
    if parts and parts[0] == "src":
        parts.pop(0)
    if parts and parts[-1] == "__init__":
        parts.pop()
    return ".".join(parts)


def dotted(node: ast.AST) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = dotted(node.value)
        return f"{prefix}.{node.attr}" if prefix else node.attr
    return None


def symbol_id(path: str, name: str) -> str:
    return f"symbol:{path}#{name}"


def module_id(path: str) -> str:
    return f"module:{path}"


def edge(source: str, target: str, kind: str, resolution: str, line: int | None = None) -> dict:
    return {"from": source, "to": target, "type": kind, "resolution": resolution, "line": line}


class FileVisitor(ast.NodeVisitor):
    def __init__(self, root: Path, path: Path, tree: ast.AST, module_index: dict[str, str]):
        self.root = root
        self.path = rel(root, path)
        self.tree = tree
        self.module_index = module_index
        self.symbols: list[dict] = []
        self.edges: list[dict] = []
        self.entrypoints: list[dict] = []
        self.aliases: dict[str, str] = {}
        self.scope: list[str] = []
        self.defined: dict[str, str] = {}

    @property
    def owner(self) -> str:
        return symbol_id(self.path, ".".join(self.scope)) if self.scope else module_id(self.path)

    def add_symbol(self, node: ast.AST, name: str, kind: str) -> None:
        qualified = ".".join([*self.scope, name])
        decorators = getattr(node, "decorator_list", [])
        start_line = min([int(getattr(node, "lineno", 1)), *[int(getattr(item, "lineno", getattr(node, "lineno", 1))) for item in decorators]])
        item = {
            "id": symbol_id(self.path, qualified), "path": self.path, "name": qualified, "kind": kind,
            "start_line": start_line, "end_line": int(getattr(node, "end_lineno", getattr(node, "lineno", 1))),
        }
        self.symbols.append(item)
        if not self.scope:
            self.defined[name] = item["id"]
        self.edges.append(edge(self.owner, item["id"], "contains", "resolved", item["start_line"]))

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self._visit_function(node, "function")

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self._visit_function(node, "async_function")

    def _visit_function(self, node: ast.FunctionDef | ast.AsyncFunctionDef, kind: str) -> None:
        parent = self.owner
        self.add_symbol(node, node.name, kind)
        qualified = ".".join([*self.scope, node.name])
        current = symbol_id(self.path, qualified)
        for decorator in node.decorator_list:
            name = dotted(decorator.func if isinstance(decorator, ast.Call) else decorator)
            tail = name.rsplit(".", 1)[-1] if name else ""
            if tail in REGISTER_NAMES:
                self.entrypoints.append({
                    "id": f"entry:{self.path}#{qualified}", "path": self.path, "symbol": qualified,
                    "kind": "worker" if tail == "task" else "cli" if tail in {"command", "callback"} else "http",
                    "evidence": f"decorator:{name}", "resolution": "candidate",
                })
                self.edges.append(edge(parent, current, "registers", "candidate", getattr(decorator, "lineno", node.lineno)))
        self.scope.append(node.name)
        for child in node.body:
            self.visit(child)
        self.scope.pop()

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        self.add_symbol(node, node.name, "class")
        self.scope.append(node.name)
        for child in node.body:
            self.visit(child)
        self.scope.pop()

    def visit_Import(self, node: ast.Import) -> None:
        for item in node.names:
            local = item.asname or item.name.split(".")[0]
            target_path = self.module_index.get(item.name)
            target = module_id(target_path) if target_path else f"external:{item.name}"
            resolution = "resolved" if target_path else "external"
            self.aliases[local] = target
            self.edges.append(edge(self.owner, target, "imports", resolution, node.lineno))

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
        current_module = module_name(self.root, self.root / self.path)
        base_parts: list[str] = []
        if node.level:
            base_parts = current_module.split(".")[:-1]
            base_parts = base_parts[: max(0, len(base_parts) - node.level + 1)]
        if node.module:
            base_parts.extend(node.module.split("."))
        base = ".".join(base_parts)
        for item in node.names:
            full = f"{base}.{item.name}" if base else item.name
            target_path = self.module_index.get(full) or self.module_index.get(base)
            target = symbol_id(target_path, item.name) if target_path else f"external:{full}"
            resolution = "resolved" if target_path else "external"
            self.aliases[item.asname or item.name] = target
            self.edges.append(edge(self.owner, target, "imports", resolution, node.lineno))

    def visit_Call(self, node: ast.Call) -> None:
        name = dotted(node.func)
        if name:
            first = name.split(".", 1)[0]
            if name in self.defined:
                target, resolution = self.defined[name], "resolved"
            elif first in self.aliases:
                base = self.aliases[first]
                suffix = name[len(first):]
                target = base + suffix
                resolution = "resolved" if base.startswith(("module:", "symbol:")) and "." not in suffix.lstrip(".") else "candidate"
            elif "." in name:
                target, resolution = f"call:{name}", "syntactic"
            else:
                target, resolution = f"call:{name}", "candidate"
            self.edges.append(edge(self.owner, target, "calls", resolution, node.lineno))
            if name.rsplit(".", 1)[-1] in REGISTER_NAMES and node.args:
                handler = dotted(node.args[-1])
                target_handler = self.defined.get(handler or "", f"call:{handler or 'dynamic-handler'}")
                self.edges.append(edge(self.owner, target_handler, "registers", "candidate", node.lineno))
        else:
            self.edges.append(edge(self.owner, "call:<dynamic>", "calls", "dynamic", node.lineno))
        self.generic_visit(node)


def declarative_entrypoints(root: Path, module_index: dict[str, str]) -> list[dict]:
    entries: list[dict] = []
    pyproject = root / "pyproject.toml"
    if pyproject.is_file():
        try:
            import tomllib
            data = tomllib.loads(pyproject.read_text(encoding="utf-8"))
            groups = [data.get("project", {}).get("scripts", {}), data.get("project", {}).get("gui-scripts", {})]
            for group in groups:
                for name, value in sorted(group.items()):
                    module, _, symbol = str(value).partition(":")
                    target_path = module_index.get(module, module.replace(".", "/") + ".py")
                    entries.append({"id": f"entry:{target_path}#{symbol or name}", "path": target_path, "symbol": symbol or None, "kind": "cli", "evidence": f"pyproject-script:{name}", "resolution": "resolved" if module in module_index else "candidate"})
        except (OSError, ValueError):
            pass
    setup_cfg = root / "setup.cfg"
    if setup_cfg.is_file():
        parser = configparser.ConfigParser()
        try:
            parser.read(setup_cfg, encoding="utf-8")
            for section in ("options.entry_points",):
                if parser.has_section(section):
                    for key, value in parser.items(section):
                        entries.append({"id": f"entry:setup.cfg#{key}", "path": "setup.cfg", "symbol": None, "kind": "cli", "evidence": f"setup.cfg:{key}", "resolution": "candidate"})
        except configparser.Error:
            pass
    setup_py = root / "setup.py"
    if setup_py.is_file():
        try:
            tree = ast.parse(setup_py.read_text(encoding="utf-8-sig"), filename="setup.py")
            for node in ast.walk(tree):
                if not isinstance(node, ast.Call) or dotted(node.func) not in {"setup", "setuptools.setup"}:
                    continue
                if any(keyword.arg == "entry_points" for keyword in node.keywords):
                    entries.append({"id": "entry:setup.py#entry-points", "path": "setup.py", "symbol": None, "kind": "cli", "evidence": "setup.py:entry_points", "resolution": "syntactic"})
        except (OSError, SyntaxError, UnicodeDecodeError):
            pass
    for module, path in module_index.items():
        if path.endswith("/__main__.py") or path == "__main__.py":
            entries.append({"id": f"entry:{path}", "path": path, "symbol": None, "kind": "cli", "evidence": "__main__.py", "resolution": "resolved"})
    return entries


def sort_unique(items: list[dict], keys: tuple[str, ...]) -> list[dict]:
    seen: set[str] = set()
    result: list[dict] = []
    for item in sorted(items, key=lambda value: tuple(str(value.get(k, "")) for k in keys)):
        marker = json.dumps(item, sort_keys=True, ensure_ascii=False)
        if marker not in seen:
            seen.add(marker)
            result.append(item)
    return result


def parse_entry(value: str, root: Path, symbols: list[dict]) -> str:
    if "#" in value:
        raw_path, name = value.rsplit("#", 1)
        path = rel(root, (root / raw_path).resolve())
        wanted = symbol_id(path, name)
        if any(item["id"] == wanted for item in symbols):
            return wanted
        raise UsageError(f"entry symbol을 찾을 수 없습니다: {value}")
    raw_path, line = value, None
    if ":" in value and value.rsplit(":", 1)[1].isdigit():
        raw_path, raw_line = value.rsplit(":", 1)
        line = int(raw_line)
    path = rel(root, (root / raw_path).resolve())
    candidates = [item for item in symbols if item["path"] == path and (line is None or item["start_line"] <= line <= item["end_line"])]
    if line is not None and candidates:
        candidates.sort(key=lambda item: (item["end_line"] - item["start_line"], item["name"]))
        return candidates[0]["id"]
    if (root / path).is_file():
        return module_id(path)
    raise UsageError(f"entry 파일을 찾을 수 없습니다: {value}")


def bounded_trace(start: str, edges: list[dict], symbols: list[dict], max_depth: int, max_nodes: int) -> tuple[set[str], list[dict], bool]:
    outgoing: dict[str, list[dict]] = {}
    for item in edges:
        if item["type"] in {"calls", "imports", "registers", "contains"}:
            outgoing.setdefault(item["from"], []).append(item)
    visited = {start}
    selected: list[dict] = []
    frontier = [(start, 0)]
    truncated = False
    while frontier:
        current, depth = frontier.pop(0)
        candidates = sorted(outgoing.get(current, []), key=lambda item: (item["type"], item["to"], item.get("line") or 0))
        if depth >= max_depth:
            truncated = truncated or bool(candidates)
            continue
        for item in candidates:
            selected.append(item)
            target = item["to"]
            if target not in visited:
                if len(visited) >= max_nodes:
                    truncated = True
                    continue
                visited.add(target)
                frontier.append((target, depth + 1))
    return visited, selected, truncated


def analyze(args: argparse.Namespace) -> dict:
    root = Path(args.root).resolve()
    if not root.is_dir():
        raise UsageError(f"root 디렉터리를 찾을 수 없습니다: {root}")
    files = python_files(root)
    module_index = {module_name(root, path): rel(root, path) for path in files}
    modules = [{"id": module_id(rel(root, path)), "path": rel(root, path), "language": "python"} for path in files]
    symbols: list[dict] = []
    edges: list[dict] = []
    entrypoints = declarative_entrypoints(root, module_index)
    diagnostics: list[dict] = []
    contents: list[tuple[str, bytes]] = []
    for path in files:
        relative = rel(root, path)
        raw = path.read_bytes()
        contents.append((relative, raw))
        try:
            tree = ast.parse(raw.decode("utf-8-sig"), filename=relative)
        except (SyntaxError, UnicodeDecodeError) as error:
            diagnostics.append({"level": "error", "code": "python-parse-error", "message": f"{relative}:{getattr(error, 'lineno', 1) or 1}"})
            continue
        visitor = FileVisitor(root, path, tree, module_index)
        visitor.visit(tree)
        symbols.extend(visitor.symbols)
        edges.extend(visitor.edges)
        entrypoints.extend(visitor.entrypoints)
        for node in ast.walk(tree):
            if isinstance(node, ast.If) and isinstance(node.test, ast.Compare) and "__name__" in ast.dump(node.test) and "__main__" in ast.dump(node.test):
                entrypoints.append({"id": f"entry:{relative}:main-guard", "path": relative, "symbol": None, "kind": "cli", "evidence": "main-guard", "resolution": "resolved"})
                break
    digest = hashlib.sha256()
    for relative, raw in sorted(contents):
        digest.update(relative.encode()); digest.update(b"\0"); digest.update(raw); digest.update(b"\0")
    capabilities = ["python-ast", "module-graph", "symbol-index", "call-candidates", "entrypoint-discovery"]
    tools = [{"name": "python", "version": sys.version.split()[0]}, {"name": "python-ast", "version": sys.version.split()[0]}]
    try:
        import jedi  # type: ignore
        capabilities.append("jedi-available")
        tools.append({"name": "jedi", "version": getattr(jedi, "__version__", "unknown")})
    except ImportError:
        pass
    read_set: list[dict] = []
    if args.command == "trace":
        if not args.entry:
            raise UsageError("trace에는 --entry가 필요합니다.")
        start = parse_entry(args.entry, root, symbols)
        visited, edges, truncated = bounded_trace(start, edges, symbols, args.max_depth, args.max_nodes)
        symbols = [item for item in symbols if item["id"] in visited]
        module_paths = {item["path"] for item in symbols}
        if start.startswith("module:"):
            module_paths.add(start.removeprefix("module:"))
        modules = [item for item in modules if item["id"] in visited or item["path"] in module_paths]
        for item in symbols:
            read_set.append({"path": item["path"], "start_line": item["start_line"], "end_line": item["end_line"], "reason": "trace-symbol"})
        if start.startswith("module:"):
            path = root / start.removeprefix("module:")
            count = max(1, len(path.read_text(encoding="utf-8-sig").splitlines()))
            read_set.append({"path": rel(root, path), "start_line": 1, "end_line": count, "reason": "trace-entry"})
        if truncated:
            diagnostics.append({"level": "warning", "code": "trace-truncated", "message": f"--max-depth {args.max_depth} 또는 --max-nodes {args.max_nodes} 제한에 도달했습니다."})
    commit = run_git(root, "rev-parse", "HEAD")
    status = run_git(root, "status", "--porcelain")
    result = {
        "schema_version": SCHEMA_VERSION,
        "snapshot": {"git_commit": commit, "dirty": None if status is None else bool(status), "source_digest": digest.hexdigest()},
        "tools": sort_unique(tools, ("name", "version")),
        "capabilities": sorted(set(capabilities)),
        "entrypoints": sort_unique(entrypoints, ("path", "symbol", "kind", "evidence")),
        "modules": sort_unique(modules, ("path",)),
        "symbols": sort_unique(symbols, ("path", "start_line", "name")),
        "edges": sort_unique(edges, ("from", "type", "to", "line")),
        "read_set": sort_unique(read_set, ("path", "start_line", "end_line", "reason")),
        "diagnostics": sort_unique(diagnostics, ("level", "code", "message")),
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(prog="analyze-python.py")
    parser.add_argument("command", choices=("discover", "trace"))
    parser.add_argument("--root", required=True)
    parser.add_argument("--entry")
    parser.add_argument("--profile", choices=("auto", "http", "worker", "cli", "generic"), default="auto")
    parser.add_argument("--max-depth", type=int, default=4)
    parser.add_argument("--max-nodes", type=int, default=80)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if args.max_depth < 0 or args.max_nodes < 1:
        print("max-depth는 0 이상, max-nodes는 1 이상이어야 합니다.", file=sys.stderr)
        return 2
    try:
        result = analyze(args)
        output = Path(args.output).resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=False) + "\n", encoding="utf-8", newline="\n")
        print(f"python {args.command}: entrypoints={len(result['entrypoints'])} modules={len(result['modules'])} symbols={len(result['symbols'])} edges={len(result['edges'])} read_set={len(result['read_set'])}")
        for item in result["read_set"]:
            print(f"  {item['path']}:{item['start_line']}-{item['end_line']} ({item['reason']})")
        return 4 if any(item["level"] == "error" for item in result["diagnostics"]) else 0
    except UsageError as error:
        print(str(error), file=sys.stderr)
        return 2
    except (OSError, ValueError) as error:
        print(f"분석 실패: {error}", file=sys.stderr)
        return 4


if __name__ == "__main__":
    raise SystemExit(main())
