interface Entry<T = unknown> {
  task: (signal: AbortSignal) => Promise<T>;
  priority: number;
  order: number;
  tag?: string;
  controller: AbortController;
  resolve: (result: T) => void;
  reject: (error: unknown) => void;
  detach: () => void;
}
export class PriorityActionQueue {
  private pending: Entry<any>[] = [];
  private active?: Entry<any>;
  private sequence = 0;
  private waiters: (() => void)[] = [];
  get busy(): boolean {
    return !!this.active || this.pending.length > 0;
  }
  run<T>(
    task: (signal: AbortSignal) => Promise<T>,
    options: { priority?: number; signal?: AbortSignal; tag?: string } = {},
  ): Promise<T> {
    if (options.signal?.aborted) return Promise.reject(options.signal.reason);
    return new Promise<T>((resolve, reject) => {
      const controller = new AbortController();
      const entry: Entry<T> = {
        task,
        priority: options.priority ?? 0,
        order: this.sequence++,
        tag: options.tag,
        controller,
        resolve,
        reject,
        detach: () => options.signal?.removeEventListener("abort", abort),
      };
      const abort = () => {
        controller.abort(options.signal?.reason);
        this.removeAborted();
      };
      options.signal?.addEventListener("abort", abort, { once: true });
      this.pending.push(entry);
      this.pending.sort((a, b) => b.priority - a.priority || a.order - b.order);
      this.pump();
    });
  }
  cancelPending(tag?: string): void {
    for (const entry of this.pending)
      if (!tag || entry.tag === tag)
        entry.controller.abort(new Error("Action cancelled"));
    this.removeAborted();
  }
  cancelAll(): void {
    this.cancelPending();
    this.active?.controller.abort(new Error("Action cancelled"));
  }
  idle(): Promise<void> {
    return this.busy
      ? new Promise((resolve) => this.waiters.push(resolve))
      : Promise.resolve();
  }
  private removeAborted(): void {
    this.pending = this.pending.filter((entry) => {
      if (!entry.controller.signal.aborted) return true;
      entry.detach();
      entry.reject(entry.controller.signal.reason);
      return false;
    });
    this.notifyIdle();
  }
  private notifyIdle(): void {
    if (!this.busy) for (const resolve of this.waiters.splice(0)) resolve();
  }
  private pump(): void {
    if (this.active) return;
    const entry = this.pending.shift();
    if (!entry) {
      this.notifyIdle();
      return;
    }
    this.active = entry;
    void (async () => {
      try {
        entry.controller.signal.throwIfAborted();
        const result = await entry.task(entry.controller.signal);
        entry.controller.signal.throwIfAborted();
        entry.resolve(result);
      } catch (error) {
        entry.reject(error);
      } finally {
        entry.detach();
        this.active = undefined;
        this.pump();
      }
    })();
  }
}
