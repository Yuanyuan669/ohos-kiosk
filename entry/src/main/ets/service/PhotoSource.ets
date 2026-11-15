import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import common from '@ohos.app.ability.common';
import { Log } from '../common/Logger';

const PHOTO_DIR_NAME: string = 'photos';
const ALLOWED: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'];
const MAX_EDGE: number = 1280;

export class PhotoSource {
  static dir(context: common.Context): string {
    return context.filesDir + '/' + PHOTO_DIR_NAME;
  }

  static ensureDir(context: common.Context): void {
    const path: string = PhotoSource.dir(context);
    try {
      if (!fs.accessSync(path)) {
        fs.mkdirSync(path);
        Log.info('created photo dir ' + path);
      }
    } catch (e) {
      Log.warn('ensureDir failed: ' + (e as Error).message);
    }
  }

  static list(context: common.Context): string[] {
    const path: string = PhotoSource.dir(context);
    const out: string[] = [];
    try {
      const names: string[] = fs.listFileSync(path);
      for (let i = 0; i < names.length; i++) {
        const lower: string = names[i].toLowerCase();
        for (let k = 0; k < ALLOWED.length; k++) {
          if (lower.endsWith(ALLOWED[k])) {
            out.push(path + '/' + names[i]);
            break;
          }
        }
      }
      out.sort();
    } catch (e) {
      Log.warn('list photos failed: ' + (e as Error).message);
    }
    return out;
  }

  static async decode(filePath: string): Promise<image.PixelMap | null> {
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const size: image.Size = { width: MAX_EDGE, height: MAX_EDGE };
      const opts: image.DecodingOptions = { editable: false, desiredSize: size };
      const pm: image.PixelMap = await source.createPixelMap(opts);
      return pm;
    } catch (e) {
      Log.warn('decode failed ' + filePath + ': ' + (e as Error).message);
      return null;
    } finally {
      if (source !== null) {
        await source.release();
      }
      if (file !== null) {
        fs.closeSync(file);
      }
    }
  }

  static async releaseMap(pm: image.PixelMap | null): Promise<void> {
    if (pm !== null) {
      try {
        await pm.release();
      } catch (e) {
        Log.warn('pixelmap release failed');
      }
    }
  }
}
