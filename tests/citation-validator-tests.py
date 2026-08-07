#!/usr/bin/env python3
"""Regression tests for the Markdown evidence citation validator."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = (
    REPOSITORY_ROOT
    / "skills"
    / "write-diataxis-docs"
    / "scripts"
    / "validate-citations.py"
)


def write(path: Path, content: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.strip() + "\n", encoding="utf-8")
    return path


def expect_code(expected: int, *arguments: Path | str) -> None:
    result = subprocess.run(
        [sys.executable, str(VALIDATOR), *(str(argument) for argument in arguments)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if result.returncode != expected:
        raise AssertionError(
            f"expected={expected}, actual={result.returncode}\n"
            f"stdout={result.stdout}\nstderr={result.stderr}"
        )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="citation-validator-tests-") as temporary:
        root = Path(temporary)

        local = write(
            root / "local.md",
            """
# 재시도

상태를 먼저 읽는다.[[1]](#cite-state-check) 같은 근거를 다시 쓴다.[[1]](#cite-state-check)
일반 [탐색 링크](guide.md)와 일반 각주[^note]는 검사 대상이 아니다.
`[[9]](#cite-inline-example)`

```markdown
[[8]](#cite-fenced-example)
8. <a name="cite-fenced-example"></a> 예시
```

<!-- [[7]](#cite-comment-example) -->

## 근거

1. <a name="cite-state-check"></a> **상태 확인.** `src/orders/retry.py`의 `load_state`를 확인했다.

[^note]: 일반 설명이다.
""",
        )
        expect_code(0, local)

        chapter_one = write(
            root / "chapters" / "one.md",
            """
# 첫 장

상태를 읽는다.[[1]](../references.md#cite-state-check)
""",
        )
        chapter_two = write(
            root / "chapters" / "two.md",
            """
# 둘째 장

같은 상태를 사용한다.[[1]](../references.md#cite-state-check)
재시도한다.[[2]](../references.md#cite-retry-call)
""",
        )
        registry = write(
            root / "references.md",
            """
# 근거

1. <a name="cite-state-check"></a> 상태 조회 구현.
2. <a name="cite-retry-call"></a> 재시도 구현.
""",
        )
        expect_code(0, "--registry", registry, chapter_one, chapter_two)

        wrong_order = write(
            root / "wrong-order.md",
            """
첫 근거다.[[2]](#cite-first)

## 근거

2. <a name="cite-first"></a> 첫 근거.
""",
        )
        expect_code(1, wrong_order)

        malformed = write(
            root / "malformed.md",
            "잘못된 번호다.[[0]](#cite-invalid-number)",
        )
        expect_code(1, malformed)

        duplicate = write(
            root / "duplicate.md",
            """
첫 근거다.[[1]](#cite-first) 둘째 근거다.[[2]](#cite-second)

## 근거

1. <a name="cite-first"></a> 첫 근거.
1. <a name="cite-second"></a> 둘째 근거.
1. <a name="cite-first"></a> 중복 근거.
""",
        )
        expect_code(1, duplicate)

        missing_and_unused = write(
            root / "missing-and-unused.md",
            """
필요한 근거다.[[1]](#cite-required)

## 근거

1. <a name="cite-unused"></a> 사용하지 않은 근거.
""",
        )
        expect_code(1, missing_and_unused)

        wrong_target = write(
            root / "chapters" / "wrong-target.md",
            "틀린 중앙 문서다.[[1]](other.md#cite-state-check)",
        )
        expect_code(1, "--registry", registry, wrong_target)

        windows_absolute = write(
            root / "windows-absolute.md",
            r"""
근거다.[[1]](#cite-windows-path)

## 근거

1. <a name="cite-windows-path"></a> `C:\Users\person\repo\source.py`
""",
        )
        expect_code(1, windows_absolute)

        posix_absolute = write(
            root / "posix-absolute.md",
            """
근거다.[[1]](#cite-posix-path)

## 근거

1. <a name="cite-posix-path"></a> `/home/person/repo/source.py`
""",
        )
        expect_code(1, posix_absolute)

        expect_code(2, root / "missing.md")

    print("[ok] 인용 검사기 회귀 테스트를 통과했습니다.")


if __name__ == "__main__":
    main()
