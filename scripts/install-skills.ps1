[CmdletBinding()]
param(
    [ValidateSet('Codex', 'Claude', 'All')][string]$Target = 'All',
    [ValidateSet('User', 'Project')][string]$Scope = 'User',
    [string]$ProjectPath,
    [string]$Name,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

function Get-SafeSkillDestination {
    param(
        [Parameter(Mandatory = $true)][string]$SkillsRoot,
        [Parameter(Mandatory = $true)][string]$SkillName
    )

    $resolvedSkillsRoot = [IO.Path]::GetFullPath($SkillsRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $destination = [IO.Path]::GetFullPath((Join-Path $resolvedSkillsRoot $SkillName))
    $destinationParent = [IO.Path]::GetFullPath((Split-Path -Parent $destination)).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $comparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }

    if (-not [string]::Equals($resolvedSkillsRoot, $destinationParent, $comparison)) {
        throw "안전하지 않은 Skill 설치 경로입니다: $destination"
    }
    return $destination
}

try {
    $root = Get-RepositoryRoot
    $validator = Join-Path $PSScriptRoot 'validate-skills.ps1'
    $validationArguments = @('-SkipSensitiveCheck')
    if (-not [string]::IsNullOrWhiteSpace($Name)) { $validationArguments += @('-Name', $Name) }
    if ((Invoke-PowerShellScript -Path $validator -Arguments $validationArguments) -ne 0) {
        throw 'Skill 검증에 실패해 설치를 중단했습니다.'
    }

    $skills = @(Get-SkillDirectories -Root $root -Name $Name)
    if ($skills.Count -eq 0) {
        Write-Host '설치할 Skill이 없습니다.'
        exit 0
    }

    $targets = @()
    if ($Scope -eq 'Project') {
        if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
            throw 'Project 범위에는 -ProjectPath가 필요합니다.'
        }
        if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
            throw "프로젝트 디렉터리를 찾을 수 없습니다: $ProjectPath"
        }
        $projectRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectPath).Path)
        if ($Target -in @('Codex', 'All')) {
            $targets += [PSCustomObject]@{ Name = 'Codex'; Path = Join-Path $projectRoot '.agents/skills' }
        }
        if ($Target -in @('Claude', 'All')) {
            $targets += [PSCustomObject]@{ Name = 'Claude'; Path = Join-Path $projectRoot '.claude/skills' }
        }
    }
    else {
        if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) {
            throw '-ProjectPath는 Project 범위에서만 사용할 수 있습니다.'
        }
        $homeDirectory = Get-UserHomeDirectory
        if ($Target -in @('Codex', 'All')) {
            $agentsHome = Join-Path $homeDirectory '.agents'
            $targets += [PSCustomObject]@{ Name = 'Codex'; Path = Join-Path $agentsHome 'skills' }
        }
        if ($Target -in @('Claude', 'All')) {
            $claudeHome = if ([string]::IsNullOrWhiteSpace($env:CLAUDE_HOME)) { Join-Path $homeDirectory '.claude' } else { $env:CLAUDE_HOME }
            $targets += [PSCustomObject]@{ Name = 'Claude'; Path = Join-Path $claudeHome 'skills' }
        }
    }

    $conflicts = New-Object System.Collections.Generic.List[string]
    foreach ($targetInfo in $targets) {
        [IO.Directory]::CreateDirectory($targetInfo.Path) | Out-Null
        foreach ($skill in $skills) {
            $destination = Get-SafeSkillDestination -SkillsRoot $targetInfo.Path -SkillName $skill.Name
            if (Test-Path -LiteralPath $destination) {
                $sourceHash = Get-DirectoryFingerprint -Path $skill.FullName
                $destinationHash = Get-DirectoryFingerprint -Path $destination
                if ($sourceHash -eq $destinationHash) {
                    Write-Host "[same] $($targetInfo.Name): $($skill.Name)"
                    continue
                }
                if (-not $Force) {
                    $conflicts.Add("$($targetInfo.Name): $destination")
                    continue
                }
                Remove-Item -LiteralPath $destination -Recurse -Force
            }

            Copy-Item -LiteralPath $skill.FullName -Destination $destination -Recurse
            Write-Host "[installed] $($targetInfo.Name): $($skill.Name)"
        }
    }

    if ($conflicts.Count -gt 0) {
        foreach ($conflict in $conflicts) { Write-Error "다른 내용의 설치 대상이 있습니다: $conflict" }
        Write-Error '기존 복사본을 확인한 뒤 의도적으로 교체할 때만 -Force를 사용하세요.'
        exit 1
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
