param(
    [string]$DevEcoSdk = 'C:\Program Files\Huawei\DevEco Studio\sdk',
    [switch]$Stage
)

$ErrorActionPreference = 'Stop'
$clientRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = (Resolve-Path (Join-Path $clientRoot '../..')).Path
$buildRoot = Join-Path $clientRoot '.core-build'
$go = Join-Path $buildRoot 'ohos-go/bin/go.exe'
$native = Join-Path $DevEcoSdk 'default/openharmony/native'
$clang = Join-Path $native 'llvm/bin/clang.exe'
$readelf = Join-Path $native 'llvm/bin/llvm-readelf.exe'
foreach ($file in @($go, $clang, $readelf)) {
    if (!(Test-Path -LiteralPath $file)) { throw "Missing build tool: $file" }
}

$probe = Join-Path $buildRoot 'core-probe.go'
@'
package main

import "C"

import "github.com/sagernet/sing-box/experimental/libbox"

//export SBCheckConfig
func SBCheckConfig(config *C.char) C.int {
    if config == nil || libbox.CheckConfig(C.GoString(config)) != nil {
        return 1
    }
    return 0
}

func main() {}
'@ | Set-Content -LiteralPath $probe -Encoding ascii

$artifact = Join-Path $buildRoot 'libsingbox-probe.so'
$source = $probe
if ($Stage) {
    $artifact = Join-Path $buildRoot 'libsingbox.so'
    $source = './clients/harmonyos/core'
}
$settings = @{
    GOOS = 'openharmony'
    GOARCH = 'arm64'
    CGO_ENABLED = '1'
    GOTOOLCHAIN = 'local'
    CC = '"{0}" --target=aarch64-linux-ohos "--sysroot={1}" -D__MUSL__' -f $clang, (Join-Path $native 'sysroot')
    CGO_CFLAGS = '-O2 -ftls-model=global-dynamic'
    GOCACHE = Join-Path $buildRoot 'go-cache'
    GOMODCACHE = Join-Path $buildRoot 'go-mod-cache'
}
$previous = @{}
Push-Location $repoRoot
try {
    foreach ($name in $settings.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $settings[$name])
    }
    & $go build -mod=readonly -trimpath -buildmode=c-shared -tags 'with_gvisor,with_quic,with_utls,with_clash_api' -ldflags '-checklinkname=0 -linkmode external -extldflags "-Wl,-soname,libsingbox.so -Wl,-z,lazy"' -o $artifact $source
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile libbox for OpenHarmony ARM64.' }

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
