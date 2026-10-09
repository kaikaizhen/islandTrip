import { z } from 'zod';
import { SUPPORTED_CITIES, isCity, type City } from './domain/cities.js';

/** 所有設定都來自環境變數（NAS 上的 .env，不進 Git）。 */
const schema = z.object({
  PORT: z.coerce.number().int().positive().default(8080),
  TDX_CLIENT_ID: z.string().min(1, '缺少 TDX_CLIENT_ID'),
  TDX_CLIENT_SECRET: z.string().min(1, '缺少 TDX_CLIENT_SECRET'),
  // MQTT 使用會員中心的「資料存取金鑰」；未設定時只用 REST 輪詢異常消息。
  TDX_MQTT_CLIENT_ID: z.string().optional(),
  TDX_MQTT_USERNAME: z.string().optional(),
  TDX_MQTT_PASSWORD: z.string().optional(),
  /** App 呼叫本服務的金鑰。這不是 TDX 密鑰，只用來擋掉陌生請求。 */
  APP_API_KEY: z.string().min(24, 'APP_API_KEY 至少 24 個字元'),
  CITIES: z
    .string()
    .default(SUPPORTED_CITIES.join(','))
    .transform((value, context) => {
      const cities = value.split(',').map((city) => city.trim()).filter(Boolean);
      const invalid = cities.filter((city) => !isCity(city));
      if (invalid.length > 0) {
        context.addIssue({ code: z.ZodIssueCode.custom, message: `不支援的縣市：${invalid.join(', ')}` });
        return z.NEVER;
      }
      return cities as City[];
    }),
  DATA_DIR: z.string().default('./data'),
});

export type Config = z.infer<typeof schema> & {
  mqtt?: { clientId: string; username: string; password: string };
};

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    // 只列出哪些設定有問題，不印出設定值。
    const problems = parsed.error.issues.map((issue) => `${issue.path.join('.')}: ${issue.message}`).join('; ');
    throw new Error(`設定錯誤：${problems}`);
  }
  const value = parsed.data;
  const mqtt =
    value.TDX_MQTT_CLIENT_ID && value.TDX_MQTT_USERNAME && value.TDX_MQTT_PASSWORD
      ? { clientId: value.TDX_MQTT_CLIENT_ID, username: value.TDX_MQTT_USERNAME, password: value.TDX_MQTT_PASSWORD }
      : undefined;
  return { ...value, mqtt };
}
