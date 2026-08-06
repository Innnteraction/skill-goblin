Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-RepositoryRoot {
    $root = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) {
        throw '현재 디렉터리는 Git 저장소가 아닙니다.'
    }
    return [System.IO.Path]::GetFullPath($root.Trim())
}

function Test-SkillName {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $Name.Length -le 64 -and $Name -match '^[a-z0-9]+(?:-[a-z0-9]+)*$'
}

function Get-SkillDirectories {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$Name
    )

    $skillsRoot = Join-Path $Root 'skills'
    if (-not (Test-Path -LiteralPath $skillsRoot -PathType Container)) {
        return @()
    }

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        if (-not (Test-SkillName -Name $Name)) {
            throw "올바르지 않은 Skill 이름입니다: $Name"
        }
        $selected = Join-Path $skillsRoot $Name
        if (-not (Test-Path -LiteralPath $selected -PathType Container)) {
            throw "Skill을 찾을 수 없습니다: $Name"
        }
        return @((Get-Item -LiteralPath $selected))
    }

    return @(Get-ChildItem -LiteralPath $skillsRoot -Directory | Sort-Object Name)
}

function Get-DirectoryFingerprint {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $null
    }

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($file in @(Get-ChildItem -LiteralPath $resolved -File -Recurse | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($resolved.Length).TrimStart('\', '/').Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $parts.Add("$relative`n$hash")
    }

    $joined = [string]::Join("`n", $parts)
    $bytes = [Text.Encoding]::UTF8.GetBytes($joined)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Get-UserHomeDirectory {
    if (-not [string]::IsNullOrWhiteSpace($env:HOME)) {
        return [System.IO.Path]::GetFullPath($env:HOME)
    }
    return [Environment]::GetFolderPath('UserProfile')
}

function Invoke-PowerShellScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Arguments = @()
    )

    $engine = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $engine) {
        $engine = Get-Command powershell -ErrorAction SilentlyContinue
    }
    if ($null -eq $engine) {
        throw 'PowerShell 실행 파일을 찾을 수 없습니다.'
    }

    & $engine.Source -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments |
        ForEach-Object { Write-Host $_ }
    $exitCode = $LASTEXITCODE
    return $exitCode
}
