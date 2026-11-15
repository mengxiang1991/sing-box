import { Want } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

export const MAX_CONFIG_BYTES: number = 4 * 1024 * 1024;

export interface ViewState {
  state: string;
  error?: string;
  updated: number;
}

export function vpnWant(): Want {
  return { bundleName: 'com.sagernet.singbox.harmony', abilityName: 'VpnAbility' };
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
    return fileIo.readTextSync(path, { length: size });
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

export function writeStatus(directory: string, state: string, error?: string): void {
  const status: ViewState = { state: state, error: error, updated: Date.now() };
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
