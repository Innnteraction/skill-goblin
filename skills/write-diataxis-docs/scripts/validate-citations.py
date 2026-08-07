#!/usr/bin/env python3
"""Validate reader-facing numbered evidence citations in Markdown documents."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


KEY_PATTERN = r"cite-[a-z0-9](?:[a-z0-9-]*[a-z0-9])?"
CITATION_RE = re.compile(
    rf"\[\[(?P<number>[1-9][0-9]*)\]\]\((?P<target>[^\s)#]*)#(?P<key>{KEY_PATTERN})\)"
)
CITATION_CANDIDATE_RE = re.compile(
    r"\[\[[^\]\r\n]+\]\]\([^\)\r\n]*#cite-[^\)\s]+\)"
)
ENTRY_RE = re.compile(
    rf"^[ \t]*(?P<number>[1-9][0-9]*)\.[ \t]+"
    rf"<a[ \t]+name=[\"'](?P<key>{KEY_PATTERN})[\"'][ \t]*></a>(?:[ \t]+|$)"
)
FENCE_RE = re.compile(r"^[ \t]{0,3}(?P<fence>`{3,}|~{3,})")
WINDOWS_ABSOLUTE_RE = re.compile(r"(?<![A-Za-z0-9])[A-Za-z]:[\\/]")
UNC_RE = re.compile(r"(?<![\\])\\\\[^\\\s]+[\\]")
HOME_RE = re.compile(r"(?<![A-Za-z0-9])~[\\/]")
POSIX_LOCAL_RE = re.compile(
    r"(?<![A-Za-z0-9:])/(?:Users|home|var|srv|opt|tmp|private|mnt|Volumes)/"
)


@dataclass(frozen=True)
class Citation:
    number: int
    target: str
    key: str
    line: int


@dataclass(frozen=True)
class Entry:
    number: int
    key: str
    line: int


@dataclass
class Document:
    path: Path
    text: str
    citations: list[Citation]
    entries: list[Entry]
    invalid_citation_lines: list[int]


@dataclass(frozen=True)
class Issue:
    path: Path
    line: int
    rule: str


class InputError(Exception):
    pass


def hide_inline_code(line: str) -> str:
    chars = list(line)
    index = 0
    while index < len(chars):
        if chars[index] != "`":
            index += 1
            continue
        end_run = index
        while end_run < len(chars) and chars[end_run] == "`":
            end_run += 1
        marker = "`" * (end_run - index)
        closing = line.find(marker, end_run)
        if closing < 0:
            index = end_run
            continue
        for hidden in range(index, closing + len(marker)):
            chars[hidden] = " "
        index = closing + len(marker)
    return "".join(chars)


def visible_lines(text: str) -> list[str]:
    result: list[str] = []
    fence_character: str | None = None
    fence_length = 0
    in_comment = False

    for raw_line in text.splitlines():
        fence_match = FENCE_RE.match(raw_line)
        if fence_character is not None:
            if fence_match:
                marker = fence_match.group("fence")
                if marker[0] == fence_character and len(marker) >= fence_length:
                    fence_character = None
                    fence_length = 0
            result.append(" " * len(raw_line))
            continue
        if fence_match:
            marker = fence_match.group("fence")
            fence_character = marker[0]
            fence_length = len(marker)
            result.append(" " * len(raw_line))
            continue

        chars = list(raw_line)
        index = 0
        while index < len(raw_line):
            if in_comment:
                closing = raw_line.find("-->", index)
                if closing < 0:
                    for hidden in range(index, len(chars)):
                        chars[hidden] = " "
                    index = len(chars)
                else:
                    for hidden in range(index, closing + 3):
                        chars[hidden] = " "
                    in_comment = False
                    index = closing + 3
                continue
            opening = raw_line.find("<!--", index)
            if opening < 0:
                break
            closing = raw_line.find("-->", opening + 4)
            if closing < 0:
                for hidden in range(opening, len(chars)):
                    chars[hidden] = " "
                in_comment = True
                index = len(chars)
            else:
                for hidden in range(opening, closing + 3):
                    chars[hidden] = " "
                index = closing + 3
        result.append(hide_inline_code("".join(chars)))
    return result


def load_document(path: Path) -> Document:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise InputError(str(path)) from error

    citations: list[Citation] = []
    entries: list[Entry] = []
    invalid_citation_lines: list[int] = []
    for line_number, line in enumerate(visible_lines(text), start=1):
        valid_matches = list(CITATION_RE.finditer(line))
        valid_spans = {match.span() for match in valid_matches}
        for match in valid_matches:
            citations.append(
                Citation(
                    number=int(match.group("number")),
                    target=match.group("target"),
                    key=match.group("key"),
                    line=line_number,
                )
            )
        if any(match.span() not in valid_spans for match in CITATION_CANDIDATE_RE.finditer(line)):
            invalid_citation_lines.append(line_number)
        entry_match = ENTRY_RE.match(line)
        if entry_match:
            entries.append(
                Entry(
                    number=int(entry_match.group("number")),
                    key=entry_match.group("key"),
                    line=line_number,
                )
            )
    return Document(
        path=path,
        text=text,
        citations=citations,
        entries=entries,
        invalid_citation_lines=invalid_citation_lines,
    )


def add_entry_issues(document: Document, issues: list[Issue]) -> dict[str, Entry]:
    by_key: dict[str, Entry] = {}
    by_number: dict[int, Entry] = {}
    raw_lines = document.text.splitlines()
    for entry in document.entries:
        if entry.key in by_key:
            issues.append(Issue(document.path, entry.line, "duplicate-entry-key"))
        else:
            by_key[entry.key] = entry
        if entry.number in by_number:
            issues.append(Issue(document.path, entry.line, "duplicate-entry-number"))
        else:
            by_number[entry.number] = entry
        line = raw_lines[entry.line - 1]
        if any(pattern.search(line) for pattern in (WINDOWS_ABSOLUTE_RE, UNC_RE, HOME_RE, POSIX_LOCAL_RE)):
            issues.append(Issue(document.path, entry.line, "absolute-local-path"))
    return by_key


def expected_numbers(documents: Iterable[Document]) -> dict[str, int]:
    expected: dict[str, int] = {}
    for document in documents:
        for citation in document.citations:
            if citation.key not in expected:
                expected[citation.key] = len(expected) + 1
    return expected


def validate_citation_numbers(
    documents: Iterable[Document], expected: dict[str, int], issues: list[Issue]
) -> None:
    assigned: dict[int, str] = {}
    for document in documents:
        for citation in document.citations:
            if citation.number != expected[citation.key]:
                issues.append(Issue(document.path, citation.line, "citation-number-order"))
            previous_key = assigned.get(citation.number)
            if previous_key is not None and previous_key != citation.key:
                issues.append(Issue(document.path, citation.line, "duplicate-citation-number"))
            else:
                assigned[citation.number] = citation.key


def compare_entries(
    expected: dict[str, int], registry: Document, issues: list[Issue]
) -> None:
    entries = add_entry_issues(registry, issues)
    for key in expected:
        entry = entries.get(key)
        if entry is None:
            issues.append(Issue(registry.path, 1, "missing-entry"))
        elif entry.number != expected[key]:
            issues.append(Issue(registry.path, entry.line, "entry-number-order"))
    for key, entry in entries.items():
        if key not in expected:
            issues.append(Issue(registry.path, entry.line, "unused-entry"))


def same_path(first: Path, second: Path) -> bool:
    first_value = str(first.resolve())
    second_value = str(second.resolve())
    if sys.platform == "win32":
        return first_value.casefold() == second_value.casefold()
    return first_value == second_value


def validate_local(documents: list[Document]) -> list[Issue]:
    issues: list[Issue] = []
    for document in documents:
        for line in document.invalid_citation_lines:
            issues.append(Issue(document.path, line, "invalid-citation-syntax"))
        expected = expected_numbers([document])
        validate_citation_numbers([document], expected, issues)
        for citation in document.citations:
            if citation.target:
                issues.append(Issue(document.path, citation.line, "local-citation-target"))
        compare_entries(expected, document, issues)
    return issues


def validate_global(documents: list[Document], registry: Document) -> list[Issue]:
    issues: list[Issue] = []
    for document in documents:
        for line in document.invalid_citation_lines:
            issues.append(Issue(document.path, line, "invalid-citation-syntax"))
    expected = expected_numbers(documents)
    validate_citation_numbers(documents, expected, issues)
    for document in documents:
        for citation in document.citations:
            if not citation.target:
                issues.append(Issue(document.path, citation.line, "missing-registry-target"))
                continue
            target = document.path.parent / citation.target
            if not same_path(target, registry.path):
                issues.append(Issue(document.path, citation.line, "wrong-registry-target"))
    compare_entries(expected, registry, issues)
    return issues


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Markdown의 cite- 번호 인용과 근거 항목을 검증한다."
    )
    parser.add_argument("documents", nargs="+", type=Path, help="읽기 순서의 Markdown 문서")
    parser.add_argument("--registry", type=Path, help="전역 번호용 중앙 근거 문서")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        documents = [load_document(path) for path in args.documents]
        if args.registry is None:
            issues = validate_local(documents)
        else:
            registry = load_document(args.registry)
            issues = validate_global(documents, registry)
    except InputError as error:
        print(f"{error}: input-read-error", file=sys.stderr)
        return 2

    if issues:
        for issue in issues:
            print(f"{issue.path}:{issue.line}: {issue.rule}", file=sys.stderr)
        return 1

    print(f"[ok] 인용 검증을 통과했습니다: {len(documents)}개 문서")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
