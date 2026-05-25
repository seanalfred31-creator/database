# Async Ruby with PostgreSQL Guide

Learn high-concurrency patterns with Async Ruby and PostgreSQL.

## Why Async Ruby?

Traditional Ruby uses threads for concurrency, which can be:
- Heavy on memory
- Limited by GIL (Global Interpreter Lock)
- Complex to manage

Async Ruby provides:
- Lightweight fibers instead of threads
- Non-blocking I/O
- Better resource utilization
- Simpler concurrency model

## Core Concepts

### Fibers vs Threads

```ruby
# Threads (traditional)
threads = 10.times.map do
  Thread.new { perform_query }
end
threads.each(&:join)

# Fibers (async)
Async do |task|
  10.times do
    task.async { perform_query }
  end
end
```

### Async Blocks

```ruby
# Synchronous
result = expensive_operation()

# Asynchronous
Async do
  result = expensive_operation().wait
end
```

### Barriers for Synchronization

```ruby
Async do |task|
  barrier = Async::Barrier.new
  
  # Start multiple operations
  barrier.async { query_1 }
  barrier.async { query_2 }
  barrier.async { query_3 }
  
  # Wait for all to complete
  barrier.wait
end
```

## PostgreSQL with Async

### Parallel Queries

```ruby
class AsyncPostgresOperations
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
end
```

### Concurrent Updates

```ruby
def concurrent_price_updates(updates)
  Async do |task|
    barrier = Async::Barrier.new
    results = []

    updates.each do |id, new_price|
      barrier.async do
        result = update_price(id, new_price)
        results << { id: id, updated: result }
      end
    end

    barrier.wait
    results
  end
end
```

### Streaming Large Results

```ruby
def stream_products(batch_size: 100)
  Async do |task|
    offset = 0

    loop do
      batch = fetch_batch(offset, batch_size)
      break if batch.empty?

      # Process batch asynchronously
      task.async do
        process_batch(batch)
      end

      offset += batch_size
    end
  end
end
```

## Connection Pooling with Async

### Semaphore for Rate Limiting

```ruby
class AsyncPostgresOperations
  def initialize(database_url, pool_size: 20)
    @database_url = database_url
    @semaphore = Async::Semaphore.new(pool_size)
  end

  def async_query(sql, params = [])
    Async do
      @semaphore.async do
        db = db_connection
        db.fetch(sql, *params).all
      end
    end
  end
end
```

### Health-Checked Pool

```ruby
class HealthCheckedPool
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
      @connections.each do |conn|
        task.async do
          check_connection_health(conn)
        end
      end
    end
  end
end
```

## Falcon Web Server

Falcon is a high-performance async web server for Ruby.

### Basic Setup

```ruby
# config/falcon.rb
require 'async'
require 'falcon'

service 'my-api' do
  include Falcon::Environment::Rack

  endpoint Async::HTTP::Endpoint.parse('http://0.0.0.0:3000')
  
  app MyAsyncApp.new
  
  count 4  # Number of worker processes
end
```

### Async Request Handling

```ruby
class MyAsyncApp
  def call(env)
    Async do
      result = handle_request_async(env)
      [200, {}, [result.to_json]]
    end.wait
  end

  private

  def handle_request_async(env)
    Async do |task|
      # Parallel operations
      user_data = task.async { fetch_user }
      products = task.async { fetch_products }
      
      {
        user: user_data.wait,
        products: products.wait
      }
    end
  end
end
```

### Running Falcon

```bash
# Development
falcon serve --config config/falcon.rb

# Production
falcon host --config config/falcon.rb

# With specific concurrency
FALCON_CONCURRENCY=8 falcon serve
```

## Advanced Patterns

### Retry with Exponential Backoff

```ruby
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

# Usage
AsyncRetry.with_retry do
  perform_database_operation
end.wait
```

### Batch Processing

```ruby
class BatchProcessor
  def process_in_batches(items, batch_size: 100)
    Async do |task|
      results = { success: [], failed: [] }
      barrier = Async::Barrier.new

      items.each_slice(batch_size) do |batch|
        barrier.async do
          begin
            process_batch(batch)
            results[:success].concat(batch)
          rescue => e
            results[:failed].concat(
              batch.map { |item| { item: item, error: e.message } }
            )
          end
        end
      end

      barrier.wait
      results
    end
  end
end
```

### Rate Limiting

```ruby
class RateLimitedOperations
  def initialize(rate_limit: 10)
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
end
```

### Timeout Handling

```ruby
require 'async/io/timeout'

Async do |task|
  task.with_timeout(5) do
    # Operation must complete within 5 seconds
    perform_long_operation
  end
rescue Async::TimeoutError
  puts "Operation timed out"
end
```

## Performance Comparison

### Sequential vs Parallel

```ruby
require 'benchmark'

brands = ['Dell', 'Apple', 'Sony', 'HP', 'Lenovo']

# Sequential
sequential_time = Benchmark.realtime do
  brands.each { |brand| query_by_brand(brand) }
end

# Parallel with Async
parallel_time = Benchmark.realtime do
  Async do |task|
    barrier = Async::Barrier.new
    brands.each { |brand| barrier.async { query_by_brand(brand) } }
    barrier.wait
  end.wait
end

puts "Sequential: #{sequential_time}s"
puts "Parallel: #{parallel_time}s"
puts "Speedup: #{(sequential_time / parallel_time).round(2)}x"
```

Typical results:
```
Sequential: 0.523s
Parallel: 0.112s
Speedup: 4.67x
```

## Best Practices

### 1. Use Semaphores for Connection Limits

```ruby
# Limit concurrent database connections
@semaphore = Async::Semaphore.new(20)

@semaphore.async do
  # Database operation
end
```

### 2. Handle Errors Gracefully

```ruby
Async do |task|
  task.async do
    begin
      risky_operation
    rescue => e
      log_error(e)
      # Don't let one failure stop others
    end
  end
end
```

### 3. Use Barriers for Coordination

```ruby
Async do |task|
  barrier = Async::Barrier.new
  
  # Start operations
  barrier.async { operation_1 }
  barrier.async { operation_2 }
  
  # Wait for all
  barrier.wait
end
```

### 4. Monitor Resource Usage

```ruby
def with_monitoring
  start_time = Time.now
  fiber_count = Fiber.count
  
  result = yield
  
  duration = Time.now - start_time
  puts "Duration: #{duration}s, Fibers: #{Fiber.count - fiber_count}"
  
  result
end
```

### 5. Test Async Code

```ruby
RSpec.describe AsyncOperations do
  it "performs parallel queries" do
    Async do
      results = async_ops.parallel_brand_queries(['Dell', 'Apple']).wait
      expect(results.keys).to contain_exactly('Dell', 'Apple')
    end.wait
  end
end
```

## Common Pitfalls

### 1. Forgetting to Wait

```ruby
# Wrong - doesn't wait for completion
Async do
  perform_operation
end

# Correct
Async do
  perform_operation
end.wait
```

### 2. Blocking Operations

```ruby
# Wrong - blocks the fiber
Async do
  sleep 5  # Blocks!
end

# Correct - yields to other fibers
Async do
  task.sleep 5  # Non-blocking
end
```

### 3. Shared State

```ruby
# Wrong - race condition
results = []
Async do |task|
  10.times { task.async { results << fetch_data } }
end

# Correct - use mutex or collect results properly
Async do |task|
  results = 10.times.map do
    task.async { fetch_data }
  end.map(&:wait)
end
```

## Integration with PgBouncer

Async Ruby works seamlessly with PgBouncer:

```ruby
# Configure connection pool
DB = Sequel.connect(
  'postgresql://user:pass@pgbouncer:6432/db',
  max_connections: 50,  # Higher for async
  pool_timeout: 5
)

# Use with async
Async do |task|
  barrier = Async::Barrier.new
  
  100.times do
    barrier.async do
      DB[:products].first
    end
  end
  
  barrier.wait
end
```

## Monitoring and Debugging

### Logging

```ruby
require 'async/logger'

Async.logger.level = Logger::DEBUG

Async do
  Async.logger.info "Starting operation"
  perform_operation
  Async.logger.info "Completed operation"
end
```

### Performance Profiling

```ruby
require 'async/clock'

Async do
  start = Async::Clock.now
  perform_operation
  duration = Async::Clock.now - start
  puts "Operation took #{duration}s"
end
```

## Resources

- [Async Gem](https://github.com/socketry/async)
- [Falcon Server](https://github.com/socketry/falcon)
- [Async::IO](https://github.com/socketry/async-io)
- [Async Patterns](https://github.com/socketry/async/wiki)

## Next Steps

1. Start with simple parallel queries
2. Add connection pooling with semaphores
3. Implement error handling and retries
4. Deploy with Falcon for production
5. Monitor and tune for your workload
