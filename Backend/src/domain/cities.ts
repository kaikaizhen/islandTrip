/** 支援的縣市（TDX `City` 參數，已依官方 Swagger enum 核對）。 */
export const SUPPORTED_CITIES = ['Taipei', 'NewTaipei', 'Keelung', 'Taoyuan', 'Taichung', 'Kaohsiung'] as const;

export type City = (typeof SUPPORTED_CITIES)[number];

export function isCity(value: string): value is City {
  return (SUPPORTED_CITIES as readonly string[]).includes(value);
}
