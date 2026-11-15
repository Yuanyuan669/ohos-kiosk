import window from '@ohos.window';
import { Log } from './Logger';
import { Settings } from './SettingsStore';

export class KioskSetup {
  static async apply(win: window.Window, s: Settings): Promise<void> {
    if (s.landscape) {
      await KioskSetup.safe('setPreferredOrientation(landscape)', () => {
        return win.setPreferredOrientation(window.Orientation.LANDSCAPE);
      });
    } else {
      await KioskSetup.safe('setPreferredOrientation(portrait)', () => {
        return win.setPreferredOrientation(window.Orientation.PORTRAIT);
      });
    }

    await KioskSetup.safe('setWindowLayoutFullScreen', () => {
      return win.setWindowLayoutFullScreen(true);
    });

    await KioskSetup.safe('setWindowSystemBarEnable([])', () => {
      return win.setWindowSystemBarEnable([]);
    });

    if (s.keepScreenOn) {
      await KioskSetup.safe('setWindowKeepScreenOn(true)', () => {
        return win.setWindowKeepScreenOn(true);
      });
    }
  }

  private static async safe(label: string, call: () => Promise<void>): Promise<void> {
    try {
      await call();
      Log.info('window api ok: ' + label);
    } catch (e) {
      Log.warn('window api unsupported: ' + label + ' -> ' + (e as Error).message);
    }
  }
}
