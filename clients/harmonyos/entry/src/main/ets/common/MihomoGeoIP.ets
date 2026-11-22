import { resourceManager } from '@kit.LocalizationKit';
import { fileIo } from '@kit.CoreFileKit';

export async function seedMihomoGeoIP(filesDir: string, resources: resourceManager.ResourceManager): Promise<void> {
  const directory = `${filesDir}/mihomo`;
  const target = `${directory}/Country.mmdb`;
  if (fileIo.accessSync(target)) {
    console.info('Mihomo Country.mmdb cache found');
    return;
  }
  let data: Uint8Array;
  try {
    data = await resources.getRawFileContent('mihomo-country.mmdb');
  } catch (_) {
    console.info('Mihomo GEOIP resource unavailable');
    return;
  }
  if (!fileIo.accessSync(directory)) { fileIo.mkdirSync(directory, true); }
  const temp = `${target}.seed-${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
  try {
    const file = fileIo.openSync(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const bytes = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
      if (fileIo.writeSync(file.fd, bytes) !== data.byteLength) { throw new Error('GEOIP 数据库写入不完整'); }
    } finally {
      fileIo.closeSync(file);
    }
    if (!fileIo.accessSync(target)) { fileIo.renameSync(temp, target); }
    console.info('Mihomo bundled GEOIP database prepared');
  } finally {
    if (fileIo.accessSync(temp)) { fileIo.unlinkSync(temp); }
  }
}
