export interface WeatherSnapshot {
  temperature: number;
  windSpeed: number;
  windDirection: number;
  code: number;
  text: string;
  fetchedAt: number;
  ok: boolean;
  error: string;
}

interface OpenMeteoCurrentWeather {
  temperature: number;
  wind_speed: number;
  wind_direction: number;
  // current_weather 里历史上叫 weathercode，hourly 才叫 weather_code，两个都兜住
  weathercode?: number;
  weather_code?: number;
  time: string;
  is_day: number;
}

interface OpenMeteoResponse {
  current_weather: OpenMeteoCurrentWeather;
  error?: string;
  reason?: string;
}

export interface FeedPayload {
  title: string;
  lines: string[];
}

// wttr.in 的 j1 返回结构（谷底备用源；open-meteo 在部分出口被墙时用得上）
interface WttrDesc {
  value: string;
}

interface WttrCurrent {
  temp_C: string;
  windspeedKmph: string;
  winddirDegree: string;
  weatherCode: string;
  weatherDesc: WttrDesc[];
}

interface WttrResponse {
  current_condition: WttrCurrent[];
}

export interface FeedSnapshot {
  title: string;
  lines: string[];
  fetchedAt: number;
  ok: boolean;
  error: string;
}

export class WeatherCodec {
  static parse(raw: string): WeatherSnapshot {
    const parsed: OpenMeteoResponse = JSON.parse(raw) as OpenMeteoResponse;
    const cw: OpenMeteoCurrentWeather = parsed.current_weather;
    let codeNum: number = -1;
    if (cw.weathercode !== undefined) {
      codeNum = cw.weathercode;
    } else if (cw.weather_code !== undefined) {
      codeNum = cw.weather_code;
    }
    const snap: WeatherSnapshot = {
      temperature: cw.temperature,
      windSpeed: cw.wind_speed,
      windDirection: cw.wind_direction,
      code: codeNum,
      text: WeatherCodec.describe(codeNum),
      fetchedAt: Date.now(),
      ok: true,
      error: ''
    };
    return snap;
  }

  static describe(code: number): string {
    if (code === 0) {
      return '晴';
    }
    if (code === 1 || code === 2) {
      return '少云';
    }
    if (code === 3) {
      return '阴';
    }
    if (code === 45 || code === 48) {
      return '雾';
    }
    if (code >= 51 && code <= 57) {
      return '毛毛雨';
    }
    if (code >= 61 && code <= 67) {
      return '雨';
    }
    if (code >= 71 && code <= 77) {
      return '雪';
    }
    if (code >= 80 && code <= 82) {
      return '阵雨';
    }
    if (code >= 85 && code <= 86) {
      return '阵雪';
    }
    if (code >= 95) {
      return '雷雨';
    }
    return '未知';
  }

  static parseWttr(raw: string): WeatherSnapshot {
    const parsed: WttrResponse = JSON.parse(raw) as WttrResponse;
    const cc: WttrCurrent = parsed.current_condition[0];
    if (cc === undefined || cc === null) {
      throw new Error('wttr: 缺少 current_condition');
    }
    // ArkTS 限制 parseInt/parseFloat，用 Number() 转
    const code: number = Number(cc.weatherCode);
    const snap: WeatherSnapshot = {
      temperature: Number(cc.temp_C),
      windSpeed: Number(cc.windspeedKmph),
      windDirection: Number(cc.winddirDegree),
      code: code,
      text: WeatherCodec.describeWwo(code),
      fetchedAt: Date.now(),
      ok: true,
      error: ''
    };
    return snap;
  }

  // WWO 天气代码（wttr.in）-> 中文
  static describeWwo(code: number): string {
    if (code === 113) {
      return '晴';
    }
    if (code === 116) {
      return '少云';
    }
    if (code === 119) {
      return '多云';
    }
    if (code === 122) {
      return '阴';
    }
    if (code === 143 || code === 248 || code === 260) {
      return '雾';
    }
    if (code === 149) {
      return '霾';
    }
    if (code >= 176 && code <= 185) {
      return '局部有雨雪';
    }
    if (code >= 200 && code <= 230 && code !== 227) {
      return '雷雨';
    }
    if (code === 227 || (code >= 323 && code <= 338)) {
      return '雪';
    }
    if (code >= 263 && code <= 284) {
      return '毛毛雨';
    }
    if (code >= 293 && code <= 314) {
      return code <= 302 ? '小雨' : '大雨';
    }
    if (code >= 317 && code <= 320) {
      return '雨夹雪';
    }
    if (code >= 350 && code <= 377) {
      return '阵雨';
    }
    if (code >= 386 && code <= 395) {
      return '雷阵雨';
    }
    return '未知';
  }

  static feedParse(raw: string): FeedPayload {
    const parsed: FeedPayload = JSON.parse(raw) as FeedPayload;
    const lines: string[] = parsed.lines === undefined || parsed.lines === null ? [] : parsed.lines;
    const title: string = parsed.title === undefined || parsed.title === null ? '自定义信息源' : parsed.title;
    const clean: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      clean.push('' + lines[i]);
    }
    return { title: title, lines: clean };
  }
}
