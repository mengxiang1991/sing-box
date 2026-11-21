import { http } from '@kit.NetworkKit';
import { configPath, MAX_CONFIG_BYTES, readText, writeAtomic } from './Files';

export interface Profile {
  id: string;
  name: string;
  config: string;
  url?: string;
}

export interface Profiles {
  active: string;
  items: Profile[];
}

export function loadProfiles(directory: string): Profiles {
  try {
    return JSON.parse(readText(`${directory}/profiles.json`, 64 * 1024 * 1024)) as Profiles;
  } catch (_) {
    try {
      const legacy: Profile = { id: 'local', name: 'sing-box.json', config: readText(configPath(directory), MAX_CONFIG_BYTES) };
      return { active: legacy.id, items: [legacy] };
    } catch (_) {
      return { active: '', items: [] };
    }
  }
}

export function saveProfiles(directory: string, profiles: Profiles): void {
  writeAtomic(`${directory}/profiles.json`, JSON.stringify(profiles));
}

export function activeProfile(profiles: Profiles): Profile | undefined {
  return profiles.items.find((item: Profile): boolean => item.id === profiles.active);
}

interface Inbound {
  type?: string;
  tag?: string;
  address?: string[];
  auto_route?: boolean;
  auto_redirect?: boolean;
  stack?: string;
}

interface Config {
  inbounds?: Inbound[];
  outbounds?: Outbound[];
  dns?: DnsConfig;
  route?: RouteConfig;
}

interface Outbound {
  type?: string;
  tag?: string;
}

interface DnsServer {
  type: string;
  tag: string;
  server?: string;
  inet4_range?: string;
}

interface DnsConfig {
  servers: DnsServer[];
  final: string;
  rules?: DnsRule[];
}

interface DnsRule {
  inbound: string[];
  domain?: string | string[];
  domain_suffix?: string | string[];
  query_type: string[];
  action: string;
  server: string;
}

interface RouteRule {
  inbound?: string[];
  protocol?: string;
  action?: string;
  outbound?: string;
  domain?: string | string[];
  domain_suffix?: string | string[];
}

interface RouteConfig {
  rules?: RouteRule[];
}

function desktopProxyDnsRules(config: Config, inboundTag: string): DnsRule[] {
  const shadowsocks = new Set((config.outbounds ?? []).filter((outbound: Outbound) => outbound.type === 'shadowsocks')
    .map((outbound: Outbound) => outbound.tag));
  const result: DnsRule[] = [];
  for (const rule of config.route?.rules ?? []) {
    const simpleDomainMatch = Object.keys(rule).every((key: string) =>
      key === 'domain' || key === 'domain_suffix' || key === 'action' || key === 'outbound');
    if (simpleDomainMatch && (rule.domain || rule.domain_suffix) && rule.outbound && shadowsocks.has(rule.outbound) &&
      (!rule.action || rule.action === 'route')) {
      result.push({ inbound: [inboundTag], domain: rule.domain, domain_suffix: rule.domain_suffix,
        query_type: ['A', 'AAAA'], action: 'route', server: 'harmony-proxy-dns' });
    }
  }
  return result;
}

// A desktop HTTP/SOCKS listener receives domain names from the proxy client.
// TUN receives packets addressed to IPs and must also handle system DNS queries.
export function prepareVpnProfile(config: string, nameservers: string[]): string {
  const parsed = JSON.parse(config) as Config;
  const inbounds = parsed.inbounds ?? [];
  const tunnel = inbounds.find((item: Inbound) => item.type === 'tun');
  const desktop = inbounds.some((item: Inbound) => item.type === 'http' || item.type === 'socks' || item.type === 'mixed');
  if (!desktop || !tunnel || parsed.dns !== undefined) {
    return config;
  }
  const server = nameservers.find((address: string) => address.length > 0 && !address.includes(':')) ??
    nameservers.find((address: string) => address.length > 0 && !address.toLowerCase().startsWith('fe80:'));
  if (!server) {
    throw new Error('当前网络没有可用的 DNS 服务器');
  }
  let tag = tunnel.tag;
  if (!tag) {
    const tags = new Set(inbounds.map((item: Inbound) => item.tag ?? ''));
    tag = 'harmony-tun';
    while (tags.has(tag)) { tag += '-vpn'; }
    tunnel.tag = tag;
  }
  const resolver: DnsServer = { type: 'udp', tag: 'harmony-system-dns', server: server };
  parsed.dns = { servers: [resolver], final: resolver.tag };
  const proxyDnsRules = desktopProxyDnsRules(parsed, tag);
  if (proxyDnsRules.length > 0) {
    // FakeIP lets the TUN restore the destination domain before dialing Shadowsocks.
    const proxyDns: DnsServer = { type: 'fakeip', tag: 'harmony-proxy-dns', inet4_range: '198.18.0.0/15' };
    parsed.dns.servers.push(proxyDns);
    parsed.dns.rules = proxyDnsRules;
  }
  const sniff: RouteRule = { inbound: [tag], action: 'sniff' };
  const dns: RouteRule = { inbound: [tag], protocol: 'dns', action: 'hijack-dns' };
  const route: RouteConfig = parsed.route ?? {};
  route.rules = [sniff, dns, ...(route.rules ?? [])];
  parsed.route = route;
  return JSON.stringify(parsed);
}

export function checkProfile(config: string, adaptTun: boolean = false): string {
  let parsed: Config;
  try {
    parsed = JSON.parse(config) as Config;
  } catch (_) {
    throw new Error('JSON 格式错误，请粘贴完整配置，去掉注释、代码块标记和多余逗号');
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed) ||
    (parsed.inbounds !== undefined && !Array.isArray(parsed.inbounds))) {
    throw new Error('配置必须是完整的 sing-box JSON 对象，inbounds 必须是列表');
  }
  const inbounds = parsed.inbounds ?? [];
  if (inbounds.length === 0 && (!Array.isArray(parsed.outbounds) || parsed.outbounds.length === 0)) {
    throw new Error('配置没有入站或出站，请粘贴完整的 sing-box 配置');
  }
  const tunnels = inbounds.filter((item: Inbound) => item?.type === 'tun');
  if (tunnels.length === 0) {
    if (adaptTun) {
      const tunnel: Inbound = { type: 'tun', address: ['172.19.0.1/30'], auto_route: true };
      parsed.inbounds = [...inbounds, tunnel];
      return JSON.stringify(parsed);
    }
    throw new Error('这份配置没有 TUN 入站，请选「适配鸿蒙并保存」添加鸿蒙 VPN 入站');
  }
  if (tunnels.length > 1) {
    throw new Error('鸿蒙 VPN 需要恰好一个 TUN 入站，请确认要保留哪一个');
  }
  const tunnel = tunnels[0];
  if (adaptTun) {
    tunnel.auto_route = true;
    tunnel.auto_redirect = undefined;
    tunnel.stack = undefined;
    return JSON.stringify(parsed);
  }
  if (tunnel.stack && tunnel.stack !== 'go') {
    throw new Error('TUN 使用了其他网络栈，请选「适配鸿蒙并保存」切换到默认 Go 栈');
  }
  if (tunnel.auto_redirect || tunnel.auto_route !== true) {
    throw new Error('TUN 路由设置不适用，请选「适配鸿蒙并保存」启用 auto_route 并关闭 auto_redirect');
  }
  return config;
}

export function validateProfile(config: string): void {
  checkProfile(config);
}

export async function fetchProfile(url: string): Promise<string> {
  if (!/^https:\/\/[^\s]+$/i.test(url)) {
    throw new Error('请输入 HTTPS 订阅地址');
  }
  const request = http.createHttp();
  try {
    const response = await request.request(url, {
      method: http.RequestMethod.GET, expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000, readTimeout: 15000, maxLimit: MAX_CONFIG_BYTES
    });
    if (response.responseCode !== 200 || typeof response.result !== 'string') {
      throw new Error('订阅下载失败');
    }
    validateProfile(response.result);
    return response.result;
  } finally {
    request.destroy();
  }
}
