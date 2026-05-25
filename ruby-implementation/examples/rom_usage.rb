#!/usr/bin/env ruby

# ROM (Ruby Object Mapper) examples
# 
# Run: ruby examples/rom_usage.rb

require_relative '../lib/rom_repository'

# Configuration
database_url = ENV['PGBOUNCER_URL'] || 'postgresql://pguser:pgpass@localhost:6434/advanced_pg'

puts "=== ROM (Ruby Object Mapper) Examples ===\n\n"

# Initialize ROM
rom_config = ROMConfiguration.new(database_url)
repo = rom_config.product_repo

# Example 1: Basic queries
puts "1. Basic queries with ROM..."
dell_products = repo.find_by_brand('Dell')
puts "  Dell products: #{dell_products.size}"

affordable = repo.find_in_price_range(200, 500)
puts "  Affordable products ($200-$500): #{affordable.size}"

electronics = repo.find_with_tag('electronics')
puts "  Electronics: #{electronics.size}\n\n"

# Example 2: Complex search
puts "2. Complex search (Apple, $500-$1000, mobile tag)..."
results = repo.search(
  brand: 'Apple',
  min_price: 500,
  max_price: 1000,
  tag: 'mobile'
)
results.each do |product|
  metadata = product.metadata
  puts "  - #{product.name}: $#{metadata['price']}"
end
puts "\n"

# Example 3: Aggregations
puts "3. Aggregations..."
stats = repo.price_statistics
puts "  Total products: #{stats[:total_products]}"
puts "  Average price: $#{stats[:avg_price].to_f.round(2)}"
puts "  Min price: $#{stats[:min_price]}"
puts "  Max price: $#{stats[:max_price]}\n\n"

# Example 4: Count by brand
puts "4. Products per brand..."
by_brand = repo.count_by_brand
by_brand.first(5).each do |row|
  puts "  #{row[:brand]}: #{row[:count]} products"
end
puts "\n"

# Example 5: All tags
puts "5. All unique tags..."
tags = repo.all_tags
puts "  Tags: #{tags.join(', ')}\n\n"

# Example 6: Create product
puts "6. Creating new product..."
new_product = repo.create_product(
  'Wireless Keyboard',
  {
    brand: 'Logitech',
    specs: {
      type: 'mechanical',
      wireless: true,
      battery: '2 years'
    },
    price: 89.99,
    tags: ['electronics', 'peripherals', 'keyboards']
  }
)
puts "  ✓ Created: #{new_product[:name]} (ID: #{new_product[:id]})\n\n"

# Example 7: Update price
puts "7. Updating product price..."
repo.update_price(new_product[:id], 79.99)
puts "  ✓ Updated price to $79.99\n\n"

# Example 8: Add discount
puts "8. Adding discount..."
repo.add_discount(new_product[:id], 10)
puts "  ✓ Added 10% discount\n\n"

# Example 9: Remove discount
puts "9. Removing discount..."
repo.remove_discount(new_product[:id])
puts "  ✓ Removed discount\n\n"

# Example 10: Bulk operations
puts "10. Bulk operations..."
repo.add_discount_to_brand('Dell', 15)
puts "  ✓ Added 15% discount to all Dell products"

repo.mark_premium
puts "  ✓ Marked all premium products (>$1000)\n\n"

# Example 11: Working with custom structs
puts "11. Working with custom Product structs..."
examples = ROMExamples.new(database_url)

apple_products = repo.find_by_brand('Apple')
if apple_products.any?
  product = apple_products.first
  
  # Access via custom struct methods
  puts "  Product: #{product.name}"
  puts "  Brand: #{product.brand}" if product.respond_to?(:brand)
  puts "  Price: $#{product.metadata['price']}"
  puts "  Tags: #{product.metadata['tags']&.join(', ')}"
  
  # Custom predicates
  if product.respond_to?(:premium?)
    puts "  Premium: #{product.premium? ? 'Yes' : 'No'}"
  end
  if product.respond_to?(:on_sale?)
    puts "  On Sale: #{product.on_sale? ? 'Yes' : 'No'}"
  end
end
puts "\n"

# Example 12: Chaining queries
puts "12. Chaining relation methods..."
premium_electronics = rom_config.container.relations[:products]
  .with_tag('electronics')
  .premium
  .ordered_by_price(:desc)
  .limit(5)
  .to_a

puts "  Top 5 premium electronics:"
premium_electronics.each do |product|
  puts "    - #{product[:name]}: $#{product[:metadata]['price']}"
end
puts "\n"

# Example 13: Advanced patterns with Dry::Monads
puts "13. Using Dry::Monads for error handling..."
updater = AdvancedROMPatterns::UpdateProductPrice.new

result = updater.call(repo, new_product[:id], 99.99)
case result
when Dry::Monads::Success
  puts "  ✓ Price updated successfully"
when Dry::Monads::Failure
  puts "  ✗ Failed: #{result.failure}"
end
puts "\n"

# Cleanup
puts "14. Cleanup..."
rom_config.container.gateways[:default].connection[:products]
  .where(id: new_product[:id])
  .delete
puts "  ✓ Deleted test product\n\n"

puts "=== All ROM examples completed! ===\n"
puts "\nKey benefits of ROM:"
puts "  - Clean separation of concerns (Relations, Repositories, Structs)"
puts "  - Explicit data mapping and transformations"
puts "  - Composable queries with method chaining"
puts "  - Type safety with Dry::Types integration"
puts "  - Flexible architecture for complex domains"
puts "  - Works seamlessly with JSONB and PostgreSQL features"
