import mqtt from 'mqtt';
import { isCity, type City } from '../domain/cities.js';
import type { AlertStore } from '../services/alerts.js';

/** 官方 MQTT 連線位址（tdxmotc/MQTTSampleCode）。 */
export const TDX_MQTT_URL = 'mqtts://mqtt.transportdata.tw:8883';

export function alertTopic(city: City): string {
  return `v2/Bus/Alert/City/${city}`;
}

/** 從主題取回縣市；不認得的主題回傳 undefined。 */
export function cityFromTopic(topic: string): City | undefined {
  const city = topic.split('/').at(-1);
  return city && isCity(city) ? city : undefined;
}

export interface AlertSubscriberOptions {
  clientId: string;
  username: string;
  password: string;
  cities: readonly City[];
  store: AlertStore;
  log: (message: string) => void;
}

/**
 * 常駐訂閱各縣市公車通阻主題。
 * 同一組帳密只能有一條連線，所以整個服務只建立一個連線。CleanSession = true（官方建議）。
 */
export function startAlertSubscriber(options: AlertSubscriberOptions): mqtt.MqttClient {
  const client = mqtt.connect(TDX_MQTT_URL, {
    clientId: options.clientId,
    username: options.username,
    password: options.password,
    clean: true,
    reconnectPeriod: 30_000,
    connectTimeout: 20_000,
  });

  client.on('connect', () => {
    options.store.mqttConnected = true;
    client.subscribe(options.cities.map(alertTopic), { qos: 1 }, (error) => {
      if (error) options.log(`MQTT subscribe failed: ${error.message}`);
    });
    options.log('MQTT connected');
  });
  client.on('close', () => {
    options.store.mqttConnected = false;
  });
  client.on('error', (error) => {
    options.log(`MQTT error: ${error.message}`);
  });
  client.on('message', (topic, payload) => {
    const city = cityFromTopic(topic);
    if (!city) return;
    try {
      options.store.ingest(city, JSON.parse(payload.toString('utf8')));
    } catch {
      options.log(`MQTT message on ${topic} is not valid JSON`);
    }
  });
  return client;
}
