require "rails_helper"
require_relative "../support/committed_auction_context"

RSpec.describe "Scheduled reconciliation lease" do
  self.use_transactional_tests = false
  include_context "committed auction concurrency"

  after do
    ApplicationRecord.connection.execute("DELETE FROM reconciliation_leases")
    @auction_ids.each { |id| redis.call("DEL", "#{AuctionPublicProjection::KEY_PREFIX}#{id}") }
    redis.close
  end

  let(:redis) { RedisClient.config(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"), timeout: 1).new_client }

  def expire(name)
    sql = ApplicationRecord.sanitize_sql_array([ "UPDATE reconciliation_leases SET expires_at = clock_timestamp() - interval '1 second' WHERE name = ?", name ])
    ApplicationRecord.connection.execute(sql)
  end

  def set_cursor(name, cursor)
    sql = ApplicationRecord.sanitize_sql_array([ "UPDATE reconciliation_leases SET cursor = ? WHERE name = ?", cursor, name ])
    ApplicationRecord.connection.execute(sql)
  end

  it "allows one chain per type across scheduler instances and another after completion" do
    auction = active_auction
    Sidekiq.testing!(:fake) do
      ReconciliationSweepJob.clear
      AuctionProjectionReconciliationJob.clear
      first = ReconciliationScheduler.new(interval: 5)
      second = ReconciliationScheduler.new(interval: 5)
      first.run_once
      5.times { second.run_once }
      expect(ReconciliationSweepJob.jobs.length).to eq(1)
      expect(AuctionProjectionReconciliationJob.jobs.length).to eq(1)
      auction.place_bid!(bidder: @bidder, amount: 10_000)
      expect(auction.reload.current_price).to eq(10_000)
      before = auction.attributes

      sweep_token = ReconciliationSweepJob.jobs.first.fetch("args").last
      projection_token = AuctionProjectionReconciliationJob.jobs.first.fetch("args").last
      set_cursor(ReconciliationLease::POSTGRESQL_STATE, auction.id - 1)
      set_cursor(ReconciliationLease::PROJECTION, auction.id - 1)
      ReconciliationSweepJob.new.perform(auction.id - 1, auction.id, sweep_token)
      AuctionProjectionReconciliationJob.new.perform(auction.id - 1, auction.id, projection_token)
      expect(ReconciliationLease.renew(ReconciliationLease::POSTGRESQL_STATE, sweep_token, 0)).to be(false)
      expect(ReconciliationLease.renew(ReconciliationLease::PROJECTION, projection_token, 0)).to be(false)

      second.run_once
      expect(ReconciliationSweepJob.jobs.length).to eq(2)
      expect(AuctionProjectionReconciliationJob.jobs.length).to eq(2)
      expect(ReconciliationSweepJob.jobs.last.fetch("args").last).not_to eq(sweep_token)
      expect(AuctionProjectionReconciliationJob.jobs.last.fetch("args").last).not_to eq(projection_token)
      expect(auction.reload.attributes).to eq(before)
    ensure
      ReconciliationSweepJob.clear
      AuctionProjectionReconciliationJob.clear
    end
  end

  it "reclaims abandoned ownership and fences an old queued page" do
    auction = active_auction
    old_token = ReconciliationLease.claim(ReconciliationLease::PROJECTION)
    expect(old_token).to be_present
    expire(ReconciliationLease::PROJECTION)
    new_token = ReconciliationLease.claim(ReconciliationLease::PROJECTION)
    expect(new_token).to be_present
    expect(new_token).not_to eq(old_token)

    set_cursor(ReconciliationLease::PROJECTION, auction.id - 1)
    AuctionProjectionReconciliationJob.new.perform(auction.id - 1, auction.id, old_token)
    expect(redis.call("EXISTS", "#{AuctionPublicProjection::KEY_PREFIX}#{auction.id}")).to eq(0)
    AuctionProjectionReconciliationJob.new.perform(auction.id - 1, auction.id, new_token)
    expect(redis.call("EXISTS", "#{AuctionPublicProjection::KEY_PREFIX}#{auction.id}")).to eq(1)
    expect(ReconciliationLease.claim(ReconciliationLease::PROJECTION)).to be_present
  end

  it "carries ownership through pagination and releases it after an empty final page" do
    first = active_auction
    last = active_auction
    token = ReconciliationLease.claim(ReconciliationLease::PROJECTION)
    set_cursor(ReconciliationLease::PROJECTION, first.id - 1)
    stub_const("AuctionProjectionReconciliationJob::BATCH_SIZE", 1)
    Sidekiq.testing!(:fake) do
      AuctionProjectionReconciliationJob.clear
      AuctionProjectionReconciliationJob.new.perform(first.id - 1, last.id, token)
      expect(AuctionProjectionReconciliationJob.jobs.last.fetch("args")).to eq([ first.id, last.id, token ])
      AuctionProjectionReconciliationJob.new.perform(first.id - 1, last.id, token)
      expect(AuctionProjectionReconciliationJob.jobs.length).to eq(1)
      AuctionProjectionReconciliationJob.jobs.pop
      expect(ReconciliationLease.claim(ReconciliationLease::PROJECTION)).to be_nil

      AuctionProjectionReconciliationJob.new.perform(first.id, last.id, token)
      expect(AuctionProjectionReconciliationJob.jobs.pop.fetch("args")).to eq([ last.id, last.id, token ])
      AuctionProjectionReconciliationJob.new.perform(last.id, last.id, token)
      expect(ReconciliationLease.renew(ReconciliationLease::PROJECTION, token, last.id)).to be(false)
      expect(ReconciliationLease.claim(ReconciliationLease::PROJECTION)).to be_present
    ensure
      AuctionProjectionReconciliationJob.clear
    end
  end

  it "does not branch after a crash between cursor advancement and successor enqueue" do
    first = active_auction
    last = active_auction
    token = ReconciliationLease.claim(ReconciliationLease::PROJECTION)
    set_cursor(ReconciliationLease::PROJECTION, first.id - 1)
    stub_const("AuctionProjectionReconciliationJob::BATCH_SIZE", 1)
    allow(AuctionProjectionReconciliationJob).to receive(:perform_async).and_raise(IOError, "crash before enqueue")

    expect { AuctionProjectionReconciliationJob.new.perform(first.id - 1, last.id, token) }
      .to raise_error(IOError, "crash before enqueue")
    expect(ReconciliationLease.renew(ReconciliationLease::PROJECTION, token, first.id - 1)).to be(false)
    expect(ReconciliationLease.renew(ReconciliationLease::PROJECTION, token, first.id)).to be(true)
    expect(AuctionProjectionReconciliationJob.new.perform(first.id - 1, last.id, token)).to be_nil
    expect(AuctionProjectionReconciliationJob).to have_received(:perform_async).once

    expire(ReconciliationLease::PROJECTION)
    replacement = ReconciliationLease.claim(ReconciliationLease::PROJECTION)
    expect(replacement).to be_present
    expect(replacement).not_to eq(token)
    expect(ReconciliationLease.renew(ReconciliationLease::PROJECTION, replacement, 0)).to be(true)
  end

  it "atomically grants one owner when two scheduler processes race" do
    ready = Queue.new
    release = Queue.new
    threads = Array.new(2) do
      Thread.new do
        ready << true
        release.pop
        ReconciliationLease.claim(ReconciliationLease::PROJECTION)
      end
    end
    @threads.concat(threads)
    2.times { take(ready) }
    2.times { release << true }
    expect(threads.map { |thread| result(thread) }.compact.length).to eq(1)
  ensure
    2.times { release << true } if release
  end

  it "releases a claim when the initial queue write fails" do
    scheduler = ReconciliationScheduler.new(interval: 5)
    allow(AuctionProjectionReconciliationJob).to receive(:perform_async).and_raise(IOError)
    expect { scheduler.run_once }.to raise_error(IOError)
    expect(ReconciliationLease.claim(ReconciliationLease::PROJECTION)).to be_present
  end
end
