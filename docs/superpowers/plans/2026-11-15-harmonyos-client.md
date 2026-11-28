# HarmonyOS client implementation plan

Build a native ARM64 HAP for the Mate 70 Pro on HarmonyOS 7 using the sing-box source in this checkout.

1. Bootstrap an OpenHarmony-capable Go compiler and verify that it can produce an ARM64 shared library with the DevEco SDK. Then build the current `experimental/libbox` and resolve target-specific dependency failures.
2. Connect the Go core to ArkTS with N-API. Create the TUN from `libbox.TunOptions` in `VpnExtensionAbility`, hand its descriptor to the core, and protect outbound sockets before they connect. Shut down the core and destroy the VPN on failed startup or stop.
3. Add a native screen to import sing-box JSON, start and stop the extension, and display its actual state and recent errors. Store configuration privately and avoid writing configuration contents to logs.
4. Build and sign the debug HAP. On the phone, verify first-use VPN authorization, traffic via a supplied configuration, disconnect, and recovery after invalid configuration or a declined authorization.
