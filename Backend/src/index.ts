import { loadConfig } from './config.js';
import { buildServer } from './http/server.js';
import { startAlertSubscriber } from './mqtt/alertSubscriber.js';
import { AlertStore } from './services/alerts.js';
import { ArrivalService } from './services/arrivals.js';
import { JourneyService } from './services/journeys.js';
import { MaasPlanner } from './services/maasPlanner.js';
import { RailAlertService } from './services/railAlerts.js';
import { RailDepartureService } from './services/railDepartures.js';
import { RailStationStore } from './services/railStations.js';
import { RAIL_SYSTEMS } from './domain/railSystems.js';
import { StaticDataStore } from './services/staticData.js';
import { TdxTokenProvider } from './tdx/auth.js';
import { TdxClient } from './tdx/client.js';
import { RequestThrottle } from './tdx/throttle.js';
import { UsageMeter } from './tdx/usage.js';

const log = (message: string) => console.log(`${new Date().toISOString()} ${message}`);

const config = loadConfig();
const tokens = new TdxTokenProvider({ clientId: config.TDX_CLIENT_ID, clientSecret: config.TDX_CLIENT_SECRET });
const usage = new UsageMeter();
// 一般 API 與 MaaS 用同一把金鑰，必須共用同一個閘門（各自限流時加起來會超過 TDX 上限）。
const throttle = new RequestThrottle();
const api = new TdxClient({ tokens, usage, throttle });
const staticData = new StaticDataStore(api, { dataDir: config.DATA_DIR });
const arrivals = new ArrivalService(api);
const alerts = new AlertStore(api);
const journeys = new JourneyService(staticData, arrivals, { cities: config.CITIES });
const railStations = new RailStationStore(api, RAIL_SYSTEMS, { dataDir: config.DATA_DIR });
const railDepartures = new RailDepartureService(api);
const railAlerts = new RailAlertService(api);
// MaaS 旅運規劃：不同基底網址、不是 OData，共用同一組 token
// 真實測試：MaaS 偶爾要 40 秒以上才回應；單次 25 秒、只重試 1 次，避免 App 等太久
const maas = new TdxClient({ tokens, baseUrl: 'https://tdx.transportdata.tw/api/maas', odataFormat: false, timeoutMs: 25_000, maxRetries: 1, usage, usagePrefix: 'MaaS', throttle });
const planner = new MaasPlanner(maas, staticData, arrivals, config.CITIES, { rail: { stations: railStations, departures: railDepartures } });

if (config.mqtt) {
  startAlertSubscriber({ ...config.mqtt, cities: config.CITIES, store: alerts, log });
} else {
  log('MQTT credentials not set; alerts will be fetched via REST');
}

// 啟動時先在背景載入各縣市靜態資料，之後每天更新一次。
// 依序下載（不同時送出），避免觸發 TDX 的頻率限制（HTTP 429）。
const warmUp = async () => {
  let ready = 0;
  for (const city of config.CITIES) {
    try {
      await staticData.get(city);
      ready += 1;
    } catch (error) {
      // 錯誤訊息只含路徑與 HTTP 狀態，不含密鑰。
      log(`static data for ${city} failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  log(`static data ready (${ready}/${config.CITIES.length} cities)`);
  log(`rail stations ready (${(await railStations.all()).length})`);
};
void warmUp();
setInterval(() => void warmUp(), 24 * 60 * 60 * 1000).unref();

const server = buildServer({
  appApiKey: config.APP_API_KEY, journeys, arrivals, alerts, staticData, railStations, railDepartures, railAlerts, planner, usage, log,
});
await server.listen({ host: '0.0.0.0', port: config.PORT });
log(`listening on ${config.PORT}`);
