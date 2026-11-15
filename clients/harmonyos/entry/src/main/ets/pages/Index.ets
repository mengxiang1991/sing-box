import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { vpnExtension } from '@kit.NetworkKit';
import { configPath, MAX_CONFIG_BYTES, readStatus, readText, requestStop, vpnWant, writeAtomic } from '../common/Files';

interface ErrorEntry {
  id: number;
  time: string;
  message: string;
}

@Entry
@Component
struct Index {
  @State private configured: boolean = false;
  @State private state: string = 'stopped';
  @State private errors: ErrorEntry[] = [];
  @State private busy: boolean = false;
  private timer: number = -1;
  private requestedAt: number = 0;
  private stopRequestedAt: number = 0;
  private lastServiceError: number = 0;
  private nextErrorId: number = 0;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    try {
      this.configured = fileIo.accessSync(configPath(this.context().filesDir));
    } catch (_) {
      this.recordError('无法检查已导入的配置文件');
    }
    this.refresh();
    this.timer = setInterval(() => this.refresh(), 250);
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
  }

  private refresh(): void {
    const status = readStatus(this.context().filesDir);
    const now = Date.now();
    if (this.stopRequestedAt > 0) {
      if (status.state === 'stopped' && status.updated >= this.stopRequestedAt) {
        this.stopRequestedAt = 0;
      } else if (now - this.stopRequestedAt < 10000) {
        return;
      } else {
        this.stopRequestedAt = 0;
        this.recordError('正常断开超时，已请求系统关闭 VPN');
        vpnExtension.stopVpnExtensionAbility(vpnWant()).catch(() => {
          this.recordError('请求系统关闭 VPN 失败');
        });
      }
    }
    if (status.updated < this.requestedAt && now - this.requestedAt < 30000) {
      return;
    }
    if (this.requestedAt && status.updated < this.requestedAt) {
      this.recordError('VPN 未启动，请确认已接受系统授权');
      this.requestedAt = 0;
      this.state = 'stopped';
      return;
    }
    if (status.updated >= this.requestedAt) {
      this.requestedAt = 0;
    }
    if (status.state === 'connected' && now - status.updated > 6000) {
      if (this.state !== 'stopped') { this.recordError('VPN 服务已退出'); }
      this.state = 'stopped';
    } else if (status.state === 'starting' && now - status.updated > 30000) {
      if (this.state !== 'stopped') { this.recordError('VPN 启动超时'); }
      this.state = 'stopped';
    } else if (status.state === 'stopping' && now - status.updated > 10000) {
      if (this.state !== 'stopped') { this.recordError('VPN 断开超时'); }
      this.state = 'stopped';
    } else {
      this.state = status.state;
      if (status.error && status.updated > this.lastServiceError) {
        this.lastServiceError = status.updated;
        this.recordError(status.error, status.updated);
      }
    }
  }

  private recordError(message: string, timestamp: number = Date.now()): void {
    const entry: ErrorEntry = { id: this.nextErrorId++, time: new Date(timestamp).toLocaleTimeString(), message: message };
    this.errors = [entry, ...this.errors].slice(0, 8);
  }

  private async importConfig(): Promise<void> {
    this.busy = true;
    try {
      const selector = new picker.DocumentViewPicker(this.context());
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const files = await selector.select(options);
      if (files.length === 0) { return; }
      const config = readText(files[0], MAX_CONFIG_BYTES);
      JSON.parse(config);
      writeAtomic(configPath(this.context().filesDir), config);
      this.configured = true;
    } catch (_) {
      this.recordError('导入失败，请选择 UTF-8 编码的 sing-box JSON 文件（最大 4 MB）');
    } finally {
      this.busy = false;
    }
  }

  private async toggle(): Promise<void> {
    this.busy = true;
    try {
      if (this.state === 'connected' || this.state === 'starting') {
        const awaitingAuthorization = this.requestedAt > 0;
        this.requestedAt = 0;
        if (awaitingAuthorization) {
          await vpnExtension.stopVpnExtensionAbility(vpnWant());
          this.refresh();
        } else {
          this.stopRequestedAt = Date.now();
          requestStop(this.context().filesDir);
          this.state = 'stopping';
        }
      } else {
        this.requestedAt = Date.now();
        this.state = 'starting';
        await vpnExtension.startVpnExtensionAbility(vpnWant());
      }
    } catch (cause) {
      const code = (cause as BusinessError).code;
      this.recordError(`VPN 操作失败${code ? `（系统错误 ${code}）` : ''}`);
      this.requestedAt = 0;
      this.stopRequestedAt = 0;
      this.refresh();
    } finally {
      this.busy = false;
    }
  }

  private label(): string {
    switch (this.state) {
      case 'connected': return '已连接';
      case 'starting': return '正在连接';
      case 'stopping': return '正在断开';
      default: return '未连接';
    }
  }

  build() {
    Scroll() {
      Column({ space: 24 }) {
        Text('sing-box').fontSize(34).fontWeight(FontWeight.Bold).fontColor('#122C3A')

        Column({ space: 8 }) {
          Text('VPN').fontSize(14).fontColor('#A3EADC')
          Text(this.label()).fontSize(30).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
          Button(this.state === 'connected' ? '断开' : this.state === 'starting' ? '取消连接' : '连接')
            .width('100%').margin({ top: 12 }).fontColor('#122C3A').backgroundColor('#A3EADC')
            .enabled(this.configured && !this.busy && this.state !== 'stopping')
            .onClick(() => { this.toggle(); })
        }.width('100%').padding(20).alignItems(HorizontalAlign.Start).backgroundColor('#122C3A').borderRadius(18)

        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text('配置文件').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#122C3A')
            Text(this.configured ? '已导入 sing-box JSON' : '请选择 sing-box JSON').fontSize(14).fontColor('#415C69')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button(this.configured ? '替换' : '导入').fontColor('#122C3A').backgroundColor('#DAEAE8')
            .enabled(!this.busy && this.state === 'stopped').onClick(() => { this.importConfig(); })
        }.width('100%')

        if (this.errors.length > 0) {
          Column({ space: 10 }) {
            Text('最近错误').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#122C3A')
            ForEach(this.errors, (entry: ErrorEntry) => {
              Text(`${entry.time}  ${entry.message}`).fontSize(14).fontColor('#9C2A16')
            }, (entry: ErrorEntry) => entry.id.toString())
          }.width('100%').alignItems(HorizontalAlign.Start)
        }
      }.width('100%').constraintSize({ maxWidth: 560 }).alignItems(HorizontalAlign.Start).padding(24)
    }.align(Alignment.Top).width('100%').height('100%').backgroundColor('#F1F7F6')
  }
}
