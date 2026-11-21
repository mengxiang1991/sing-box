# sing-box

The universal proxy platform.

[![Packaging status](https://repology.org/badge/vertical-allrepos/sing-box.svg)](https://repology.org/project/sing-box/versions)

## Documentation

https://sing-box.sagernet.org

## HarmonyOS client

This branch includes a native ArkTS client for ARM64 phones and tablets running HarmonyOS 7 (API 26), including the MatePad mini. The client builds the sing-box core from this repository and uses the system VPN extension for TUN routing. It supports local and pasted JSON, HTTPS JSON subscriptions, and outbound selection and latency testing. Imported configurations can be edited in a full-screen JSON editor with syntax highlighting, line numbers, and formatting.

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
