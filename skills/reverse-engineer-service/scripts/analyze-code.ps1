[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($Arguments.Count -lt 1 -or $Arguments[0] -notin @('discover', 'trace')) {
    Write-Error '첫 인자는 discover 또는 trace여야 합니다.'
    exit 2
}
$Command = $Arguments[0]
$Root = $null
$Entry = $null
$Profile = 'auto'
$MaxDepth = 4
$MaxNodes = 80
$TypeScriptPath = $null
$Output = $null
for ($index = 1; $index -lt $Arguments.Count; $index += 2) {
    if ($index + 1 -ge $Arguments.Count) { Write-Error "값이 없는 인자입니다: $($Arguments[$index])"; exit 2 }
    $name = $Arguments[$index].TrimStart('-').ToLowerInvariant()
    $value = $Arguments[$index + 1]
    switch ($name) {
        'root' { $Root = $value }
        'entry' { $Entry = $value }
        'profile' { $Profile = $value }
        'max-depth' { if (-not [int]::TryParse($value, [ref]$MaxDepth)) { Write-Error 'max-depth는 정수여야 합니다.'; exit 2 } }
        'max-nodes' { if (-not [int]::TryParse($value, [ref]$MaxNodes)) { Write-Error 'max-nodes는 정수여야 합니다.'; exit 2 } }
        'typescript-path' { $TypeScriptPath = $value }
        'output' { $Output = $value }
        default { Write-Error "지원하지 않는 인자입니다: $($Arguments[$index])"; exit 2 }
    }
}
if ([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($Output)) { Write-Error '--root와 --output이 필요합니다.'; exit 2 }
if ($Profile -notin @('auto', 'http', 'worker', 'cli', 'generic')) { Write-Error '지원하지 않는 profile입니다.'; exit 2 }
if ($MaxDepth -lt 0 -or $MaxNodes -lt 1) { Write-Error 'max-depth는 0 이상, max-nodes는 1 이상이어야 합니다.'; exit 2 }

function Invoke-Analyzer {
    param([string]$Language, [string]$Destination)
    $common = @($Command, '--root', $resolvedRoot, '--profile', $Profile, '--max-depth', "$MaxDepth", '--max-nodes', "$MaxNodes", '--output', $Destination)
    if ($Entry) { $common += @('--entry', $Entry) }
    if ($Language -eq 'python') {
        $python = Get-Command python -ErrorAction SilentlyContinue
        if ($null -eq $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
        if ($null -eq $python) { Write-Error 'Python 런타임을 찾을 수 없습니다.'; return 3 }
        & $python.Source (Join-Path $PSScriptRoot 'analyze-python.py') @common | Out-Host
        $processCode = $LASTEXITCODE
        return $processCode
    }
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($null -eq $node) { Write-Error 'Node.js 런타임을 찾을 수 없습니다.'; return 3 }
    if ($TypeScriptPath) { $common += @('--typescript-path', $TypeScriptPath) }
    & $node.Source (Join-Path $PSScriptRoot 'analyze-js-ts.mjs') @common | Out-Host
    $processCode = $LASTEXITCODE
    return $processCode
}

function Test-RepositoryFile {
    param([string]$Start, [ValidateSet('python', 'js')][string]$Language)
    $excluded = @('.git', '.hg', '.venv', 'venv', 'node_modules', 'dist', 'build', 'coverage', '__pycache__')
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($Start)
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        foreach ($file in [IO.Directory]::EnumerateFiles($current)) {
            $name = [IO.Path]::GetFileName($file)
            if ($Language -eq 'python' -and ($name -eq 'pyproject.toml' -or $name -eq 'setup.cfg' -or $name -eq 'setup.py' -or $name.EndsWith('.py'))) { return $true }
            if ($Language -eq 'js' -and $name -eq 'package.json') { return $true }
        }
        foreach ($directory in [IO.Directory]::EnumerateDirectories($current)) {
            $name = [IO.Path]::GetFileName($directory)
            if ($name -notin $excluded -and -not $name.StartsWith('.')) { $pending.Push($directory) }
        }
    }
    return $false
}

try {
    $resolvedRoot = [IO.Path]::GetFullPath($Root)
    if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) { throw "root 디렉터리를 찾을 수 없습니다: $resolvedRoot" }
    if ($Command -eq 'trace' -and [string]::IsNullOrWhiteSpace($Entry)) { Write-Error 'trace에는 -Entry 또는 --entry가 필요합니다.'; exit 2 }
    $hasPython = Test-RepositoryFile -Start $resolvedRoot -Language python
    $hasJs = Test-RepositoryFile -Start $resolvedRoot -Language js
    $language = $null
    if ($Command -eq 'trace') {
        $entryPath = ($Entry -split '#')[0]
        $entryPath = $entryPath -replace ':\d+$', ''
        if ($entryPath -match '\.py$') { $language = 'python' }
        elseif ($entryPath -match '\.[cm]?[jt]sx?$') { $language = 'js' }
        elseif ($hasPython -and -not $hasJs) { $language = 'python' }
        elseif ($hasJs -and -not $hasPython) { $language = 'js' }
        else { Write-Error 'entry 언어를 결정할 수 없습니다. 파일 확장자를 포함하십시오.'; exit 2 }
    }
    elseif ($hasPython -and -not $hasJs) { $language = 'python' }
    elseif ($hasJs -and -not $hasPython) { $language = 'js' }
    elseif (-not $hasPython -and -not $hasJs) { Write-Error '지원하는 Python 또는 JS/TS 소스를 찾지 못했습니다.'; exit 2 }

    $resolvedOutput = [IO.Path]::GetFullPath($Output)
    if ($language) {
        $code = Invoke-Analyzer -Language $language -Destination $resolvedOutput
        exit $code
    }

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('reverse-engineer-service-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    try {
        $pythonOutput = Join-Path $tempRoot 'python.json'
        $jsOutput = Join-Path $tempRoot 'js.json'
        $pythonCode = Invoke-Analyzer -Language python -Destination $pythonOutput
        if ($pythonCode -notin @(0, 4)) { exit $pythonCode }
        $jsCode = Invoke-Analyzer -Language js -Destination $jsOutput
        if ($jsCode -notin @(0, 4)) { exit $jsCode }
        $pythonFacts = Get-Content -Raw -LiteralPath $pythonOutput | ConvertFrom-Json
        $jsFacts = Get-Content -Raw -LiteralPath $jsOutput | ConvertFrom-Json
        $digestText = @($pythonFacts.snapshot.source_digest, $jsFacts.snapshot.source_digest) -join "`n"
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $digest = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($digestText)))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
        $merged = [ordered]@{
            schema_version = '1.0.0'
            snapshot = [ordered]@{ git_commit = $pythonFacts.snapshot.git_commit; dirty = $pythonFacts.snapshot.dirty; source_digest = $digest }
            tools = @($pythonFacts.tools) + @($jsFacts.tools) | Sort-Object name, version -Unique
            capabilities = @($pythonFacts.capabilities) + @($jsFacts.capabilities) | Sort-Object -Unique
            entrypoints = @($pythonFacts.entrypoints) + @($jsFacts.entrypoints) | Sort-Object path, symbol, kind, evidence -Unique
            modules = @($pythonFacts.modules) + @($jsFacts.modules) | Sort-Object path -Unique
            symbols = @($pythonFacts.symbols) + @($jsFacts.symbols) | Sort-Object path, start_line, name -Unique
            edges = @($pythonFacts.edges) + @($jsFacts.edges) | Sort-Object from, type, to, line -Unique
            read_set = @()
            diagnostics = @($pythonFacts.diagnostics) + @($jsFacts.diagnostics) | Sort-Object level, code, message -Unique
        }
        $parent = Split-Path -Parent $resolvedOutput
        if ($parent) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
        $json = $merged | ConvertTo-Json -Depth 12
        [IO.File]::WriteAllText($resolvedOutput, ($json + "`n"), (New-Object Text.UTF8Encoding($false)))
        Write-Host "mixed discover: entrypoints=$($merged.entrypoints.Count) modules=$($merged.modules.Count) symbols=$($merged.symbols.Count) edges=$($merged.edges.Count)"
        if ($pythonCode -eq 4 -or $jsCode -eq 4) { exit 4 }
        exit 0
    }
    finally {
        $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
        if ($resolvedTemp.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedTemp).StartsWith('reverse-engineer-service-')) {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 4
}
