require 'json'
require 'sequel'
require_relative 'lib/jsonb_operations'
require_relative 'lib/connection_pooling'

# Load environment variables
require 'dotenv'
Dotenv.load

# Initialize connections
direct_url = ENV['DATABASE_URL'] || 'postgresql://pguser:pgpass@postgres:5432/advanced_pg'
pooled_url = ENV['PGBOUNCER_URL'] || 'postgresql://pguser:pgpass@pgbouncer:5432/advanced_pg'

pooling = ConnectionPooling.new(direct_url, pooled_url)
jsonb = JsonbOperations.new(pooling.pooled_db)

# Simple Rack application
app = lambda do |env|
  request = Rack::Request.new(env)
  path = request.path
  method = request.request_method

  begin
    response = case path
    when '/'
      {
        message: 'PostgreSQL Advanced Features API (Ruby)',
        endpoints: {
          'GET /products/brand/:brand' => 'Get products by brand',
          'GET /products/cpu/:cpu' => 'Get products by CPU',
          'GET /products/tag/:tag' => 'Get products by tag',
          'GET /products/search' => 'Search products (query params: brand, min_price, max_price, tag)',
          'GET /products/stats' => 'Get price statistics',
          'GET /products/tags' => 'Get all unique tags',
          'GET /benchmark' => 'Benchmark connection pooling',
          'GET /pool-stats' => 'Get pool statistics',
          'GET /load-test' => 'Simulate high load',
          'GET /transaction-test' => 'Test transaction pooling'
        }
      }

    when %r{^/products/brand/(.+)$}
      brand = $1
      jsonb.get_products_by_brand(brand)

    when %r{^/products/cpu/(.+)$}
      cpu = $1
      jsonb.get_products_by_cpu(cpu)

    when %r{^/products/tag/(.+)$}
      tag = $1
      jsonb.get_products_by_tag(tag)

    when '/products/search'
      filters = {}
      filters[:brand] = request.params['brand'] if request.params['brand']
      filters[:min_price] = request.params['min_price'].to_f if request.params['min_price']
      filters[:max_price] = request.params['max_price'].to_f if request.params['max_price']
      filters[:tag] = request.params['tag'] if request.params['tag']
      jsonb.search_products(filters)

    when '/products/stats'
      jsonb.get_price_statistics

    when '/products/tags'
      { tags: jsonb.get_all_tags }

    when '/benchmark'
      iterations = (request.params['iterations'] || 100).to_i
      pooling.benchmark_connections(iterations)

    when '/pool-stats'
      pooling.get_pool_stats

    when '/load-test'
      queries = (request.params['queries'] || 50).to_i
      pooling.simulate_high_load(queries)

    when '/transaction-test'
      pooling.test_transaction_pooling

    else
      { error: 'Not found' }
    end

    [200, { 'Content-Type' => 'application/json' }, [JSON.pretty_generate(response)]]
  rescue => e
    [500, { 'Content-Type' => 'application/json' }, [JSON.pretty_generate({ error: e.message })]]
  end
end

run app
