[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Description,
    [switch]$WithScripts,
    [switch]$WithReferences,
    [switch]$WithAssets
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

try {
    if (-not (Test-SkillName -Name $Name)) {
        throw 'Skill 이름은 64자 이하의 소문자, 숫자, 하이픈만 사용하고 하이픈으로 시작하거나 끝낼 수 없습니다.'
    }
    if ([string]::IsNullOrWhiteSpace($Description)) {
        throw 'Skill description은 비워 둘 수 없습니다.'
    }
    if ($Description.Length -gt 1024) {
        throw 'Skill description은 1024자를 넘을 수 없습니다.'
    }

    $root = Get-RepositoryRoot
    $destination = Join-Path (Join-Path $root 'skills') $Name
    if (Test-Path -LiteralPath $destination) {
        throw "이미 같은 이름의 경로가 있습니다: skills/$Name"
    }

    $templatePath = Join-Path $root 'templates/skill/SKILL.md'
    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        throw 'Skill 템플릿을 찾을 수 없습니다.'
    }

    $title = (($Name -split '-') | ForEach-Object {
        if ($_.Length -gt 0) { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }
    }) -join ' '
    $yamlDescription = $Description.Replace("'", "''")
    $content = [IO.File]::ReadAllText($templatePath, [Text.Encoding]::UTF8)
    $content = $content.Replace('__SKILL_NAME__', $Name)
    $content = $content.Replace('__SKILL_DESCRIPTION__', $yamlDescription)
    $content = $content.Replace('__SKILL_TITLE__', $title)

    [IO.Directory]::CreateDirectory($destination) | Out-Null
    [IO.File]::WriteAllText((Join-Path $destination 'SKILL.md'), $content, (New-Object Text.UTF8Encoding($false)))

    if ($WithScripts) { [IO.Directory]::CreateDirectory((Join-Path $destination 'scripts')) | Out-Null }
    if ($WithReferences) { [IO.Directory]::CreateDirectory((Join-Path $destination 'references')) | Out-Null }
    if ($WithAssets) { [IO.Directory]::CreateDirectory((Join-Path $destination 'assets')) | Out-Null }

    Write-Host "Skill 골격을 만들었습니다: skills/$Name/SKILL.md"
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
