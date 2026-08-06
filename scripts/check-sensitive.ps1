[CmdletBinding(DefaultParameterSetName = 'Staged')]
param(
    [Parameter(ParameterSetName = 'Staged')][switch]$Staged,
    [Parameter(ParameterSetName = 'All', Mandatory = $true)][switch]$All,
    [Parameter(ParameterSetName = 'Range', Mandatory = $true)][string]$Range,
    [switch]$SkipGitleaks
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

function Get-AddedDiffText {
    param([string[]]$GitArguments)
    $diff = @(& git @GitArguments)
    if ($LASTEXITCODE -ne 0) { throw 'Git diff를 읽지 못했습니다.' }
    return (($diff | Where-Object { $_ -match '^\+' -and $_ -notmatch '^\+\+\+' } | ForEach-Object { $_.Substring(1) }) -join "`n")
}

function Add-Finding {
    param(
        [System.Collections.Generic.List[string]]$Findings,
        [string]$Rule,
        [string]$Path
    )
    $message = "[$Rule] $Path"
    if (-not $Findings.Contains($message)) { $Findings.Add($message) }
}

try {
    $root = Get-RepositoryRoot
    Push-Location $root
    try {
        $mode = if ($PSCmdlet.ParameterSetName -eq 'All') { 'All' } elseif ($PSCmdlet.ParameterSetName -eq 'Range') { 'Range' } else { 'Staged' }
        $paths = @()
        $contentItems = New-Object System.Collections.Generic.List[object]

        if ($mode -eq 'Staged') {
            $paths = @(& git diff --cached --name-only --diff-filter=ACMR --)
            if ($LASTEXITCODE -ne 0) { throw 'staged 파일 목록을 읽지 못했습니다.' }
            foreach ($path in $paths) {
                $stagedContent = @(& git show ":$path" 2>$null) -join "`n"
                if ($LASTEXITCODE -eq 0) {
                    $contentItems.Add([PSCustomObject]@{ Path = $path.Replace('\', '/'); Text = $stagedContent })
                }
            }
        }
        elseif ($mode -eq 'Range') {
            if ($Range -notmatch '^[0-9a-fA-F.^~!]+(?:\.\.[0-9a-fA-F.^~!]+)?$') {
                throw '안전하지 않거나 올바르지 않은 Git revision 범위입니다.'
            }
            $paths = @(& git diff --name-only --diff-filter=ACMR $Range --)
            if ($LASTEXITCODE -ne 0) { throw "Git 범위를 읽지 못했습니다: $Range" }
            $rangeText = Get-AddedDiffText -GitArguments @('diff', '--no-ext-diff', '--unified=0', '--no-color', $Range, '--')
            $contentItems.Add([PSCustomObject]@{ Path = "Git 범위: $Range"; Text = $rangeText })
        }
        else {
            $paths = @(& git ls-files --cached --others --exclude-standard)
            if ($LASTEXITCODE -ne 0) { throw '추적 파일 목록을 읽지 못했습니다.' }
            foreach ($path in $paths) {
                $fullPath = Join-Path $root $path
                if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
                try {
                    $text = [IO.File]::ReadAllText($fullPath, [Text.Encoding]::UTF8)
                    $contentItems.Add([PSCustomObject]@{ Path = $path.Replace('\', '/'); Text = $text })
                }
                catch {
                    # Binary or unreadable files are covered by risky filename checks.
                }
            }
        }

        $findings = New-Object System.Collections.Generic.List[string]
        $riskyPathPatterns = @(
            '(?i)(^|/)\.env(?:\..+)?$',
            '(?i)\.(?:key|pem|p12|pfx|jks|keystore)$',
            '(?i)(^|/)(?:credentials|service-account[^/]*)\.json$',
            '(?i)(^|/)(?:secrets?|\.aws|\.ssh)/'
        )
        foreach ($path in $paths) {
            $normalized = $path.Replace('\', '/')
            if ($normalized -in @('.env.example', '.env.sample')) { continue }
            foreach ($pattern in $riskyPathPatterns) {
                if ($normalized -match $pattern) {
                    Add-Finding -Findings $findings -Rule 'risky-file' -Path $normalized
                    break
                }
            }
        }

        $contentRules = [ordered]@{
            'private-key'      = ('-----BEGIN ' + '(?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----')
            'github-token'     = '(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'
            'aws-access-key'   = '(?:AKIA|ASIA)[A-Z0-9]{16}'
            'slack-token'      = 'xox[baprs]-[A-Za-z0-9-]{20,}'
            'openai-api-key'   = 'sk-[A-Za-z0-9_-]{20,}'
            'generic-secret'   = '(?im)\b(?:password|passwd|secret|api[_-]?key|access[_-]?token)\b\s*[:=]\s*["'']?(?!EXAMPLE|PLACEHOLDER|CHANGEME|REDACTED|<)[A-Za-z0-9_./+=:-]{12,}'
        }
        foreach ($item in $contentItems) {
            foreach ($entry in $contentRules.GetEnumerator()) {
                if ($item.Text -match $entry.Value) {
                    Add-Finding -Findings $findings -Rule $entry.Key -Path $item.Path
                }
            }
        }

        if ($findings.Count -gt 0) {
            Write-Error '민감정보로 의심되는 항목을 발견했습니다. 실제 값은 출력하지 않습니다.'
            foreach ($finding in $findings) { Write-Error $finding }
            exit 1
        }

        if (-not $SkipGitleaks) {
            $gitleaks = Get-Command gitleaks -ErrorAction SilentlyContinue
            if ($null -eq $gitleaks) {
                Write-Warning 'Gitleaks가 없어 내장 검사만 실행했습니다.'
            }
            else {
                if ($mode -eq 'Staged') {
                    & $gitleaks.Source git --pre-commit --redact --staged --verbose
                }
                elseif ($mode -eq 'Range') {
                    & $gitleaks.Source git --redact --verbose "--log-opts=$Range" .
                }
                else {
                    & $gitleaks.Source git --redact --verbose .
                }
                if ($LASTEXITCODE -ne 0) { throw 'Gitleaks 검사에 실패했습니다.' }
            }
        }

        Write-Host "민감정보 검사를 통과했습니다: $mode"
    }
    finally {
        Pop-Location
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
