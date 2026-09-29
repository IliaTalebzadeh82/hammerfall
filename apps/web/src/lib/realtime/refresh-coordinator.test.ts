import { expect, it, vi } from "vitest";
import { RefreshCoordinator } from "./refresh-coordinator";

function harness() {
  const pending: ((value: { revision: number }) => void)[] = [];
  const read = vi.fn(
    () => new Promise<{ revision: number }>((resolve) => pending.push(resolve)),
  );
  const accept = vi.fn();
  const error = vi.fn();
  const loading = vi.fn();
  const coordinator = new RefreshCoordinator({ read, accept, error, loading });
  const resolve = async (revision: number) => {
    pending.shift()?.({ revision });
    await Promise.resolve();
    await Promise.resolve();
  };
  return { coordinator, read, accept, error, loading, resolve };
}
it("ignores stale and equal hints, coalesces a burst and trusts the newer REST revision", async () => {
  const h = harness();
  h.coordinator.refresh();
  await h.resolve(20);
  h.coordinator.invalidate(20);
  h.coordinator.invalidate(19);
  expect(h.read).toHaveBeenCalledTimes(1);
  for (const revision of [21, 22, 23, 24, 24, 23])
    h.coordinator.invalidate(revision);
  expect(h.read).toHaveBeenCalledTimes(2);
  await h.resolve(22);
  expect(h.read).toHaveBeenCalledTimes(3);
  await h.resolve(25);
  h.coordinator.invalidate(24);
  expect(h.read).toHaveBeenCalledTimes(3);
  expect(h.accept.mock.calls.map(([v]) => v.revision)).toEqual([20, 22, 25]);
});
it("never regresses on an older REST response and can recover explicitly", async () => {
  const h = harness();
  h.coordinator.refresh();
  await h.resolve(12);
  h.coordinator.refresh();
  await h.resolve(11);
  expect(h.accept).toHaveBeenCalledTimes(1);
  expect(h.error).toHaveBeenCalledOnce();
  h.coordinator.refresh();
  await h.resolve(13);
  expect(h.accept).toHaveBeenLastCalledWith({ revision: 13 });
});
it("queues a command or reconnect refresh after the read already in flight", async () => {
  const h = harness();
  h.coordinator.refresh();
  h.coordinator.refresh();
  h.coordinator.refresh();
  expect(h.read).toHaveBeenCalledTimes(1);
  await h.resolve(10);
  expect(h.read).toHaveBeenCalledTimes(2);
  await h.resolve(11);
  expect(h.accept).toHaveBeenLastCalledWith({ revision: 11 });
});
it("bounds retries when REST remains behind the observed hint", async () => {
  const h = harness();
  h.coordinator.invalidate(24);
  await h.resolve(20);
  await h.resolve(20);
  expect(h.read).toHaveBeenCalledTimes(2);
  expect(h.error).toHaveBeenCalledOnce();
});
it("retains current state on network error and refreshes after reconfirmation", async () => {
  const accept = vi.fn();
  const error = vi.fn();
  const read = vi
    .fn()
    .mockResolvedValueOnce({ revision: 10 })
    .mockRejectedValueOnce(new TypeError("offline"))
    .mockResolvedValue({ revision: 12 });
  const c = new RefreshCoordinator({ read, accept, error, loading: vi.fn() });
  c.refresh();
  await Promise.resolve();
  c.invalidate(12);
  await Promise.resolve();
  expect(error).toHaveBeenCalledOnce();
  expect(accept).toHaveBeenCalledTimes(1);
  c.refresh();
  await Promise.resolve();
  expect(accept).toHaveBeenLastCalledWith({ revision: 12 });
  expect(read).toHaveBeenCalledTimes(3);
});
it("ignores late work after unmount and cancels the read", async () => {
  const h = harness();
  h.coordinator.refresh();
  h.coordinator.dispose();
  await h.resolve(10);
  h.coordinator.invalidate(20);
  h.coordinator.refresh();
  expect(h.accept).not.toHaveBeenCalled();
  expect(h.read).toHaveBeenCalledOnce();
});
