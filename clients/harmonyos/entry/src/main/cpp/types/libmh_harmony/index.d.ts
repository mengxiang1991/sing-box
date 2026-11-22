export function checkProfile(config: string): boolean;
export function start(config: string, directory: string): boolean;
export function status(): string;
export function setTunnel(fd: number): boolean;
export function stop(): void;
export function control(action: string, group: string, node: string): boolean;
export function rules(config: string, rules?: string): string;
