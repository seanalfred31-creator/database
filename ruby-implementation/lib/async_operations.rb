require 'async'
require 'async/barrier'
require 'async/semaphore'
require 'sequel'

# Async PostgreSQL operations with connection pooling
class AsyncPostgresOperations
  def initialize(database_url, pool_size: 20)
    @database_url = database_url
    @pool_size = pool_size
    @semaphore = Async::Semaphore.new(pool_size)
  end

  # Get database connection (thread-safe)
  def db_connection
    Thread.current[:db] ||= Sequel.connect(@database_url)
  end

  # Async query execution
  def async_query(sql, params = [])
    Async do
      @semaphore.async do
        db = db_connection
        db.fetch(sql, *params).all
      end
    end
  end

  # Parallel JSONB queries
  def parallel_brand_queries(brands)
    Async do |task|
      results = {}
      barrier = Async::Barrier.new

      brands.each do |brand|
        barrier.async do
          results[brand] = query_by_brand(brand)
        end
      end

      barrier.wait
      results
    end
  end

  # Query by brand
  def query_by_brand(brand)
    db = db_connection
    db[:products]
      .where(Sequel.lit("metadata->>'brand' = ?", brand))
      .all
  end

  # Concurrent price updates
  def concurrent_price_updates(updates)
    Async do |task|
      barrier = Async::Barrier.new
      results = []

      updates.each do |id, new_price|
        barrier.async do
          db = db_connection
          result = db[:products]
            .where(id: id)
            .update(Sequel.lit("metadata = jsonb_set(metadata, '{price}', ?::jsonb)", new_price.to_json))
          results << { id: id, updated: result > 0 }
        end
      end

      barrier.wait
      results
    end
  end

  # Batch insert with async
  def async_batch_insert(products)
    Async do |task|
      db = db_connection
      
      db.transaction do
        products.each_slice(100) do |batch|
          task.async do
            db[:products].multi_insert(batch)
          end.wait
        end
      end
    end
  end

  # Parallel aggregations
  def parallel_aggregations
    Async do |task|
      results = {}

      # Run multiple aggregations in parallel
      tasks = {
        total_count: task.async { count_products },
        price_stats: task.async { price_statistics },
        brand_counts: task.async { count_by_brand },
        tag_list: task.async { all_tags }
      }

      tasks.each do |key, async_task|
        results[key] = async_task.wait
      end

      results
    end
  end

  # Stream large result sets
  def stream_products(batch_size: 100)
    Async do |task|
      db = db_connection
      offset = 0

      loop do
        batch = db[:products]
          .limit(batch_size)
          .offset(offset)
          .all

        break if batch.empty?

        # Process batch asynchronously
        task.async do
          process_batch(batch)
        end

        offset += batch_size
      end
    end
  end

  private

  def count_products
    db_connection[:products].count
  end

  def price_statistics
    db_connection[:products]
      .select(
        Sequel.lit("COUNT(*) as total"),
        Sequel.lit("AVG((metadata->>'price')::numeric) as avg_price"),
        Sequel.lit("MIN((metadata->>'price')::numeric) as min_price"),
        Sequel.lit("MAX((metadata->>'price')::numeric) as max_price")
      )
      .first
  end

  def count_by_brand
    db_connection[:products]
      .select(Sequel.lit("metadata->>'brand' as brand"))
      .select_append { count(:*).as(:count) }
      .group(Sequel.lit("metadata->>'brand'"))
      .all
  end

  def all_tags
    db_connection[:products]
      .select(Sequel.lit("DISTINCT jsonb_array_elements_text(metadata->'tags') as tag"))
      .order(:tag)
      .map { |row| row[:tag] }
  end

  def process_batch(batch)
    # Process each item in batch
    batch.each do |item|
      # Your processing logic here
    end
  end
end

# Async HTTP server with Falcon
class AsyncProductAPI
  def initialize(database_url)
    @async_ops = AsyncPostgresOperations.new(database_url)
  end

  def call(env)
    request = Rack::Request.new(env)
    path = request.path
    method = request.request_method

    Async do
      response = handle_request(path, method, request)
      [200, { 'Content-Type' => 'application/json' }, [response.to_json]]
    end.wait
  rescue => e
    [500, { 'Content-Type' => 'application/json' }, [{ error: e.message }.to_json]]
  end

  private

  def handle_request(path, method, request)
    case path
    when '/'
      {
        message: 'Async PostgreSQL API',
        endpoints: {
          'GET /products/brands' => 'Get products for multiple brands (parallel)',
          'POST /products/batch' => 'Batch insert products',
          'GET /aggregations' => 'Run parallel aggregations',
          'GET /stream' => 'Stream large result set'
        }
      }

    when '/products/brands'
      brands = request.params['brands']&.split(',') || ['Dell', 'Apple', 'Sony']
      @async_ops.parallel_brand_queries(brands).wait

    when '/aggregations'
      @async_ops.parallel_aggregations.wait

    when '/products/batch'
      if method == 'POST'
        products = JSON.parse(request.body.read)
        @async_ops.async_batch_insert(products).wait
        { inserted: products.size }
      else
        { error: 'POST required' }
      end

    else
      { error: 'Not found' }
    end
  end
end

# Advanced async patterns
module AsyncPatterns
  # Rate-limited async operations
  class RateLimitedOperations
    def initialize(database_url, rate_limit: 10)
      @async_ops = AsyncPostgresOperations.new(database_url)
      @semaphore = Async::Semaphore.new(rate_limit)
    end

    def rate_limited_queries(queries)
      Async do |task|
        results = []

        queries.each do |query|
          @semaphore.async do
            results << execute_query(query)
          end
        end

        results
      end
    end

    private

    def execute_query(query)
      # Execute with rate limiting
      @async_ops.async_query(query[:sql], query[:params]).wait
    end
  end

  # Async connection pool with health checks
  class HealthCheckedPool
    def initialize(database_url, pool_size: 20)
      @database_url = database_url
      @pool_size = pool_size
      @connections = []
      @semaphore = Async::Semaphore.new(pool_size)
    end

    def with_connection
      Async do
        @semaphore.async do
          conn = acquire_connection
          
          begin
            yield conn
          ensure
            release_connection(conn)
          end
        end
      end
    end

    def health_check
      Async do |task|
        results = []

        @connections.each do |conn|
          task.async do
            begin
              conn.test_connection
              results << { connection: conn.object_id, healthy: true }
            rescue => e
              results << { connection: conn.object_id, healthy: false, error: e.message }
            end
          end
        end

        results
      end
    end

    private

    def acquire_connection
      if @connections.empty?
        Sequel.connect(@database_url)
      else
        @connections.pop
      end
    end

    def release_connection(conn)
      @connections.push(conn) if @connections.size < @pool_size
    end
  end

  # Async retry with exponential backoff
  class AsyncRetry
    def self.with_retry(max_attempts: 3, base_delay: 0.1)
      Async do
        attempts = 0

        begin
          attempts += 1
          yield
        rescue => e
          if attempts < max_attempts
            delay = base_delay * (2 ** (attempts - 1))
            sleep delay
            retry
          else
            raise e
          end
        end
      end
    end
  end

  # Async batch processor with error handling
  class BatchProcessor
    def initialize(database_url, batch_size: 100)
      @async_ops = AsyncPostgresOperations.new(database_url)
      @batch_size = batch_size
    end

    def process_in_batches(items)
      Async do |task|
        results = { success: [], failed: [] }
        barrier = Async::Barrier.new

        items.each_slice(@batch_size) do |batch|
          barrier.async do
            begin
              process_batch(batch)
              results[:success].concat(batch)
            rescue => e
              results[:failed].concat(batch.map { |item| { item: item, error: e.message } })
            end
          end
        end

        barrier.wait
        results
      end
    end

    private

    def process_batch(batch)
      # Process batch
      @async_ops.async_batch_insert(batch).wait
    end
  end
end

# Example usage
class AsyncExamples
  def self.run(database_url)
    async_ops = AsyncPostgresOperations.new(database_url)

    puts "=== Async PostgreSQL Operations ===\n\n"

    # Example 1: Parallel brand queries
    puts "1. Parallel brand queries..."
    Async do
      results = async_ops.parallel_brand_queries(['Dell', 'Apple', 'Sony']).wait
      results.each do |brand, products|
        puts "  #{brand}: #{products.size} products"
      end
    end.wait
    puts "\n"

    # Example 2: Parallel aggregations
    puts "2. Parallel aggregations..."
    Async do
      results = async_ops.parallel_aggregations.wait
      puts "  Total products: #{results[:total_count]}"
      puts "  Average price: $#{results[:price_stats][:avg_price].to_f.round(2)}"
      puts "  Brands: #{results[:brand_counts].size}"
      puts "  Tags: #{results[:tag_list].size}"
    end.wait
    puts "\n"

    # Example 3: Concurrent updates
    puts "3. Concurrent price updates..."
    updates = {
      'id1' => 99.99,
      'id2' => 149.99,
      'id3' => 199.99
    }
    Async do
      results = async_ops.concurrent_price_updates(updates).wait
      successful = results.count { |r| r[:updated] }
      puts "  Updated #{successful}/#{results.size} products"
    end.wait
    puts "\n"

    puts "=== All async examples completed! ===\n"
  end
end
