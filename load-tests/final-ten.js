import exec from 'k6/execution';
import { sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import { bid, fixture, key } from './common.js';

const contenders = Number(__ENV.VUS || 1000);
const attempts = new Counter('benchmark_challenge_attempts');
const launchOffset = new Trend('benchmark_challenge_launch_offset_ms', true);

export const options = {
  scenarios: { challengers: { executor: 'per-vu-iterations', vus: contenders,
    iterations: 1, maxDuration: '75s', exec: 'challenge' } },
  summaryTrendStats: ['min', 'med', 'p(95)', 'p(99)', 'max'],
};

export function challenge() {
  // Client time only paces the generator. Rails checks eligibility against
  // PostgreSQL clock_timestamp() after acquiring the auction row lock.
  const target = Date.parse(fixture.ends_at) - 8000;
  const delay = target - Date.now();
  if (delay > 0) sleep(delay / 1000);
  launchOffset.add(Date.now() - target);
  const vu = exec.vu.idInTest;
  attempts.add(1);
  bid(fixture.auctions[0], fixture.users[(vu - 1) % fixture.users.length],
    Number(fixture.starting_price) + Number(fixture.minimum_increment), key('challenge', 0, vu));
}
