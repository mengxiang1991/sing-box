# sing-box for HarmonyOS

Native ArkTS client for ARM64 phones running HarmonyOS 7 (API 26). The VPN extension creates the system TUN and passes its descriptor to the sing-box core built from this checkout. The app imports a local JSON file and displays the VPN state and recent errors.

## Build on Windows

Use DevEco Studio with the API 26 HarmonyOS SDK and a Windows Go installation (1.24.6 or newer) as the bootstrap compiler. Run these commands from the repository root in PowerShell.

```powershell
./clients/harmonyos/scripts/bootstrap-go.ps1 -BootstrapRoot 'C:\Program Files\Go'
./clients/harmonyos/scripts/check-core.ps1 -Stage
./clients/harmonyos/scripts/build-hap.ps1
```

Pass `-DevEcoSdk` or `-DevEco` if Studio is installed elsewhere. The first script builds the pinned [OpenHarmony Go toolchain](https://github.com/star4277/ohos-go/tree/19667c7abfc332f848b5bd1f293e4aeb0e9991a9) from source. The next verifies the ARM64 ELF and TLS relocations before staging the library. The HAP is written to `entry/build/default/outputs/default/`.

To install on a physical device, open `clients/harmonyos` in DevEco Studio, enable developer mode and USB debugging on the phone, and set up automatic debug signing for `com.sagernet.singbox.harmony` under **Project Structure → Signing Configs**. Run the HAP build again and install the signed output with `hdc install -r`.

## Configuration and device checks

Import one UTF-8 sing-box JSON file up to 4 MiB. Use one `tun` inbound with an address and `auto_route: true`. Leave `stack` and `auto_redirect` unset to use the default Go stack with system-managed routing. The first version binds to the network selected at connect time. Reconnect after switching between Wi-Fi and cellular. Options for Android package filters and the system HTTP proxy are unsupported.

Start with [direct-test.json](direct-test.json) to check the VPN without a proxy server. On a connected phone, grant the system VPN prompt, confirm the VPN icon appears, and use another app to check DNS and HTTPS. Disconnect and check that the icon disappears and ordinary traffic still works. Repeat with a rejected authorization and an invalid profile to check recovery. Then test your own configuration and proxy server.
