[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

try {
    $root = Get-RepositoryRoot
    Push-Location $root
    try {
        $expected = [ordered]@{
            'user.name'      = 'Innnteraction'
            'user.email'     = 'innnteractive@gmail.com'
            'core.hooksPath' = '.githooks'
            'pull.ff'        = 'only'
            'push.default'   = 'current'
            'fetch.prune'    = 'true'
        }

        foreach ($entry in $expected.GetEnumerator()) {
            & git config --local $entry.Key $entry.Value
            if ($LASTEXITCODE -ne 0) {
                throw "Git 로컬 설정을 저장하지 못했습니다: $($entry.Key)"
            }
            $actual = (& git config --local --get $entry.Key).Trim()
            if ($actual -ne $entry.Value) {
                throw "Git 설정 검증에 실패했습니다: $($entry.Key)"
            }
            Write-Host "[ok] $($entry.Key)=$actual"
        }
    }
    finally {
        Pop-Location
    }

    Write-Host '저장소 로컬 Git 설정과 hook 경로를 적용했습니다.'
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
