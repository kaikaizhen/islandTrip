/** 簡單的時效快取：同一個 key 在有效期內共用結果，並避免同時重複呼叫。 */
export class TtlCache<T> {
  private readonly values = new Map<string, { at: number; value: T }>();
  private readonly pending = new Map<string, Promise<T>>();

  /** @param maxEntries 超過時清掉過期項目（以位置為 key 時，key 會一直增加）。 */
  constructor(private readonly ttlMs: number, private readonly now: () => number = Date.now, private readonly maxEntries = 500) {}

  get size(): number {
    return this.values.size;
  }

  async get(key: string, load: () => Promise<T>): Promise<T> {
    const cached = this.values.get(key);
    if (cached && this.now() - cached.at < this.ttlMs) return cached.value;
    const inflight = this.pending.get(key);
    if (inflight) return inflight;
    const promise = load()
      .then((value) => {
        this.values.set(key, { at: this.now(), value });
        if (this.values.size > this.maxEntries) this.prune();
        return value;
      })
      .finally(() => this.pending.delete(key));
    this.pending.set(key, promise);
    return promise;
  }

  private prune(): void {
    const time = this.now();
    for (const [key, entry] of this.values) {
      if (time - entry.at >= this.ttlMs) this.values.delete(key);
    }
    // 仍然太多（都還沒過期）就從最舊的開始刪。
    for (const key of this.values.keys()) {
      if (this.values.size <= this.maxEntries) break;
      this.values.delete(key);
    }
  }
}
