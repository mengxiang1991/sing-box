import { Want } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

export const MAX_CONFIG_BYTES: number = 4 * 1024 * 1024;
export const BUNDLE_NAME: string = 'com.sagernet.singbox.harmony';

export interface NodeItem {
  tag: string;
  type: string;
  urlTestDelay?: number;
  dialerProxy?: string;
}

export interface NodeGroup {
  tag: string;
  selected?: string;
  selectable?: boolean;
  items?: NodeItem[];
}

export interface NodeGroups {
  group?: NodeGroup[];
}

export interface LiveConnection {
  id: string;
  destination: string;
  network: string;
  rule: string;
  upload: number;
  download: number;
}

export interface NodeCommand {
  id: number;
  action: string;
  group: string;
  node: string;
}

export function readNodeCommand(directory: string): NodeCommand | undefined {
  try {
    return JSON.parse(readText(`${directory}/node-command.json`, 16384)) as NodeCommand;
  } catch (_) {
    return undefined;
  }
}

export function writeNodeCommand(directory: string, command: NodeCommand): void {
  writeAtomic(`${directory}/node-command.json`, JSON.stringify(command));
}

export interface ViewState {
  state: string;
  error?: string;
  updated: number;
  connectedAt?: number;
  groups?: NodeGroups;
  commandId?: number;
  networkError?: string;
  mode?: string;
  connections?: LiveConnection[];
}

export function vpnWant(): Want {
  return { bundleName: BUNDLE_NAME, abilityName: 'VpnAbility' };
}

export function configPath(directory: string): string {
  return `${directory}/sing-box.json`;
}

export function readText(path: string, maximum: number): string {
  const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
  try {
    const size = fileIo.statSync(file.fd).size;
    if (size <= 0 || size > maximum) {
      throw new Error('文件为空或超出大小限制');
    }
    const bytes = new Uint8Array(size);
    const chunk = new ArrayBuffer(Math.min(size, 64 * 1024));
    let position = 0;
    while (position < size) {
      const count = fileIo.readSync(file.fd, chunk, { length: Math.min(chunk.byteLength, size - position) });
      if (count === 0) {
        throw new Error('文件读取不完整');
      }
      bytes.set(new Uint8Array(chunk, 0, count), position);
      position += count;
    }
    return util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true }).decodeToString(bytes);
  } finally {
    fileIo.closeSync(file);
  }
}

export function writeAtomic(path: string, text: string): void {
  const temp = `${path}.tmp`;
  const file = fileIo.openSync(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(file.fd, text);
  } finally {
    fileIo.closeSync(file);
  }
  fileIo.renameSync(temp, path);
}

export function readStatus(directory: string): ViewState {
  try {
    return JSON.parse(fileIo.readTextSync(`${directory}/vpn-status.json`)) as ViewState;
  } catch (_) {
    return { state: 'stopped', updated: 0 };
  }
}

export function writeStatus(directory: string, state: string, error?: string, connectedAt?: number,
  groups?: NodeGroups, commandId?: number, networkError?: string, mode?: string,
  connections?: LiveConnection[]): void {
  const status: ViewState = { state: state, error: error, updated: Date.now(), connectedAt: connectedAt,
    groups: groups, commandId: commandId, networkError: networkError, mode: mode, connections: connections };
  writeAtomic(`${directory}/vpn-status.json`, JSON.stringify(status));
}

export function requestStop(directory: string): void {
  writeAtomic(`${directory}/vpn-stop`, Date.now().toString());
}

export function stopRequested(directory: string, startedAt: number): boolean {
  try {
    return Number(fileIo.readTextSync(`${directory}/vpn-stop`)) >= startedAt;
  } catch (_) {
    return false;
  }
}
