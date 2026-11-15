import http from '@ohos.net.http';
import {
  WeatherSnapshot, WeatherCodec, FeedSnapshot, FeedPayload,
  KioskSummary, GlobalQuote
} from '../model/Types';
import { Log } from '../common/Logger';

const WEATHER_BASE: string = 'https://api.open-meteo.com/v1/forecast';
// 备用源：open-meteo 走 Hetzner，国内不少出口直接 reset，这时代价小、无需 key 的 wttr.in 能顶上。
const WEATHER_FALLBACK_BASE: string = 'https://wttr.in/';
const CONNECT_TIMEOUT: number = 8000;
const READ_TIMEOUT: number = 8000;

class RefererHeader {
  Referer: string = '';
}

export class HttpProbe {
  static async getString(url: string, timeoutMs: number = CONNECT_TIMEOUT, referer: string = ''): Promise<string> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const opt: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs
      };
      if (referer.length > 0) {
        const h: RefererHeader = new RefererHeader();
        h.Referer = referer;
        opt.header = h;
      }
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
    const url: string = WEATHER_BASE + '?latitude=' + lat + '&longitude=' + lon
      + '&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,'
      + 'wind_speed_10m,wind_direction_10m,is_day&timezone=auto';
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
          humidity: 0,
          apparentTemperature: 0,
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

const SINA_URL: string =
  'https://hq.sinajs.cn/list=s_sh000001,s_sz399001,s_sz399006,int_hangseng,int_dji,int_nasdaq,int_sp500,hf_GC,hf_SI,hf_CL,hf_OIL';
const SINA_REFERER: string = 'https://finance.sina.com.cn';
const SUMMARY_FALLBACKS: string[] = [
  'https://raw.githubusercontent.com/Yuanyuan669/ohos-kiosk/main/feed/kiosk_summary.json',
  'https://ghproxy.net/https://raw.githubusercontent.com/Yuanyuan669/ohos-kiosk/main/feed/kiosk_summary.json',
  'https://ghfast.top/https://raw.githubusercontent.com/Yuanyuan669/ohos-kiosk/main/feed/kiosk_summary.json',
  'https://cdn.statically.io/gh/Yuanyuan669/ohos-kiosk/main/feed/kiosk_summary.json',
  'https://cdn.jsdelivr.net/gh/Yuanyuan669/ohos-kiosk@main/feed/kiosk_summary.json'
];

export class StockService {
  static async fetchSummary(url: string): Promise<KioskSummary | null> {
    const candidates: string[] = [];
    if (url.length > 0) {
      candidates.push(url);
    }
    for (let i = 0; i < SUMMARY_FALLBACKS.length; i++) {
      if (SUMMARY_FALLBACKS[i] !== url) {
        candidates.push(SUMMARY_FALLBACKS[i]);
      }
    }
    if (candidates.length === 0) {
      return null;
    }
    let lastError: string = '';
    for (let i = 0; i < candidates.length; i++) {
      const candidate: string = candidates[i];
      try {
        const body: string = await HttpProbe.getString(candidate, 6000);
        const summary: KioskSummary = JSON.parse(body) as KioskSummary;
        if (summary === null || summary.generated_at === undefined) {
          throw new Error('empty summary');
        }
        Log.info('stock summary ok via ' + candidate + ' @ ' + summary.generated_at);
        return summary;
      } catch (e) {
        lastError = (e as Error).message;
        Log.warn('stock summary failed (' + candidate + '): ' + lastError);
      }
    }
    Log.warn('stock summary all failed: ' + lastError);
    return null;
  }

  static async fetchGlobals(): Promise<GlobalQuote[]> {
    try {
      const body: string = await HttpProbe.getString(SINA_URL, 7000, SINA_REFERER);
      const quotes: GlobalQuote[] = StockService.parseSina(body);
      Log.info('global quotes ok ' + quotes.length);
      return quotes;
    } catch (e) {
      Log.warn('global quotes failed: ' + (e as Error).message);
      return [];
    }
  }

  private static parseSina(body: string): GlobalQuote[] {
    const quotes: GlobalQuote[] = [];
    const lines: string[] = body.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      const marker: string = 'hq_str_';
      const start: number = line.indexOf(marker);
      if (start < 0) {
        continue;
      }
      const eq: number = line.indexOf('="', start);
      if (eq < 0) {
        continue;
      }
      const end: number = line.indexOf('"', eq + 2);
      if (end < 0) {
        continue;
      }
      const key: string = line.substring(start + marker.length, eq);
      const value: string = line.substring(eq + 2, end);
      const parts: string[] = value.split(',');
      if (parts.length < 2) {
        continue;
      }
      const name: string = StockService.labelFor(key);
      if (name.length === 0) {
        continue;
      }
      let rawPrice: string = '';
      let rawPct: string = '';
      if (key.indexOf('s_') === 0 || key.indexOf('int_') === 0) {
        rawPrice = parts[1];
        rawPct = parts.length > 3 ? parts[3] : '';
      } else if (key.indexOf('hf_') === 0) {
        rawPrice = parts[0];
      }
      const price: number = Number(rawPrice);
      if (Number.isNaN(price) || price === 0) {
        continue;
      }
      if (key.indexOf('hf_') === 0 && parts.length > 7) {
        const prev: number = Number(parts[7]);
        if (!Number.isNaN(prev) && prev > 0) {
          const diff: number = (price - prev) / prev * 100;
          rawPct = '' + diff;
        }
      }
      let pct: string = '';
      if (rawPct.length > 0) {
        const p: number = Number(rawPct);
        if (!Number.isNaN(p)) {
          pct = (p >= 0 ? '+' : '') + p.toFixed(2) + '%';
        }
      }
      quotes.push({
        key: key,
        name: name,
        price: price.toFixed(2),
        pct: pct
      });
    }
    return quotes;
  }

  private static labelFor(key: string): string {
    if (key === 's_sh000001') {
      return '上证';
    }
    if (key === 's_sz399001') {
      return '深成';
    }
    if (key === 's_sz399006') {
      return '创业板';
    }
    if (key === 'int_hangseng') {
      return '恒生';
    }
    if (key === 'int_dji') {
      return '道指';
    }
    if (key === 'int_nasdaq') {
      return '纳指';
    }
    if (key === 'int_sp500') {
      return '标普';
    }
    if (key === 'hf_GC') {
      return '黄金';
    }
    if (key === 'hf_SI') {
      return '白银';
    }
    if (key === 'hf_CL') {
      return 'WTI';
    }
    if (key === 'hf_OIL') {
      return '布伦特';
    }
    return '';
  }
}
