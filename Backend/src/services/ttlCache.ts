/** 簡單的時效快取：同一個 key 在有效期內共用結果，並避免同時重複呼叫。 */
export class TtlCache<T> {
  private readonly values = new Map<string, { at: number; value: T }>();
  private readonly pending = new Map<string, Promise<T>>();

  constructor(private readonly ttlMs: number, private readonly now: () => number = Date.now) {}

  async get(key: string, load: () => Promise<T>): Promise<T> {
    const cached = this.values.get(key);
    if (cached && this.now() - cached.at < this.ttlMs) return cached.value;
    const inflight = this.pending.get(key);
    if (inflight) return inflight;
    const promise = load()
      .then((value) => {
        this.values.set(key, { at: this.now(), value });
        return value;
      })
      .finally(() => this.pending.delete(key));
    this.pending.set(key, promise);
    return promise;
  }
}
