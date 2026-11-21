# sing-box 鸿蒙客户端

适用于运行 HarmonyOS 7（API 26）的 ARM64 手机和平板，已在 Mate 70 Pro 和 MatePad mini 上验证。界面使用 ArkTS，系统 VPN 扩展创建 TUN，sing-box 内核从本仓库源码编译。

## 导入配置和连接

1. 在应用里选择 **导入文件** 或 **粘贴 JSON**，导入完整的 UTF-8 sing-box JSON，单份配置最大 4 MiB。也可以添加返回完整 sing-box JSON 的 **HTTPS 订阅**。应用最多保存八份配置，订阅下载或格式检查失败时保留旧配置。
2. 在底部 **配置** 页选择 **编辑**，可在全屏编辑器修改 JSON、查看行号和语法高亮，并一键格式化。鸿蒙 VPN 需要一个带地址并启用 `auto_route` 的 `tun` 入站。如果提示缺少 TUN 或路由设置不适用，点 **适配鸿蒙并保存**。应用会按需添加 TUN，或将现有 TUN 改为默认 Go 栈并移除 Linux 专用的 `auto_redirect`。引用原入站标签的分流规则仍只匹配原入站。
3. 选择配置，点 **连接**，首次连接时在系统提示中授权。首页显示当前配置、连接时长和节点组的已选节点，支持断开和手动重连。Wi-Fi 和移动数据切换后，请重连以重新选择底层网络。
4. 配置里有出站组时，连接后可以点 **测速** 查看延迟，并在 `selector` 组里用 **切换** 选择节点。遇到故障时可用 **复制诊断信息** 导出近期错误，内容不含订阅地址和配置正文。

系统将 sing-box 自身的连接排除在 VPN 路由之外，避免出站流量回到 TUN。对于包含 HTTP、SOCKS 或 mixed 入站、同时缺少 DNS 段的配置，客户端启动时会使用底层网络的 DNS，并为 TUN 添加域名识别和 DNS 接管规则。

在这类桌面配置中，匹配简单 `domain` 或 `domain_suffix` 规则并直达 Shadowsocks 出站的域名使用 FakeIP。内核恢复域名后将其交给节点解析，其他域名继续使用底层网络的 DNS。这些调整只应用于启动时的配置副本，用户提供的 JSON 和显式 DNS 配置会保留。

## 在 Windows 上构建和签名

安装带 API 26 HarmonyOS SDK 的 DevEco Studio，以及用于自举的 Windows Go（1.24.6 或更新版本）。在仓库根目录用 PowerShell 运行：

```powershell
./clients/harmonyos/scripts/bootstrap-go.ps1 -BootstrapRoot 'C:\Program Files\Go'
./clients/harmonyos/scripts/check-core.ps1 -Stage
./clients/harmonyos/scripts/build-hap.ps1
```

DevEco Studio 装在其他位置时，可以用 `-DevEcoSdk` 和 `-DevEco` 指定路径。第一步从源码构建固定版本的 [OpenHarmony Go 工具链](https://github.com/star4277/ohos-go/tree/19667c7abfc332f848b5bd1f293e4aeb0e9991a9)。第二步编译内核，并检查 ARM64 ELF 和 TLS 重定位。HAP 输出在 `clients/harmonyos/entry/build/default/outputs/default/`。

真机调试时，用 DevEco Studio 打开 `clients/harmonyos`。在手机或平板开启开发者模式和 USB 调试，在 **Project Structure → Signing Configs** 为 `com.sagernet.singbox.harmony` 配置自动调试签名。确认工程级 `build-profile.json5` 的 `default` 产品引用了已生成的 `signingConfig`。新增平板时，调试 Profile 需要包含该平板的 UDID。可用 DevEco Studio 的 **Run** 部署，也可重新构建后安装签名包。

```powershell
hdc install -r clients/harmonyos/entry/build/default/outputs/default/entry-default-signed.hap
```

## 真机验证

- 先导入 [直连测试配置](direct-test.json)，连接后用手机或平板的浏览器访问普通 HTTPS 网站。断开后，确认 VPN 图标消失且浏览器仍能联网。这份配置只需验证 TUN 和直连，无需代理节点。
- 再用自己的配置测试代理站点。如果直连正常、只有代理站点超时，先核对域名是否命中代理规则，再检查当前网络能否连到节点的 TCP 端口。配置校验通过只说明内核能加载配置。
- 如果连接报错 `2203002`，在系统设置中搜索 **VPN**，断开占用连接的 VPN 后重试。如果列表为空且错误持续，可重启设备，再打开 sing-box 连接。
- 当前订阅格式为完整的 sing-box JSON。Clash/Mihomo 订阅、`ss://` 等单节点链接及按应用分流暂不支持。
