import exec from 'k6/execution';
import { sleep } from 'k6';
import { api, bid, classify, data, fixture, key, userAt } from './common.js';

export const options = { vus: Number(__ENV.VUS || 4), duration: __ENV.DURATION || '30s',
  summaryTrendStats: ['min', 'med', 'p(95)', 'p(99)', 'max'] };

export default function () {
  const n = exec.scenario.iterationInTest;
  const aid = fixture.auctions[0];
  const state = api('GET', `/api/v1/auctions/${aid}`, null);
  classify(state, 'pre_bid_read');
  const auction = data(state);
  if (auction && auction.status === 'active') {
    const amount = Number(auction.current_price) + Number(auction.minimum_increment);
    bid(aid, userAt(n + exec.vu.idInTest), amount, key('hot', n, exec.vu.idInTest));
  }
  sleep(Number(__ENV.THINK_SECONDS || 0.02));
}
