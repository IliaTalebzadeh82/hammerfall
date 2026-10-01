import { sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { api, classify, fixture } from './common.js';

const initial = new Trend('benchmark_burst_initial_duration', true);
const later = new Trend('benchmark_burst_later_duration', true);
const bidders = Number(__ENV.VUS || 32);

export const options = {
  scenarios: { burst: { executor: 'per-vu-iterations', vus: bidders,
    iterations: 1, maxDuration: '30s' } },
  summaryTrendStats: ['min', 'med', 'p(95)', 'p(99)', 'max'],
};

function request() {
  return api('POST', `/api/v1/auctions/${fixture.auctions[0]}/bids`,
    { bid: { bidder_id: fixture.users[0], amount: fixture.starting_price } }, fixture.duplicate_key);
}

export default function () {
  // Each VU sends the same intention at once, then retries after ownership
  // has normally completed. Record these waves separately.
  const first = request();
  classify(first, 'bid');
  initial.add(first.timings.duration);
  sleep(0.5);
  const second = request();
  classify(second, 'bid');
  later.add(second.timings.duration);
}
