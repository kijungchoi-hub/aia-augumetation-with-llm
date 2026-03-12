[CmdletBinding()]
param(
    [int]$Port = 8000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue

if (-not $pythonCommand) {
    throw "python 명령을 찾을 수 없습니다. Python 설치 또는 PATH 설정을 확인하세요."
}

$url = "http://localhost:$Port/web/quality-review.html"

Write-Host "Starting local server at $url"
Write-Host "Press Ctrl+C to stop the server."

Push-Location $projectRoot
try {
    & $pythonCommand.Source -m http.server $Port
}
finally {
    Pop-Location
}
