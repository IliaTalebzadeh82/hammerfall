import exec from 'k6/execution';
import { sleep } from 'k6';
import ws from 'k6/ws';
import { Counter } from 'k6/metrics';
import { api, bid, classify, data, fixture, key, userAt } from './common.js';

const attempted = new Counter('benchmark_socket_attempted');
const opened = new Counter('benchmark_socket_opened');
const confirmed = new Counter('benchmark_socket_confirmed');
const failed = new Counter('benchmark_socket_failed');
const invalidations = new Counter('benchmark_socket_invalidations');
const disconnected = new Counter('benchmark_socket_disconnected');
const holdSeconds = Number.parseInt(__ENV.DURATION || '20s', 10);

export const options = {
  scenarios: {
    subscribers: { executor: 'per-vu-iterations', vus: Number(__ENV.VUS || 20),
      iterations: 1, maxDuration: `${holdSeconds + 5}s`, exec: 'subscriber' },
    mutations: { executor: 'constant-vus', vus: 1, startTime: '3s',
      duration: `${Math.max(holdSeconds - 5, 1)}s`, exec: 'mutator' },
  },
  summaryTrendStats: ['min', 'med', 'p(95)', 'p(99)', 'max'],
};

export function subscriber() {
  const aid = fixture.auctions[0];
  const url = fixture.api_base_url.replace(/^http/, 'ws') + '/cable';
  const identifier = JSON.stringify({ channel: 'AuctionChannel', auction_id: aid });
  attempted.add(1);
  let didOpen = false;
  let hadError = false;
  const response = ws.connect(url, { headers: {
    Origin: 'http://127.0.0.1:3000',
    'Sec-WebSocket-Protocol': 'actioncable-v1-json',
  } }, (socket) => {
    socket.on('open', () => {
      didOpen = true;
      opened.add(1);
      socket.send(JSON.stringify({ command: 'subscribe', identifier }));
    });
    socket.on('message', (message) => {
      let frame;
      try { frame = JSON.parse(message); } catch (_) { return; }
      if (frame.type === 'confirm_subscription') confirmed.add(1);
      if (frame.message?.type === 'auction.changed.v1' && frame.message.auction_id === aid) {
        invalidations.add(1);
      }
    });
    socket.on('error', () => { hadError = true; failed.add(1); });
    socket.on('close', () => { disconnected.add(1); });
    socket.setTimeout(() => socket.close(), Math.max(holdSeconds - 1, 1) * 1000);
  });
  if (response.status !== 101 && !hadError) failed.add(1);
  if (response.status === 101 && !didOpen && !hadError) failed.add(1);
}

export function mutator() {
  const n = exec.scenario.iterationInTest;
  const aid = fixture.auctions[0];
  const response = api('GET', `/api/v1/auctions/${aid}`, null);
  classify(response, 'pre_bid_read');
  const auction = data(response);
  if (auction?.status === 'active') {
    bid(aid, userAt(n), Number(auction.current_price) + Number(auction.minimum_increment),
      key('fanout', n, exec.vu.idInTest));
  }
  sleep(0.5);
}
