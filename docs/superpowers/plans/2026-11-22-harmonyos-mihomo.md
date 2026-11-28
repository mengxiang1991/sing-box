# HarmonyOS Mihomo Implementation Plan

**Goal.** Run Clash YAML and subscriptions on HarmonyOS phones and tablets while preserving the existing sing-box JSON experience.

**Architecture.** Use Mihomo for Clash configurations and keep the current sing-box library and configuration path for JSON. The VPN extension owns the system tunnel and hands its descriptor to the selected core. Only one core runs at a time.

- [ ] Build a pinned Mihomo version as an OpenHarmony ARM64 library. Verify loading, descriptor handoff, socket protection, DNS, TCP, UDP, and stop/reconnect on both device types.
- [ ] Add a backward-compatible profile format field. Existing records default to sing-box. Add YAML file, paste and HTTPS subscription support, retaining the last working configuration if validation or refresh fails.
- [ ] Connect Mihomo mode, provider refresh, group selection, latency, and connection data to native ArkUI. Use validated changes to the YAML for rule editing.
- [ ] Verify providers, routing, connection controls and edited rules with reproducible configurations. Verify the existing JSON import, paste, editor, subscription, TUN, and node controls on both targets.
