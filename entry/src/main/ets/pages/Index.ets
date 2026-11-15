import router from '@ohos.router';
import image from '@ohos.multimedia.image';
import common from '@ohos.app.ability.common';
import deviceInfo from '@ohos.deviceInfo';
import { Log } from '../common/Logger';
import { pad, stamp, windName, WEEKDAYS } from '../common/Format';
import { SettingsStore, Settings } from '../common/SettingsStore';
import { WeatherService, FeedService } from '../service/HttpServices';
import { PhotoSource } from '../service/PhotoSource';
import { WeatherSnapshot, FeedSnapshot } from '../model/Types';

const PHOTO_ROTATE_SEC: number = 15;
const RETRY_SEC: number = 120;
const APP_VERSION: string = '1.0.0';

@Entry
@Component
struct Index {
  @State clockText: string = '--:--:--';
  @State dateText: string = '----';
  @State cityText: string = '--';
  @State tempText: string = '--';
  @State weatherText: string = '连接中';
  @State weatherDetail: string = '';
  @State feedTitle: string = '自定义信息源';
  @State feedLines: string[] = [];
  @State notes: string[] = [];
  @State photo: image.PixelMap | null = null;
  @State photoIndex: number = 0;
  @State photoCount: number = 0;
  @State statusText: string = '启动';
  private settings: Settings = new Settings();
  private paths: string[] = [];
  private nextWeatherAt: number = 0;
  private nextFeedAt: number = 0;
  private nextPhotoAt: number = 0;
  private tickId: number = -1;
  private busyWeather: boolean = false;
  private busyFeed: boolean = false;

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    Log.info('index appear, api=' + deviceInfo.sdkApiVersion);
    SettingsStore.load(ctx).then((s: Settings) => {
      this.settings = s;
      this.cityText = s.city;
      this.notes = s.notes;
      this.reloadPhotos(ctx);
      this.heartbeat(Date.now());
    });
    this.tickId = setInterval(() => {
      this.onTick();
    }, 1000);
    this.tickClock();
  }

  aboutToDisappear(): void {
    if (this.tickId >= 0) {
      clearInterval(this.tickId);
      this.tickId = -1;
    }
    PhotoSource.releaseMap(this.photo);
  }

  onPageShow(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    SettingsStore.load(ctx).then((s: Settings) => {
      this.settings = s;
      this.cityText = s.city;
      this.notes = s.notes;
      this.reloadPhotos(ctx);
      Log.info('settings reloaded after page show');
    });
  }

  onTick(): void {
    this.tickClock();
    this.heartbeat(Date.now());
  }

  tickClock(): void {
    const d: Date = new Date();
    this.clockText = pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
    this.dateText = d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate())
      + '  ' + WEEKDAYS[d.getDay()];
  }

  heartbeat(now: number): void {
    if (now >= this.nextWeatherAt) {
      this.refreshWeather();
    }
    if (now >= this.nextFeedAt) {
      this.refreshFeed();
    }
    if (this.photoCount > 1 && now >= this.nextPhotoAt) {
      this.stepPhoto(now, 1);
    }
  }

  refreshWeather(): void {
    if (this.busyWeather) {
      return;
    }
    this.busyWeather = true;
    WeatherService.fetch(this.settings.lat, this.settings.lon).then((w: WeatherSnapshot) => {
      if (w.ok) {
        this.tempText = w.temperature.toFixed(1) + '°C';
        this.weatherText = w.text;
        this.weatherDetail = '风 ' + w.windSpeed.toFixed(0) + ' km/h ' + windName(w.windDirection);
        this.statusText = '天气已更新 ' + stamp(Date.now());
        this.nextWeatherAt = Date.now() + this.settings.weatherIntervalSec * 1000;
      } else {
        this.weatherText = '离线';
        this.weatherDetail = w.error;
        this.statusText = '天气不可达，' + RETRY_SEC + 's 后重试';
        this.nextWeatherAt = Date.now() + RETRY_SEC * 1000;
      }
      this.busyWeather = false;
    });
  }

  refreshFeed(): void {
    if (this.busyFeed) {
      return;
    }
    this.busyFeed = true;
    FeedService.fetch(this.settings.feedUrl).then((f: FeedSnapshot) => {
      this.feedTitle = f.title;
      this.feedLines = f.lines;
      if (f.ok) {
        this.nextFeedAt = Date.now() + this.settings.feedIntervalSec * 1000;
      } else {
        this.nextFeedAt = Date.now() + RETRY_SEC * 1000;
      }
      this.busyFeed = false;
    });
  }

  reloadPhotos(ctx: common.UIAbilityContext): void {
    PhotoSource.ensureDir(ctx);
    this.paths = PhotoSource.list(ctx);
    this.photoCount = this.paths.length;
    this.photoIndex = 0;
    Log.info('photos found ' + this.photoCount);
    if (this.photoCount > 0) {
      this.showPhoto(this.paths[0], Date.now());
    } else {
      this.photo = null;
    }
  }

  stepPhoto(now: number, delta: number): void {
    if (this.photoCount === 0) {
      return;
    }
    this.photoIndex = (this.photoIndex + delta + this.photoCount) % this.photoCount;
    this.showPhoto(this.paths[this.photoIndex], now);
  }

  showPhoto(path: string, now: number): void {
    this.nextPhotoAt = now + PHOTO_ROTATE_SEC * 1000;
    PhotoSource.decode(path).then((pm: image.PixelMap | null) => {
      if (pm === null) {
        this.statusText = '照片解码失败: ' + path;
        return;
      }
      PhotoSource.releaseMap(this.photo);
      this.photo = pm;
    });
  }

  build() {
    Column({ space: 12 }) {
      this.Header()
      Row({ space: 12 }) {
        Column({ space: 12 }) {
          this.WeatherCard()
          this.FeedCard()
        }
        .width('38%')
        .height('100%')

        Column({ space: 12 }) {
          this.PhotoCard()
          this.NoteCard()
        }
        .layoutWeight(1)
        .height('100%')
      }
      .layoutWeight(1)
      .width('100%')

      this.Footer()
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.kiosk_bg'))
  }

  @Builder
  Header() {
    Row() {
      Text(this.clockText)
        .fontSize(46)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.kiosk_text_primary'))
      Column({ space: 2 }) {
        Text(this.dateText)
          .fontSize(15)
          .fontColor($r('app.color.kiosk_text_secondary'))
        Text(this.cityText)
          .fontSize(15)
          .fontColor($r('app.color.kiosk_accent'))
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 14 })

      Blank()
      Text(this.statusText)
        .fontSize(12)
        .fontColor($r('app.color.kiosk_text_secondary'))
        .margin({ right: 12 })
      Button('设置')
        .fontSize(14)
        .backgroundColor($r('app.color.kiosk_card'))
        .fontColor($r('app.color.kiosk_text_primary'))
        .onClick(() => {
          router.pushUrl({ url: 'pages/Settings' });
        })
    }
    .width('100%')
    .height(72)
    .padding({ left: 6, right: 6 })
  }

  @Builder
  WeatherCard() {
    Column({ space: 6 }) {
      Text('天气')
        .fontSize(13)
        .fontColor($r('app.color.kiosk_text_secondary'))
      Row({ space: 10 }) {
        Text(this.tempText)
          .fontSize(38)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.kiosk_text_primary'))
        Text(this.weatherText)
          .fontSize(20)
          .fontColor($r('app.color.kiosk_accent'))
      }
      Text(this.weatherDetail)
        .fontSize(13)
        .fontColor($r('app.color.kiosk_text_secondary'))
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.kiosk_card'))
  }

  @Builder
  FeedCard() {
    Column({ space: 6 }) {
      Text(this.feedTitle)
        .fontSize(13)
        .fontColor($r('app.color.kiosk_text_secondary'))
      if (this.feedLines.length === 0) {
        Text('暂无数据')
          .fontSize(14)
          .fontColor($r('app.color.kiosk_text_secondary'))
      } else {
        Scroll() {
          Column({ space: 4 }) {
            ForEach(this.feedLines, (line: string) => {
              Text(line)
                .fontSize(15)
                .fontColor($r('app.color.kiosk_text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }, (line: string, idx: number) => idx + '_' + line)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .scrollable(ScrollDirection.Vertical)
        .height(140)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .layoutWeight(1)
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.kiosk_card'))
  }

  @Builder
  PhotoCard() {
    Stack() {
      if (this.photo !== null) {
        Image(this.photo)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
      } else {
        Text(this.photoCount === 0
          ? '还没有照片\n运行 bash scripts/push-photos.sh 推送'
          : '照片加载中…')
          .fontSize(15)
          .textAlign(TextAlign.Center)
          .fontColor($r('app.color.kiosk_text_secondary'))
      }
    }
    .width('100%')
    .layoutWeight(1)
    .borderRadius(16)
    .backgroundColor($r('app.color.kiosk_card'))
    .onClick(() => {
      this.stepPhoto(Date.now(), 1);
    })
  }

  @Builder
  NoteCard() {
    Column({ space: 4 }) {
      Text('备忘')
        .fontSize(13)
        .fontColor($r('app.color.kiosk_text_secondary'))
      ForEach(this.notes, (note: string) => {
        Text('· ' + note)
          .fontSize(14)
          .fontColor($r('app.color.kiosk_text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }, (note: string, idx: number) => idx + '_' + note)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height(96)
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.kiosk_card'))
    .onClick(() => {
      router.pushUrl({ url: 'pages/Settings' });
    })
  }

  @Builder
  Footer() {
    Row({ space: 12 }) {
      Text(deviceInfo.deviceType + ' · API ' + deviceInfo.sdkApiVersion + ' · ' + deviceInfo.osFullName)
        .fontSize(11)
        .fontColor($r('app.color.kiosk_text_secondary'))
      Blank()
      Text('HomeKiosk v' + APP_VERSION)
        .fontSize(11)
        .fontColor($r('app.color.kiosk_text_secondary'))
    }
    .width('100%')
    .height(24)
  }
}
