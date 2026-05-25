require 'sequel'

class JsonbOperations
  def initialize(db)
    @db = db
  end

  # Query JSONB field using -> operator
  def get_products_by_brand(brand)
    @db[:products]
      .select(Sequel.lit("id, name, metadata->>'brand' as brand, metadata"))
      .where(Sequel.lit("metadata->>'brand' = ?", brand))
      .all
  end

  # Query nested JSONB fields
  def get_products_by_cpu(cpu)
    @db[:products]
      .select(Sequel.lit("id, name, metadata->'specs'->>'cpu' as cpu, metadata"))
      .where(Sequel.lit("metadata->'specs'->>'cpu' = ?", cpu))
      .all
  end

  # Query JSONB array containment using @> operator
  def get_products_by_tag(tag)
    @db[:products]
      .select(:id, :name, :metadata)
      .where(Sequel.lit("metadata->'tags' @> ?::jsonb", [tag].to_json))
      .all
  end

  # Update JSONB field using jsonb_set
  def update_product_price(id, new_price)
    @db[:products]
      .where(id: id)
      .update(Sequel.lit("metadata = jsonb_set(metadata, '{price}', ?::jsonb)", new_price.to_json))
  end

  # Add new key to JSONB using || operator
  def add_product_discount(id, discount)
    @db[:products]
      .where(id: id)
      .update(Sequel.lit("metadata = metadata || ?::jsonb", { discount: discount }.to_json))
  end

  # Remove key from JSONB using - operator
  def remove_product_discount(id)
    @db[:products]
      .where(id: id)
      .update(Sequel.lit("metadata = metadata - 'discount'"))
  end

  # Complex JSONB query with multiple conditions
  def search_products(filters = {})
    dataset = @db[:products].select(:id, :name, :metadata)

    if filters[:brand]
      dataset = dataset.where(Sequel.lit("metadata->>'brand' = ?", filters[:brand]))
    end

    if filters[:min_price]
      dataset = dataset.where(Sequel.lit("(metadata->>'price')::numeric >= ?", filters[:min_price]))
    end

    if filters[:max_price]
      dataset = dataset.where(Sequel.lit("(metadata->>'price')::numeric <= ?", filters[:max_price]))
    end

    if filters[:tag]
      dataset = dataset.where(Sequel.lit("metadata->'tags' @> ?::jsonb", [filters[:tag]].to_json))
    end

    dataset.order(Sequel.lit("(metadata->>'price')::numeric")).all
  end

  # Aggregate JSONB data
  def get_price_statistics
    @db[:products]
      .select(
        Sequel.lit("COUNT(*) as total_products"),
        Sequel.lit("AVG((metadata->>'price')::numeric) as avg_price"),
        Sequel.lit("MIN((metadata->>'price')::numeric) as min_price"),
        Sequel.lit("MAX((metadata->>'price')::numeric) as max_price")
      )
      .first
  end

  # Extract all unique tags
  def get_all_tags
    @db[:products]
      .select(Sequel.lit("DISTINCT jsonb_array_elements_text(metadata->'tags') as tag"))
      .order(:tag)
      .map { |row| row[:tag] }
  end

  # Build JSONB object from scratch
  def create_product(name, brand, specs, price, tags)
    metadata = {
      brand: brand,
      specs: specs,
      price: price,
      tags: tags
    }

    @db[:products].insert(
      name: name,
      metadata: Sequel.pg_jsonb(metadata)
    )
  end
end
