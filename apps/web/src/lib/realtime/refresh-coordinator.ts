// One active REST read, one queued forced refresh, and the highest invalidation hint.
// No auction/command state is ever synthesized from Cable messages.
export class RefreshCoordinator<T extends { revision: number }> {
  private known = -1;
  private target = -1;
  private flight: AbortController | null = null;
  private forced = false;
  private stopped = false;
  constructor(
    private callbacks: {
      read: (signal: AbortSignal) => Promise<T>;
      accept: (value: T) => void;
      error: (error: unknown) => void;
      loading: (loading: boolean) => void;
    },
  ) {}
  refresh = () => {
    if (this.stopped) return;
    if (this.flight) this.forced = true;
    else void this.run();
  };
  invalidate = (revision: number) => {
    if (this.stopped || revision <= this.known || revision <= this.target)
      return;
    this.target = revision;
    if (!this.flight) void this.run();
  };
  dispose() {
    this.stopped = true;
    this.flight?.abort();
  }
  private async run() {
    const controller = new AbortController();
    this.flight = controller;
    this.callbacks.loading(true);
    // One follow-up for an unchanged unmet hint; new activity can queue further reads.
    let retries = 1;
    try {
      do {
        this.forced = false;
        const requested = this.target;
        const value = await this.callbacks.read(controller.signal);
        if (this.stopped || controller.signal.aborted) return;
        if (value.revision < this.known)
          throw new Error("Older auction response");
        this.known = value.revision;
        this.callbacks.accept(value);
        if (!this.forced && this.target <= this.known) break;
        if (this.forced || this.target > requested) retries = 1;
        else if (retries-- === 0) {
          this.callbacks.error(
            new Error("Newer state is pending; refresh to check again."),
          );
          break;
        }
      } while (!this.stopped);
    } catch (error) {
      if (!this.stopped) this.callbacks.error(error);
    } finally {
      this.flight = null;
      if (!this.stopped) this.callbacks.loading(false);
    }
  }
}
