require 'active_record'

# ActiveRecord model with JSONB support
class Product < ActiveRecord::Base
  # Validations
  validates :name, presence: true
  validates :metadata, presence: true

  # Scopes for JSONB queries
  scope :by_brand, ->(brand) { where("metadata->>'brand' = ?", brand) }
  scope :price_range, ->(min, max) { where("(metadata->>'price')::numeric BETWEEN ? AND ?", min, max) }
  scope :with_tag, ->(tag) { where("metadata->'tags' @> ?::jsonb", [tag].to_json) }
  scope :with_spec, ->(key, value) { where("metadata->'specs'->>? = ?", key, value) }
  scope :premium, -> { where("(metadata->>'price')::numeric > 1000") }
  scope :on_sale, -> { where("metadata ? 'discount'") }

  # Virtual attributes from JSONB
  def brand
    metadata['brand']
  end

  def brand=(value)
    self.metadata = metadata.merge('brand' => value)
  end

  def price
    metadata['price']&.to_f
  end

  def price=(value)
    self.metadata = metadata.merge('price' => value)
  end

  def tags
    metadata['tags'] || []
  end

  def add_tag(tag)
    current_tags = tags
    current_tags << tag unless current_tags.include?(tag)
    self.metadata = metadata.merge('tags' => current_tags)
  end

  def specs
    metadata['specs'] || {}
  end

  def set_spec(key, value)
    current_specs = specs
    current_specs[key] = value
    self.metadata = metadata.merge('specs' => current_specs)
  end

  def discount
    metadata['discount']
  end

  def add_discount(amount)
    self.metadata = metadata.merge('discount' => amount)
  end

  def remove_discount
    meta = metadata.dup
    meta.delete('discount')
    self.metadata = meta
  end

  # Class methods for complex queries
  def self.search(filters = {})
    relation = all

    relation = relation.by_brand(filters[:brand]) if filters[:brand]
    relation = relation.price_range(filters[:min_price], filters[:max_price]) if filters[:min_price] && filters[:max_price]
    relation = relation.with_tag(filters[:tag]) if filters[:tag]

    relation
  end

  def self.price_statistics
    select(
      "COUNT(*) as total_products",
      "AVG((metadata->>'price')::numeric) as avg_price",
      "MIN((metadata->>'price')::numeric) as min_price",
      "MAX((metadata->>'price')::numeric) as max_price"
    ).first
  end

  def self.count_by_brand
    group("metadata->>'brand'")
      .select("metadata->>'brand' as brand", "COUNT(*) as count")
      .order("count DESC")
  end

  def self.all_tags
    select("DISTINCT jsonb_array_elements_text(metadata->'tags') as tag")
      .order(:tag)
      .pluck(:tag)
  end

  def self.products_by_tag
    from("products, jsonb_array_elements_text(metadata->'tags') as tag")
      .group(:tag)
      .select("tag", "COUNT(*) as product_count")
      .order("product_count DESC")
  end

  # Bulk operations
  def self.add_discount_to_brand(brand, discount)
    where("metadata->>'brand' = ?", brand)
      .update_all("metadata = metadata || '{\"discount\": #{discount}}'::jsonb")
  end

  def self.update_prices_by_percentage(brand, percentage)
    where("metadata->>'brand' = ?", brand)
      .update_all(
        "metadata = jsonb_set(
          metadata, 
          '{price}', 
          ((metadata->>'price')::numeric * #{1 + percentage / 100.0})::text::jsonb
        )"
      )
  end

  def self.mark_premium
    where("(metadata->>'price')::numeric > 1000")
      .update_all("metadata = metadata || '{\"premium\": true}'::jsonb")
  end
end

# Example usage class
class RailsActiveRecordExamples
  def self.basic_queries
    # Find by brand
    dell_products = Product.by_brand('Dell')

    # Price range
    affordable = Product.price_range(200, 500)

    # With tag
    electronics = Product.with_tag('electronics')

    # Chain scopes
    results = Product.by_brand('Apple')
                    .price_range(500, 1000)
                    .with_tag('mobile')

    # Order by price
    expensive_first = Product.order("(metadata->>'price')::numeric DESC")

    {
      dell: dell_products.to_a,
      affordable: affordable.to_a,
      electronics: electronics.to_a,
      filtered: results.to_a,
      expensive: expensive_first.limit(5).to_a
    }
  end

  def self.complex_queries
    # Subquery - products more expensive than brand average
    expensive_by_brand = Product.where(
      "(metadata->>'price')::numeric > (
        SELECT AVG((metadata->>'price')::numeric)
        FROM products p2
        WHERE p2.metadata->>'brand' = products.metadata->>'brand'
      )"
    )

    # Multiple tag matching
    multi_tag = Product.where(
      "metadata->'tags' ?& array['electronics', 'computers']"
    )

    # Products with discount
    on_sale = Product.on_sale

    # Complex search
    search_results = Product.search(
      brand: 'Dell',
      min_price: 500,
      max_price: 1500,
      tag: 'computers'
    )

    {
      expensive_by_brand: expensive_by_brand.to_a,
      multi_tag: multi_tag.to_a,
      on_sale: on_sale.to_a,
      search: search_results.to_a
    }
  end

  def self.aggregations
    # Price statistics
    stats = Product.price_statistics

    # Count by brand
    by_brand = Product.count_by_brand

    # All unique tags
    tags = Product.all_tags

    # Products per tag
    by_tag = Product.products_by_tag

    {
      statistics: stats.attributes,
      by_brand: by_brand.map(&:attributes),
      tags: tags,
      by_tag: by_tag.map(&:attributes)
    }
  end

  def self.create_examples
    # Create with JSONB
    product = Product.create(
      name: 'Gaming Mouse',
      metadata: {
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

    # Create and modify
    keyboard = Product.new(name: 'Mechanical Keyboard')
    keyboard.brand = 'Corsair'
    keyboard.price = 149.99
    keyboard.add_tag('electronics')
    keyboard.add_tag('gaming')
    keyboard.set_spec('type', 'mechanical')
    keyboard.set_spec('rgb', true)
    keyboard.save

    {
      mouse: product,
      keyboard: keyboard
    }
  end

  def self.update_examples
    product = Product.first

    # Update using virtual attributes
    product.price = 899.99
    product.add_discount(10)
    product.add_tag('featured')
    product.save

    # Bulk updates
    Product.add_discount_to_brand('Dell', 15)
    Product.update_prices_by_percentage('Sony', 5)
    Product.mark_premium

    # Update with raw SQL
    Product.where("metadata->>'brand' = ?", 'Apple')
           .update_all(
             "metadata = jsonb_set(
               metadata, 
               '{warranty}', 
               '\"2 years\"'::jsonb
             )"
           )

    { updated: product }
  end

  def self.transaction_examples
    ActiveRecord::Base.transaction do
      # Create product
      product = Product.create!(
        name: 'New Product',
        metadata: {
          brand: 'TestBrand',
          price: 99.99,
          tags: ['test']
        }
      )

      # Update related products
      Product.where("metadata->>'brand' = ?", 'TestBrand')
             .update_all("metadata = metadata || '{\"related_to\": \"#{product.id}\"}'::jsonb")

      # Verify
      count = Product.where("metadata ? 'related_to'").count
      raise ActiveRecord::Rollback if count == 0

      product
    end
  end

  def self.advanced_jsonb_operations
    # Check if key exists
    with_discount = Product.where("metadata ? 'discount'")

    # Check multiple keys
    complete_products = Product.where("metadata ?& array['brand', 'price', 'specs']")

    # Extract nested array elements
    all_spec_keys = Product
      .select("DISTINCT jsonb_object_keys(metadata->'specs') as spec_key")
      .pluck(:spec_key)

    # JSONB path queries (PostgreSQL 12+)
    wireless_products = Product.where(
      "metadata @? '$.specs.wireless ? (@ == true)'"
    )

    # Build complex JSONB from query
    summary = Product
      .select(
        "metadata->>'brand' as brand",
        "jsonb_agg(jsonb_build_object(
          'name', name,
          'price', metadata->'price'
        )) as products"
      )
      .group("metadata->>'brand'")

    {
      with_discount: with_discount.to_a,
      complete: complete_products.to_a,
      spec_keys: all_spec_keys,
      wireless: wireless_products.to_a,
      summary: summary.map(&:attributes)
    }
  end
end
