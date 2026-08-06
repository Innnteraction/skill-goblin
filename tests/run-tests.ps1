[CmdletBinding()]
param(
    [string]$TempBase
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message (expected=$Expected, actual=$Actual)"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-TestScript {
    param([string]$Path, [string[]]$Arguments = @(), [int]$ExpectedExitCode = 0)
    $engine = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $engine) { $engine = Get-Command powershell -ErrorAction Stop }
    & $engine.Source -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments | Out-Host
    Assert-Equal -Expected $ExpectedExitCode -Actual $LASTEXITCODE -Message "예상하지 못한 종료 코드: $Path"
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($TempBase)) {
    $TempBase = [IO.Path]::GetTempPath()
}
$resolvedTempBase = [IO.Path]::GetFullPath($TempBase)
[IO.Directory]::CreateDirectory($resolvedTempBase) | Out-Null
$temporaryRoot = Join-Path $resolvedTempBase ("skill-goblin-tests-" + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null

try {
    foreach ($directoryName in @('scripts', 'templates', '.githooks')) {
        Copy-Item -LiteralPath (Join-Path $repositoryRoot $directoryName) -Destination (Join-Path $temporaryRoot $directoryName) -Recurse
    }
    Copy-Item -LiteralPath (Join-Path $repositoryRoot '.gitattributes') -Destination (Join-Path $temporaryRoot '.gitattributes')
    [IO.Directory]::CreateDirectory((Join-Path $temporaryRoot 'skills')) | Out-Null

    Push-Location $temporaryRoot
    try {
        & git init --initial-branch=main | Out-Null
        if ($LASTEXITCODE -ne 0) { throw '임시 Git 저장소를 만들지 못했습니다.' }

        $globalNameBefore = & git config --global --get user.name
        $globalEmailBefore = & git config --global --get user.email

        Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/setup.ps1')
        Assert-Equal 'Innnteraction' (& git config --local --get user.name) '로컬 Git 이름 설정 실패'
        Assert-Equal 'innnteractive@gmail.com' (& git config --local --get user.email) '로컬 Git 이메일 설정 실패'
        Assert-Equal '.githooks' (& git config --local --get core.hooksPath) 'hook 경로 설정 실패'
        Assert-Equal $globalNameBefore (& git config --global --get user.name) '전역 Git 이름이 변경됨'
        Assert-Equal $globalEmailBefore (& git config --global --get user.email) '전역 Git 이메일이 변경됨'

        Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/new-skill.ps1') -Arguments @(
            '-Name', 'sample-skill',
            '-Description', '한국어 설명을 처리한다. 샘플 작업을 요청할 때 사용한다.',
            '-WithScripts', '-WithReferences'
        )
        Assert-True (Test-Path -LiteralPath (Join-Path $temporaryRoot 'skills/sample-skill/SKILL.md')) 'Skill 생성 실패'
        Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/validate-skills.ps1')

        foreach ($caseName in @('Bad_Name', ('a' * 65))) {
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/new-skill.ps1') -Arguments @('-Name', $caseName, '-Description', 'invalid') -ExpectedExitCode 1
        }

        $invalidDirectory = Join-Path $temporaryRoot 'skills/broken-skill'
        [IO.Directory]::CreateDirectory($invalidDirectory) | Out-Null
        [IO.File]::WriteAllText((Join-Path $invalidDirectory 'SKILL.md'), "# frontmatter 없음`n", [Text.Encoding]::UTF8)
        Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/validate-skills.ps1') -Arguments @('-SkipSensitiveCheck') -ExpectedExitCode 1
        Remove-Item -LiteralPath $invalidDirectory -Recurse -Force

        $brokenReferenceDirectory = Join-Path $temporaryRoot 'skills/broken-reference'
        [IO.Directory]::CreateDirectory($brokenReferenceDirectory) | Out-Null
        $brokenReference = "---`nname: broken-reference`ndescription: '깨진 참조 검증용 Skill이다.'`n---`n`n[참조](references/missing.md)`n"
        [IO.File]::WriteAllText((Join-Path $brokenReferenceDirectory 'SKILL.md'), $brokenReference, [Text.Encoding]::UTF8)
        Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/validate-skills.ps1') -Arguments @('-Name', 'broken-reference', '-SkipSensitiveCheck') -ExpectedExitCode 1
        Remove-Item -LiteralPath $brokenReferenceDirectory -Recurse -Force

        $longSkillDirectory = Join-Path $temporaryRoot 'skills/long-skill'
        [IO.Directory]::CreateDirectory($longSkillDirectory) | Out-Null
        $longLines = New-Object System.Collections.Generic.List[string]
        foreach ($line in @('---', 'name: long-skill', "description: '길이 제한 검증용 Skill이다.'", '---')) { $longLines.Add($line) }
        for ($lineNumber = 0; $lineNumber -lt 497; $lineNumber++) { $longLines.Add("검증 줄 $lineNumber") }
        [IO.File]::WriteAllLines((Join-Path $longSkillDirectory 'SKILL.md'), $longLines, [Text.Encoding]::UTF8)
        Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/validate-skills.ps1') -Arguments @('-Name', 'long-skill', '-SkipSensitiveCheck') -ExpectedExitCode 1
        Remove-Item -LiteralPath $longSkillDirectory -Recurse -Force

        $oldCodexHome = $env:CODEX_HOME
        $oldClaudeHome = $env:CLAUDE_HOME
        try {
            $env:CODEX_HOME = Join-Path $temporaryRoot 'codex-home'
            $env:CLAUDE_HOME = Join-Path $temporaryRoot 'claude-home'
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/install-skills.ps1') -Arguments @('-Target', 'All', '-Name', 'sample-skill')
            $codexCopy = Join-Path $env:CODEX_HOME 'skills/sample-skill/SKILL.md'
            $claudeCopy = Join-Path $env:CLAUDE_HOME 'skills/sample-skill/SKILL.md'
            Assert-True (Test-Path -LiteralPath $codexCopy) 'Codex 설치 실패'
            Assert-True (Test-Path -LiteralPath $claudeCopy) 'Claude 설치 실패'

            [IO.File]::AppendAllText($codexCopy, "`n충돌`n", [Text.Encoding]::UTF8)
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/install-skills.ps1') -Arguments @('-Target', 'Codex', '-Name', 'sample-skill') -ExpectedExitCode 1
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/install-skills.ps1') -Arguments @('-Target', 'Codex', '-Name', 'sample-skill', '-Force')
            Assert-True (-not ([IO.File]::ReadAllText($codexCopy).Contains('충돌'))) 'Force 재설치 실패'
        }
        finally {
            $env:CODEX_HOME = $oldCodexHome
            $env:CLAUDE_HOME = $oldClaudeHome
        }

        & git add .
        if ($LASTEXITCODE -ne 0) { throw '안전한 파일 staging 실패' }
        & git commit -m '안전한 테스트 커밋' | Out-Host
        Assert-Equal 0 $LASTEXITCODE '안전한 commit이 hook에서 차단됨'
        $headCommit = (& git rev-parse HEAD).Trim()
        Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/check-sensitive.ps1') -Arguments @('-Range', ($headCommit + '^!'), '-SkipGitleaks')

        $mockBin = Join-Path $temporaryRoot 'mock-bin'
        [IO.Directory]::CreateDirectory($mockBin) | Out-Null
        [IO.File]::WriteAllText((Join-Path $mockBin 'gitleaks.cmd'), "@echo off`r`nexit /b 9`r`n", [Text.Encoding]::ASCII)
        $oldPath = $env:PATH
        try {
            $env:PATH = $mockBin + [IO.Path]::PathSeparator + $oldPath
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/check-sensitive.ps1') -Arguments @('-Staged') -ExpectedExitCode 1
        }
        finally {
            $env:PATH = $oldPath
        }

        $fakeToken = 'ghp_' + ('A' * 30)
        [IO.File]::WriteAllText((Join-Path $temporaryRoot 'unsafe.txt'), "token=$fakeToken`n", [Text.Encoding]::UTF8)
        & git add unsafe.txt
        Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/check-sensitive.ps1') -Arguments @('-Staged', '-SkipGitleaks') -ExpectedExitCode 1
        & git reset -- unsafe.txt | Out-Null
        Remove-Item -LiteralPath (Join-Path $temporaryRoot 'unsafe.txt') -Force

        [IO.File]::WriteAllText((Join-Path $temporaryRoot '.env'), "EXAMPLE_TOKEN=placeholder`n", [Text.Encoding]::UTF8)
        & git add -f .env
        Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/check-sensitive.ps1') -Arguments @('-Staged', '-SkipGitleaks') -ExpectedExitCode 1
        & git reset -- .env | Out-Null
        Remove-Item -LiteralPath (Join-Path $temporaryRoot '.env') -Force
    }
    finally {
        Pop-Location
    }

    Write-Host '[ok] 모든 통합 테스트를 통과했습니다.'
}
finally {
    $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
    if ($resolvedTemporaryRoot.StartsWith($resolvedTempBase, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemporaryRoot).StartsWith('skill-goblin-tests-')) {
        try {
            Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "임시 테스트 폴더를 자동 삭제하지 못했습니다: $resolvedTemporaryRoot"
        }
    }
}
