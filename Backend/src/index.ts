import { loadConfig } from './config.js';
import { buildServer } from './http/server.js';
import { startAlertSubscriber } from './mqtt/alertSubscriber.js';
import { AlertStore } from './services/alerts.js';
import { ArrivalService } from './services/arrivals.js';
import { JourneyService } from './services/journeys.js';
import { StaticDataStore } from './services/staticData.js';
import { TdxTokenProvider } from './tdx/auth.js';
import { TdxClient } from './tdx/client.js';

const log = (message: string) => console.log(`${new Date().toISOString()} ${message}`);

const config = loadConfig();
const tokens = new TdxTokenProvider({ clientId: config.TDX_CLIENT_ID, clientSecret: config.TDX_CLIENT_SECRET });
const api = new TdxClient({ tokens });
const staticData = new StaticDataStore(api, { dataDir: config.DATA_DIR });
const arrivals = new ArrivalService(api);
const alerts = new AlertStore(api);
const journeys = new JourneyService(staticData, arrivals, { cities: config.CITIES });

if (config.mqtt) {
  startAlertSubscriber({ ...config.mqtt, cities: config.CITIES, store: alerts, log });
} else {
  log('MQTT credentials not set; alerts will be fetched via REST');
}

// 啟動時先在背景載入各縣市靜態資料，之後每天更新一次。
const warmUp = () =>
  Promise.allSettled(config.CITIES.map((city) => staticData.get(city))).then((results) => {
    results.forEach((result, index) => {
      // 錯誤訊息只含路徑與 HTTP 狀態，不含密鑰。
      if (result.status === 'rejected') log(`static data for ${config.CITIES[index]} failed: ${String(result.reason?.message ?? result.reason)}`);
    });
    const failed = results.filter((result) => result.status === 'rejected').length;
    log(`static data ready (${results.length - failed}/${results.length} cities)`);
  });
void warmUp();
setInterval(() => void warmUp(), 24 * 60 * 60 * 1000).unref();

const server = buildServer({ appApiKey: config.APP_API_KEY, journeys, arrivals, alerts, staticData, log });
await server.listen({ host: '0.0.0.0', port: config.PORT });
log(`listening on ${config.PORT}`);
