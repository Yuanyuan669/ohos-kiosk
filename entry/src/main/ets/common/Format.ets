export const WEEKDAYS: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

export function pad(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}

export function stamp(now: number): string {
  const d: Date = new Date(now);
  return pad(d.getHours()) + ':' + pad(d.getMinutes());
}

export function windName(degRaw: number): string {
  const names: string[] = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
  let deg: number = degRaw % 360;
  if (deg < 0) {
    deg += 360;
  }
  const idx: number = Math.floor(((deg + 22.5) % 360) / 45);
  return '来自' + names[idx];
}
