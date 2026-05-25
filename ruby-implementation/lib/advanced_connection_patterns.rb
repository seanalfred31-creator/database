require 'sequel'
require 'connection_pool'
require 'concurrent'

# ConnectionPool gem internals and patterns
module AdvancedConnectionPatterns
  # Custom connection pool using ConnectionPool gem
  class CustomConnectionPool
    attr_reader :pool

    def initialize(database_url, size: 25, timeout: 5)
      @pool = ConnectionPool.new(size: size, timeout: timeout) do
        Sequel.connect(database_url)
      end
    end

    # Execute query with automatic checkout/checkin
    def with_connection
      @pool.with do |conn|
        yield conn
      end
    end

    # Get pool statistics
    def stats
      {
        size: @pool.size,
        available: @pool.available
      }
    end

    # Parallel queries using connection pool
    def parallel_queries(queries)
      threads = queries.map do |query|
        Thread.new do
          with_connection do |conn|
            conn.fetch(query[:sql], *query[:params]).all
          end
        end
      end

      threads.map(&:value)
    end

    # Health check all connections
    def health_check
      results = []
      
      @pool.size.times do
        with_connection do |conn|
          begin
            conn.test_connection
            results << { healthy: true }
          rescue => e
            results << { healthy: false, error: e.message }
          end
        end
      end

      results
    end

    # Reload connections (useful after fork)
    def reload!
      @pool.reload do |conn|
        conn.disconnect
        Sequel.connect(conn.opts)
      end
    end
  end

  # ActiveRecord connection multiplexing
  class ActiveRecordMultiplexing
    # Configure multiple database connections
    def self.configure_multiple_databases
      ActiveRecord::Base.configurations = {
        'primary' => {
          adapter: 'postgresql',
          host: 'localhost',
          database: 'primary_db',
          pool: 25
        },
        'replica' => {
          adapter: 'postgresql',
          host: 'replica-host',
          database: 'primary_db',
          pool: 50,
          replica: true
        },
        'analytics' => {
          adapter: 'postgresql',
          host: 'analytics-host',
          database: 'analytics_db',
          pool: 10
        }
      }
    end

    # Abstract class for multi-database models
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
      
      # Automatic read/write splitting
      connects_to database: { writing: :primary, reading: :replica }
    end

    # Model using primary database
    class Product < ApplicationRecord
      # Writes go to primary, reads to replica
    end

    # Model using analytics database
    class AnalyticsEvent < ActiveRecord::Base
      self.abstract_class = true
      connects_to database: { writing: :analytics, reading: :analytics }
    end

    # Manual connection switching
    def self.with_replica
      ActiveRecord::Base.connected_to(role: :reading) do
        yield
      end
    end

    def self.with_primary
      ActiveRecord::Base.connected_to(role: :writing) do
        yield
      end
    end

    # Shard-based routing
    def self.with_shard(shard_key)
      ActiveRecord::Base.connected_to(shard: shard_key) do
        yield
      end
    end
  end

  # Puma thread-safety patterns
  class PumaThreadSafety
    # Thread-local connection storage
    def self.thread_local_connection(database_url)
      Thread.current[:db_connection] ||= Sequel.connect(database_url)
    end

    # Connection per thread pattern
    class ThreadSafeRepository
      def initialize(database_url)
        @database_url = database_url
        @connections = Concurrent::Map.new
      end

      def connection
        thread_id = Thread.current.object_id
        @connections.compute_if_absent(thread_id) do
          Sequel.connect(@database_url)
        end
      end

      def query(sql, *params)
        connection.fetch(sql, *params).all
      end

      def disconnect_all
        @connections.each_value(&:disconnect)
        @connections.clear
      end
    end

    # Puma configuration for optimal connection handling
    def self.puma_config
      <<~CONFIG
        # config/puma.rb
        
        # Workers and threads
        workers ENV.fetch("WEB_CONCURRENCY") { 4 }
        threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
        threads threads_count, threads_count
        
        # Preload app for better memory usage
        preload_app!
        
        # Before fork - disconnect connections
        before_fork do
          ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
        end
        
        # On worker boot - establish new connections
        on_worker_boot do
          ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
        end
        
        # Connection pool size should match thread count
        # DATABASE_URL with pool parameter
        # postgresql://user:pass@host/db?pool=5
      CONFIG
    end

    # Puma worker killer for memory management
    def self.setup_worker_killer
      require 'puma_worker_killer'

      PumaWorkerKiller.config do |config|
        config.ram = 2048 # MB
        config.frequency = 5 # seconds
        config.percent_usage = 0.98
        config.rolling_restart_frequency = 12 * 3600 # 12 hours
      end

      PumaWorkerKiller.start
    end
  end

  # Sequel threaded connection pools
  class SequelThreadedPools
    # Configure Sequel with threaded pool
    def self.configure_threaded_pool(database_url)
      Sequel.connect(
        database_url,
        max_connections: 25,
        pool_timeout: 5,
        pool_class: Sequel::ThreadedConnectionPool,
        
        # Connection validation
        test: true,
        
        # Keep-alive settings
        keepalives: 1,
        keepalives_idle: 30,
        keepalives_interval: 10,
        keepalives_count: 3,
        
        # Timeouts
        connect_timeout: 5,
        read_timeout: 30,
        write_timeout: 30
      )
    end

    # Sharded connection pool
    class ShardedPool
      def initialize(shard_configs)
        @shards = {}
        shard_configs.each do |shard_name, config|
          @shards[shard_name] = Sequel.connect(
            config[:url],
            max_connections: config[:pool_size] || 10
          )
        end
      end

      def with_shard(shard_name)
        raise "Unknown shard: #{shard_name}" unless @shards[shard_name]
        yield @shards[shard_name]
      end

      def shard_for_key(key)
        shard_index = key.hash % @shards.size
        @shards.keys[shard_index]
      end

      def query_all_shards(sql, *params)
        results = {}
        threads = @shards.map do |shard_name, db|
          Thread.new do
            [shard_name, db.fetch(sql, *params).all]
          end
        end

        threads.each do |thread|
          shard_name, result = thread.value
          results[shard_name] = result
        end

        results
      end

      def disconnect_all
        @shards.each_value(&:disconnect)
      end
    end

    # Connection pool monitoring
    class PoolMonitor
      def initialize(db)
        @db = db
      end

      def stats
        pool = @db.pool
        {
          size: pool.size,
          max_size: pool.max_size,
          allocated: pool.allocated.size,
          available: pool.available_connections.size,
          created_count: pool.created_count,
          timeout: pool.timeout
        }
      end

      def monitor(interval: 5)
        Thread.new do
          loop do
            stats_snapshot = stats
            log_stats(stats_snapshot)
            
            # Alert if pool is saturated
            if stats_snapshot[:available] == 0
              alert_pool_saturation(stats_snapshot)
            end

            sleep interval
          end
        end
      end

      private

      def log_stats(stats)
        puts "[Pool Monitor] #{Time.now} - #{stats.inspect}"
      end

      def alert_pool_saturation(stats)
        puts "[ALERT] Connection pool saturated! #{stats.inspect}"
      end
    end

    # Automatic connection retry
    class RetryableConnection
      def initialize(database_url, max_retries: 3, retry_delay: 0.5)
        @database_url = database_url
        @max_retries = max_retries
        @retry_delay = retry_delay
        @db = connect_with_retry
      end

      def query(sql, *params)
        retries = 0
        begin
          @db.fetch(sql, *params).all
        rescue Sequel::DatabaseConnectionError, Sequel::PoolTimeout => e
          retries += 1
          if retries <= @max_retries
            sleep @retry_delay * retries
            @db = connect_with_retry
            retry
          else
            raise e
          end
        end
      end

      private

      def connect_with_retry
        retries = 0
        begin
          Sequel.connect(@database_url)
        rescue => e
          retries += 1
          if retries <= @max_retries
            sleep @retry_delay * retries
            retry
          else
            raise e
          end
        end
      end
    end
  end

  # Advanced connection patterns
  class ConnectionPatterns
    # Lazy connection initialization
    class LazyConnection
      def initialize(database_url)
        @database_url = database_url
        @connection = nil
      end

      def connection
        @connection ||= Sequel.connect(@database_url)
      end

      def query(sql, *params)
        connection.fetch(sql, *params).all
      end

      def disconnect
        @connection&.disconnect
        @connection = nil
      end
    end

    # Connection with automatic reconnection
    class AutoReconnectConnection
      def initialize(database_url)
        @database_url = database_url
        @connection = Sequel.connect(database_url)
        setup_reconnection
      end

      def query(sql, *params)
        @connection.fetch(sql, *params).all
      rescue Sequel::DatabaseDisconnectError
        reconnect
        retry
      end

      private

      def setup_reconnection
        @connection.extension(:connection_validator)
        @connection.pool.connection_validation_timeout = 60
      end

      def reconnect
        @connection.disconnect
        @connection = Sequel.connect(@database_url)
        setup_reconnection
      end
    end

    # Read/Write splitting
    class ReadWriteSplitter
      def initialize(write_url, read_urls)
        @write_db = Sequel.connect(write_url)
        @read_dbs = read_urls.map { |url| Sequel.connect(url) }
        @read_index = 0
      end

      def write_query(sql, *params)
        @write_db.fetch(sql, *params).all
      end

      def read_query(sql, *params)
        # Round-robin read replicas
        db = @read_dbs[@read_index % @read_dbs.size]
        @read_index += 1
        db.fetch(sql, *params).all
      end

      def transaction
        @write_db.transaction do
          yield @write_db
        end
      end
    end

    # Connection with circuit breaker
    class CircuitBreakerConnection
      FAILURE_THRESHOLD = 5
      TIMEOUT_DURATION = 60

      def initialize(database_url)
        @database_url = database_url
        @connection = Sequel.connect(database_url)
        @failure_count = 0
        @last_failure_time = nil
        @state = :closed # :closed, :open, :half_open
      end

      def query(sql, *params)
        case @state
        when :open
          if Time.now - @last_failure_time > TIMEOUT_DURATION
            @state = :half_open
          else
            raise "Circuit breaker is OPEN"
          end
        end

        begin
          result = @connection.fetch(sql, *params).all
          on_success
          result
        rescue => e
          on_failure
          raise e
        end
      end

      private

      def on_success
        @failure_count = 0
        @state = :closed
      end

      def on_failure
        @failure_count += 1
        @last_failure_time = Time.now

        if @failure_count >= FAILURE_THRESHOLD
          @state = :open
        end
      end
    end
  end
end

# Example usage
class AdvancedConnectionExamples
  def self.run(database_url)
    puts "=== Advanced Connection Patterns ===\n\n"

    # Example 1: Custom connection pool
    puts "1. Custom ConnectionPool gem usage..."
    pool = AdvancedConnectionPatterns::CustomConnectionPool.new(database_url, size: 10)
    
    pool.with_connection do |conn|
      result = conn[:products].first
      puts "  ✓ Query executed: #{result[:name]}"
    end
    
    puts "  Pool stats: #{pool.stats.inspect}\n\n"

    # Example 2: Parallel queries with pool
    puts "2. Parallel queries with connection pool..."
    queries = [
      { sql: "SELECT COUNT(*) FROM products WHERE metadata->>'brand' = ?", params: ['Dell'] },
      { sql: "SELECT COUNT(*) FROM products WHERE metadata->>'brand' = ?", params: ['Apple'] },
      { sql: "SELECT COUNT(*) FROM products WHERE metadata->>'brand' = ?", params: ['Sony'] }
    ]
    
    results = pool.parallel_queries(queries)
    results.each_with_index do |result, i|
      puts "  Query #{i + 1}: #{result.first[:count]} products"
    end
    puts "\n"

    # Example 3: Sequel threaded pool
    puts "3. Sequel threaded connection pool..."
    db = AdvancedConnectionPatterns::SequelThreadedPools.configure_threaded_pool(database_url)
    
    monitor = AdvancedConnectionPatterns::SequelThreadedPools::PoolMonitor.new(db)
    puts "  Pool stats: #{monitor.stats.inspect}\n\n"

    # Example 4: Retryable connection
    puts "4. Retryable connection with automatic retry..."
    retryable = AdvancedConnectionPatterns::SequelThreadedPools::RetryableConnection.new(
      database_url,
      max_retries: 3,
      retry_delay: 0.5
    )
    
    result = retryable.query("SELECT COUNT(*) as count FROM products")
    puts "  ✓ Query with retry: #{result.first[:count]} products\n\n"

    # Example 5: Circuit breaker
    puts "5. Circuit breaker pattern..."
    circuit = AdvancedConnectionPatterns::ConnectionPatterns::CircuitBreakerConnection.new(database_url)
    
    begin
      result = circuit.query("SELECT 1")
      puts "  ✓ Circuit breaker: Query successful\n\n"
    rescue => e
      puts "  ✗ Circuit breaker: #{e.message}\n\n"
    end

    puts "=== All advanced connection examples completed! ===\n"
  end
end
