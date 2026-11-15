param(
    [Parameter(Mandatory = $true)]
    [string]$BootstrapRoot
)

$ErrorActionPreference = 'Stop'
$clientRoot = Split-Path $PSScriptRoot -Parent
$buildRoot = Join-Path $clientRoot '.core-build'
$sourceRoot = Join-Path $buildRoot 'ohos-go'
$revision = '19667c7abfc332f848b5bd1f293e4aeb0e9991a9'
$bootstrap = (Resolve-Path -LiteralPath $BootstrapRoot).Path
if (!(Test-Path -LiteralPath (Join-Path $bootstrap 'bin/go.exe'))) {
    throw 'BootstrapRoot must point to a Go installation (Go 1.24.6 or newer).'
}

New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
if (!(Test-Path -LiteralPath $sourceRoot)) {
    git clone --depth 1 --single-branch --branch v1.26.5-beta1 https://github.com/star4277/ohos-go.git $sourceRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not clone the OpenHarmony Go toolchain.' }
}
$actualRevision = git -C $sourceRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $actualRevision -ne $revision) {
    throw "Expected OpenHarmony Go revision $revision in $sourceRoot."
}

$previousBootstrap = $env:GOROOT_BOOTSTRAP
$previousToolchain = $env:GOTOOLCHAIN
$previousCache = $env:GOCACHE
Push-Location (Join-Path $sourceRoot 'src')
try {
    $env:GOROOT_BOOTSTRAP = $bootstrap
    $env:GOTOOLCHAIN = 'local'
    $env:GOCACHE = Join-Path $buildRoot 'go-cache'
    & .\make.bat
    if ($LASTEXITCODE -ne 0) { throw 'Could not bootstrap OpenHarmony Go.' }
} finally {
    $env:GOROOT_BOOTSTRAP = $previousBootstrap
    $env:GOTOOLCHAIN = $previousToolchain
    $env:GOCACHE = $previousCache
    Pop-Location
}

$targets = & (Join-Path $sourceRoot 'bin/go.exe') tool dist list
if ($LASTEXITCODE -ne 0 -or $targets -notcontains 'openharmony/arm64') {
    throw 'The compiler does not report an openharmony/arm64 target.'
}
