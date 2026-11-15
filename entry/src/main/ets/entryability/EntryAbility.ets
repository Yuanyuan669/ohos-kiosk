import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { Log } from '../common/Logger';
import { SettingsStore, Settings } from '../common/SettingsStore';
import { KioskSetup } from '../common/KioskSetup';
import { PhotoSource } from '../service/PhotoSource';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Log.info('ability onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    PhotoSource.ensureDir(this.context);
    windowStage.loadContent('pages/Index').then(() => {
      return windowStage.getMainWindow();
    }).then((win: window.Window) => {
      return SettingsStore.load(this.context).then((s: Settings) => {
        KioskSetup.apply(win, s);
      });
    }).catch((e: Error) => {
      Log.warn('window init failed: ' + e.message);
    });
  }

  onWindowStageDestroy(): void {
    Log.info('ability windowStage destroy');
  }

  onForeground(): void {
    Log.info('ability foreground');
  }

  onBackground(): void {
    Log.info('ability background');
  }
}
