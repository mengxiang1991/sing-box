import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { vpnExtension } from '@kit.NetworkKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { MAX_CONFIG_BYTES, NodeCommand, NodeGroup, NodeItem, readStatus, readText, requestStop, vpnWant,
  writeNodeCommand } from '../common/Files';
import { activeProfile, checkProfile, fetchProfile, loadProfiles, Profile, Profiles, saveProfiles, validateProfile } from '../common/Profiles';

interface ErrorEntry {
  id: number;
  time: string;
  message: string;
}

@Entry
@Component
struct Index {
  @State private profiles: Profiles = { active: '', items: [] };
  @State private subscription: string = '';
  @State private showJsonImport: boolean = false;
  @State private jsonInput: string = '';
  @State private jsonImportError: string = '';
  @State private state: string = 'stopped';
  @State private errors: ErrorEntry[] = [];
  @State private busy: boolean = false;
  @State private connectedSeconds: number = 0;
  @State private copied: boolean = false;
  @State private nodeGroups: NodeGroup[] = [];
  @State private pendingNodeCommand: number = 0;
  private timer: number = -1;
  private requestedAt: number = 0;
  private stopRequestedAt: number = 0;
  private lastServiceError: number = 0;
  private nextErrorId: number = 0;
  private reconnectPending: boolean = false;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    this.profiles = loadProfiles(this.context().filesDir);
    this.refresh();
    this.timer = setInterval(() => this.refresh(), 250);
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
  }

  private refresh(): void {
    const status = readStatus(this.context().filesDir);
    const now = Date.now();
    if (this.pendingNodeCommand > 0) {
      if (status.state !== 'connected' || (status.commandId ?? 0) >= this.pendingNodeCommand) {
        this.pendingNodeCommand = 0;
      } else if (now - this.pendingNodeCommand > 5000) {
        this.pendingNodeCommand = 0;
        this.recordError('节点操作等待响应超时');
      }
    }
    if (this.stopRequestedAt > 0) {
      if (status.state === 'stopped' && status.updated >= this.stopRequestedAt) {
        this.stopRequestedAt = 0;
        if (this.reconnectPending) {
          this.reconnectPending = false;
          this.state = 'stopped';
          this.toggle();
          return;
        }
      } else if (now - this.stopRequestedAt < 10000) {
        return;
      } else {
        this.stopRequestedAt = 0;
        this.reconnectPending = false;
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
      if (status.state === 'connected') {
        this.connectedSeconds = Math.floor(Math.max(0, now - (status.connectedAt ?? now)) / 1000);
        this.nodeGroups = status.groups?.group ?? [];
      }
      if (status.error && status.updated > this.lastServiceError) {
        this.lastServiceError = status.updated;
        this.recordError(status.error, status.updated);
      }
    }
  }

  private recordError(message: string, timestamp: number = Date.now()): void {
    this.copied = false;
    const entry: ErrorEntry = { id: this.nextErrorId++, time: new Date(timestamp).toLocaleTimeString(), message: message };
    this.errors = [entry, ...this.errors].slice(0, 8);
  }

  private async copyErrors(): Promise<void> {
    const lines = this.errors.map((entry: ErrorEntry) => `${entry.time}  ${entry.message}`);
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, lines.join('\n')));
      this.copied = true;
    } catch (_) {
      this.recordError('无法复制诊断信息');
    }
  }

  private duration(): string {
    const seconds = this.connectedSeconds;
    return `${Math.floor(seconds / 3600).toString().padStart(2, '0')}:` +
      `${Math.floor(seconds / 60 % 60).toString().padStart(2, '0')}:${(seconds % 60).toString().padStart(2, '0')}`;
  }

  private async importConfig(): Promise<void> {
    this.busy = true;
    let config: string;
    try {
      const selector = new picker.DocumentViewPicker(this.context());
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const files = await selector.select(options);
      if (files.length === 0) { return; }
      config = readText(files[0], MAX_CONFIG_BYTES).trim();
    } catch (_) {
      this.recordError('无法读取文件，请确认文件可访问、非空且大小不超过 4 MB');
      return;
    } finally {
      this.busy = false;
    }
    try {
      validateProfile(config);
    } catch (error) {
      this.jsonInput = config;
      this.jsonImportError = (error as Error).message;
      this.showJsonImport = true;
      return;
    }
    try {
      this.addProfile(`本地配置 ${this.profiles.items.length + 1}`, config);
    } catch (_) {
      this.recordError('无法保存配置，请检查存储空间或移除一份旧配置');
    }
  }

  private commitProfiles(profiles: Profiles): void {
    saveProfiles(this.context().filesDir, profiles);
    this.profiles = profiles;
  }

  private addProfile(name: string, config: string, url?: string): void {
    if (this.profiles.items.length >= 8) { throw new Error('配置数量已达上限'); }
    const item: Profile = { id: Date.now().toString(), name: name, config: config, url: url };
    this.commitProfiles({ active: item.id, items: [...this.profiles.items, item] });
  }

  private async downloadProfile(update: boolean): Promise<void> {
    this.busy = true;
    try {
      const selected = activeProfile(this.profiles);
      const url = update ? selected?.url : this.subscription.trim();
      if (!url) { return; }
      const config = await fetchProfile(url);
      if (update && selected !== undefined) {
        const replacement: Profile = { id: selected.id, name: selected.name, url: url, config: config };
        const items = this.profiles.items.map((item: Profile) => item.id === selected.id ? replacement : item);
        this.commitProfiles({ active: selected.id, items: items });
      } else {
        this.addProfile(`订阅 ${this.profiles.items.length + 1}`, config, url);
        this.subscription = '';
      }
    } catch (_) {
      this.recordError('订阅导入或更新失败。请检查 HTTPS 地址及 sing-box JSON 格式。');
    } finally {
      this.busy = false;
    }
  }

  private importPastedJson(adaptTun: boolean = false): void {
    let config = this.jsonInput.trim();
    if (config.length === 0 || config.length > MAX_CONFIG_BYTES) {
      this.jsonImportError = '请粘贴非空的 sing-box JSON，最大 4 MB';
      return;
    }
    try {
      config = checkProfile(config, adaptTun);
    } catch (error) {
      this.jsonImportError = (error as Error).message;
      return;
    }
    try {
      this.addProfile(`粘贴配置 ${this.profiles.items.length + 1}`, config);
      this.jsonInput = '';
      this.jsonImportError = '';
      this.showJsonImport = false;
    } catch (_) {
      this.jsonImportError = '无法保存配置，请检查存储空间或移除一份旧配置';
    }
  }

  private changeProfile(id: string, remove: boolean): void {
    try {
      const items = remove ? this.profiles.items.filter((item: Profile) => item.id !== id) : this.profiles.items;
      const active = remove ? (this.profiles.active === id ? items[0]?.id ?? '' : this.profiles.active) : id;
      this.commitProfiles({ active: active, items: items });
    } catch (_) {
      this.recordError('保存配置列表失败');
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
      this.reconnectPending = false;
      this.refresh();
    } finally {
      this.busy = false;
    }
  }

  private reconnect(): void {
    this.reconnectPending = true;
    this.toggle();
  }

  private controlNode(action: string, group: string, node: string = ''): void {
    if (this.pendingNodeCommand > 0 || this.state !== 'connected') { return; }
    const command: NodeCommand = { id: Date.now(), action: action, group: group, node: node };
    try {
      writeNodeCommand(this.context().filesDir, command);
      this.pendingNodeCommand = command.id;
    } catch (_) {
      this.recordError('无法提交节点操作');
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
          if (this.state === 'connected') {
            Text(this.duration()).fontSize(16).fontColor('#A3EADC').accessibilityDescription('连接时长')
            if (this.nodeGroups.length > 0 && this.nodeGroups[0].selected) {
              Text(`节点 ${this.nodeGroups[0].selected}`).fontSize(16).fontColor('#FFFFFF')
            }
          }
          Button(this.state === 'connected' ? '断开' : this.state === 'starting' ? '取消连接' : '连接')
            .width('100%').margin({ top: 12 }).fontColor('#122C3A').backgroundColor('#A3EADC')
            .enabled(this.profiles.active.length > 0 && !this.busy && this.state !== 'stopping')
            .onClick(() => { this.toggle(); })
          if (this.state === 'connected') {
            Button('重连').enabled(!this.busy).onClick(() => { this.reconnect(); })
          }
        }.width('100%').padding(20).alignItems(HorizontalAlign.Start).backgroundColor('#122C3A').borderRadius(18)

        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text('配置文件').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#122C3A')
            Text(activeProfile(this.profiles)?.name ?? '请选择 sing-box JSON').fontSize(14).fontColor('#415C69')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button('导入文件').fontColor('#122C3A').backgroundColor('#DAEAE8')
            .enabled(!this.busy && this.state === 'stopped').onClick(() => { this.importConfig(); })
        }.width('100%')

        Column({ space: 8 }) {
          Button(this.showJsonImport ? '收起 JSON 输入' : '粘贴 JSON')
            .enabled(!this.busy && this.state === 'stopped')
            .onClick(() => { this.showJsonImport = !this.showJsonImport; })
          if (this.showJsonImport && this.state === 'stopped') {
            TextArea({ placeholder: '在这里长按粘贴完整的 sing-box JSON', text: this.jsonInput })
              .width('100%').height(148)
              .onChange((value: string) => { this.jsonInput = value; this.jsonImportError = ''; })
            Button('保存 JSON 配置').enabled(!this.busy && this.jsonInput.trim().length > 0)
              .onClick(() => { this.importPastedJson(); })
            if (this.jsonImportError.length > 0) {
              Text(this.jsonImportError).fontColor('#9C2A16').fontSize(14)
              if (this.jsonImportError.includes('「适配鸿蒙并保存」')) {
                Text('按需添加 TUN 入站，使用默认 Go 栈和系统 VPN 路由。').fontSize(13).fontColor('#415C69')
                Button('适配鸿蒙并保存').enabled(!this.busy)
                  .onClick(() => { this.importPastedJson(true); })
              }
            }
          }
          TextInput({ placeholder: 'HTTPS sing-box JSON 订阅地址', text: this.subscription })
            .onChange((value: string) => { this.subscription = value; })
          Row({ space: 8 }) {
            Button('添加订阅').enabled(!this.busy && this.state === 'stopped' && this.subscription.trim().length > 0)
              .onClick(() => { this.downloadProfile(false); })
            Button('更新当前订阅').enabled(!this.busy && this.state === 'stopped' && !!activeProfile(this.profiles)?.url)
              .onClick(() => { this.downloadProfile(true); })
          }
          ForEach(this.profiles.items, (item: Profile) => {
            Row({ space: 8 }) {
              Text(item.name).layoutWeight(1)
              Button(this.profiles.active === item.id ? '当前配置' : '选择')
                .enabled(!this.busy && this.state === 'stopped' && this.profiles.active !== item.id)
                .onClick(() => { this.changeProfile(item.id, false); })
              Button('移除').enabled(!this.busy && this.state === 'stopped')
                .onClick(() => { this.changeProfile(item.id, true); })
            }.width('100%')
          }, (item: Profile) => item.id)
        }.width('100%').alignItems(HorizontalAlign.Start)

        if (this.state === 'connected' && this.nodeGroups.length > 0) {
          Column({ space: 12 }) {
            Text('节点').fontSize(18).fontWeight(FontWeight.Medium)
            ForEach(this.nodeGroups, (group: NodeGroup) => {
              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  Text(group.tag).layoutWeight(1).fontWeight(FontWeight.Medium)
                  Button('测速').enabled(this.pendingNodeCommand === 0)
                    .onClick(() => { this.controlNode('test', group.tag); })
                }.width('100%')
                ForEach(group.items ?? [], (node: NodeItem) => {
                  Row({ space: 8 }) {
                    Column({ space: 4 }) {
                      Text(node.tag)
                      Text(`${node.type} · ${node.urlTestDelay ? `${node.urlTestDelay} ms` : '暂无测速结果'}`).fontSize(13)
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    if (group.selectable || node.tag === group.selected) {
                      Button(node.tag === group.selected ? '已选' : '切换')
                        .enabled(!!group.selectable && node.tag !== group.selected && this.pendingNodeCommand === 0)
                        .onClick(() => { this.controlNode('select', group.tag, node.tag); })
                    }
                  }.width('100%')
                }, (node: NodeItem) => `${node.tag}:${node.urlTestDelay ?? 0}:${group.selected ?? ''}`)
              }.width('100%')
            }, (group: NodeGroup) => JSON.stringify(group))
          }.width('100%').alignItems(HorizontalAlign.Start)
        }

        if (this.errors.length > 0) {
          Column({ space: 10 }) {
            Text('最近错误').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#122C3A')
            Button(this.copied ? '已复制' : '复制诊断信息').onClick(() => { this.copyErrors(); })
            ForEach(this.errors, (entry: ErrorEntry) => {
              Text(`${entry.time}  ${entry.message}`).fontSize(14).fontColor('#9C2A16')
            }, (entry: ErrorEntry) => entry.id.toString())
          }.width('100%').alignItems(HorizontalAlign.Start)
        }
      }.width('100%').constraintSize({ maxWidth: 560 }).alignItems(HorizontalAlign.Start).padding(24)
    }.align(Alignment.Top).width('100%').height('100%').backgroundColor('#F1F7F6')
  }
}
