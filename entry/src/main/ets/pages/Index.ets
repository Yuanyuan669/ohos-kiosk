import router from '@ohos.router';
import image from '@ohos.multimedia.image';
import common from '@ohos.app.ability.common';
import deviceInfo from '@ohos.deviceInfo';
import util from '@ohos.util';
import { Log } from '../common/Logger';
import { pad, stamp, windName, WEEKDAYS } from '../common/Format';
import { SettingsStore, Settings } from '../common/SettingsStore';
import { WeatherService, FeedService, StockService } from '../service/HttpServices';
import { PhotoSource } from '../service/PhotoSource';
import {
  WeatherSnapshot, FeedSnapshot, KioskSummary, GlobalQuote,
  KioskIndex, KioskWatch, KioskNewsItem, TodoItem
} from '../model/Types';

const PHOTO_ROTATE_SEC: number = 15;
const STOCK_PAGE_SEC: number = 20;
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
  @State todos: TodoItem[] = [];
  @State photo: image.PixelMap | null = null;
  @State photoIndex: number = 0;
  @State photoCount: number = 0;
  @State stock: KioskSummary | null = null;
  @State globals: GlobalQuote[] = [];
  @State fallbackIndices: KioskIndex[] = [];
  @State stockPage: number = 0;
  @State statusText: string = '启动';
  private settings: Settings = new Settings();
  private bundledStock: KioskSummary | null = null;
  private paths: string[] = [];
  private nextWeatherAt: number = 0;
  private nextFeedAt: number = 0;
  private nextPhotoAt: number = 0;
  private nextStockAt: number = 0;
  private nextStockPageAt: number = 0;
  private tickId: number = -1;
  private busyWeather: boolean = false;
  private busyFeed: boolean = false;
  private busyStock: boolean = false;

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    Log.info('index appear, api=' + deviceInfo.sdkApiVersion);
    SettingsStore.load(ctx).then((s: Settings) => {
      this.settings = s;
      this.cityText = s.city;
      this.notes = s.notes;
      this.todos = s.todos;
      this.reloadPhotos(ctx);
      this.loadBundledStock(ctx);
      this.heartbeat(Date.now());
      this.refreshStock();
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
      this.todos = s.todos;
      this.reloadPhotos(ctx);
      this.refreshStock();
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
    if (this.settings.stockEnabled && now >= this.nextStockAt) {
      this.refreshStock();
    }
    if (this.stock !== null && now >= this.nextStockPageAt) {
      this.stockPage = (this.stockPage + 1) % this.stockPageCount();
      this.nextStockPageAt = now + STOCK_PAGE_SEC * 1000;
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
        this.weatherDetail = '体感 ' + w.apparentTemperature.toFixed(1) + '°C · 湿度 '
          + w.humidity.toFixed(0) + '% · 风 ' + w.windSpeed.toFixed(0) + 'km/h '
          + windName(w.windDirection);
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

  stockPageCount(): number {
    return 4;
  }

  loadBundledStock(ctx: common.UIAbilityContext): void {
    ctx.resourceManager.getRawFileContent('kiosk_summary.json').then((data: Uint8Array) => {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const text: string = decoder.decodeWithStream(data, { stream: false });
      const summary: KioskSummary = JSON.parse(text) as KioskSummary;
      this.bundledStock = summary;
      if (this.stock === null && this.settings.stockEnabled) {
        this.stock = summary;
        this.nextStockPageAt = Date.now() + STOCK_PAGE_SEC * 1000;
        this.refreshGlobals();
      }
      Log.info('bundled stock loaded ' + summary.generated_at);
    }).catch((e: Error) => {
      Log.warn('bundled stock load failed: ' + e.message);
    });
  }

  refreshStock(): void {
    if (!this.settings.stockEnabled || this.settings.stockSummaryUrl.length === 0) {
      this.stock = null;
      this.globals = [];
      this.fallbackIndices = [];
      return;
    }
    if (this.busyStock) {
      return;
    }
    this.busyStock = true;
    StockService.fetchSummary(this.settings.stockSummaryUrl).then((s: KioskSummary | null) => {
      if (s === null) {
        if (this.bundledStock !== null) {
          this.stock = this.bundledStock;
          this.refreshGlobals();
        } else {
          this.stock = null;
          this.globals = [];
          this.fallbackIndices = [];
        }
        this.nextStockAt = Date.now() + RETRY_SEC * 1000;
        this.busyStock = false;
        return;
      }
      this.stock = s;
      if (this.stockPage >= this.stockPageCount()) {
        this.stockPage = 0;
      }
      this.nextStockAt = Date.now() + Math.max(60, this.settings.stockRefreshSec) * 1000;
      if (this.nextStockPageAt === 0) {
        this.nextStockPageAt = Date.now() + STOCK_PAGE_SEC * 1000;
      }
      this.busyStock = false;
      this.refreshGlobals();
    });
  }

  refreshGlobals(): void {
    StockService.fetchGlobals().then((g: GlobalQuote[]) => {
      const indexes: KioskIndex[] = [];
      const rest: GlobalQuote[] = [];
      for (let i = 0; i < g.length; i++) {
        if (g[i].key.indexOf('s_') === 0) {
          indexes.push(this.toIndex(g[i]));
        } else {
          rest.push(g[i]);
        }
      }
      this.fallbackIndices = indexes;
      this.globals = rest;
    });
  }

  toIndex(q: GlobalQuote): KioskIndex {
    let pct: number = 0;
    if (q.pct.length > 0) {
      const raw: string = q.pct.endsWith('%') ? q.pct.substring(0, q.pct.length - 1) : q.pct;
      const parsed: number = Number(raw);
      if (!Number.isNaN(parsed)) {
        pct = parsed;
      }
    }
    const price: number = Number(q.price);
    const index: KioskIndex = {
      name: q.name,
      close: Number.isNaN(price) ? 0 : price,
      pct: pct
    };
    return index;
  }

  stockTitle(): string {
    if (this.stockPage === 0) {
      return 'A 股 · 市场';
    }
    if (this.stockPage === 1) {
      return '自选股';
    }
    if (this.stockPage === 2) {
      return '全球 / 商品';
    }
    return 'FlashQuant · 舆情';
  }

  pctText(pct: number): string {
    return (pct >= 0 ? '+' : '') + pct.toFixed(2) + '%';
  }

  toggleTodo(index: number): void {
    if (index < 0 || index >= this.todos.length) {
      return;
    }
    const updated: TodoItem[] = [];
    for (let i = 0; i < this.todos.length; i++) {
      const current: TodoItem = this.todos[i];
      const item: TodoItem = {
        text: current.text,
        done: i === index ? !current.done : current.done
      };
      updated.push(item);
    }
    this.todos = updated;
    this.settings.todos = updated;
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    SettingsStore.save(ctx, this.settings).catch((e: Error) => {
      Log.warn('save todos failed: ' + e.message);
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

  private weatherIcon(): string {
    const t: string = this.weatherText;
    if (t === '晴') {
      return '☀';
    }
    if (t === '少云') {
      return '🌤';
    }
    if (t === '多云') {
      return '⛅';
    }
    if (t === '阴') {
      return '☁';
    }
    if (t === '雾' || t === '霾') {
      return '🌫';
    }
    if (t === '毛毛雨' || t === '小雨' || t === '大雨' || t === '雨') {
      return '🌧';
    }
    if (t === '阵雨' || t === '局部有雨雪') {
      return '🌦';
    }
    if (t === '雷雨' || t === '雷阵雨') {
      return '⛈';
    }
    if (t === '雪' || t === '阵雪' || t === '雨夹雪') {
      return '❄';
    }
    if (t === '离线') {
      return '📡';
    }
    if (t === '连接中') {
      return '◌';
    }
    return '？';
  }

  private weatherIconColor(): ResourceColor {
    const t: string = this.weatherText;
    if (t === '离线') {
      return $r('app.color.kiosk_err');
    }
    if (t === '晴' || t === '少云') {
      return $r('app.color.kiosk_warn');
    }
    if (t === '雨' || t === '小雨' || t === '大雨' || t === '阵雨'
      || t === '雷雨' || t === '雷阵雨') {
      return $r('app.color.kiosk_accent');
    }
    return $r('app.color.kiosk_text_secondary');
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
          this.MediaCard()
          this.TodoCard()
        }
        .layoutWeight(1)
        .height('100%')
      }
      .layoutWeight(1)
      .width('100%')
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
      Button('退出')
        .fontSize(14)
        .backgroundColor($r('app.color.kiosk_card'))
        .fontColor($r('app.color.kiosk_warn'))
        .margin({ left: 8 })
        .onClick(() => {
          const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
          ctx.terminateSelf().catch((e: Error) => {
            Log.warn('terminateSelf failed: ' + e.message);
          });
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
        Blank()
        Text(this.weatherIcon())
          .fontSize(54)
          .fontColor(this.weatherIconColor())
      }
      Text(this.weatherDetail)
        .fontSize(13)
        .fontColor($r('app.color.kiosk_text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
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
  MediaCard() {
    if (this.stock !== null) {
      this.StockCard()
    } else {
      this.PhotoCard()
    }
  }

  @Builder
  StockCard() {
    Column({ space: 6 }) {
      Row() {
        Text(this.stockTitle())
          .fontSize(13)
          .fontColor($r('app.color.kiosk_text_secondary'))
        Blank()
        Text((this.stockPage + 1) + ' / ' + this.stockPageCount())
          .fontSize(11)
          .fontColor($r('app.color.kiosk_text_secondary'))
      }
      .width('100%')

      if (this.stockPage === 0) {
        this.MarketPanel()
      } else if (this.stockPage === 1) {
        this.WatchPanel()
      } else if (this.stockPage === 2) {
        this.GlobalPanel()
      } else {
        this.NewsPanel()
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .layoutWeight(1)
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.kiosk_card'))
    .onClick(() => {
      this.stockPage = (this.stockPage + 1) % this.stockPageCount();
      this.nextStockPageAt = Date.now() + STOCK_PAGE_SEC * 1000;
    })
  }

  @Builder
  MarketPanel() {
    Column({ space: 4 }) {
      if (this.stock !== null && this.stock.market.indices.length > 0) {
        ForEach(this.stock.market.indices, (item: KioskIndex) => {
          Row() {
            Text(item.name)
              .fontSize(14)
              .fontColor($r('app.color.kiosk_text_primary'))
              .width(72)
            Text(item.close.toFixed(2))
              .fontSize(14)
              .fontColor($r('app.color.kiosk_text_primary'))
              .layoutWeight(1)
              .textAlign(TextAlign.End)
            Text(this.pctText(item.pct))
              .fontSize(13)
              .fontColor(item.pct >= 0 ? $r('app.color.kiosk_ok') : $r('app.color.kiosk_err'))
              .width(66)
              .textAlign(TextAlign.End)
          }
          .width('100%')
        }, (item: KioskIndex) => item.name)
      } else if (this.fallbackIndices.length > 0) {
        ForEach(this.fallbackIndices, (item: KioskIndex) => {
          Row() {
            Text(item.name)
              .fontSize(14)
              .fontColor($r('app.color.kiosk_text_primary'))
              .width(72)
            Text(item.close.toFixed(2))
              .fontSize(14)
              .fontColor($r('app.color.kiosk_text_primary'))
              .layoutWeight(1)
              .textAlign(TextAlign.End)
            Text(this.pctText(item.pct))
              .fontSize(13)
              .fontColor(item.pct >= 0 ? $r('app.color.kiosk_ok') : $r('app.color.kiosk_err'))
              .width(66)
              .textAlign(TextAlign.End)
          }
          .width('100%')
        }, (item: KioskIndex) => item.name)
      } else {
        Text('指数数据待更新')
          .fontSize(14)
          .fontColor($r('app.color.kiosk_text_secondary'))
      }
      Divider()
        .color($r('app.color.kiosk_border'))
        .margin({ top: 4, bottom: 4 })
      if (this.stock !== null) {
        Row() {
          Text('成交 ' + (this.stock.market.turnover_yi / 10000).toFixed(2) + ' 万亿')
            .fontSize(13)
            .fontColor($r('app.color.kiosk_text_secondary'))
          Blank()
          Text('情绪 ' + this.stock.market.sentiment_score + ' · ' + this.stock.market.sentiment_label)
            .fontSize(13)
            .fontColor($r('app.color.kiosk_accent'))
        }
        .width('100%')
        Row() {
          Text('涨 ' + this.stock.market.up_count + ' / 跌 ' + this.stock.market.down_count)
            .fontSize(12)
            .fontColor($r('app.color.kiosk_text_secondary'))
          Blank()
          Text(this.stock.market.date)
            .fontSize(11)
            .fontColor($r('app.color.kiosk_text_secondary'))
        }
        .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  WatchPanel() {
    Column({ space: 3 }) {
      if (this.stock !== null && this.stock.watchlist.length > 0) {
        ForEach(this.stock.watchlist.slice(0, 7), (item: KioskWatch) => {
          Row() {
            Text(item.name)
              .fontSize(13)
              .fontColor($r('app.color.kiosk_text_primary'))
              .width(88)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(item.symbol)
              .fontSize(11)
              .fontColor($r('app.color.kiosk_text_secondary'))
              .width(58)
            Text(item.price.toFixed(2))
              .fontSize(13)
              .fontColor($r('app.color.kiosk_text_primary'))
              .layoutWeight(1)
              .textAlign(TextAlign.End)
            Text(this.pctText(item.pct))
              .fontSize(13)
              .fontColor(item.pct >= 0 ? $r('app.color.kiosk_ok') : $r('app.color.kiosk_err'))
              .width(66)
              .textAlign(TextAlign.End)
          }
          .width('100%')
        }, (item: KioskWatch) => item.symbol + item.name)
      } else {
        Text('自选股数据待更新')
          .fontSize(14)
          .fontColor($r('app.color.kiosk_text_secondary'))
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  GlobalPanel() {
    Column({ space: 3 }) {
      if (this.globals.length > 0) {
        ForEach(this.globals, (item: GlobalQuote) => {
          Row() {
            Text(item.name)
              .fontSize(13)
              .fontColor($r('app.color.kiosk_text_primary'))
              .width(72)
            Text(item.price)
              .fontSize(13)
              .fontColor($r('app.color.kiosk_text_primary'))
              .layoutWeight(1)
              .textAlign(TextAlign.End)
            Text(item.pct.length > 0 ? item.pct : '—')
              .fontSize(12)
              .fontColor(item.pct.length === 0 ? $r('app.color.kiosk_text_secondary') :
                (item.pct.indexOf('-') === 0 ? $r('app.color.kiosk_err') : $r('app.color.kiosk_ok')))
              .width(72)
              .textAlign(TextAlign.End)
          }
          .width('100%')
        }, (item: GlobalQuote) => item.key)
      } else {
        Text('全球行情不可达')
          .fontSize(14)
          .fontColor($r('app.color.kiosk_text_secondary'))
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  NewsPanel() {
    Column({ space: 4 }) {
      if (this.stock !== null) {
        Row() {
          Text('新闻 ' + this.stock.news.kpi.total)
            .fontSize(12)
            .fontColor($r('app.color.kiosk_text_secondary'))
          Blank()
          Text('正 ' + this.stock.news.kpi.pos + ' / 负 ' + this.stock.news.kpi.neg)
            .fontSize(12)
            .fontColor($r('app.color.kiosk_text_secondary'))
        }
        .width('100%')
        if (this.stock.news.top.length === 0) {
          Text('舆情数据待更新')
            .fontSize(14)
            .fontColor($r('app.color.kiosk_text_secondary'))
        } else {
          ForEach(this.stock.news.top.slice(0, 4), (item: KioskNewsItem) => {
            Text('· ' + item.title)
              .fontSize(13)
              .fontColor($r('app.color.kiosk_text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }, (item: KioskNewsItem) => item.ts + item.title)
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  PhotoCard() {
    Stack() {
      if (this.photo !== null) {
        Image(this.photo)
          .objectFit(ImageFit.Cover)
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
  TodoCard() {
    Column({ space: 4 }) {
      Row() {
        Text('待办')
          .fontSize(13)
          .fontColor($r('app.color.kiosk_text_secondary'))
        Blank()
        Text('' + this.todos.length)
          .fontSize(11)
          .fontColor($r('app.color.kiosk_text_secondary'))
      }
      .width('100%')
      if (this.todos.length === 0) {
        Text('暂无待办，去设置添加')
          .fontSize(14)
          .fontColor($r('app.color.kiosk_text_secondary'))
      } else {
        Scroll() {
          Column({ space: 2 }) {
            ForEach(this.todos, (item: TodoItem, idx: number) => {
              Row({ space: 8 }) {
                Text(item.done ? '☑' : '☐')
                  .fontSize(15)
                  .fontColor(item.done ? $r('app.color.kiosk_ok') : $r('app.color.kiosk_accent'))
                Text(item.text)
                  .fontSize(14)
                  .fontColor(item.done ? $r('app.color.kiosk_text_secondary') : $r('app.color.kiosk_text_primary'))
                  .decoration({
                    type: item.done ? TextDecorationType.LineThrough : TextDecorationType.None,
                    color: $r('app.color.kiosk_text_secondary')
                  })
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: 2, bottom: 2 })
              .onClick(() => {
                this.toggleTodo(idx);
              })
            }, (item: TodoItem, idx: number) => idx + '_' + item.text)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .scrollable(ScrollDirection.Vertical)
        .height(104)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height(156)
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.kiosk_card'))
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
