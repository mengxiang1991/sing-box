import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { vpnExtension } from '@kit.NetworkKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import mihomoCore from 'libmh_harmony.so';
import { JsonEditorBridge } from '../common/JsonEditorBridge';
import { LiveConnection, MAX_CONFIG_BYTES, NodeCommand, NodeGroup, NodeItem, readStatus, readText, requestStop, vpnWant,
  writeNodeCommand } from '../common/Files';
import { activeProfile, checkProfile, fetchProfile, loadProfiles, Profile, Profiles, ProfileType, profileType,
  profileTypeLabel, saveProfiles, validateMihomoProfile, validateProfile } from '../common/Profiles';

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
  @State private showAddProfile: boolean = false;
  @State private addType: ProfileType = ProfileType.SingBox;
  @State private addError: string = '';
  @State private showJsonImport: boolean = false;
  @State private showYamlEditor: boolean = false;
  @State private yamlText: string = '';
  @State private yamlError: string = '';
  @State private showRuleEditor: boolean = false;
  @State private rules: string[] = [];
  @State private renameId: string = '';
  @State private renameText: string = '';
  @State private renameError: string = '';
  @State private editingProfileId: string = '';
  @State private editorTitle: string = '';
  @State private activeTab: number = 0;
  @State private state: string = 'stopped';
  @State private errors: ErrorEntry[] = [];
  @State private busy: boolean = false;
  @State private connectedSeconds: number = 0;
  @State private copied: boolean = false;
  @State private nodeGroups: NodeGroup[] = [];
  @State private mihomoMode: string = '';
  @State private connections: LiveConnection[] = [];
  @State private pendingNodeCommand: number = 0;
  private timer: number = -1;
  private requestedAt: number = 0;
  private stopRequestedAt: number = 0;
  private lastServiceError: number = 0;
  private nextErrorId: number = 0;
  private reconnectPending: boolean = false;
  private editorController: webview.WebviewController = new webview.WebviewController();
  private editorBridge: JsonEditorBridge = new JsonEditorBridge();

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
        this.mihomoMode = status.mode ?? '';
        this.connections = status.connections ?? [];
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

  private openAddProfile(): void {
    this.addError = '';
    this.showAddProfile = true;
  }

  private async importConfig(mihomo: boolean = false): Promise<void> {
    this.busy = true;
    this.addError = '';
    let config: string;
    try {
      const selector = new picker.DocumentViewPicker(this.context());
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const files = await selector.select(options);
      if (files.length === 0) { return; }
      config = readText(files[0], MAX_CONFIG_BYTES).trim();
    } catch (_) {
      this.addError = '无法读取文件，请选择可访问、非空且不超过 4 MB 的文件';
      return;
    } finally {
      this.busy = false;
    }
    if (mihomo) {
      this.openYamlEditor('', '导入 Clash YAML', config);
      return;
    }
    try {
      validateProfile(config);
    } catch (error) {
      this.openJsonEditor('', '导入配置', config, (error as Error).message);
      return;
    }
    try {
      this.addProfile(`本地配置 ${this.profiles.items.length + 1}`, config);
      this.showAddProfile = false;
    } catch (_) {
      this.addError = '无法保存配置，请检查存储空间或移除一份旧配置';
    }
  }

  private commitProfiles(profiles: Profiles): void {
    saveProfiles(this.context().filesDir, profiles);
    this.profiles = profiles;
  }

  private addProfile(name: string, config: string, url?: string, type: ProfileType = ProfileType.SingBox): void {
    if (this.profiles.items.length >= 8) { throw new Error('配置数量已达上限'); }
    const item: Profile = { id: Date.now().toString(), name: name, config: config, url: url, type: type };
    this.commitProfiles({ active: item.id, items: [...this.profiles.items, item] });
  }

  private async downloadProfile(id: string = ''): Promise<void> {
    this.busy = true;
    this.addError = '';
    try {
      const selected = this.profiles.items.find((item: Profile) => item.id === id);
      const url = id ? selected?.url : this.subscription.trim();
      if (!url) { return; }
      const type = selected ? profileType(selected) : this.addType;
      const config = await fetchProfile(url, type === ProfileType.Mihomo);
      if (selected !== undefined) {
        const replacement: Profile = { id: selected.id, name: selected.name, url: url, config: config, type: type };
        const items = this.profiles.items.map((item: Profile) => item.id === selected.id ? replacement : item);
        this.commitProfiles({ active: this.profiles.active, items: items });
      } else {
        this.addProfile(`订阅 ${this.profiles.items.length + 1}`, config, url, type);
        this.subscription = '';
        this.showAddProfile = false;
      }
    } catch (_) {
      this.addError = id ? '订阅更新失败，原配置已保留' : '无法导入订阅，请检查网络、地址和所选类型';
    } finally {
      this.busy = false;
    }
  }

  private editProfile(item: Profile): void {
    if (profileType(item) === ProfileType.Mihomo) {
      this.openYamlEditor(item.id, item.name, item.config);
      return;
    }
    this.openJsonEditor(item.id, item.name, item.config);
  }

  private openRename(item: Profile): void {
    this.renameId = item.id;
    this.renameText = item.name;
    this.renameError = '';
  }

  private saveName(): void {
    const name = this.renameText.trim();
    if (!name || name.length > 80) {
      this.renameError = '请输入 1 至 80 个字符的名称';
      return;
    }
    const current = this.profiles.items.find((item: Profile) => item.id === this.renameId);
    if (current === undefined) {
      this.renameError = '这份配置已移除';
      return;
    }
    try {
      const renamed: Profile = { id: current.id, name: name, config: current.config, url: current.url,
        type: profileType(current) };
      const items = this.profiles.items.map((item: Profile) => item.id === renamed.id ? renamed : item);
      this.commitProfiles({ active: this.profiles.active, items: items });
      this.renameId = '';
    } catch (_) {
      this.renameError = '保存配置名称失败';
    }
  }

  private openYamlEditor(id: string, title: string, config: string = ''): void {
    this.editingProfileId = id;
    this.editorTitle = title;
    this.yamlText = config;
    this.yamlError = '';
    this.showYamlEditor = true;
  }

  private closeYamlEditor(): void {
    this.showYamlEditor = false;
    this.editingProfileId = '';
    this.yamlText = '';
  }

  private openRules(): void {
    const result = mihomoCore.rules(this.yamlText);
    if (!result) {
      this.yamlError = '请先填写可读取的 Clash YAML';
      return;
    }
    this.rules = JSON.parse(result) as string[];
    this.yamlError = '';
    this.showRuleEditor = true;
  }

  private updateRule(index: number, value: string): void {
    const rules = [...this.rules];
    rules[index] = value;
    this.rules = rules;
  }

  private moveRuleUp(index: number): void {
    const rules = [...this.rules];
    const previous = rules[index - 1];
    rules[index - 1] = rules[index];
    rules[index] = previous;
    this.rules = rules;
  }

  private applyRules(): void {
    const result = mihomoCore.rules(this.yamlText, JSON.stringify(this.rules.map((rule: string) => rule.trim())));
    if (!result) {
      this.yamlError = '规则未通过 Mihomo 校验，请检查规则内容与目标节点组';
      return;
    }
    this.yamlText = result;
    this.yamlError = '';
    this.showRuleEditor = false;
  }

  private saveYaml(): void {
    const config = this.yamlText.trim();
    if (this.state !== 'stopped' || new util.TextEncoder().encodeInto(config).byteLength > MAX_CONFIG_BYTES) {
      this.yamlError = '请断开 VPN 并确认配置不超过 4 MB';
      return;
    }
    try {
      validateMihomoProfile(config);
      if (this.editingProfileId === '') {
        this.addProfile(`Clash 配置 ${this.profiles.items.length + 1}`, config, undefined, ProfileType.Mihomo);
      } else {
        const profile = this.profiles.items.find((item: Profile) => item.id === this.editingProfileId);
        if (profile === undefined) {
          this.yamlError = '这份配置已移除';
          return;
        }
        const updated: Profile = { id: profile.id, name: profile.name, config: config, url: profile.url,
          type: ProfileType.Mihomo };
        const items = this.profiles.items.map((item: Profile) => item.id === updated.id ? updated : item);
        this.commitProfiles({ active: this.profiles.active, items: items });
      }
      this.closeYamlEditor();
      this.showAddProfile = false;
    } catch (error) {
      this.yamlError = (error as Error).message;
    }
  }

  private openJsonEditor(id: string, title: string, config: string = '', error: string = ''): void {
    this.editingProfileId = id;
    this.editorTitle = title;
    this.editorController = new webview.WebviewController();
    this.editorBridge = new JsonEditorBridge();
    this.editorBridge.config = config;
    this.editorBridge.error = error;
    this.editorBridge.onSave = (value: string, adapt: boolean) => this.saveJson(value, adapt);
    this.showJsonImport = true;
  }

  private closeJsonEditor(): void {
    this.showJsonImport = false;
    this.editingProfileId = '';
    this.editorBridge.config = '';
    this.editorBridge.error = '';
  }

  private leaveJsonEditor(): void {
    if (!this.editorBridge.dirty) {
      this.closeJsonEditor();
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '放弃未保存的修改？',
      message: '关闭后将丢弃这次编辑。',
      primaryButton: { value: '继续编辑', action: () => {} },
      secondaryButton: { value: '放弃修改', action: () => { this.closeJsonEditor(); } }
    });
  }

  onBackPress(): boolean {
    if (this.renameId) {
      this.renameId = '';
      return true;
    }
    if (this.showRuleEditor) {
      this.showRuleEditor = false;
      this.yamlError = '';
      return true;
    }
    if (this.showYamlEditor) {
      this.closeYamlEditor();
      return true;
    }
    if (this.showJsonImport) {
      this.leaveJsonEditor();
      return true;
    }
    if (this.showAddProfile) {
      if (!this.busy) {
        this.showAddProfile = false;
        this.addError = '';
      }
      return true;
    }
    return false;
  }

  private saveJson(value: string, adaptTun: boolean): string {
    if (this.state !== 'stopped') {
      return '断开 VPN 后才能保存配置';
    }
    let config = value.trim();
    if (config.length === 0 || config.length > MAX_CONFIG_BYTES ||
      new util.TextEncoder().encodeInto(config).byteLength > MAX_CONFIG_BYTES) {
      return '请填写非空的 sing-box JSON，最大 4 MB';
    }
    try {
      config = checkProfile(config, adaptTun);
    } catch (error) {
      return (error as Error).message;
    }
    try {
      if (this.editingProfileId === '') {
        this.addProfile(`粘贴配置 ${this.profiles.items.length + 1}`, config);
      } else {
        const profile = this.profiles.items.find((item: Profile) => item.id === this.editingProfileId);
        if (!profile) {
          return '这份配置已移除';
        }
        const updated: Profile = { id: profile.id, name: profile.name, config: config, url: profile.url,
          type: ProfileType.SingBox };
        const items = this.profiles.items.map((item: Profile) => item.id === updated.id ? updated : item);
        this.commitProfiles({ active: this.profiles.active, items: items });
      }
      this.closeJsonEditor();
      this.showAddProfile = false;
      return '';
    } catch (_) {
      return '无法保存配置，请检查存储空间或移除一份旧配置';
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

  @Builder
  pageHeader(title: string) {
    Text(title).fontSize(30).fontWeight(FontWeight.Bold).fontColor('#172447').width('100%')
  }

  @Builder
  modeButton(label: string, mode: string) {
    Button(label).layoutWeight(1).height(40).fontColor('#172447')
      .backgroundColor(this.mihomoMode === mode ? '#92F0CE' : '#E3EBF7')
      .enabled(this.pendingNodeCommand === 0)
      .onClick(() => { this.controlNode('mode', '', mode); })
  }

  @Builder
  liveConnections() {
    Column({ space: 10 }) {
      Text('实时连接').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#172447')
      if (this.connections.length === 0) {
        Text('暂无活动连接').fontSize(14).fontColor('#51627E')
      }
      ForEach(this.connections, (item: LiveConnection) => {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text(item.destination).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor('#172447')
            Text(item.network + ' · ' + (item.rule || '直连') + ' · ↓ ' + Math.round(item.download / 1024) + ' KB')
              .fontSize(13).fontColor('#51627E').maxLines(1)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button('关闭').height(38).backgroundColor('#FFF0EF').fontColor('#963125')
            .enabled(this.pendingNodeCommand === 0)
            .onClick(() => { this.controlNode('close', '', item.id); })
        }.width('100%')
      }, (item: LiveConnection) => item.id + ':' + item.download)
    }.width('100%').padding(16).alignItems(HorizontalAlign.Start).backgroundColor('#FFFFFF').borderRadius(16)
  }

  @Builder
  engineBadge(type: ProfileType) {
    Text(profileTypeLabel(type)).fontSize(12).fontWeight(FontWeight.Medium)
      .padding({ left: 9, right: 9, top: 4, bottom: 4 }).borderRadius(6)
      .fontColor(type === ProfileType.Mihomo ? '#54398B' : '#174C3F')
      .backgroundColor(type === ProfileType.Mihomo ? '#EEE6FC' : '#DBF8EE')
  }

  @Builder
  connectionPage() {
    Scroll() {
      Column({ space: 20 }) {
        this.pageHeader('连接')
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            Circle().width(8).height(8).fill(this.state === 'connected' ? '#92F0CE' : '#AAB8D1')
            Text('VPN').fontSize(14).fontColor('#C7D4E9')
            Blank()
            if (this.state === 'connected') {
              Text(this.duration()).fontSize(15).fontColor('#92F0CE').accessibilityDescription('连接时长')
            }
          }.width('100%')
          Text(this.label()).fontSize(36).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          Divider().color('#324469').margin({ top: 4, bottom: 4 })
          Row({ space: 10 }) {
            Text(activeProfile(this.profiles)?.name ?? '请先添加配置').maxLines(1).layoutWeight(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).fontSize(16).fontColor('#DFE8F7')
            if (activeProfile(this.profiles)) {
              this.engineBadge(profileType(activeProfile(this.profiles)))
            }
          }.width('100%')
          if (this.state === 'connected' && this.nodeGroups[0]?.selected) {
            Text('当前节点 · ' + this.nodeGroups[0].selected).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).fontSize(14).fontColor('#C7D4E9')
          }
          Row({ space: 10 }) {
            Button(this.state === 'connected' ? '断开' : this.state === 'starting' ? '取消连接' : '连接')
              .layoutWeight(1).height(48).fontColor('#172447').backgroundColor('#92F0CE')
              .enabled(this.profiles.active.length > 0 && !this.busy && this.state !== 'stopping')
              .onClick(() => { this.toggle(); })
            if (this.state === 'connected') {
              Button('重连').height(48).backgroundColor('#324469').fontColor('#FFFFFF')
                .enabled(!this.busy).onClick(() => { this.reconnect(); })
            }
          }.width('100%').margin({ top: 6 })
        }.width('100%').padding(22).alignItems(HorizontalAlign.Start).backgroundColor('#172447').borderRadius(22)
        if (this.state === 'connected' && profileType(activeProfile(this.profiles)) === ProfileType.Mihomo && this.mihomoMode) {
          Row({ space: 8 }) {
            this.modeButton('规则', 'rule')
            this.modeButton('全局', 'global')
            this.modeButton('直连', 'direct')
          }.width('100%')
          this.liveConnections()
        }
        if (this.state === 'stopped') {
          Button(this.profiles.active ? '切换配置' : '添加配置').width('100%').height(44)
            .fontColor('#172447').backgroundColor('#E3EBF7')
            .onClick(() => {
              this.activeTab = 1;
              if (!this.profiles.active) { this.openAddProfile(); }
            })
        }
        if (this.errors.length > 0) {
          Column({ space: 8 }) {
            Text('最近错误').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#51627E')
            Text(this.errors[0].message).fontSize(15).fontColor('#963125').maxLines(3)
            Button('查看日志', { type: ButtonType.Normal }).height(40).fontColor('#172447')
              .backgroundColor('#E3EBF7').borderRadius(10).onClick(() => { this.activeTab = 3; })
          }.alignItems(HorizontalAlign.Start).width('100%')
        }
      }.width('100%').constraintSize({ maxWidth: 560 }).alignItems(HorizontalAlign.Start).padding(20)
    }.width('100%').height('100%').align(Alignment.Top)
  }

  @Builder
  profilesPage() {
    Scroll() {
      Column({ space: 18 }) {
        Row({ space: 12 }) {
          Text('配置').fontSize(30).fontWeight(FontWeight.Bold).fontColor('#172447').layoutWeight(1)
          Button('添加配置').height(44).backgroundColor('#172447').fontColor('#FFFFFF')
            .enabled(!this.busy && this.state === 'stopped').onClick(() => { this.openAddProfile(); })
        }.width('100%')
        if (this.state !== 'stopped') {
          Text('断开 VPN 后可导入、编辑或切换配置。').fontSize(14).fontColor('#51627E')
        }
        if (this.addError) {
          Text(this.addError).fontSize(14).fontColor('#963125').width('100%')
        }

        if (this.profiles.items.length === 0) {
          Text('暂无配置，可以从文件、剪贴板或订阅添加。').fontSize(15).fontColor('#51627E')
        }
        ForEach(this.profiles.items, (item: Profile) => {
          Column({ space: 11 }) {
            Row({ space: 8 }) {
              Column({ space: 5 }) {
                Text(item.name).fontSize(17).fontWeight(FontWeight.Medium).fontColor('#172447')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Row({ space: 8 }) {
                  this.engineBadge(profileType(item))
                  Text(item.url ? '订阅' : '本地').fontSize(13).fontColor('#51627E')
                }
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              if (this.profiles.active === item.id) {
                Text('当前配置').padding({ left: 10, right: 10, top: 5, bottom: 5 }).fontSize(12)
                  .fontColor('#174C3F').backgroundColor('#DBF8EE').borderRadius(8)
              }
            }.width('100%')
            Divider().color('#E8EEF7')
            Row({ space: 8 }) {
              if (this.profiles.active !== item.id) {
                Button('选用').height(40).backgroundColor('#172447').fontColor('#FFFFFF')
                  .enabled(!this.busy && this.state === 'stopped').onClick(() => { this.changeProfile(item.id, false); })
              }
              Button('编辑').height(40).backgroundColor('#E3EBF7').fontColor('#172447')
                .enabled(!this.busy && this.state === 'stopped').onClick(() => { this.editProfile(item); })
              Button('重命名').height(40).backgroundColor('#E3EBF7').fontColor('#172447')
                .enabled(!this.busy).onClick(() => { this.openRename(item); })
              Blank()
              Button('移除').height(40).backgroundColor('#FFF0EF').fontColor('#963125')
                .enabled(!this.busy && this.state === 'stopped').onClick(() => {
                  this.getUIContext().showAlertDialog({
                    title: '移除这份配置？',
                    message: item.name,
                    primaryButton: { value: '取消', action: () => {} },
                    secondaryButton: { value: '移除', action: () => { this.changeProfile(item.id, true); } }
                  });
                })
            }.width('100%')
            if (item.url) {
              Button('更新订阅').height(40).backgroundColor('#EFF3FA').fontColor('#172447')
                .enabled(!this.busy && this.state === 'stopped').onClick(() => { this.downloadProfile(item.id); })
            }
          }.padding(16).width('100%').alignItems(HorizontalAlign.Start).backgroundColor('#FFFFFF').borderRadius(16)
        }, (item: Profile) => item.id + ':' + item.name)
      }.width('100%').constraintSize({ maxWidth: 560 }).alignItems(HorizontalAlign.Start).padding(20)
    }.width('100%').height('100%').align(Alignment.Top)
  }

  @Builder
  nodesPage() {
    Scroll() {
      Column({ space: 16 }) {
        this.pageHeader('节点')
        if (this.state === 'connected' && profileType(activeProfile(this.profiles)) === ProfileType.Mihomo) {
          Button('请求刷新节点和规则来源').height(40).backgroundColor('#E3EBF7').fontColor('#172447')
            .enabled(this.pendingNodeCommand === 0).onClick(() => { this.controlNode('providers', ''); })
        }
        if (this.state !== 'connected') {
          Text('连接后可查看节点组、测速和切换。').fontSize(15).fontColor('#51627E')
        } else if (this.nodeGroups.length === 0) {
          Text('当前配置没有出站节点组。').fontSize(15).fontColor('#51627E')
        } else {
          ForEach(this.nodeGroups, (group: NodeGroup) => {
            Column({ space: 10 }) {
              Row({ space: 8 }) {
                Text(group.tag).layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#172447')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Button('测速').height(40).backgroundColor('#E3EBF7').fontColor('#172447')
                  .enabled(this.pendingNodeCommand === 0).onClick(() => { this.controlNode('test', group.tag); })
              }.width('100%')
              ForEach(group.items ?? [], (node: NodeItem) => {
                Divider().color('#E8EEF7')
                Row({ space: 8 }) {
                  Column({ space: 4 }) {
                    Text(node.tag).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor('#172447')
                    Text(node.type + ' · ' + (node.urlTestDelay ? node.urlTestDelay + ' ms' : '暂无测速结果'))
                      .fontSize(13).fontColor('#51627E')
                    if (node.dialerProxy) {
                      Text('链式前置 · ' + node.dialerProxy).fontSize(13).fontColor('#51627E')
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  if (node.tag === group.selected) {
                    Text('已选').padding(7).fontSize(12).fontColor('#174C3F').backgroundColor('#DBF8EE').borderRadius(8)
                  } else if (group.selectable) {
                    Button('切换').height(40).backgroundColor('#E3EBF7').fontColor('#172447')
                      .enabled(this.pendingNodeCommand === 0)
                      .onClick(() => { this.controlNode('select', group.tag, node.tag); })
                  }
                }.width('100%')
              }, (node: NodeItem) => node.tag + ':' + (node.urlTestDelay ?? 0) + ':' + (group.selected ?? ''))
            }.padding(16).width('100%').alignItems(HorizontalAlign.Start).backgroundColor('#FFFFFF').borderRadius(16)
          }, (group: NodeGroup) => JSON.stringify(group))
        }
      }.width('100%').constraintSize({ maxWidth: 560 }).alignItems(HorizontalAlign.Start).padding(20)
    }.width('100%').height('100%').align(Alignment.Top)
  }

  @Builder
  logsPage() {
    Scroll() {
      Column({ space: 16 }) {
        this.pageHeader('日志')
        if (this.errors.length === 0) {
          Text('暂无错误记录。').fontSize(15).fontColor('#51627E')
        } else {
          Button(this.copied ? '已复制' : '复制诊断信息').height(44).backgroundColor('#172447').fontColor('#FFFFFF')
            .onClick(() => { this.copyErrors(); })
          Column({ space: 10 }) {
            ForEach(this.errors, (entry: ErrorEntry) => {
              Row({ space: 12 }) {
                Text(entry.time).fontSize(12).fontColor('#51627E')
                Text(entry.message).layoutWeight(1).fontSize(14).fontColor('#963125')
              }.width('100%').alignItems(VerticalAlign.Top)
              Divider().color('#E8EEF7')
            }, (entry: ErrorEntry) => entry.id.toString())
          }.padding(16).width('100%').backgroundColor('#FFFFFF').borderRadius(16)
        }
      }.width('100%').constraintSize({ maxWidth: 560 }).alignItems(HorizontalAlign.Start).padding(20)
    }.width('100%').height('100%').align(Alignment.Top)
  }

  @Builder
  tab(label: string, index: number) {
    Column({ space: 6 }) {
      Divider().strokeWidth(3).width(22).color(this.activeTab === index ? '#247F67' : '#FFFFFF')
      Text(label).fontSize(14).fontWeight(this.activeTab === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.activeTab === index ? '#174C3F' : '#51627E')
    }.width('100%').height(54).justifyContent(FlexAlign.Center)
  }

  @Builder
  editorPage() {
    Column() {
      Row({ space: 12 }) {
        Button('返回', { type: ButtonType.Normal }).height(42).borderRadius(9)
          .backgroundColor('#253657').fontColor('#E8EDF7').onClick(() => { this.leaveJsonEditor(); })
        Column({ space: 4 }) {
          Text(this.editorTitle).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.editingProfileId && this.profiles.items.find((item: Profile) => item.id === this.editingProfileId)?.url) {
            Text('手动更新订阅会覆盖本地修改').fontSize(12).fontColor('#C7D4E9')
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 }).backgroundColor('#172447')
      Web({ src: $rawfile('json-editor.html'), controller: this.editorController })
        .javaScriptAccess(true)
        .domStorageAccess(false)
        .blockNetwork(true)
        .fileAccess(false)
        .javaScriptProxy({
          object: this.editorBridge,
          name: 'EditorHost',
          methodList: ['getConfig', 'getError', 'setDirty', 'saveConfig'],
          controller: this.editorController
        })
        .width('100%').layoutWeight(1)
    }.width('100%').height('100%').backgroundColor('#101A32')
  }

  @Builder
  addTypeButton(type: ProfileType) {
    Button(profileTypeLabel(type), { type: ButtonType.Normal }).layoutWeight(1).height(44).borderRadius(8)
      .fontWeight(this.addType === type ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.addType === type ? '#FFFFFF' : '#384A67')
      .backgroundColor(this.addType === type ? '#172447' : '#EFF3FA')
      .enabled(!this.busy)
      .onClick(() => { this.addType = type; this.addError = ''; })
  }

  @Builder
  addProfilePage() {
    Scroll() {
      Column({ space: 18 }) {
        Row({ space: 10 }) {
          Button('返回', { type: ButtonType.Normal }).height(44).borderRadius(8).backgroundColor('#E3EBF7')
            .fontColor('#172447').enabled(!this.busy)
            .onClick(() => { this.showAddProfile = false; this.addError = ''; })
          Text('添加配置').fontSize(26).fontWeight(FontWeight.Bold).fontColor('#172447').layoutWeight(1)
        }.width('100%')
        Column({ space: 8 }) {
          Text('配置类型').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#172447')
          Row({ space: 8 }) {
            this.addTypeButton(ProfileType.SingBox)
            this.addTypeButton(ProfileType.Mihomo)
          }.width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            Button('导入文件').layoutWeight(1).height(44).backgroundColor('#E3EBF7').fontColor('#172447')
              .enabled(!this.busy && this.state === 'stopped')
              .onClick(() => { this.importConfig(this.addType === ProfileType.Mihomo); })
            Button('粘贴配置').layoutWeight(1).height(44).backgroundColor('#E3EBF7').fontColor('#172447')
              .enabled(!this.busy && this.state === 'stopped')
              .onClick(() => {
                if (this.addType === ProfileType.Mihomo) {
                  this.openYamlEditor('', '粘贴 Clash 配置');
                } else {
                  this.openJsonEditor('', '粘贴 sing-box 配置');
                }
              })
          }.width('100%')
          Divider().color('#E8EEF7')
          Text('通过订阅添加').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#172447')
          TextInput({ placeholder: '输入 HTTPS 订阅地址', text: this.subscription })
            .width('100%').height(46).backgroundColor('#EFF3FA')
            .enabled(!this.busy)
            .onChange((value: string) => { this.subscription = value; this.addError = ''; })
          Button(this.busy ? '正在处理' : '添加订阅').width('100%').height(44)
            .backgroundColor('#172447').fontColor('#FFFFFF')
            .enabled(!this.busy && this.state === 'stopped' && this.subscription.trim().length > 0)
            .onClick(() => { this.downloadProfile(); })
        }.width('100%').padding(16).alignItems(HorizontalAlign.Start).backgroundColor('#FFFFFF').borderRadius(16)
        if (this.addError) {
          Text(this.addError).fontSize(14).fontColor('#963125').width('100%')
        }
      }.width('100%').constraintSize({ maxWidth: 560 }).padding(20)
    }.width('100%').height('100%').align(Alignment.Top).backgroundColor('#F1F5FB')
  }

  @Builder
  renamePage() {
    Column({ space: 16 }) {
      this.pageHeader('重命名配置')
      TextInput({ text: this.renameText, placeholder: '配置名称' })
        .width('100%').height(48).maxLength(80)
        .onChange((value: string) => { this.renameText = value; this.renameError = ''; })
        .onSubmit(() => { this.saveName(); })
      if (this.renameError) {
        Text(this.renameError).fontColor('#963125').width('100%')
      }
      Row({ space: 10 }) {
        Button('取消').layoutWeight(1).onClick(() => { this.renameId = ''; })
        Button('保存').layoutWeight(1).onClick(() => { this.saveName(); })
      }.width('100%')
    }.width('100%').constraintSize({ maxWidth: 560 }).padding(20)
  }

  @Builder
  ruleEditor() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Button('取消').onClick(() => { this.showRuleEditor = false; this.yamlError = ''; })
        Text('分流规则').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
        Button('应用').onClick(() => { this.applyRules(); })
      }.width('100%')
      if (this.yamlError) {
        Text(this.yamlError).fontColor('#963125').width('100%')
      }
      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.rules, (rule: string, index: number) => {
            Row({ space: 6 }) {
              TextInput({ text: rule, placeholder: 'DOMAIN,example.com,DIRECT' })
                .layoutWeight(1).onChange((value: string) => { this.updateRule(index, value); })
              Button('上移').enabled(index > 0).onClick(() => { this.moveRuleUp(index); })
              Button('移除').onClick(() => { this.rules = this.rules.filter((_: string, i: number) => i !== index); })
            }.width('100%')
          }, (_: string, index: number) => index.toString())
          Button('添加规则').width('100%').onClick(() => { this.rules = [...this.rules, '']; })
        }.width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }.padding(16).width('100%').height('100%').backgroundColor('#F1F5FB')
  }

  build() {
    if (this.renameId) {
      Column() {
        this.renamePage()
      }.width('100%').height('100%').backgroundColor('#F1F5FB')
    } else if (this.showRuleEditor) {
      this.ruleEditor()
    } else if (this.showYamlEditor) {
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          Button('返回').onClick(() => { this.closeYamlEditor(); })
          Text(this.editorTitle).layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
          Button('规则').onClick(() => { this.openRules(); })
          Button('保存').onClick(() => { this.saveYaml(); })
        }.width('100%')
        if (this.yamlError) {
          Text(this.yamlError).fontColor('#963125')
        }
        TextArea({ text: this.yamlText, placeholder: '粘贴 Clash 或 Mihomo YAML 配置' })
          .width('100%').layoutWeight(1).fontFamily('monospace')
          .onChange((value: string) => { this.yamlText = value; this.yamlError = ''; })
      }.padding(16).width('100%').height('100%').backgroundColor('#F1F5FB')
    } else if (this.showJsonImport) {
      this.editorPage()
    } else if (this.showAddProfile) {
      this.addProfilePage()
    } else {
      Tabs({ barPosition: BarPosition.End, index: this.activeTab }) {
        TabContent() { this.connectionPage() }.tabBar(this.tab('连接', 0))
        TabContent() { this.profilesPage() }.tabBar(this.tab('配置', 1))
        TabContent() { this.nodesPage() }.tabBar(this.tab('节点', 2))
        TabContent() { this.logsPage() }.tabBar(this.tab('日志', 3))
      }
      .width('100%').height('100%').barMode(BarMode.Fixed)
      .barHeight(58).barBackgroundColor('#FFFFFF').scrollable(false)
      .onChange((index: number) => { this.activeTab = index; })
      .backgroundColor('#F1F5FB')
    }
  }
}
