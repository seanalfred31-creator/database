<?php

namespace App;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Casts\AsArrayObject;

/**
 * Laravel Eloquent model with JSONB support
 */
class Product extends Model
{
    protected $table = 'products';
    public $incrementing = false;
    protected $keyType = 'string';
    
    protected $fillable = ['name', 'metadata'];
    
    // Cast JSONB to array
    protected $casts = [
        'metadata' => 'array',
        'id' => 'string'
    ];

    /**
     * Scope: Filter by brand
     */
    public function scopeByBrand($query, string $brand)
    {
        return $query->whereRaw("metadata->>'brand' = ?", [$brand]);
    }

    /**
     * Scope: Filter by price range
     */
    public function scopePriceRange($query, float $min, float $max)
    {
        return $query->whereRaw("(metadata->>'price')::numeric BETWEEN ? AND ?", [$min, $max]);
    }

    /**
     * Scope: Filter by tag
     */
    public function scopeWithTag($query, string $tag)
    {
        return $query->whereRaw("metadata->'tags' @> ?::jsonb", [json_encode([$tag])]);
    }

    /**
     * Scope: Search nested specs
     */
    public function scopeWithSpec($query, string $key, string $value)
    {
        return $query->whereRaw("metadata->'specs'->>? = ?", [$key, $value]);
    }

    /**
     * Accessor: Get brand from metadata
     */
    public function getBrandAttribute()
    {
        return $this->metadata['brand'] ?? null;
    }

    /**
     * Accessor: Get price from metadata
     */
    public function getPriceAttribute()
    {
        return $this->metadata['price'] ?? null;
    }

    /**
     * Accessor: Get tags from metadata
     */
    public function getTagsAttribute()
    {
        return $this->metadata['tags'] ?? [];
    }

    /**
     * Mutator: Update price in metadata
     */
    public function setPrice(float $price)
    {
        $metadata = $this->metadata;
        $metadata['price'] = $price;
        $this->metadata = $metadata;
        return $this;
    }

    /**
     * Add discount to metadata
     */
    public function addDiscount(float $discount)
    {
        $metadata = $this->metadata;
        $metadata['discount'] = $discount;
        $this->metadata = $metadata;
        return $this;
    }

    /**
     * Remove discount from metadata
     */
    public function removeDiscount()
    {
        $metadata = $this->metadata;
        unset($metadata['discount']);
        $this->metadata = $metadata;
        return $this;
    }
}

/**
 * Example usage class
 */
class LaravelEloquentExamples
{
    /**
     * Basic queries
     */
    public function basicQueries()
    {
        // Find by brand
        $dellProducts = Product::byBrand('Dell')->get();

        // Price range
        $affordable = Product::priceRange(200, 500)->get();

        // With specific tag
        $electronics = Product::withTag('electronics')->get();

        // Combine scopes
        $results = Product::byBrand('Apple')
            ->priceRange(500, 1000)
            ->withTag('mobile')
            ->get();

        return $results;
    }

    /**
     * Complex queries with JSONB
     */
    public function complexQueries()
    {
        // Order by price (from JSONB)
        $products = Product::orderByRaw("(metadata->>'price')::numeric DESC")->get();

        // Group by brand
        $byBrand = Product::selectRaw("metadata->>'brand' as brand, COUNT(*) as count")
            ->groupByRaw("metadata->>'brand'")
            ->get();

        // Aggregate prices
        $stats = Product::selectRaw("
            COUNT(*) as total,
            AVG((metadata->>'price')::numeric) as avg_price,
            MIN((metadata->>'price')::numeric) as min_price,
            MAX((metadata->>'price')::numeric) as max_price
        ")->first();

        return $stats;
    }

    /**
     * Update JSONB fields
     */
    public function updateExamples()
    {
        $product = Product::first();

        // Update using model methods
        $product->setPrice(899.99)->save();

        // Add discount
        $product->addDiscount(10)->save();

        // Bulk update with raw SQL
        Product::byBrand('Dell')
            ->update([
                'metadata' => \DB::raw("metadata || '{\"featured\": true}'::jsonb")
            ]);

        // Update nested value
        Product::whereRaw("metadata->>'brand' = ?", ['Sony'])
            ->update([
                'metadata' => \DB::raw("jsonb_set(metadata, '{specs,warranty}', '\"2 years\"'::jsonb)")
            ]);
    }

    /**
     * Advanced JSONB operations
     */
    public function advancedOperations()
    {
        // Search in array
        $withMultipleTags = Product::whereRaw(
            "metadata->'tags' ?& array['electronics', 'computers']"
        )->get();

        // Check if key exists
        $withDiscount = Product::whereRaw("metadata ? 'discount'")->get();

        // Extract array elements
        $allTags = Product::selectRaw("DISTINCT jsonb_array_elements_text(metadata->'tags') as tag")
            ->pluck('tag');

        // Subquery with JSONB
        $expensiveByBrand = Product::whereRaw("
            (metadata->>'price')::numeric > (
                SELECT AVG((metadata->>'price')::numeric)
                FROM products p2
                WHERE p2.metadata->>'brand' = products.metadata->>'brand'
            )
        ")->get();

        return $expensiveByBrand;
    }

    /**
     * Create products with JSONB
     */
    public function createExamples()
    {
        // Create with array (auto-cast to JSONB)
        $product = Product::create([
            'name' => 'Gaming Mouse',
            'metadata' => [
                'brand' => 'Logitech',
                'specs' => [
                    'dpi' => 16000,
                    'buttons' => 11,
                    'wireless' => true
                ],
                'price' => 79.99,
                'tags' => ['electronics', 'gaming', 'peripherals']
            ]
        ]);

        // Bulk insert
        $products = [
            [
                'name' => 'Keyboard',
                'metadata' => [
                    'brand' => 'Corsair',
                    'specs' => ['type' => 'mechanical', 'rgb' => true],
                    'price' => 149.99,
                    'tags' => ['electronics', 'gaming']
                ]
            ],
            [
                'name' => 'Monitor',
                'metadata' => [
                    'brand' => 'LG',
                    'specs' => ['size' => '27"', 'resolution' => '4K'],
                    'price' => 399.99,
                    'tags' => ['electronics', 'display']
                ]
            ]
        ];

        Product::insert($products);

        return $product;
    }
}
