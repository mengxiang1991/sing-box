# sing-box

The universal proxy platform.

[![Packaging status](https://repology.org/badge/vertical-allrepos/sing-box.svg)](https://repology.org/project/sing-box/versions)

## Documentation

https://sing-box.sagernet.org

## 网间拾径 · HarmonyOS client

网间拾径 is the native ArkTS client in this branch for ARM64 phones and tablets running HarmonyOS 7 (API 26), including the MatePad mini. It uses the HarmonyOS VPN extension for TUN routing and supports sing-box profiles and optional Clash profiles through Mihomo.

- Choose **sing-box** or **Clash** under **Add profile**, then import a file, paste a configuration, or add an HTTPS subscription. The configuration list and connection screen show the selected engine.
- sing-box profiles use the existing JSON editor with syntax highlighting, line numbers, and formatting. Clash profiles support a rule editor, Rule / Global / Direct modes, and a live connection list. Both engines support outbound selection and latency testing when the profile provides outbound groups.
- On Windows, build the dual-engine HAP with `clients/harmonyos/scripts/build-hap.ps1 -WithMihomo` after staging the sing-box core. Pass `-MihomoGeoIPDb` with a local `Country.mmdb` file to make GEOIP rules available on first launch without a database download.

See the [HarmonyOS client guide](clients/harmonyos/README.md) for configuration, Windows build steps, debug signing, and on-device testing.

## License

```
Copyright (C) 2022 by nekohasekai <contact-sagernet@sekai.icu>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.

In addition, no derivative work may use the name or imply association
with this application without prior consent.
```
