import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { Log } from './Logger';
import { WeatherSnapshot, FeedSnapshot } from '../model/Types';

const STORE_NAME: string = 'kiosk_stale';

const KEY_WEATHER: string = 'stale_weather';
const KEY_AQI: string = 'stale_aqi';
const KEY_FEED_PREFIX: string = 'stale_feed_';

interface AqiCached {
  aqi: number;
  at: number;
}

async function store(context: common.Context): Promise<preferences.Preferences> {
  return await preferences.getPreferences(context, STORE_NAME);
}

// “最后一次成功值”缓存：断网时各卡片显示 stale 数据 + 数据时间，而不是清空。
// 只在成功时写入；失败时读回，配 UI 上的时间标注。
export class StaleCache {
  static async putWeather(context: common.Context, snap: WeatherSnapshot): Promise<void> {
    try {
      const p: preferences.Preferences = await store(context);
      await p.put(KEY_WEATHER, JSON.stringify(snap));
      await p.flush();
    } catch (e) {
      Log.warn('stale put weather failed: ' + (e as Error).message);
    }
  }

  static async getWeather(context: common.Context): Promise<WeatherSnapshot | null> {
    try {
      const p: preferences.Preferences = await store(context);
      const raw: string = await p.get(KEY_WEATHER, '') as string;
      if (raw.length === 0) {
        return null;
      }
      const snap: WeatherSnapshot = JSON.parse(raw) as WeatherSnapshot;
      if (snap === null || !snap.ok) {
        return null;
      }
      return snap;
    } catch (e) {
      Log.warn('stale get weather failed: ' + (e as Error).message);
      return null;
    }
  }

  static async putAqi(context: common.Context, aqi: number): Promise<void> {
    if (aqi < 0) {
      return;
    }
    try {
      const p: preferences.Preferences = await store(context);
      const cached: AqiCached = { aqi: aqi, at: Date.now() };
      await p.put(KEY_AQI, JSON.stringify(cached));
      await p.flush();
    } catch (e) {
      Log.warn('stale put aqi failed: ' + (e as Error).message);
    }
  }

  static async getAqi(context: common.Context): Promise<AqiCached | null> {
    try {
      const p: preferences.Preferences = await store(context);
      const raw: string = await p.get(KEY_AQI, '') as string;
      if (raw.length === 0) {
        return null;
      }
      const cached: AqiCached = JSON.parse(raw) as AqiCached;
      if (cached === null || cached.aqi < 0) {
        return null;
      }
      return cached;
    } catch (e) {
      Log.warn('stale get aqi failed: ' + (e as Error).message);
      return null;
    }
  }

  static async putFeed(context: common.Context, url: string, snap: FeedSnapshot): Promise<void> {
    if (!snap.ok) {
      return;
    }
    try {
      const p: preferences.Preferences = await store(context);
      await p.put(KEY_FEED_PREFIX + url, JSON.stringify(snap));
      await p.flush();
    } catch (e) {
      Log.warn('stale put feed failed: ' + (e as Error).message);
    }
  }

  static async getFeed(context: common.Context, url: string): Promise<FeedSnapshot | null> {
    try {
      const p: preferences.Preferences = await store(context);
      const raw: string = await p.get(KEY_FEED_PREFIX + url, '') as string;
      if (raw.length === 0) {
        return null;
      }
      const snap: FeedSnapshot = JSON.parse(raw) as FeedSnapshot;
      if (snap === null || !snap.ok) {
        return null;
      }
      return snap;
    } catch (e) {
      Log.warn('stale get feed failed: ' + (e as Error).message);
      return null;
    }
  }
}
