#!/usr/bin/env ruby

# Basic usage examples for PostgreSQL Advanced Features
# 
# Run: ruby examples/basic_usage.rb

require 'sequel'
require_relative '../lib/jsonb_operations'
require_relative '../lib/connection_pooling'

# Configuration
direct_url = ENV['DATABASE_URL'] || 'postgresql://pguser:pgpass@localhost:5434/advanced_pg'
pooled_url = ENV['PGBOUNCER_URL'] || 'postgresql://pguser:pgpass@localhost:6434/advanced_pg'

puts "=== PostgreSQL Advanced Features - Basic Usage ===\n\n"

# Initialize connections
puts "1. Setting up connection pooling..."
pooling = ConnectionPooling.new(direct_url, pooled_url)
jsonb = JsonbOperations.new(pooling.pooled_db)
puts "✓ Connected via PgBouncer\n\n"

# Example 1: Query by brand
puts "2. Querying products by brand (Dell)..."
dell_products = jsonb.get_products_by_brand('Dell')
dell_products.each do |product|
  metadata = JSON.parse(product[:metadata])
  puts "  - #{product[:name]} (Brand: #{metadata['brand']})"
end
puts "\n"

# Example 2: Query by CPU
puts "3. Querying products by CPU (i7)..."
i7_products = jsonb.get_products_by_cpu('i7')
i7_products.each do |product|
  puts "  - #{product[:name]} (CPU: #{product[:cpu]})"
end
puts "\n"

# Example 3: Query by tag
puts "4. Querying products by tag (electronics)..."
electronics = jsonb.get_products_by_tag('electronics')
puts "  Found #{electronics.count} products\n\n"

# Example 4: Complex search
puts "5. Complex search (Apple products, $500-$1000)..."
results = jsonb.search_products(
  brand: 'Apple',
  min_price: 500,
  max_price: 1000
)
results.each do |product|
  metadata = JSON.parse(product[:metadata])
  puts "  - #{product[:name]}: $#{metadata['price']}"
end
puts "\n"

# Example 5: Update product price
puts "6. Updating product price..."
first_product = dell_products.first
if first_product
  metadata = JSON.parse(first_product[:metadata])
  old_price = metadata['price']
  new_price = (old_price * 0.9).round(2) # 10% discount
  
  jsonb.update_product_price(first_product[:id], new_price)
  puts "  ✓ Updated #{first_product[:name]} from $#{old_price} to $#{new_price}\n\n"
  
  # Restore original price
  jsonb.update_product_price(first_product[:id], old_price)
end

# Example 6: Add and remove discount
puts "7. Adding discount to product..."
if first_product
  jsonb.add_product_discount(first_product[:id], 15)
  puts "  ✓ Added 15% discount"
  
  jsonb.remove_product_discount(first_product[:id])
  puts "  ✓ Removed discount\n\n"
end

# Example 7: Get price statistics
puts "8. Getting price statistics..."
stats = jsonb.get_price_statistics
puts "  Total products: #{stats[:total_products]}"
puts "  Average price: $#{stats[:avg_price].to_f.round(2)}"
puts "  Min price: $#{stats[:min_price]}"
puts "  Max price: $#{stats[:max_price]}\n\n"

# Example 8: Get all tags
puts "9. Getting all unique tags..."
tags = jsonb.get_all_tags
puts "  Tags: #{tags.join(', ')}\n\n"

# Example 9: Benchmark connection pooling
puts "10. Benchmarking connection pooling..."
benchmark = pooling.benchmark_connections(50)
puts "  Iterations: #{benchmark[:iterations]}"
puts "  Direct time: #{benchmark[:direct_time]}s"
puts "  Pooled time: #{benchmark[:pooled_time]}s"
puts "  Improvement: #{benchmark[:improvement]}\n\n"

# Example 10: Simulate high load
puts "11. Simulating high load (50 concurrent queries)..."
load_test = pooling.simulate_high_load(50)
puts "  Queries executed: #{load_test[:queries_executed]}"
puts "  Total time: #{load_test[:total_time]}s"
puts "  Queries per second: #{load_test[:queries_per_second]}\n\n"

# Example 11: Get pool statistics
puts "12. Connection pool statistics..."
stats = pooling.get_pool_stats
puts "  Direct pool size: #{stats[:direct_pool][:size]}/#{stats[:direct_pool][:max_size]}"
puts "  Pooled pool size: #{stats[:pooled_pool][:size]}/#{stats[:pooled_pool][:max_size]}\n\n"

# Example 12: Test transaction pooling
puts "13. Testing transaction pooling..."
tx_test = pooling.test_transaction_pooling
puts "  Direct transaction time: #{tx_test[:direct_transaction_time]}s"
puts "  Pooled transaction time: #{tx_test[:pooled_transaction_time]}s"
puts "  Note: #{tx_test[:note]}\n\n"

# Cleanup
pooling.close_connections

puts "=== All examples completed successfully! ===\n"
puts "\nNext steps:"
puts "  - Review the code in lib/jsonb_operations.rb"
puts "  - Try the exercises in exercises/"
puts "  - Read the guides in docs/"
puts "  - Experiment with your own queries"
