import { api, classify } from './common.js';

export const options = { vus: 1, iterations: 1 };

export default function () {
  classify(api('GET', '/api/v1/auctions/9223372036854775807', null), 'sabotage_read');
}
