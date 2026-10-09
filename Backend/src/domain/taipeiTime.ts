/** 臺灣時間工具：TDX 時刻表都是臺北時間，NAS 可能設成 UTC，所以一律明確換算。 */
const formatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Taipei',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
  weekday: 'short',
});

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export interface TaipeiNow {
  /** yyyy-MM-dd */
  date: string;
  /** 當天第幾分鐘（0–1439）。 */
  minutes: number;
  /** 0 = 星期日 … 6 = 星期六 */
  weekday: number;
}

export function taipeiNow(epochMs: number): TaipeiNow {
  const parts = Object.fromEntries(formatter.formatToParts(new Date(epochMs)).map((part) => [part.type, part.value]));
  const hour = Number(parts.hour) % 24;
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    minutes: hour * 60 + Number(parts.minute),
    weekday: WEEKDAYS.indexOf(parts.weekday ?? 'Sun'),
  };
}

/** 「HH:mm」或「HH:mm:ss」→ 當天第幾分鐘；格式不對回傳 undefined。 */
export function minutesOfDay(time: string | null | undefined): number | undefined {
  const match = time?.match(/^(\d{1,2}):(\d{2})(?::\d{2})?$/);
  if (!match) return undefined;
  return Number(match[1]) * 60 + Number(match[2]);
}

/** 臺北日期 + 「HH:mm(:ss)」→ ISO 時間字串。 */
export function taipeiISO(date: string, time: string): string | null {
  const match = time.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/);
  if (!match) return null;
  const [, h, m, s] = match;
  return new Date(`${date}T${h!.padStart(2, '0')}:${m}:${s ?? '00'}+08:00`).toISOString();
}
