[CmdletBinding()]
param(
    [string]$Name,
    [switch]$SkipSensitiveCheck
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

function Remove-YamlQuotes {
    param([string]$Value)
    $trimmed = $Value.Trim()
    if ($trimmed.Length -ge 2 -and $trimmed.StartsWith("'") -and $trimmed.EndsWith("'")) {
        return $trimmed.Substring(1, $trimmed.Length - 2).Replace("''", "'")
    }
    if ($trimmed.Length -ge 2 -and $trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) {
        return $trimmed.Substring(1, $trimmed.Length - 2)
    }
    return $trimmed
}

$errors = New-Object System.Collections.Generic.List[string]

try {
    $root = Get-RepositoryRoot
    $directories = @(Get-SkillDirectories -Root $root -Name $Name)

    foreach ($directory in $directories) {
        $skillPath = Join-Path $directory.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
            $errors.Add("$($directory.Name): SKILL.md가 없습니다.")
            continue
        }

        if (-not (Test-SkillName -Name $directory.Name)) {
            $errors.Add("$($directory.Name): 디렉터리 이름이 kebab-case 규칙에 맞지 않습니다.")
        }

        $lines = @([IO.File]::ReadAllLines($skillPath, [Text.Encoding]::UTF8))
        if ($lines.Count -gt 500) {
            $errors.Add("$($directory.Name): SKILL.md가 500줄을 넘습니다 ($($lines.Count)줄).")
        }
        if ($lines.Count -lt 4 -or $lines[0].Trim() -ne '---') {
            $errors.Add("$($directory.Name): YAML frontmatter 시작 구분자가 없습니다.")
            continue
        }

        $closing = -1
        for ($index = 1; $index -lt $lines.Count; $index++) {
            if ($lines[$index].Trim() -eq '---') {
                $closing = $index
                break
            }
        }
        if ($closing -lt 0) {
            $errors.Add("$($directory.Name): YAML frontmatter 종료 구분자가 없습니다.")
            continue
        }

        $fields = @{}
        for ($index = 1; $index -lt $closing; $index++) {
            $line = $lines[$index]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -notmatch '^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$') {
                $errors.Add("$($directory.Name): frontmatter $($index + 1)번째 줄 형식이 올바르지 않습니다.")
                continue
            }
            $key = $Matches[1]
            if ($fields.ContainsKey($key)) {
                $errors.Add("$($directory.Name): frontmatter에 $key 필드가 중복됩니다.")
            }
            $fields[$key] = Remove-YamlQuotes -Value $Matches[2]
        }

        foreach ($key in @($fields.Keys)) {
            if ($key -notin @('name', 'description')) {
                $errors.Add("$($directory.Name): 공용 frontmatter에서 지원하지 않는 필드입니다: $key")
            }
        }
        if (-not $fields.ContainsKey('name') -or $fields['name'] -ne $directory.Name) {
            $errors.Add("$($directory.Name): frontmatter name이 디렉터리 이름과 일치하지 않습니다.")
        }
        if (-not $fields.ContainsKey('description') -or [string]::IsNullOrWhiteSpace($fields['description'])) {
            $errors.Add("$($directory.Name): description이 비어 있습니다.")
        }
        elseif ($fields['description'].Length -gt 1024) {
            $errors.Add("$($directory.Name): description이 1024자를 넘습니다.")
        }

        $content = [string]::Join("`n", $lines)
        if ($content -match '\]\([^\r\n)]*\\[^\r\n)]*\)') {
            $errors.Add("$($directory.Name): Markdown 링크에는 Windows 역슬래시 대신 /를 사용해야 합니다.")
        }
        foreach ($match in [regex]::Matches($content, '\]\(([^)]+)\)')) {
            $reference = $match.Groups[1].Value.Split('#')[0].Trim()
            if ([string]::IsNullOrWhiteSpace($reference) -or $reference -match '^(?:https?:|mailto:|#|/)') { continue }
            $decoded = [Uri]::UnescapeDataString($reference)
            $resolved = Join-Path $directory.FullName $decoded
            if (-not (Test-Path -LiteralPath $resolved)) {
                $errors.Add("$($directory.Name): 참조 파일을 찾을 수 없습니다: $reference")
            }
        }

        if ($errors.Count -eq 0) {
            Write-Host "[ok] $($directory.Name)"
        }
    }

    if (-not $SkipSensitiveCheck) {
        $scanner = Join-Path $PSScriptRoot 'check-sensitive.ps1'
        $code = Invoke-PowerShellScript -Path $scanner -Arguments @('-All', '-SkipGitleaks')
        if ($code -ne 0) {
            $errors.Add('민감정보 검사에 실패했습니다.')
        }
    }

    if ($errors.Count -gt 0) {
        foreach ($message in $errors) { Write-Error $message }
        exit 1
    }

    Write-Host "Skill 검증을 완료했습니다: $($directories.Count)개"
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
