#!/usr/bin/env ruby

# Async PostgreSQL operations examples
# 
# Run: ruby examples/async_usage.rb

require 'async'
require_relative '../lib/async_operations'

# Configuration
database_url = ENV['PGBOUNCER_URL'] || 'postgresql://pguser:pgpass@localhost:6434/advanced_pg'

puts "=== Async PostgreSQL Operations ===\n\n"

async_ops = AsyncPostgresOperations.new(database_url, pool_size: 20)

# Example 1: Parallel brand queries
puts "1. Parallel brand queries (concurrent execution)..."
start_time = Time.now

Async do
  results = async_ops.parallel_brand_queries(['Dell', 'Apple', 'Sony']).wait
  
  results.each do |brand, products|
    puts "  #{brand}: #{products.size} products"
  end
  
  duration = Time.now - start_time
  puts "  Completed in #{duration.round(3)}s\n\n"
end.wait

# Example 2: Sequential vs Parallel comparison
puts "2. Sequential vs Parallel comparison..."

# Sequential
sequential_start = Time.now
['Dell', 'Apple', 'Sony'].each do |brand|
  async_ops.query_by_brand(brand)
end
sequential_time = Time.now - sequential_start

# Parallel
parallel_start = Time.now
Async do
  async_ops.parallel_brand_queries(['Dell', 'Apple', 'Sony']).wait
end.wait
parallel_time = Time.now - parallel_start

puts "  Sequential: #{sequential_time.round(3)}s"
puts "  Parallel: #{parallel_time.round(3)}s"
puts "  Speedup: #{(sequential_time / parallel_time).round(2)}x\n\n"

# Example 3: Parallel aggregations
puts "3. Parallel aggregations (multiple queries at once)..."
Async do
  results = async_ops.parallel_aggregations.wait
  
  puts "  Total products: #{results[:total_count]}"
  puts "  Average price: $#{results[:price_stats][:avg_price].to_f.round(2)}"
  puts "  Number of brands: #{results[:brand_counts].size}"
  puts "  Number of tags: #{results[:tag_list].size}\n\n"
end.wait

# Example 4: Concurrent updates
puts "4. Concurrent price updates..."
Async do
  # Get some product IDs
  db = async_ops.db_connection
  product_ids = db[:products].limit(3).select_map(:id)
  
  if product_ids.size >= 3
    updates = {
      product_ids[0] => 99.99,
      product_ids[1] => 149.99,
      product_ids[2] => 199.99
    }
    
    start_time = Time.now
    results = async_ops.concurrent_price_updates(updates).wait
    duration = Time.now - start_time
    
    successful = results.count { |r| r[:updated] }
    puts "  Updated #{successful}/#{results.size} products in #{duration.round(3)}s\n\n"
  else
    puts "  Not enough products for demo\n\n"
  end
end.wait

# Example 5: Rate-limited operations
puts "5. Rate-limited operations (max 5 concurrent)..."
rate_limited = AsyncPatterns::RateLimitedOperations.new(database_url, rate_limit: 5)

queries = 20.times.map do |i|
  { sql: "SELECT * FROM products LIMIT 10 OFFSET ?", params: [i * 10] }
end

start_time = Time.now
Async do
  rate_limited.rate_limited_queries(queries).wait
end.wait
duration = Time.now - start_time

puts "  Executed #{queries.size} queries in #{duration.round(3)}s"
puts "  Average: #{(duration / queries.size * 1000).round(2)}ms per query\n\n"

# Example 6: Async retry with exponential backoff
puts "6. Async retry with exponential backoff..."
Async do
  result = AsyncPatterns::AsyncRetry.with_retry(max_attempts: 3, base_delay: 0.1) do
    # Simulate operation that might fail
    db = async_ops.db_connection
    db[:products].first
  end.wait
  
  puts "  ✓ Operation succeeded with retry logic\n\n"
end.wait

# Example 7: Batch processing with error handling
puts "7. Batch processing (100 items per batch)..."
processor = AsyncPatterns::BatchProcessor.new(database_url, batch_size: 100)

# Create test items
items = 250.times.map do |i|
  {
    name: "Batch Product #{i}",
    metadata: Sequel.pg_jsonb({
      brand: "BatchBrand",
      price: rand(10.0..100.0).round(2),
      tags: ['batch', 'test'],
      batch_id: i
    })
  }
end

Async do
  start_time = Time.now
  results = processor.process_in_batches(items).wait
  duration = Time.now - start_time
  
  puts "  Processed #{items.size} items in #{duration.round(3)}s"
  puts "  Success: #{results[:success].size}"
  puts "  Failed: #{results[:failed].size}"
  puts "  Throughput: #{(items.size / duration).round(2)} items/second\n\n"
  
  # Cleanup
  db = async_ops.db_connection
  db[:products].where(Sequel.lit("metadata->>'brand' = 'BatchBrand'")).delete
end.wait

# Example 8: Connection pool health check
puts "8. Connection pool health check..."
pool = AsyncPatterns::HealthCheckedPool.new(database_url, pool_size: 5)

Async do
  # Perform some operations to populate pool
  5.times do
    pool.with_connection do |conn|
      conn[:products].first
    end.wait
  end
  
  # Check health
  health_results = pool.health_check.wait
  healthy_count = health_results.count { |r| r[:healthy] }
  
  puts "  Checked #{health_results.size} connections"
  puts "  Healthy: #{healthy_count}/#{health_results.size}\n\n"
end.wait

puts "=== All async examples completed! ===\n"
puts "\nKey takeaways:"
puts "  - Async operations can significantly improve throughput"
puts "  - Parallel queries reduce total execution time"
puts "  - Rate limiting prevents overwhelming the database"
puts "  - Proper error handling is crucial for reliability"
puts "  - Connection pooling works seamlessly with async"
