import router from '@ohos.router';
import window from '@ohos.window';
import common from '@ohos.app.ability.common';
import deviceInfo from '@ohos.deviceInfo';
import promptAction from '@ohos.promptAction';
import { Log } from '../common/Logger';
import { SettingsStore, Settings } from '../common/SettingsStore';
import { KioskSetup } from '../common/KioskSetup';
import { PhotoSource } from '../service/PhotoSource';

@Entry
@Component
struct SettingsPage {
  @State city: string = '';
  @State latText: string = '';
  @State lonText: string = '';
  @State weatherIntervalText: string = '';
  @State feedUrl: string = '';
  @State feedIntervalText: string = '';
  @State notesText: string = '';
  @State keepScreenOn: boolean = true;
  @State landscape: boolean = true;
  @State photoDir: string = '';
  @State deviceLine: string = '';

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.photoDir = PhotoSource.dir(ctx);
    this.deviceLine = deviceInfo.brand + ' ' + deviceInfo.productModel
      + ' · API ' + deviceInfo.sdkApiVersion + ' · ' + deviceInfo.osFullName;
    SettingsStore.load(ctx).then((s: Settings) => {
      this.city = s.city;
      this.latText = '' + s.lat;
      this.lonText = '' + s.lon;
      this.weatherIntervalText = '' + s.weatherIntervalSec;
      this.feedUrl = s.feedUrl;
      this.feedIntervalText = '' + s.feedIntervalSec;
      this.notesText = s.notes.join('\n');
      this.keepScreenOn = s.keepScreenOn;
      this.landscape = s.landscape;
    });
  }

  private num(text: string, fallback: number): number {
    const parsed: number = Number.parseFloat(text);
    if (Number.isNaN(parsed)) {
      return fallback;
    }
    return parsed;
  }

  private save(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const s: Settings = new Settings();
    s.city = this.city;
    s.lat = this.num(this.latText, 39.9042);
    s.lon = this.num(this.lonText, 116.4074);
    s.weatherIntervalSec = Math.max(60, Math.round(this.num(this.weatherIntervalText, 900)));
    s.feedUrl = this.feedUrl.trim();
    s.feedIntervalSec = Math.max(15, Math.round(this.num(this.feedIntervalText, 60)));
    s.keepScreenOn = this.keepScreenOn;
    s.landscape = this.landscape;
    const split: string[] = this.notesText.split('\n');
    const notes: string[] = [];
    for (let i = 0; i < split.length; i++) {
      const one: string = split[i].trim();
      if (one.length > 0) {
        notes.push(one);
      }
    }
    s.notes = notes;

    SettingsStore.save(ctx, s).then(() => {
      window.getLastWindow(ctx).then((win: window.Window) => {
        KioskSetup.apply(win, s);
      }).catch((e: Error) => {
        Log.warn('apply window failed: ' + e.message);
      });
      promptAction.showToast({ message: '已保存', duration: 1200 });
    });
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor($r('app.color.kiosk_card'))
          .fontColor($r('app.color.kiosk_text_primary'))
          .onClick(() => {
            router.back();
          })
        Blank()
        Text('信息屏设置')
          .fontSize(18)
          .fontColor($r('app.color.kiosk_text_primary'))
      }
      .width('100%')
      .height(48)

      Text(this.deviceLine)
        .fontSize(12)
        .fontColor($r('app.color.kiosk_text_secondary'))
        .width('100%')

      Scroll() {
        Column({ space: 12 }) {
          Row({ space: 10 }) {
            Text('城市名')
              .fontSize(14)
              .fontColor($r('app.color.kiosk_text_secondary'))
              .width(110)
            TextInput({ text: this.city, placeholder: '显示在左上角' })
              .fontSize(14)
              .backgroundColor($r('app.color.kiosk_card'))
              .fontColor($r('app.color.kiosk_text_primary'))
              .layoutWeight(1)
              .onChange((v: string) => {
                this.city = v;
              })
          }
          .width('100%')

          Row({ space: 10 }) {
            Text('纬度 / 经度')
              .fontSize(14)
              .fontColor($r('app.color.kiosk_text_secondary'))
              .width(110)
            TextInput({ text: this.latText, placeholder: '39.9042' })
              .fontSize(14)
              .backgroundColor($r('app.color.kiosk_card'))
              .fontColor($r('app.color.kiosk_text_primary'))
              .layoutWeight(1)
              .onChange((v: string) => {
                this.latText = v;
              })
            TextInput({ text: this.lonText, placeholder: '116.4074' })
              .fontSize(14)
              .backgroundColor($r('app.color.kiosk_card'))
              .fontColor($r('app.color.kiosk_text_primary'))
              .layoutWeight(1)
              .onChange((v: string) => {
                this.lonText = v;
              })
          }
          .width('100%')

          Row({ space: 10 }) {
            Text('天气刷新秒')
              .fontSize(14)
              .fontColor($r('app.color.kiosk_text_secondary'))
              .width(110)
            TextInput({ text: this.weatherIntervalText, placeholder: '最小 60' })
              .type(InputType.Number)
              .fontSize(14)
              .backgroundColor($r('app.color.kiosk_card'))
              .fontColor($r('app.color.kiosk_text_primary'))
              .layoutWeight(1)
              .onChange((v: string) => {
                this.weatherIntervalText = v;
              })
          }
          .width('100%')

          Row({ space: 10 }) {
            Text('信息源 URL')
              .fontSize(14)
              .fontColor($r('app.color.kiosk_text_secondary'))
              .width(110)
            TextInput({ text: this.feedUrl, placeholder: '返回 {"title":"","lines":[]} 的接口' })
              .fontSize(12)
              .backgroundColor($r('app.color.kiosk_card'))
              .fontColor($r('app.color.kiosk_text_primary'))
              .layoutWeight(1)
              .onChange((v: string) => {
                this.feedUrl = v;
              })
          }
          .width('100%')

          Row({ space: 10 }) {
            Text('信息源刷新秒')
              .fontSize(14)
              .fontColor($r('app.color.kiosk_text_secondary'))
              .width(110)
            TextInput({ text: this.feedIntervalText, placeholder: '最小 15' })
              .type(InputType.Number)
              .fontSize(14)
              .backgroundColor($r('app.color.kiosk_card'))
              .fontColor($r('app.color.kiosk_text_primary'))
              .layoutWeight(1)
              .onChange((v: string) => {
                this.feedIntervalText = v;
              })
          }
          .width('100%')

          Column({ space: 4 }) {
            Text('备忘（每行一条）')
              .fontSize(13)
              .fontColor($r('app.color.kiosk_text_secondary'))
            TextArea({ text: this.notesText, placeholder: '一行一条' })
              .fontSize(14)
              .height(120)
              .backgroundColor($r('app.color.kiosk_card'))
              .fontColor($r('app.color.kiosk_text_primary'))
              .onChange((v: string) => {
                this.notesText = v;
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Row({ space: 10 }) {
            Text('屏幕常亮')
              .fontSize(14)
              .fontColor($r('app.color.kiosk_text_secondary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.keepScreenOn })
              .onChange((isOn: boolean) => {
                this.keepScreenOn = isOn;
              })
          }
          .width('100%')

          Row({ space: 10 }) {
            Text('强制横屏')
              .fontSize(14)
              .fontColor($r('app.color.kiosk_text_secondary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.landscape })
              .onChange((isOn: boolean) => {
                this.landscape = isOn;
              })
          }
          .width('100%')

          Text('照片目录：' + this.photoDir)
            .fontSize(11)
            .fontColor($r('app.color.kiosk_text_secondary'))
            .width('100%')

          Button('保存并应用')
            .width('100%')
            .onClick(() => {
              this.save();
            })
        }
        .width('100%')
        .padding({ bottom: 20 })
      }
      .scrollable(ScrollDirection.Vertical)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.kiosk_bg'))
  }
}
