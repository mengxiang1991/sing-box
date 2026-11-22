import { BusinessError } from '@kit.BasicServicesKit';
import { connection, vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import nativeCore from 'libsb_harmony.so';
import mihomoCore from 'libmh_harmony.so';
import { BUNDLE_NAME, LiveConnection, NodeGroups, readNodeCommand, stopRequested, vpnWant, writeStatus } from '../common/Files';
import { activeProfile, loadProfiles, prepareVpnProfile, ProfileType, profileType } from '../common/Profiles';
import { seedMihomoGeoIP } from '../common/MihomoGeoIP';

interface TunPlan {
  addresses: string[];
  routes: string[];
  dns: string[] | null;
  mtu: number;
}

interface CoreState {
  state: string;
  error?: string;
  tun?: TunPlan;
  groups?: NodeGroups;
  networkError?: string;
  mode?: string;
  connections?: LiveConnection[];
}

function parsePrefix(value: string): connection.LinkAddress {
  const parts = value.split('/');
  const address = parts[0];
  return {
    address: { address: address, family: address.includes(':') ? 2 : 1, port: 0 },
    prefixLength: Number(parts[1])
  };
}

function vpnConfig(plan: TunPlan): vpnExtension.VpnConfig {
  const addresses = plan.addresses.map((prefix: string) => parsePrefix(prefix));
  const routes = plan.routes.map((prefix: string): connection.RouteInfo => {
    const destination = parsePrefix(prefix);
    const v6 = destination.address.family === 2;
    return {
      interface: 'vpn-tun', destination: destination,
      gateway: { address: v6 ? '::' : '0.0.0.0', family: destination.address.family, port: 0 },
      hasGateway: false, isDefaultRoute: destination.prefixLength === 0
    };
  });
  return {
    addresses: addresses, routes: routes, mtu: plan.mtu, dnsAddresses: plan.dns ?? [],
    // Keep sockets opened by the VPN app itself on the underlying network.
    blockedApplications: [BUNDLE_NAME],
    isIPv4Accepted: addresses.some((address: connection.LinkAddress) => address.address.family === 1),
    isIPv6Accepted: addresses.some((address: connection.LinkAddress) => address.address.family === 2)
  };
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => { setTimeout(resolve, ms); });
}

export default class VpnAbility extends VpnExtensionAbility {
  private vpn?: vpnExtension.VpnConnection;
  private stopping: boolean = false;
  private creation?: Promise<number>;
  private destroyTask?: Promise<void>;
  private shutdownReady: boolean = false;
  private shutdownError?: string;
  private mihomo: boolean = false;

  onCreate(): void {
    this.run();
  }

  onDestroy(): void {
    this.stopping = true;
    this.stopCore();
    this.destroyVpn().catch(() => {});
    if (this.shutdownReady) {
      this.publishStopped(this.shutdownError);
    }
  }

  private publishStopped(error?: string): void {
    try {
      writeStatus(this.context.filesDir, 'stopped', error);
    } catch (_) {
      // The UI also treats an expired heartbeat as a stopped extension.
    }
  }

  private stopCore(): void {
    if (this.mihomo) {
      mihomoCore.stop();
    } else {
      nativeCore.stop();
    }
  }

  private coreState(): CoreState {
    return JSON.parse(this.mihomo ? mihomoCore.status() : nativeCore.status()) as CoreState;
  }

  private destroyVpn(): Promise<void> {
    if (this.destroyTask === undefined) {
      this.destroyTask = this.destroyAfterCreation();
    }
    return this.destroyTask;
  }

  private async destroyAfterCreation(): Promise<void> {
    if (this.creation !== undefined) {
      try {
        await this.creation;
      } catch (_) {
        return;
      }
      await this.vpn?.destroy();
    }
  }

  private async createSystemVpn(vpn: vpnExtension.VpnConnection, config: vpnExtension.VpnConfig): Promise<number> {
    try {
      return await vpn.create(config);
    } catch (error) {
      const failure = error as BusinessError;
      if (failure.code !== 2203002 || this.stopping) {
        return Promise.reject(failure);
      }
      // A previous extension may have left this app's system VPN registered.
      await vpn.destroy();
      if (this.stopping) {
        return Promise.reject(failure);
      }
      return await vpn.create(config);
    }
  }

  private async run(): Promise<void> {
    const directory = this.context.filesDir;
    const startedAt = Date.now();
    let error: string | undefined;
    let stage = '读取配置';
    try {
      writeStatus(directory, 'starting');
      const profile = activeProfile(loadProfiles(directory));
      if (profile === undefined) { throw new Error('没有选中的配置'); }
      this.mihomo = profileType(profile) === ProfileType.Mihomo;
      if (this.mihomo) {
        stage = '准备 GEOIP 数据库';
        await seedMihomoGeoIP(directory, this.context.resourceManager);
      }
      stage = '查询默认网络';
      const network = await connection.getDefaultNet();
      const properties = await connection.getConnectionProperties(network);
      if (this.stopping || stopRequested(directory, startedAt)) { return; }
      stage = '准备 VPN 的 DNS 和路由';
      const config = this.mihomo ? profile.config :
        prepareVpnProfile(profile.config, properties.dnses.map((dns: connection.NetAddress) => dns.address));
      this.vpn = vpnExtension.createVpnConnection(this.context);
      stage = '启动内核';
      const started = this.mihomo ? mihomoCore.start(config, directory) :
        nativeCore.start(config, directory, properties.interfaceName, network.netId);
      if (!started) {
        throw new Error('无法启动内核');
      }
      let lastUpdate = 0;
      let connectedAt = 0;
      let commandId = 0;
      let commandError: string | undefined;
      let lastNetworkError: string | undefined;
      const deadline = Date.now() + 30000;
      while (!this.stopping && !stopRequested(directory, startedAt)) {
        const current = this.coreState();
        if (current.state === 'stopped') {
          error = current.error;
          break;
        }
        if (current.tun !== undefined) {
          stage = '创建系统 VPN';
          this.creation = this.createSystemVpn(this.vpn, vpnConfig(current.tun));
          const fd = await this.creation;
          if (this.stopping || stopRequested(directory, startedAt)) { return; }
          stage = '保护 VPN 出站';
          await this.vpn.protectProcessNet();
          if (this.stopping || stopRequested(directory, startedAt)) { return; }
          stage = '交接 TUN';
          if (!(this.mihomo ? mihomoCore.setTunnel(fd) : nativeCore.setTunnel(fd))) {
            throw new Error('无法将系统 VPN 交给内核');
          }
        }
        if (current.state !== 'connected' && Date.now() > deadline) {
          throw new Error('启动超时');
        }
        if (current.state === 'connected' && connectedAt === 0) {
          connectedAt = Date.now();
          lastUpdate = 0;
        }
        if (current.state === 'connected') {
          const command = readNodeCommand(directory);
          if (command !== undefined && command.id >= startedAt && command.id > commandId) {
            commandId = command.id;
            const ok = this.mihomo ? mihomoCore.control(command.action, command.group, command.node) :
              nativeCore.control(command.action, command.group, command.node);
            commandError = ok ? undefined : command.action === 'select' ? '切换失败，原节点保持选中' :
              command.action === 'test' ? '无法启动测速' : '连接操作失败';
            writeStatus(directory, current.state, commandError, connectedAt, current.groups, commandId,
              current.networkError, current.mode, current.connections);
            commandError = undefined;
            lastUpdate = Date.now();
          }
        }
        if (Date.now() - lastUpdate >= 1000) {
          const errorUpdate = current.networkError !== lastNetworkError ? current.networkError : undefined;
          writeStatus(directory, current.state, errorUpdate, connectedAt || undefined, current.groups, commandId,
            current.networkError, current.mode, current.connections);
          lastNetworkError = current.networkError;
          lastUpdate = Date.now();
        }
        await delay(current.state === 'connected' ? 1000 : 100);
      }
    } catch (cause) {
      const code = (cause as BusinessError).code;
      error = `${stage}失败${code ? `（系统错误 ${code}）` : ''}`;
    } finally {
      this.stopCore();
      try {
        await this.destroyVpn();
      } catch (_) {
        error = error ?? '关闭系统 VPN 失败';
      }
      const deadline = Date.now() + 5000;
      while (this.coreState().state !== 'stopped' && Date.now() < deadline) {
        await delay(100);
      }
      if (this.coreState().state !== 'stopped') {
        error = error ?? '内核关闭超时';
      }
      if (this.stopping) {
        this.publishStopped(error);
      } else {
        this.shutdownError = error;
        this.shutdownReady = true;
        try {
          writeStatus(directory, 'stopping');
        } catch (_) {
          // Still request system shutdown when the status file cannot be updated.
        }
        try {
          await vpnExtension.stopVpnExtensionAbility(vpnWant());
        } catch (_) {
          this.publishStopped(error ?? '请求系统停止 VPN 扩展失败');
        }
      }
    }
  }
}
