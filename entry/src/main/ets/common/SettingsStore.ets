import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { Log } from './Logger';

const STORE_NAME: string = 'kiosk_prefs';

export const KEY_LAT: string = 'lat';
export const KEY_LON: string = 'lon';
export const KEY_CITY: string = 'city';
export const KEY_WEATHER_INTERVAL: string = 'weatherIntervalSec';
export const KEY_FEED_URL: string = 'feedUrl';
export const KEY_FEED_INTERVAL: string = 'feedIntervalSec';
export const KEY_NOTES: string = 'notesJson';
export const KEY_KEEP_SCREEN_ON: string = 'keepScreenOn';
export const KEY_LANDSCAPE: string = 'landscape';
export const KEY_LOCATION_VERSION: string = 'locationVersion';
export const KEY_STOCK_ENABLED: string = 'stockEnabled';
export const KEY_STOCK_SUMMARY_URL: string = 'stockSummaryUrl';
export const KEY_STOCK_REFRESH: string = 'stockRefreshSec';

export class Settings {
  lat: number = 22.5431;
  lon: number = 114.0579;
  city: string = '深圳';
  weatherIntervalSec: number = 900;
  feedUrl: string = '';
  feedIntervalSec: number = 60;
  notes: string[] = ['推送照片: 在电脑上运行 bash scripts/push-photos.sh'];
  keepScreenOn: boolean = true;
  landscape: boolean = true;
  stockEnabled: boolean = true;
  stockSummaryUrl: string = 'https://raw.githubusercontent.com/Yuanyuan669/ohos-kiosk/main/feed/kiosk_summary.json';
  stockRefreshSec: number = 300;
}

export class SettingsStore {
  private static async store(context: common.Context): Promise<preferences.Preferences> {
    return await preferences.getPreferences(context, STORE_NAME);
  }

  static async load(context: common.Context): Promise<Settings> {
    const s: Settings = new Settings();
    try {
      const p: preferences.Preferences = await SettingsStore.store(context);
      s.lat = await p.get(KEY_LAT, s.lat) as number;
      s.lon = await p.get(KEY_LON, s.lon) as number;
      s.city = await p.get(KEY_CITY, s.city) as string;
      s.weatherIntervalSec = await p.get(KEY_WEATHER_INTERVAL, s.weatherIntervalSec) as number;
      s.feedUrl = await p.get(KEY_FEED_URL, s.feedUrl) as string;
      s.feedIntervalSec = await p.get(KEY_FEED_INTERVAL, s.feedIntervalSec) as number;
      s.keepScreenOn = await p.get(KEY_KEEP_SCREEN_ON, s.keepScreenOn) as boolean;
      s.landscape = await p.get(KEY_LANDSCAPE, s.landscape) as boolean;
      s.stockEnabled = await p.get(KEY_STOCK_ENABLED, s.stockEnabled) as boolean;
      s.stockSummaryUrl = await p.get(KEY_STOCK_SUMMARY_URL, s.stockSummaryUrl) as string;
      s.stockRefreshSec = await p.get(KEY_STOCK_REFRESH, s.stockRefreshSec) as number;
      const notesRaw: string = await p.get(KEY_NOTES, '[]') as string;
      const parsed: string[] = JSON.parse(notesRaw) as string[];
      if (parsed.length > 0) {
        s.notes = parsed;
      }
      const locVersion: number = await p.get(KEY_LOCATION_VERSION, 0) as number;
      if (locVersion < 1) {
        s.city = '深圳';
        s.lat = 22.5431;
        s.lon = 114.0579;
        await p.put(KEY_CITY, s.city);
        await p.put(KEY_LAT, s.lat);
        await p.put(KEY_LON, s.lon);
        await p.put(KEY_LOCATION_VERSION, 1);
        await p.flush();
      }
    } catch (e) {
      Log.warn('settings load failed, using defaults: ' + (e as Error).message);
    }
    return s;
  }

  static async save(context: common.Context, s: Settings): Promise<void> {
    try {
      const p: preferences.Preferences = await SettingsStore.store(context);
      await p.put(KEY_LAT, s.lat);
      await p.put(KEY_LON, s.lon);
      await p.put(KEY_CITY, s.city);
      await p.put(KEY_WEATHER_INTERVAL, s.weatherIntervalSec);
      await p.put(KEY_FEED_URL, s.feedUrl);
      await p.put(KEY_FEED_INTERVAL, s.feedIntervalSec);
      await p.put(KEY_KEEP_SCREEN_ON, s.keepScreenOn);
      await p.put(KEY_LANDSCAPE, s.landscape);
      await p.put(KEY_STOCK_ENABLED, s.stockEnabled);
      await p.put(KEY_STOCK_SUMMARY_URL, s.stockSummaryUrl);
      await p.put(KEY_STOCK_REFRESH, s.stockRefreshSec);
      await p.put(KEY_NOTES, JSON.stringify(s.notes));
      await p.put(KEY_LOCATION_VERSION, 1);
      await p.flush();
      Log.info('settings saved');
    } catch (e) {
      Log.error('settings save failed: ' + (e as Error).message);
    }
  }
}
