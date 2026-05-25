# Falcon server configuration for async Ruby
# 
# Run: falcon serve --config config/falcon.rb

require 'async'
require 'falcon'
require_relative '../lib/async_operations'

# Load environment
require 'dotenv'
Dotenv.load

# Configuration
database_url = ENV['PGBOUNCER_URL'] || 'postgresql://pguser:pgpass@pgbouncer:5432/advanced_pg'

# Async application
class AsyncApp
  def initialize
    @async_ops = AsyncPostgresOperations.new(database_url, pool_size: 50)
  end

  def call(env)
    request = Rack::Request.new(env)
    
    Async do
      handle_request(request)
    end.wait
  rescue => e
    [500, { 'Content-Type' => 'application/json' }, [{ error: e.message }.to_json]]
  end

  private

  def handle_request(request)
    path = request.path
    method = request.request_method

    case path
    when '/'
      json_response({
        message: 'Async PostgreSQL API (Falcon)',
        server: 'Falcon',
        features: ['Async I/O', 'High Concurrency', 'Connection Pooling'],
        endpoints: {
          'GET /products/brands?brands=Dell,Apple' => 'Parallel brand queries',
          'GET /aggregations' => 'Parallel aggregations',
          'GET /health' => 'Health check',
          'GET /metrics' => 'Performance metrics'
        }
      })

    when '/products/brands'
      brands = request.params['brands']&.split(',') || ['Dell', 'Apple', 'Sony']
      results = @async_ops.parallel_brand_queries(brands).wait
      json_response(results)

    when '/aggregations'
      results = @async_ops.parallel_aggregations.wait
      json_response(results)

    when '/health'
      json_response({
        status: 'healthy',
        database: 'connected',
        timestamp: Time.now.iso8601
      })

    when '/metrics'
      json_response({
        pool_size: @async_ops.instance_variable_get(:@pool_size),
        active_connections: Thread.list.size,
        timestamp: Time.now.iso8601
      })

    else
      [404, { 'Content-Type' => 'application/json' }, [{ error: 'Not found' }.to_json]]
    end
  end

  def json_response(data)
    [200, { 'Content-Type' => 'application/json' }, [JSON.pretty_generate(data)]]
  end
end

# Falcon configuration
service 'async-postgres-api' do
  include Falcon::Environment::Rack

  # Bind to all interfaces
  endpoint Async::HTTP::Endpoint.parse('http://0.0.0.0:3000')

  # Application
  app AsyncApp.new

  # Concurrency
  count ENV.fetch('FALCON_CONCURRENCY', 4).to_i
end
