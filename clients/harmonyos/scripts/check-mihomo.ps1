param(
    [string]$DevEcoSdk = 'C:\Program Files\Huawei\DevEco Studio\sdk',
    [switch]$Stage
)

$ErrorActionPreference = 'Stop'
$clientRoot = Split-Path $PSScriptRoot -Parent
$buildRoot = Join-Path $clientRoot '.core-build'
$go = Join-Path $buildRoot 'ohos-go/bin/go.exe'
$native = Join-Path $DevEcoSdk 'default/openharmony/native'
$clang = Join-Path $native 'llvm/bin/clang.exe'
$readelf = Join-Path $native 'llvm/bin/llvm-readelf.exe'
$artifact = Join-Path $buildRoot 'libmihomo.so'
$settings = @{
    GOOS = 'openharmony'
    GOARCH = 'arm64'
    GOTOOLCHAIN = 'local'
    CGO_ENABLED = '1'
    CC = '"{0}" --target=aarch64-linux-ohos "--sysroot={1}" -D__MUSL__' -f $clang, (Join-Path $native 'sysroot')
    CGO_CFLAGS = '-O2 -ftls-model=global-dynamic'
    GOCACHE = Join-Path $buildRoot 'go-cache'
    GOMODCACHE = Join-Path $buildRoot 'go-mod-cache'
}
$previous = @{}
Push-Location (Join-Path $clientRoot 'mihomo')
try {
    foreach ($name in $settings.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $settings[$name])
    }
    & $go build -mod=readonly -trimpath -buildmode=c-shared -ldflags '-s -w -checklinkname=0 -linkmode external -extldflags=-Wl,-soname,libmihomo.so,-z,lazy' -o $artifact .
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile Mihomo for OpenHarmony ARM64.' }
    $headers = & $readelf -h -l $artifact | Out-String
    if ($LASTEXITCODE -ne 0 -or $headers -notmatch 'AArch64' -or $headers -notmatch '\bTLS\b') {
        throw 'Expected an AArch64 shared library with a TLS segment.'
    }
    $relocations = & $readelf -r $artifact | Out-String
    if ($LASTEXITCODE -ne 0 -or $relocations -notmatch 'R_AARCH64_TLSDESC' -or $relocations -match 'R_AARCH64_TLS_TPREL') {
        throw 'Expected TLSDESC without initial-exec TLS relocations.'
    }
    if ($Stage) {
        $libs = Join-Path $clientRoot 'entry/libs/arm64-v8a'
        New-Item -ItemType Directory -Path $libs -Force | Out-Null
        Copy-Item -LiteralPath $artifact -Destination $libs
    }
    Write-Output $artifact
} finally {
    foreach ($name in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name])
    }
    Pop-Location
}
