import http from 'k6/http';
import { Counter, Trend } from 'k6/metrics';

export const fixture = JSON.parse(open(__ENV.MANIFEST || '/work/manifest.json'));
export const base = (__ENV.API_BASE_URL || fixture.api_base_url).replace(/\/$/, '');
export const outcomes = new Counter('benchmark_outcomes');
export const commandLatency = new Trend('benchmark_command_duration', true);
const outcomeCounters = Object.fromEntries(
  ['accepted', 'domain_rejected', 'idempotent_replay', 'conflict', 'client_error', 'server_error', 'timeout', 'transport_error']
    .map((name) => [name, new Counter(`benchmark_${name}`)]),
);
const latencyByOperation = {
  bid: new Trend('benchmark_bid_duration', true),
  maximum: new Trend('benchmark_maximum_duration', true),
  read: new Trend('benchmark_read_duration', true),
};
const replayLatency = new Trend('benchmark_replay_duration', true);
const originalLatency = new Trend('benchmark_original_duration', true);
const acceptedBidLatency = new Trend('benchmark_accepted_bid_duration', true);
const rejectedBidLatency = new Trend('benchmark_rejected_bid_duration', true);
const mutationAccepted = new Counter('benchmark_mutation_accepted');
const mutationRejected = new Counter('benchmark_mutation_domain_rejected');

http.setResponseCallback(http.expectedStatuses(200, 201, 409, 422));

export function api(method, path, body, key) {
  const headers = { 'Content-Type': 'application/json' };
  if (key) headers['Idempotency-Key'] = key;
  return http.request(method, `${base}${path}`, body === null ? null : JSON.stringify(body), {
    headers, timeout: __ENV.REQUEST_TIMEOUT || '15s', tags: { name: path.replace(/\/[0-9]+/g, '/:id') },
  });
}

export function data(response) {
  try { return response.json('data'); } catch (_) { return null; }
}

export function classify(response, operation) {
  let outcome;
  let errorCode = null;
  try { errorCode = response.json('error.code'); } catch (_) { /* success or non-JSON transport error */ }
  if (response.status === 0) outcome = /timeout|deadline/i.test(response.error || '') ? 'timeout' : 'transport_error';
  else if (response.status >= 500) outcome = 'server_error';
  else if (response.status === 409) outcome = errorCode === 'idempotency_key_conflict' ? 'conflict' : 'client_error';
  else if (response.status === 422) outcome = [
    'bid_too_low', 'maximum_bid_too_low', 'maximum_bid_cannot_decrease',
    'auction_ended', 'auction_not_open', 'invalid_auction_state',
  ].includes(errorCode) ? 'domain_rejected' : 'client_error';
  else if (response.status >= 400) outcome = 'client_error';
  else if (response.headers['Idempotency-Replayed'] === 'true') outcome = 'idempotent_replay';
  else if (response.status === 200 || response.status === 201) outcome = 'accepted';
  else outcome = 'client_error';
  const tags = { operation, outcome };
  outcomes.add(1, tags);
  outcomeCounters[outcome].add(1);
  if (operation === 'bid' || operation === 'maximum') {
    if (outcome === 'accepted') mutationAccepted.add(1);
    if (outcome === 'domain_rejected') mutationRejected.add(1);
  }
  commandLatency.add(response.timings.duration, tags);
  if (operation === 'bid') latencyByOperation.bid.add(response.timings.duration);
  else if (operation === 'maximum') latencyByOperation.maximum.add(response.timings.duration);
  else latencyByOperation.read.add(response.timings.duration);
  if (outcome === 'idempotent_replay') replayLatency.add(response.timings.duration);
  if (operation === 'bid' && outcome === 'accepted') {
    originalLatency.add(response.timings.duration);
    acceptedBidLatency.add(response.timings.duration);
  }
  if (operation === 'bid' && outcome === 'domain_rejected') rejectedBidLatency.add(response.timings.duration);
  return outcome;
}

export function bid(auctionId, bidderId, amount, key) {
  return classify(api('POST', `/api/v1/auctions/${auctionId}/bids`,
    { bid: { bidder_id: bidderId, amount } }, key), 'bid');
}

export function maximum(auctionId, bidderId, amount, key) {
  return classify(api('PUT', `/api/v1/auctions/${auctionId}/maximum-bid`,
    { maximum_bid: { bidder_id: bidderId, maximum_amount: amount } }, key), 'maximum');
}

export function key(prefix, iteration, vu) {
  return `${fixture.run_id}-${prefix}-${iteration}-${vu}`;
}

export function auctionAt(iteration) {
  return fixture.auctions[iteration % fixture.auctions.length];
}

export function userAt(iteration) {
  return fixture.users[iteration % fixture.users.length];
}
