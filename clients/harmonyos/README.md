# sing-box 鸿蒙客户端

适用于运行 HarmonyOS 7（API 26）的 ARM64 手机和平板，已在 Mate 70 Pro 和 MatePad mini 上验证。界面使用 ArkTS，系统 VPN 扩展创建 TUN，sing-box 内核从本仓库源码编译。

## 导入配置和连接

1. 在 **配置** 页点 **添加配置**，选择 **sing-box**，然后导入文件、粘贴配置或输入 HTTPS 订阅地址。sing-box 配置应为完整的 UTF-8 JSON，单份最大 4 MiB。应用最多保存八份配置，订阅下载或格式检查失败时保留旧配置。
2. 在底部 **配置** 页选择 **编辑**，可在全屏编辑器修改 JSON、查看行号和语法高亮，并一键格式化。鸿蒙 VPN 需要一个带地址并启用 `auto_route` 的 `tun` 入站。如果提示缺少 TUN 或路由设置不适用，点 **适配鸿蒙并保存**。应用会按需添加 TUN，或将现有 TUN 改为默认 Go 栈并移除 Linux 专用的 `auto_redirect`。引用原入站标签的分流规则仍只匹配原入站。
3. 选择配置，点 **连接**，首次连接时在系统提示中授权。首页显示当前配置、连接时长和节点组的已选节点，支持断开和手动重连。Wi-Fi 和移动数据切换后，请重连以重新选择底层网络。
4. 配置里有出站组时，连接后可以点 **测速** 查看延迟，并在 `selector` 组里用 **切换** 选择节点。遇到故障时可用 **复制诊断信息** 导出近期错误，内容不含订阅地址和配置正文。
5. 在配置卡片上点 **重命名** 可修改显示名称。配置内容、订阅地址和当前选用状态会保留。

### Clash / Mihomo

使用包含 Mihomo 的安装包时，在 **添加配置** 页选择 **Clash**，然后导入文件、粘贴配置或添加订阅。订阅应返回完整的 Mihomo 配置。应用保存 YAML 原文，并用 Mihomo 运行其中的节点组、分流、DNS、`proxy-providers` 和 `rule-providers`。配置卡片和连接页显示 **sing-box** 或 **Clash**，来源单独标为本地或订阅。每张订阅卡片可直接更新自己的订阅。

编辑 YAML 时，可点 **规则** 增加、修改、移除或调整顶层规则的顺序。点 **应用** 校验规则，再点 **保存** 写入配置。连接后可切换规则、全局和直连模式，查看并关闭活动连接，或在 **节点** 页测速、切换节点、请求刷新 HTTP 提供者。

链式代理在出站节点上用 `dialer-proxy` 指定前置节点或节点组。配置完成后，节点页会显示链式前置。旧版 `relay` 节点组可按 [Mihomo 迁移说明](https://wiki.metacubex.one/config/proxies/dialer-proxy/) 改写。

鸿蒙系统管理 TUN、地址和路由。Mihomo 运行时使用鸿蒙的虚拟网卡，并关闭桌面配置里的代理监听端口、外部控制面板和系统路由修改。依赖桌面本地文件的提供者需要相应资源，推荐使用 HTTPS 或内联提供者。Clash Verge Rev 的桌面脚本、配置合并和 WebDAV 同步不属于 YAML 内核功能。

系统将 sing-box 自身的连接排除在 VPN 路由之外，避免出站流量回到 TUN。对于包含 HTTP、SOCKS 或 mixed 入站、同时缺少 DNS 段的配置，客户端启动时会使用底层网络的 DNS，并为 TUN 添加域名识别和 DNS 接管规则。

在这类桌面配置中，匹配简单 `domain` 或 `domain_suffix` 规则并直达 Shadowsocks 出站的域名使用 FakeIP。内核恢复域名后将其交给节点解析，其他域名继续使用底层网络的 DNS。这些调整只应用于启动时的配置副本，用户提供的 JSON 和显式 DNS 配置会保留。

## 在 Windows 上构建和签名

安装带 API 26 HarmonyOS SDK 的 DevEco Studio，以及用于自举的 Windows Go（1.24.6 或更新版本）。在仓库根目录用 PowerShell 运行：

```powershell
./clients/harmonyos/scripts/bootstrap-go.ps1 -BootstrapRoot 'C:\Program Files\Go'
./clients/harmonyos/scripts/check-core.ps1 -Stage
./clients/harmonyos/scripts/build-hap.ps1
```

需要同时支持 sing-box 和 Clash 时，将最后一条构建命令替换为 `./clients/harmonyos/scripts/build-hap.ps1 -WithMihomo`。该选项会编译固定版本的 Mihomo 并随 HAP 打包。

DevEco Studio 装在其他位置时，可以用 `-DevEcoSdk` 和 `-DevEco` 指定路径。第一步从源码构建固定版本的 [OpenHarmony Go 工具链](https://github.com/star4277/ohos-go/tree/19667c7abfc332f848b5bd1f293e4aeb0e9991a9)。第二步编译内核，并检查 ARM64 ELF 和 TLS 重定位。HAP 输出在 `clients/harmonyos/entry/build/default/outputs/default/`。

真机调试时，用 DevEco Studio 打开 `clients/harmonyos`。在手机或平板开启开发者模式和 USB 调试，在 **Project Structure → Signing Configs** 为 `com.sagernet.singbox.harmony` 配置自动调试签名。确认工程级 `build-profile.json5` 的 `default` 产品引用了已生成的 `signingConfig`。新增平板时，调试 Profile 需要包含该平板的 UDID。可用 DevEco Studio 的 **Run** 部署，也可重新构建后安装签名包。

```powershell
hdc list targets
$device = '从 hdc list targets 复制设备标识'
hdc -t $device install -r clients/harmonyos/entry/build/default/outputs/default/entry-default-signed.hap
```

## 真机验证

- 先导入 [直连测试配置](direct-test.json)，连接后用手机或平板的浏览器访问普通 HTTPS 网站。断开后，确认 VPN 图标消失且浏览器仍能联网。这份配置只需验证 TUN 和直连，无需代理节点。
- 再用自己的配置测试代理站点。如果直连正常、只有代理站点超时，先核对域名是否命中代理规则，再检查当前网络能否连到节点的 TCP 端口。配置校验通过只说明内核能加载配置。
- 如果连接报错 `2203002`，在系统设置中搜索 **VPN**，断开占用连接的 VPN 后重试。如果列表为空且错误持续，可重启设备，再打开 sing-box 连接。
- 订阅应返回完整的 sing-box JSON 或 Mihomo YAML。添加时先选对应的配置类型，再填入订阅地址。`ss://` 等单节点链接和按应用分流暂不支持。
