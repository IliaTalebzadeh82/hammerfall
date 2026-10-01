import { sleep } from 'k6';
import { api, auctionAt, classify } from './common.js';

export const options = { vus: 1, duration: __ENV.DURATION || '5s' };

let iteration = 0;
export default function () {
  classify(api('GET', `/api/v1/auctions/${auctionAt(iteration++)}`, null), 'warmup_read');
  sleep(0.05);
}
