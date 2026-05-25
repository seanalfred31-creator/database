#!/usr/bin/env ruby

# Advanced connection patterns examples
# 
# Run: ruby examples/advanced_connections.rb

require_relative '../lib/advanced_connection_patterns'

# Configuration
database_url = ENV['PGBOUNCER_URL'] || 'postgresql://pguser:pgpass@localhost:6434/advanced_pg'

puts "=== Advanced Connection Patterns ===\n\n"

# Example 1: ConnectionPool gem
puts "1. ConnectionPool gem usage..."
pool = AdvancedConnectionPatterns::CustomConnectionPool.new(database_url, size: 10, timeout: 5)

pool.with_connection do |conn|
  result = conn[:products].first
  puts "  ✓ Query executed: #{result[:name]}"
end

stats = pool.stats
puts "  Pool size: #{stats[:size]}"
puts "  Available: #{stats[:available]}\n\n"

# Example 2: Parallel queries
puts "2. Parallel queries with connection pool..."
queries = [
  { sql: "SELECT COUNT(*) FROM products WHERE metadata->>'brand' = ?", params: ['Dell'] },
  { sql: "SELECT COUNT(*) FROM products WHERE metadata->>'brand' = ?", params: ['Apple'] },
  { sql: "SELECT COUNT(*) FROM products WHERE metadata->>'brand' = ?", params: ['Sony'] },
  { sql: "SELECT AVG((metadata->>'price')::numeric) FROM products", params: [] }
]

start_time = Time.now
results = pool.parallel_queries(queries)
duration = Time.now - start_time

results.each_with_index do |result, i|
  value = result.first.values.first
  puts "  Query #{i + 1}: #{value}"
end
puts "  Execution time: #{duration.round(4)}s\n\n"

# Example 3: Health check
puts "3. Connection pool health check..."
health = pool.health_check
healthy_count = health.count { |h| h[:healthy] }
puts "  Healthy connections: #{healthy_count}/#{health.size}\n\n"

# Example 4: Sequel threaded pool
puts "4. Sequel threaded connection pool..."
db = AdvancedConnectionPatterns::SequelThreadedPools.configure_threaded_pool(database_url)

monitor = AdvancedConnectionPatterns::SequelThreadedPools::PoolMonitor.new(db)
stats = monitor.stats

puts "  Pool size: #{stats[:size]}/#{stats[:max_size]}"
puts "  Allocated: #{stats[:allocated]}"
puts "  Available: #{stats[:available]}\n\n"

# Example 5: Retryable connection
puts "5. Retryable connection with automatic retry..."
retryable = AdvancedConnectionPatterns::SequelThreadedPools::RetryableConnection.new(
  database_url,
  max_retries: 3,
  retry_delay: 0.5
)

result = retryable.query("SELECT COUNT(*) as count FROM products")
puts "  ✓ Query with retry: #{result.first[:count]} products\n\n"

# Example 6: Sharded pool
puts "6. Sharded connection pool..."
shard_configs = {
  shard_1: { url: database_url, pool_size: 10 },
  shard_2: { url: database_url, pool_size: 10 }
}

sharded = AdvancedConnectionPatterns::SequelThreadedPools::ShardedPool.new(shard_configs)

sharded.with_shard(:shard_1) do |db|
  count = db[:products].count
  puts "  Shard 1: #{count} products"
end

sharded.with_shard(:shard_2) do |db|
  count = db[:products].count
  puts "  Shard 2: #{count} products"
end
puts "\n"

# Example 7: Query all shards
puts "7. Query all shards in parallel..."
start_time = Time.now
results = sharded.query_all_shards("SELECT COUNT(*) as count FROM products")
duration = Time.now - start_time

results.each do |shard_name, result|
  puts "  #{shard_name}: #{result.first[:count]} products"
end
puts "  Execution time: #{duration.round(4)}s\n\n"

# Example 8: Circuit breaker
puts "8. Circuit breaker pattern..."
circuit = AdvancedConnectionPatterns::ConnectionPatterns::CircuitBreakerConnection.new(database_url)

5.times do |i|
  begin
    result = circuit.query("SELECT 1")
    puts "  ✓ Query #{i + 1}: Success"
  rescue => e
    puts "  ✗ Query #{i + 1}: #{e.message}"
  end
end
puts "\n"

# Example 9: Read/Write splitting
puts "9. Read/Write splitting..."
splitter = AdvancedConnectionPatterns::ConnectionPatterns::ReadWriteSplitter.new(
  database_url,  # write
  [database_url, database_url]  # read replicas
)

# Write query
write_result = splitter.write_query("SELECT COUNT(*) as count FROM products")
puts "  Write query: #{write_result.first[:count]} products"

# Read queries (round-robin)
3.times do |i|
  read_result = splitter.read_query("SELECT COUNT(*) as count FROM products")
  puts "  Read query #{i + 1}: #{read_result.first[:count]} products"
end
puts "\n"

# Example 10: Thread-safe repository
puts "10. Thread-safe repository..."
repo = AdvancedConnectionPatterns::PumaThreadSafety::ThreadSafeRepository.new(database_url)

threads = 5.times.map do |i|
  Thread.new do
    result = repo.query("SELECT COUNT(*) as count FROM products")
    puts "  Thread #{i + 1}: #{result.first[:count]} products"
  end
end

threads.each(&:join)
puts "\n"

# Example 11: Benchmark thread safety
puts "11. Benchmark thread-safe operations..."
iterations = 100
thread_count = 10

start_time = Time.now
threads = thread_count.times.map do
  Thread.new do
    iterations.times do
      repo.query("SELECT 1")
    end
  end
end

threads.each(&:join)
duration = Time.now - start_time

total_queries = iterations * thread_count
puts "  Total queries: #{total_queries}"
puts "  Duration: #{duration.round(4)}s"
puts "  Queries per second: #{(total_queries / duration).round(2)}\n\n"

# Cleanup
repo.disconnect_all
sharded.disconnect_all

puts "=== All advanced connection examples completed! ===\n"
puts "\nKey patterns demonstrated:"
puts "  - ConnectionPool gem for thread-safe pooling"
puts "  - Parallel query execution"
puts "  - Health checking and monitoring"
puts "  - Automatic retry with exponential backoff"
puts "  - Sharded connection pools"
puts "  - Circuit breaker for fault tolerance"
puts "  - Read/write splitting"
puts "  - Thread-safe repositories"
