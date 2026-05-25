require 'sequel'
require 'benchmark'

class ConnectionPooling
  attr_reader :direct_db, :pooled_db

  def initialize(direct_url, pooled_url)
    # Direct PostgreSQL connection
    @direct_db = Sequel.connect(
      direct_url,
      max_connections: 5,
      pool_timeout: 5
    )

    # PgBouncer pooled connection
    @pooled_db = Sequel.connect(
      pooled_url,
      max_connections: 20,
      pool_timeout: 5
    )
  end

  # Benchmark direct vs pooled connections
  def benchmark_connections(iterations = 100)
    # Warm up
    @direct_db.fetch('SELECT 1').first
    @pooled_db.fetch('SELECT 1').first

    # Benchmark direct connections
    direct_time = Benchmark.realtime do
      iterations.times do
        @direct_db.fetch('SELECT 1').first
      end
    end

    # Benchmark pooled connections
    pooled_time = Benchmark.realtime do
      iterations.times do
        @pooled_db.fetch('SELECT 1').first
      end
    end

    improvement = ((direct_time - pooled_time) / direct_time * 100).round(2)

    {
      iterations: iterations,
      direct_time: direct_time.round(4),
      pooled_time: pooled_time.round(4),
      improvement: "#{improvement}%"
    }
  end

  # Get connection pool statistics
  def get_pool_stats
    {
      direct_pool: {
        size: @direct_db.pool.size,
        max_size: @direct_db.pool.max_size,
        allocated: @direct_db.pool.allocated.size
      },
      pooled_pool: {
        size: @pooled_db.pool.size,
        max_size: @pooled_db.pool.max_size,
        allocated: @pooled_db.pool.allocated.size
      }
    }
  end

  # Simulate high-concurrency scenario
  def simulate_high_load(concurrent_queries = 50)
    start_time = Time.now

    threads = []
    concurrent_queries.times do |i|
      threads << Thread.new do
        @pooled_db[:sessions].insert(
          user_id: rand(1..1000),
          data: Sequel.pg_jsonb({
            session_id: SecureRandom.uuid,
            timestamp: Time.now.to_i
          }),
          expires_at: Time.now + 3600
        )
      end
    end

    threads.each(&:join)
    duration = Time.now - start_time

    {
      queries_executed: concurrent_queries,
      total_time: duration.round(4),
      queries_per_second: (concurrent_queries / duration).round(2)
    }
  end

  # Test transaction handling with pooling
  def test_transaction_pooling
    results = []

    # Test with direct connection
    direct_time = Benchmark.realtime do
      @direct_db.transaction do
        @direct_db[:products].where(Sequel.lit("metadata->>'brand' = ?", 'Dell')).all
        @direct_db[:sessions].where(Sequel.lit('user_id > ?', 100)).limit(10).all
      end
    end

    # Test with pooled connection
    pooled_time = Benchmark.realtime do
      @pooled_db.transaction do
        @pooled_db[:products].where(Sequel.lit("metadata->>'brand' = ?", 'Dell')).all
        @pooled_db[:sessions].where(Sequel.lit('user_id > ?', 100)).limit(10).all
      end
    end

    {
      direct_transaction_time: direct_time.round(4),
      pooled_transaction_time: pooled_time.round(4),
      note: 'PgBouncer transaction mode handles transactions efficiently'
    }
  end

  # Monitor connection usage over time
  def monitor_connections(duration_seconds = 10, interval_seconds = 1)
    snapshots = []
    start_time = Time.now

    while (Time.now - start_time) < duration_seconds
      snapshots << {
        timestamp: Time.now.to_i,
        stats: get_pool_stats
      }
      sleep interval_seconds
    end

    snapshots
  end

  def close_connections
    @direct_db.disconnect
    @pooled_db.disconnect
  end
end
