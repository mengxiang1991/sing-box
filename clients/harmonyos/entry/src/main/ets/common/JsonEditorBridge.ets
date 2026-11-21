export class JsonEditorBridge {
  config: string = '';
  error: string = '';
  dirty: boolean = false;
  onSave: (config: string, adapt: boolean) => string = () => '编辑器尚未就绪';

  getConfig(): string {
    return this.config;
  }

  getError(): string {
    return this.error;
  }

  setDirty(dirty: boolean): void {
    this.dirty = dirty;
  }

  saveConfig(config: string, adapt: boolean): string {
    return this.onSave(config, adapt);
  }
}
