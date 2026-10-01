import exec from 'k6/execution';
import { sleep } from 'k6';
import { bid, fixture } from './common.js';

export const options = { vus: Number(__ENV.VUS || 8), duration: __ENV.DURATION || '15s',
  summaryTrendStats: ['min', 'med', 'p(95)', 'p(99)', 'max'] };

export default function () {
  const n = exec.scenario.iterationInTest;
  const amount = fixture.starting_price + (n % 20 === 19 ? fixture.minimum_increment : 0);
  bid(fixture.auctions[0], fixture.users[0], amount, fixture.duplicate_key);
  if (n % 5 === 0) sleep(0.2); // delayed matching and conflicting retries
}
