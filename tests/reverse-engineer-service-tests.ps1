[CmdletBinding()]
param([string]$TypeScriptPath)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Expected {
    param([string]$Path, [string[]]$Arguments, [int]$ExitCode)
    & $Path @Arguments | Out-Host
    if ($LASTEXITCODE -ne $ExitCode) { throw "예상하지 못한 종료 코드: expected=$ExitCode actual=$LASTEXITCODE" }
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$skillRoot = Join-Path $repositoryRoot 'skills/reverse-engineer-service'
$analyzer = Join-Path $skillRoot 'scripts/analyze-code.ps1'
$pythonFixture = Join-Path $PSScriptRoot 'fixtures/reverse-engineer-service/python'
$invalidPythonFixture = Join-Path $PSScriptRoot 'fixtures/reverse-engineer-service/python-invalid'
$typescriptFixture = Join-Path $PSScriptRoot 'fixtures/reverse-engineer-service/typescript'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('reverse-engineer-service-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null

try {
    $discoverOne = Join-Path $temporaryRoot 'python-discover-1.json'
    $discoverTwo = Join-Path $temporaryRoot 'python-discover-2.json'
    Invoke-Expected $analyzer @('discover', '--root', $pythonFixture, '--output', $discoverOne) 0
    Invoke-Expected $analyzer @('discover', '--root', $pythonFixture, '--output', $discoverTwo) 0
    Assert-True ((Get-FileHash $discoverOne).Hash -eq (Get-FileHash $discoverTwo).Hash) 'Python discover 결과가 결정적이지 않습니다.'
    $pythonFacts = Get-Content -Raw $discoverOne | ConvertFrom-Json
    Assert-True ($pythonFacts.schema_version -eq '1.0.0') 'schema_version이 올바르지 않습니다.'
    Assert-True ($pythonFacts.entrypoints.Count -ge 3) 'Python entrypoint 후보가 부족합니다.'
    Assert-True (($pythonFacts.edges | Where-Object type -eq 'registers').Count -ge 2) 'Python 등록 edge를 찾지 못했습니다.'
    Assert-True (@($pythonFacts.edges | Where-Object { $_.type -eq 'imports' -and $_.to -eq 'external:fastapi.APIRouter' }).Count -eq 1) 'Python absolute import가 잘못 해석되었습니다.'
    Assert-True (-not ((Get-Content -Raw $discoverOne).Contains('/orders'))) 'route 리터럴이 출력되었습니다.'
    Assert-True (-not ((Get-Content -Raw $discoverOne).Contains('fixture-secret-value-should-not-leak'))) '소스 리터럴이 출력되었습니다.'

    $trace = Join-Path $temporaryRoot 'python-trace.json'
    Invoke-Expected $analyzer @('trace', '--root', $pythonFixture, '--entry', 'src/sample/api.py#post_order', '--max-depth', '4', '--max-nodes', '40', '--output', $trace) 0
    $traceFacts = Get-Content -Raw $trace | ConvertFrom-Json
    Assert-True ($traceFacts.read_set.Count -ge 1) 'Python trace read_set이 비었습니다.'
    Assert-True (@($traceFacts.read_set | Where-Object { $_.path -eq 'src/sample/api.py' -and $_.start_line -eq 8 }).Count -eq 1) 'decorator가 read_set에서 빠졌습니다.'
    Assert-True (($traceFacts.edges | Where-Object type -eq 'calls').Count -ge 1) 'Python 호출 edge가 없습니다.'

    $limitedTrace = Join-Path $temporaryRoot 'python-limited.json'
    Invoke-Expected $analyzer @('trace', '--root', $pythonFixture, '--entry', 'src/sample/api.py#post_order', '--max-depth', '0', '--output', $limitedTrace) 0
    Assert-True (@((Get-Content -Raw $limitedTrace | ConvertFrom-Json).diagnostics | Where-Object code -eq 'trace-truncated').Count -eq 1) 'trace 제한 진단이 없습니다.'

    Invoke-Expected $analyzer @('trace', '--root', $pythonFixture, '--entry', 'missing.py', '--output', (Join-Path $temporaryRoot 'missing.json')) 2
    Invoke-Expected $analyzer @('discover', '--root', $invalidPythonFixture, '--output', (Join-Path $temporaryRoot 'invalid-python.json')) 4

    $jsDiscover = Join-Path $temporaryRoot 'js-discover.json'
    $jsArgs = @('discover', '--root', $typescriptFixture, '--output', $jsDiscover)
    if ($TypeScriptPath) { $jsArgs += @('--typescript-path', $TypeScriptPath) }
    Invoke-Expected $analyzer $jsArgs 0
    $jsFacts = Get-Content -Raw $jsDiscover | ConvertFrom-Json
    Assert-True ($jsFacts.entrypoints.Count -ge 2) 'JS/TS manifest entrypoint를 찾지 못했습니다.'
    if ($TypeScriptPath) {
        Assert-True ($jsFacts.capabilities -contains 'typescript-compiler-api') 'TypeScript semantic capability가 없습니다.'
        Assert-True (($jsFacts.edges | Where-Object type -eq 'registers').Count -ge 2) 'TypeScript 등록 edge를 찾지 못했습니다.'
        $jsTrace = Join-Path $temporaryRoot 'js-trace.json'
        Invoke-Expected $analyzer @('trace', '--root', $typescriptFixture, '--entry', 'src/server.ts#postOrder', '--typescript-path', $TypeScriptPath, '--output', $jsTrace) 0
        Assert-True ((Get-Content -Raw $jsTrace | ConvertFrom-Json).read_set.Count -ge 1) 'TypeScript trace read_set이 비었습니다.'
    }
    else {
        Assert-True ($jsFacts.capabilities -contains 'manifest-only') 'manifest-only fallback이 표시되지 않았습니다.'
        Invoke-Expected $analyzer @('trace', '--root', $typescriptFixture, '--entry', 'src/server.ts#postOrder', '--output', (Join-Path $temporaryRoot 'js-trace.json')) 3
    }

    foreach ($factsPath in @($discoverOne, $trace, $jsDiscover)) {
        $facts = Get-Content -Raw $factsPath | ConvertFrom-Json
        foreach ($name in @('snapshot', 'tools', 'capabilities', 'entrypoints', 'modules', 'symbols', 'edges', 'read_set', 'diagnostics')) {
            Assert-True ($null -ne $facts.$name) "필수 필드가 없습니다: $name"
        }
        Assert-True ($facts.snapshot.source_digest -match '^[a-f0-9]{64}$') 'source_digest 형식이 올바르지 않습니다.'
    }
    $schema = Get-Content -Raw (Join-Path $skillRoot 'scripts/code-facts.schema.json') | ConvertFrom-Json
    Assert-True ($schema.properties.schema_version.const -eq '1.0.0') 'JSON Schema를 읽지 못했습니다.'
    Write-Host '[ok] reverse-engineer-service 분석기 테스트를 통과했습니다.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($temporaryRoot)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('reverse-engineer-service-tests-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
