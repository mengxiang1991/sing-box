param(
    [string]$DevEco = 'C:\Program Files\Huawei\DevEco Studio',
    [switch]$WithMihomo,
    [string]$MihomoGeoIPDb
)

$ErrorActionPreference = 'Stop'
$clientRoot = Split-Path $PSScriptRoot -Parent
$core = Join-Path $clientRoot 'entry/libs/arm64-v8a/libsingbox.so'
if (!(Test-Path -LiteralPath $core)) {
    throw 'Run scripts/check-core.ps1 -Stage to build the ARM64 sing-box library first.'
}
if ($WithMihomo) {
    & (Join-Path $PSScriptRoot 'check-mihomo.ps1') -DevEcoSdk (Join-Path $DevEco 'sdk') -Stage
}
if ($MihomoGeoIPDb -and !$WithMihomo) {
    throw '-MihomoGeoIPDb requires -WithMihomo.'
}
$geoResource = Join-Path $clientRoot 'entry/src/main/resources/rawfile/mihomo-country.mmdb'
$stagedGeoIP = $false

Push-Location $clientRoot
try {
    if ($MihomoGeoIPDb) {
        if (Test-Path -LiteralPath $geoResource) { throw "A GEOIP resource is already staged: $geoResource" }
        $stagedGeoIP = $true
        Copy-Item -LiteralPath $MihomoGeoIPDb -Destination $geoResource
    }
    if (!(Test-Path -LiteralPath 'build-profile.json5')) {
        Copy-Item -LiteralPath 'build-profile.example.json5' -Destination 'build-profile.json5'
    }
    $env:JAVA_HOME = Join-Path $DevEco 'jbr'
    $env:DEVECO_SDK_HOME = Join-Path $DevEco 'sdk'
    $env:HVIGOR_USER_HOME = Join-Path $clientRoot '.hvigor-user'
    $env:NODE_PATH = Join-Path $clientRoot 'node_modules'
    $env:PATH = "$(Join-Path $DevEco 'tools/node');$env:PATH"
    $moduleRoot = Join-Path $clientRoot 'node_modules/@ohos'
    New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
    foreach ($module in @('hvigor', 'hvigor-ohos-plugin')) {
        $link = Join-Path $moduleRoot $module
        if (!(Test-Path -LiteralPath $link)) {
            New-Item -ItemType Junction -Path $link -Target (Join-Path $DevEco "tools/hvigor/$module") | Out-Null
        }
    }
    $node = Join-Path $DevEco 'tools/node/node.exe'
    & $node (Join-Path $DevEco 'tools/ohpm/bin/pm-cli.js') install --all
    if ($LASTEXITCODE -ne 0) { throw 'Could not resolve local HarmonyOS dependencies.' }
    & $node (Join-Path $DevEco 'tools/hvigor/hvigor/bin/hvigor.js') --mode module -p product=default -p module=entry@default assembleHap --no-daemon
    if ($LASTEXITCODE -ne 0) { throw 'Could not assemble the HarmonyOS HAP.' }
} finally {
    if ($stagedGeoIP -and (Test-Path -LiteralPath $geoResource)) {
        Remove-Item -LiteralPath $geoResource
    }
    Pop-Location
}
