import http from '@ohos.net.http';
import { WeatherSnapshot, WeatherCodec, FeedSnapshot, FeedPayload } from '../model/Types';
import { Log } from '../common/Logger';

const WEATHER_BASE: string = 'https://api.open-meteo.com/v1/forecast';
// 备用源：open-meteo 走 Hetzner，国内不少出口直接 reset，这时代价小、无需 key 的 wttr.in 能顶上。
const WEATHER_FALLBACK_BASE: string = 'https://wttr.in/';
const CONNECT_TIMEOUT: number = 8000;
const READ_TIMEOUT: number = 8000;

export class HttpProbe {
  static async getString(url: string, timeoutMs: number = CONNECT_TIMEOUT): Promise<string> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const opt: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs
      };
      const resp: http.HttpResponse = await req.request(url, opt);
      if (resp.responseCode !== 200) {
        throw new Error('http ' + resp.responseCode);
      }
      return resp.result as string;
    } finally {
      req.destroy();
    }
  }
}

export class WeatherService {
  static async fetch(lat: number, lon: number): Promise<WeatherSnapshot> {
    const url: string =
      WEATHER_BASE + '?latitude=' + lat + '&longitude=' + lon + '&current_weather=true&timezone=auto';
    try {
      const body: string = await HttpProbe.getString(url, 6000);
      const snap: WeatherSnapshot = WeatherCodec.parse(body);
      Log.info('weather ok ' + snap.temperature + 'C ' + snap.text + ' code=' + snap.code);
      return snap;
    } catch (e) {
      const msg: string = (e as Error).message;
      Log.warn('weather primary failed: ' + msg + '，试备用源 wttr.in');
      const fbUrl: string = WEATHER_FALLBACK_BASE + lat + ',' + lon + '?format=j1';
      try {
        const fbBody: string = await HttpProbe.getString(fbUrl, 9000);
        const fbSnap: WeatherSnapshot = WeatherCodec.parseWttr(fbBody);
        Log.info('weather fallback ok ' + fbSnap.temperature + 'C ' + fbSnap.text);
        return fbSnap;
      } catch (e2) {
        const all: string = msg + ' / 备用: ' + (e2 as Error).message;
        Log.warn('weather failed: ' + all);
        const bad: WeatherSnapshot = {
          temperature: 0,
          windSpeed: 0,
          windDirection: 0,
          code: -1,
          text: '离线',
          fetchedAt: Date.now(),
          ok: false,
          error: all
        };
        return bad;
      }
    }
  }
}

export class FeedService {
  static async fetch(url: string): Promise<FeedSnapshot> {
    if (url.length === 0) {
      const empty: FeedSnapshot = {
        title: '自定义信息源未配置',
        lines: ['在设置页填写 JSON 接口地址，形如 {"title":"...","lines":["..."]}'],
        fetchedAt: Date.now(),
        ok: false,
        error: ''
      };
      return empty;
    }
    try {
      const body: string = await HttpProbe.getString(url);
      const payload: FeedPayload = WeatherCodec.feedParse(body);
      const good: FeedSnapshot = {
        title: payload.title,
        lines: payload.lines,
        fetchedAt: Date.now(),
        ok: true,
        error: ''
      };
      return good;
    } catch (e) {
      const msg: string = (e as Error).message;
      Log.warn('feed failed: ' + msg);
      const bad: FeedSnapshot = {
        title: '自定义信息源不可达',
        lines: [],
        fetchedAt: Date.now(),
        ok: false,
        error: msg
      };
      return bad;
    }
  }
}
