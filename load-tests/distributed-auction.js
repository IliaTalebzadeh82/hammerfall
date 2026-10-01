import exec from 'k6/execution';
import { sleep } from 'k6';
import { api, bid, classify, data, fixture, key, userAt } from './common.js';

export const options = { vus: Number(__ENV.VUS || 16), duration: __ENV.DURATION || '30s',
  summaryTrendStats: ['min', 'med', 'p(95)', 'p(99)', 'max'] };

export default function () {
  const n = exec.scenario.iterationInTest;
  const aid = fixture.auctions[n % fixture.auctions.length];
  const response = api('GET', `/api/v1/auctions/${aid}`, null);
  classify(response, 'pre_bid_read');
  const auction = data(response);
  if (auction?.status === 'active') {
    bid(aid, userAt(n + exec.vu.idInTest),
      Number(auction.current_price) + Number(auction.minimum_increment),
      key('distributed', n, exec.vu.idInTest));
  }
  sleep(Number(__ENV.THINK_SECONDS || 0.02));
}
