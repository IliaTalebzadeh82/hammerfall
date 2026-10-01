import exec from 'k6/execution';
import { sleep } from 'k6';
import { api, auctionAt, bid, classify, data, fixture, key, maximum, userAt } from './common.js';

// Fixed mix: 50% auction GET, 20% history GET, 20% manual bids, 10% maximum bids.
export const options = { vus: Number(__ENV.VUS || 4), duration: __ENV.DURATION || '30s',
  summaryTrendStats: ['min', 'med', 'p(95)', 'p(99)', 'max'] };

export default function () {
  const n = exec.scenario.iterationInTest;
  const slot = n % 10;
  // Vary the auction independently of the ten-operation workload cycle.
  const auctionId = auctionAt(Math.floor(n / 10) * 3 + slot);
  if (slot < 5) {
    classify(api('GET', `/api/v1/auctions/${auctionId}`, null), 'auction_read');
  } else if (slot < 7) {
    classify(api('GET', `/api/v1/auctions/${auctionId}/bids?limit=20`, null), 'history_read');
  } else {
    const state = api('GET', `/api/v1/auctions/${auctionId}`, null);
    classify(state, 'pre_bid_read');
    const auction = data(state);
    if (auction && auction.status === 'active') {
      const bidderId = userAt(Math.floor(n / 10) + exec.vu.idInTest);
      const amount = Number(auction.current_price) + Number(auction.minimum_increment) * (slot === 9 ? 4 : 1);
      if (slot === 9) maximum(auctionId, bidderId, amount, key('max', n, exec.vu.idInTest));
      else bid(auctionId, bidderId, amount, key('bid', n, exec.vu.idInTest));
    }
  }
  sleep(Number(__ENV.THINK_SECONDS || 0.05));
}
