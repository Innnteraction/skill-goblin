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

function Get-BashCommand {
    if ($env:OS -eq 'Windows_NT') {
        $gitBash = 'C:\Program Files\Git\bin\bash.exe'
        if (Test-Path -LiteralPath $gitBash -PathType Leaf) { return $gitBash }
    }
    $bash = Get-Command bash -ErrorAction Stop
    return $bash.Source
}

function Invoke-BashTestScript {
    param([string]$Path, [string[]]$Arguments = @(), [int]$ExpectedExitCode = 0)
    $bash = Get-BashCommand
    & $bash -l $Path @Arguments | Out-Host
    Assert-Equal -Expected $ExpectedExitCode -Actual $LASTEXITCODE -Message "예상하지 못한 Bash 종료 코드: $Path"
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($TempBase)) {
    $TempBase = [IO.Path]::GetTempPath()
}
$resolvedTempBase = [IO.Path]::GetFullPath($TempBase)
[IO.Directory]::CreateDirectory($resolvedTempBase) | Out-Null
$temporaryRoot = Join-Path $resolvedTempBase ("skill-goblin-tests-" + [Guid]::NewGuid().ToString('N'))
$worktreeRoot = $temporaryRoot + '-worktrees'
$remoteRoot = $temporaryRoot + '-remote.git'
[IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null

try {
    foreach ($directoryName in @('scripts', 'templates', '.githooks')) {
        Copy-Item -LiteralPath (Join-Path $repositoryRoot $directoryName) -Destination (Join-Path $temporaryRoot $directoryName) -Recurse
    }
    Copy-Item -LiteralPath (Join-Path $repositoryRoot '.gitattributes') -Destination (Join-Path $temporaryRoot '.gitattributes')
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'VERSION') -Destination (Join-Path $temporaryRoot 'VERSION')
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
        Assert-Equal 'only' (& git config --local --get merge.ff) 'fast-forward merge 설정 실패'
        Assert-Equal 'only' (& git config --local --get pull.ff) 'fast-forward pull 설정 실패'
        Assert-Equal 'nothing' (& git config --local --get push.default) 'main-only 명시 push 설정 실패'
        Assert-Equal $globalNameBefore (& git config --global --get user.name) '전역 Git 이름이 변경됨'
        Assert-Equal $globalEmailBefore (& git config --global --get user.email) '전역 Git 이메일이 변경됨'

        Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/new-skill.ps1') -Arguments @(
            '-Name', 'sample-skill',
            '-Description', '한국어 설명을 처리한다. 샘플 작업을 요청할 때 사용한다.',
            '-WithScripts', '-WithReferences'
        )
        Assert-True (Test-Path -LiteralPath (Join-Path $temporaryRoot 'skills/sample-skill/SKILL.md')) 'Skill 생성 실패'
        Assert-Equal '1' ([IO.File]::ReadAllText((Join-Path $temporaryRoot 'skills/sample-skill/VERSION')).Trim()) 'Skill 초기 VERSION 생성 실패'
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
        [IO.File]::WriteAllText((Join-Path $brokenReferenceDirectory 'VERSION'), "1`n", [Text.Encoding]::UTF8)
        Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/validate-skills.ps1') -Arguments @('-Name', 'broken-reference', '-SkipSensitiveCheck') -ExpectedExitCode 1
        Remove-Item -LiteralPath $brokenReferenceDirectory -Recurse -Force

        $longSkillDirectory = Join-Path $temporaryRoot 'skills/long-skill'
        [IO.Directory]::CreateDirectory($longSkillDirectory) | Out-Null
        $longLines = New-Object System.Collections.Generic.List[string]
        foreach ($line in @('---', 'name: long-skill', "description: '길이 제한 검증용 Skill이다.'", '---')) { $longLines.Add($line) }
        for ($lineNumber = 0; $lineNumber -lt 497; $lineNumber++) { $longLines.Add("검증 줄 $lineNumber") }
        [IO.File]::WriteAllLines((Join-Path $longSkillDirectory 'SKILL.md'), $longLines, [Text.Encoding]::UTF8)
        [IO.File]::WriteAllText((Join-Path $longSkillDirectory 'VERSION'), "1`n", [Text.Encoding]::UTF8)
        Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/validate-skills.ps1') -Arguments @('-Name', 'long-skill', '-SkipSensitiveCheck') -ExpectedExitCode 1
        Remove-Item -LiteralPath $longSkillDirectory -Recurse -Force

        foreach ($versionCase in @(
            [PSCustomObject]@{ Name = 'missing-version'; Value = $null },
            [PSCustomObject]@{ Name = 'zero-version'; Value = '0' },
            [PSCustomObject]@{ Name = 'negative-version'; Value = '-1' },
            [PSCustomObject]@{ Name = 'dotted-version'; Value = '1.0' }
        )) {
            $versionDirectory = Join-Path $temporaryRoot ("skills/" + $versionCase.Name)
            [IO.Directory]::CreateDirectory($versionDirectory) | Out-Null
            $versionSkill = "---`nname: $($versionCase.Name)`ndescription: 'VERSION 검증용 Skill이다.'`n---`n"
            [IO.File]::WriteAllText((Join-Path $versionDirectory 'SKILL.md'), $versionSkill, [Text.Encoding]::UTF8)
            if ($null -ne $versionCase.Value) {
                [IO.File]::WriteAllText((Join-Path $versionDirectory 'VERSION'), ($versionCase.Value + "`n"), [Text.Encoding]::UTF8)
            }
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/validate-skills.ps1') -Arguments @('-Name', $versionCase.Name, '-SkipSensitiveCheck') -ExpectedExitCode 1
            Remove-Item -LiteralPath $versionDirectory -Recurse -Force
        }

        $validRepositoryVersion = [IO.File]::ReadAllText((Join-Path $temporaryRoot 'VERSION'), [Text.Encoding]::UTF8)
        try {
            [IO.File]::WriteAllText((Join-Path $temporaryRoot 'VERSION'), "01.2.3`n", [Text.Encoding]::UTF8)
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/validate-skills.ps1') -Arguments @('-SkipSensitiveCheck') -ExpectedExitCode 1
        }
        finally {
            [IO.File]::WriteAllText((Join-Path $temporaryRoot 'VERSION'), $validRepositoryVersion, (New-Object Text.UTF8Encoding($false)))
        }

        $oldHome = $env:HOME
        $oldCodexHome = $env:CODEX_HOME
        $oldClaudeHome = $env:CLAUDE_HOME
        try {
            $env:HOME = Join-Path $temporaryRoot 'user-home'
            $env:CODEX_HOME = Join-Path $temporaryRoot 'legacy-codex-home'
            $env:CLAUDE_HOME = Join-Path $temporaryRoot 'claude-home'
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/install-skills.ps1') -Arguments @('-Target', 'All', '-Name', 'sample-skill')
            $codexCopy = Join-Path $env:HOME '.agents/skills/sample-skill/SKILL.md'
            $codexVersionCopy = Join-Path $env:HOME '.agents/skills/sample-skill/VERSION'
            $legacyCodexCopy = Join-Path $env:CODEX_HOME 'skills/sample-skill/SKILL.md'
            $claudeCopy = Join-Path $env:CLAUDE_HOME 'skills/sample-skill/SKILL.md'
            Assert-True (Test-Path -LiteralPath $codexCopy) 'Codex 설치 실패'
            Assert-Equal '1' ([IO.File]::ReadAllText($codexVersionCopy).Trim()) 'Codex 설치본 VERSION 누락'
            Assert-True (-not (Test-Path -LiteralPath $legacyCodexCopy)) 'Codex가 이전 CODEX_HOME/skills 경로를 사용함'
            Assert-True (Test-Path -LiteralPath $claudeCopy) 'Claude 설치 실패'

            [IO.File]::AppendAllText($codexCopy, "`n충돌`n", [Text.Encoding]::UTF8)
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/install-skills.ps1') -Arguments @('-Target', 'Codex', '-Name', 'sample-skill') -ExpectedExitCode 1
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/install-skills.ps1') -Arguments @('-Target', 'Codex', '-Name', 'sample-skill', '-Force')
            Assert-True (-not ([IO.File]::ReadAllText($codexCopy).Contains('충돌'))) 'Force 재설치 실패'

            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/install-skills.ps1') -Arguments @('-Scope', 'Project', '-Name', 'sample-skill') -ExpectedExitCode 1
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/install-skills.ps1') -Arguments @('-Scope', 'Project', '-ProjectPath', (Join-Path $temporaryRoot 'missing-project'), '-Name', 'sample-skill') -ExpectedExitCode 1
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/install-skills.ps1') -Arguments @('-Scope', 'User', '-ProjectPath', $temporaryRoot, '-Name', 'sample-skill') -ExpectedExitCode 1

            $projectInstallRoot = Join-Path $temporaryRoot 'target-project'
            [IO.Directory]::CreateDirectory($projectInstallRoot) | Out-Null
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/install-skills.ps1') -Arguments @('-Target', 'All', '-Scope', 'Project', '-ProjectPath', $projectInstallRoot, '-Name', 'sample-skill')
            $projectCodexCopy = Join-Path $projectInstallRoot '.agents/skills/sample-skill/SKILL.md'
            $projectClaudeCopy = Join-Path $projectInstallRoot '.claude/skills/sample-skill/SKILL.md'
            Assert-True (Test-Path -LiteralPath $projectCodexCopy) 'Codex 프로젝트 설치 실패'
            Assert-True (Test-Path -LiteralPath $projectClaudeCopy) 'Claude 프로젝트 설치 실패'

            [IO.File]::AppendAllText($projectCodexCopy, "`n충돌`n", [Text.Encoding]::UTF8)
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/install-skills.ps1') -Arguments @('-Target', 'Codex', '-Scope', 'Project', '-ProjectPath', $projectInstallRoot, '-Name', 'sample-skill') -ExpectedExitCode 1
            Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/install-skills.ps1') -Arguments @('-Target', 'Codex', '-Scope', 'Project', '-ProjectPath', $projectInstallRoot, '-Name', 'sample-skill', '-Force')
            Assert-True (-not ([IO.File]::ReadAllText($projectCodexCopy).Contains('충돌'))) '프로젝트 Force 재설치 실패'

            Invoke-BashTestScript -Path './scripts/install-skills.sh' -Arguments @('--target', 'all', '--name', 'sample-skill')
            $bashProjectRoot = Join-Path $temporaryRoot 'bash-target-project'
            [IO.Directory]::CreateDirectory($bashProjectRoot) | Out-Null
            Invoke-BashTestScript -Path './scripts/install-skills.sh' -Arguments @('--target', 'all', '--scope', 'project', '--project-path', $bashProjectRoot, '--name', 'sample-skill')
            Assert-True (Test-Path -LiteralPath (Join-Path $bashProjectRoot '.agents/skills/sample-skill/SKILL.md')) 'Bash Codex 프로젝트 설치 실패'
            Assert-True (Test-Path -LiteralPath (Join-Path $bashProjectRoot '.claude/skills/sample-skill/SKILL.md')) 'Bash Claude 프로젝트 설치 실패'
            Invoke-BashTestScript -Path './scripts/install-skills.sh' -Arguments @('--scope', 'project', '--name', 'sample-skill') -ExpectedExitCode 1
            Invoke-BashTestScript -Path './scripts/install-skills.sh' -Arguments @('--project-path') -ExpectedExitCode 2
        }
        finally {
            $env:HOME = $oldHome
            $env:CODEX_HOME = $oldCodexHome
            $env:CLAUDE_HOME = $oldClaudeHome
        }

        & git add .
        if ($LASTEXITCODE -ne 0) { throw '안전한 파일 staging 실패' }
        & git commit -m '안전한 테스트 커밋' | Out-Host
        Assert-Equal 0 $LASTEXITCODE '안전한 commit이 hook에서 차단됨'
        $headCommit = (& git rev-parse HEAD).Trim()
        Invoke-TestScript -Path (Join-Path $temporaryRoot 'scripts/check-sensitive.ps1') -Arguments @('-Range', ($headCommit + '^!'), '-SkipGitleaks')

        & git init --bare --initial-branch=main $remoteRoot | Out-Null
        Assert-Equal 0 $LASTEXITCODE 'worktree 테스트용 bare remote 생성 실패'
        & git remote add origin $remoteRoot
        Assert-Equal 0 $LASTEXITCODE 'worktree 테스트용 remote 등록 실패'
        & git push --no-verify -u origin main | Out-Host
        Assert-Equal 0 $LASTEXITCODE '초기 main push 실패'

        $worktreeA = Join-Path $worktreeRoot 'task-a'
        $worktreeB = Join-Path $worktreeRoot 'task-b'
        [IO.Directory]::CreateDirectory($worktreeRoot) | Out-Null
        & git worktree add -b 'feat/task-a' $worktreeA main | Out-Host
        Assert-Equal 0 $LASTEXITCODE '첫 worktree 생성 실패'
        & git worktree add -b 'feat/task-b' $worktreeB main | Out-Host
        Assert-Equal 0 $LASTEXITCODE '두 번째 worktree 생성 실패'

        Push-Location $worktreeA
        try {
            [IO.File]::WriteAllText((Join-Path $worktreeA 'task-a.txt'), "task-a`n", [Text.Encoding]::UTF8)
            & git add task-a.txt
            & git commit -m 'feat: 첫 worktree 변경' | Out-Host
            Assert-Equal 0 $LASTEXITCODE '첫 worktree commit 실패'
        }
        finally {
            Pop-Location
        }

        Push-Location $worktreeB
        try {
            [IO.File]::WriteAllText((Join-Path $worktreeB 'task-b.txt'), "task-b`n", [Text.Encoding]::UTF8)
            & git add task-b.txt
            & git commit -m 'feat: 두 번째 worktree 변경' | Out-Host
            Assert-Equal 0 $LASTEXITCODE '두 번째 worktree commit 실패'
        }
        finally {
            Pop-Location
        }

        & git merge --ff-only 'feat/task-a' | Out-Host
        Assert-Equal 0 $LASTEXITCODE '첫 worktree fast-forward 병합 실패'
        Push-Location $worktreeB
        try {
            & git rebase main | Out-Host
            Assert-Equal 0 $LASTEXITCODE '두 번째 worktree rebase 실패'
        }
        finally {
            Pop-Location
        }
        & git merge --ff-only 'feat/task-b' | Out-Host
        Assert-Equal 0 $LASTEXITCODE '두 번째 worktree fast-forward 병합 실패'
        & git push --no-verify origin main | Out-Host
        Assert-Equal 0 $LASTEXITCODE '통합된 main push 실패'

        $remoteHeads = @(& git ls-remote --heads origin)
        Assert-Equal 1 $remoteHeads.Count '원격에 main 외 작업 브랜치가 push됨'
        Assert-True ($remoteHeads[0] -match 'refs/heads/main$') '원격 main ref를 찾지 못함'
        Assert-Equal '' ((& git -C $worktreeA status --porcelain) -join "`n") '첫 worktree가 clean하지 않음'
        Assert-Equal '' ((& git -C $worktreeB status --porcelain) -join "`n") '두 번째 worktree가 clean하지 않음'

        & git worktree remove $worktreeA
        Assert-Equal 0 $LASTEXITCODE '첫 worktree 제거 실패'
        & git worktree remove $worktreeB
        Assert-Equal 0 $LASTEXITCODE '두 번째 worktree 제거 실패'
        & git branch -d 'feat/task-a' 'feat/task-b' | Out-Host
        Assert-Equal 0 $LASTEXITCODE '병합된 worktree 브랜치 제거 실패'
        $worktreeList = (& git worktree list --porcelain) -join "`n"
        Assert-True (-not $worktreeList.Contains($worktreeRoot)) '제거한 worktree metadata가 남음'

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

    Invoke-TestScript -Path (Join-Path $repositoryRoot 'tests/reverse-engineer-service-tests.ps1')
    & python (Join-Path $repositoryRoot 'tests/citation-validator-tests.py')
    Assert-Equal 0 $LASTEXITCODE '인용 검사기 회귀 테스트 실패'
    Write-Host '[ok] 모든 통합 테스트를 통과했습니다.'
}
finally {
    foreach ($cleanupPath in @($temporaryRoot, $worktreeRoot, $remoteRoot)) {
        $resolvedCleanupPath = [IO.Path]::GetFullPath($cleanupPath)
        if ($resolvedCleanupPath.StartsWith($resolvedTempBase, [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path -Leaf $resolvedCleanupPath).StartsWith('skill-goblin-tests-') -and
            (Test-Path -LiteralPath $resolvedCleanupPath)) {
            try {
                Remove-Item -LiteralPath $resolvedCleanupPath -Recurse -Force -ErrorAction Stop
            }
            catch {
                Write-Warning "임시 테스트 폴더를 자동 삭제하지 못했습니다: $resolvedCleanupPath"
            }
        }
    }
}
