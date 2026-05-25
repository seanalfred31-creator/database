require 'rom'
require 'rom-sql'

# ROM setup for PostgreSQL with JSONB support
module ProductCatalog
  # ROM Relation - defines the data source
  class Products < ROM::Relation[:sql]
    schema(:products, infer: true) do
      attribute :id, ROM::Types::String
      attribute :name, ROM::Types::String
      attribute :metadata, ROM::Types::PG::JSONB
      attribute :created_at, ROM::Types::Time
    end

    # Custom methods for JSONB queries
    def by_brand(brand)
      where(Sequel.lit("metadata->>'brand' = ?", brand))
    end

    def price_range(min, max)
      where(Sequel.lit("(metadata->>'price')::numeric BETWEEN ? AND ?", min, max))
    end

    def with_tag(tag)
      where(Sequel.lit("metadata->'tags' @> ?::jsonb", [tag].to_json))
    end

    def with_spec(key, value)
      where(Sequel.lit("metadata->'specs'->>? = ?", key, value))
    end

    def premium
      where(Sequel.lit("(metadata->>'price')::numeric > 1000"))
    end

    def on_sale
      where(Sequel.lit("metadata ? 'discount'"))
    end

    def ordered_by_price(direction = :asc)
      order(Sequel.lit("(metadata->>'price')::numeric #{direction}"))
    end
  end

  # ROM Repository - business logic layer
  class ProductRepository < ROM::Repository[:products]
    commands :create, :update, :delete

    # Query methods
    def find_by_brand(brand)
      products.by_brand(brand).to_a
    end

    def find_in_price_range(min, max)
      products.price_range(min, max).to_a
    end

    def find_with_tag(tag)
      products.with_tag(tag).to_a
    end

    def find_premium
      products.premium.ordered_by_price(:desc).to_a
    end

    def search(filters = {})
      relation = products

      relation = relation.by_brand(filters[:brand]) if filters[:brand]
      relation = relation.price_range(filters[:min_price], filters[:max_price]) if filters[:min_price] && filters[:max_price]
      relation = relation.with_tag(filters[:tag]) if filters[:tag]

      relation.to_a
    end

    # Aggregations
    def price_statistics
      products
        .select_append {[
          function(:count, :*).as(:total_products),
          function(:avg, Sequel.lit("(metadata->>'price')::numeric")).as(:avg_price),
          function(:min, Sequel.lit("(metadata->>'price')::numeric")).as(:min_price),
          function(:max, Sequel.lit("(metadata->>'price')::numeric")).as(:max_price)
        ]}
        .first
    end

    def count_by_brand
      products
        .select_append(Sequel.lit("metadata->>'brand' as brand"))
        .select_append { function(:count, :*).as(:count) }
        .group(Sequel.lit("metadata->>'brand'"))
        .order(Sequel.desc(:count))
        .to_a
    end

    def all_tags
      products
        .select_append(Sequel.lit("DISTINCT jsonb_array_elements_text(metadata->'tags') as tag"))
        .order(:tag)
        .pluck(:tag)
    end

    # Create with JSONB
    def create_product(name, metadata)
      products.command(:create).call(
        name: name,
        metadata: metadata
      )
    end

    # Update JSONB fields
    def update_price(id, new_price)
      products
        .by_pk(id)
        .command(:update)
        .call(
          metadata: Sequel.lit("jsonb_set(metadata, '{price}', ?::jsonb)", new_price.to_json)
        )
    end

    def add_discount(id, discount)
      products
        .by_pk(id)
        .command(:update)
        .call(
          metadata: Sequel.lit("metadata || ?::jsonb", { discount: discount }.to_json)
        )
    end

    def remove_discount(id)
      products
        .by_pk(id)
        .command(:update)
        .call(
          metadata: Sequel.lit("metadata - 'discount'")
        )
    end

    # Bulk operations
    def add_discount_to_brand(brand, discount)
      products
        .by_brand(brand)
        .command(:update)
        .call(
          metadata: Sequel.lit("metadata || ?::jsonb", { discount: discount }.to_json)
        )
    end

    def mark_premium
      products
        .premium
        .command(:update)
        .call(
          metadata: Sequel.lit("metadata || '{\"premium\": true}'::jsonb")
        )
    end
  end

  # Custom struct for product data
  class Product < ROM::Struct
    def brand
      metadata['brand']
    end

    def price
      metadata['price']&.to_f
    end

    def tags
      metadata['tags'] || []
    end

    def specs
      metadata['specs'] || {}
    end

    def discount
      metadata['discount']
    end

    def premium?
      price && price > 1000
    end

    def on_sale?
      !discount.nil?
    end
  end
end

# ROM Configuration
class ROMConfiguration
  attr_reader :container

  def initialize(database_url)
    @container = ROM.container(:sql, database_url) do |config|
      config.register_relation(ProductCatalog::Products)
      
      # Custom types for JSONB
      config.gateways[:default].use_logger(Logger.new($stdout))
    end
  end

  def product_repo
    @product_repo ||= ProductCatalog::ProductRepository.new(@container)
  end
end

# Example usage
class ROMExamples
  def initialize(database_url)
    @rom = ROMConfiguration.new(database_url)
    @repo = @rom.product_repo
  end

  def basic_queries
    # Find by brand
    dell_products = @repo.find_by_brand('Dell')

    # Price range
    affordable = @repo.find_in_price_range(200, 500)

    # With tag
    electronics = @repo.find_with_tag('electronics')

    # Premium products
    premium = @repo.find_premium

    # Complex search
    results = @repo.search(
      brand: 'Apple',
      min_price: 500,
      max_price: 1000,
      tag: 'mobile'
    )

    {
      dell: dell_products,
      affordable: affordable,
      electronics: electronics,
      premium: premium,
      search: results
    }
  end

  def aggregations
    # Statistics
    stats = @repo.price_statistics

    # Count by brand
    by_brand = @repo.count_by_brand

    # All tags
    tags = @repo.all_tags

    {
      statistics: stats,
      by_brand: by_brand,
      tags: tags
    }
  end

  def create_and_update
    # Create product
    product = @repo.create_product(
      'Gaming Mouse',
      {
        brand: 'Logitech',
        specs: {
          dpi: 16000,
          buttons: 11,
          wireless: true
        },
        price: 79.99,
        tags: ['electronics', 'gaming', 'peripherals']
      }
    )

    # Update price
    @repo.update_price(product.id, 69.99)

    # Add discount
    @repo.add_discount(product.id, 10)

    # Remove discount
    @repo.remove_discount(product.id)

    product
  end

  def bulk_operations
    # Add discount to brand
    @repo.add_discount_to_brand('Dell', 15)

    # Mark premium products
    @repo.mark_premium
  end

  def working_with_structs
    products = @repo.find_by_brand('Apple')

    products.each do |product|
      puts "Product: #{product.name}"
      puts "  Brand: #{product.brand}"
      puts "  Price: $#{product.price}"
      puts "  Tags: #{product.tags.join(', ')}"
      puts "  Premium: #{product.premium? ? 'Yes' : 'No'}"
      puts "  On Sale: #{product.on_sale? ? 'Yes' : 'No'}"
    end
  end
end

# Advanced ROM patterns
module AdvancedROMPatterns
  # Custom mapper for transforming data
  class ProductMapper < ROM::Transformer
    relation :products

    map_array do
      rename_keys brand: :manufacturer
      unwrap :metadata, prefix: true
      accept_keys [:id, :name, :manufacturer, :metadata_price]
    end
  end

  # Changesets for complex updates
  class UpdateProductPrice
    include Dry::Monads[:result]

    def call(repo, product_id, new_price)
      return Failure(:invalid_price) if new_price <= 0

      product = repo.products.by_pk(product_id).one
      return Failure(:not_found) unless product

      repo.update_price(product_id, new_price)
      Success(product)
    rescue => e
      Failure(e.message)
    end
  end

  # Repository with transactions
  class TransactionalProductRepository < ProductCatalog::ProductRepository
    def create_with_related(product_data, related_data)
      products.transaction do
        product = create_product(product_data[:name], product_data[:metadata])
        
        # Create related records
        related_data.each do |related|
          # ... create related records
        end

        product
      end
    end

    def bulk_update_with_validation(updates)
      products.transaction do
        updates.each do |id, data|
          product = products.by_pk(id).one
          raise "Product #{id} not found" unless product
          
          # Validate and update
          update_price(id, data[:price]) if data[:price]
        end
      end
    end
  end
end
