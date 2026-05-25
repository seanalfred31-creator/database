<?php

namespace App;

use PDO;

class JsonbOperations
{
    private PDO $pdo;

    public function __construct(PDO $pdo)
    {
        $this->pdo = $pdo;
    }

    /**
     * Query JSONB field using -> operator (returns JSON)
     */
    public function getProductsByBrand(string $brand): array
    {
        $stmt = $this->pdo->prepare("
            SELECT id, name, metadata->>'brand' as brand, metadata
            FROM products
            WHERE metadata->>'brand' = :brand
        ");
        $stmt->execute(['brand' => $brand]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    /**
     * Query nested JSONB fields
     */
    public function getProductsByCpu(string $cpu): array
    {
        $stmt = $this->pdo->prepare("
            SELECT id, name, metadata->'specs'->>'cpu' as cpu, metadata
            FROM products
            WHERE metadata->'specs'->>'cpu' = :cpu
        ");
        $stmt->execute(['cpu' => $cpu]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    /**
     * Query JSONB array containment using @> operator
     */
    public function getProductsByTag(string $tag): array
    {
        $stmt = $this->pdo->prepare("
            SELECT id, name, metadata
            FROM products
            WHERE metadata->'tags' @> :tag::jsonb
        ");
        $stmt->execute(['tag' => json_encode([$tag])]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    /**
     * Update JSONB field using jsonb_set
     */
    public function updateProductPrice(string $id, float $newPrice): bool
    {
        $stmt = $this->pdo->prepare("
            UPDATE products
            SET metadata = jsonb_set(metadata, '{price}', :price::jsonb)
            WHERE id = :id
        ");
        return $stmt->execute([
            'id' => $id,
            'price' => json_encode($newPrice)
        ]);
    }

    /**
     * Add new key to JSONB
     */
    public function addProductDiscount(string $id, float $discount): bool
    {
        $stmt = $this->pdo->prepare("
            UPDATE products
            SET metadata = metadata || :discount::jsonb
            WHERE id = :id
        ");
        return $stmt->execute([
            'id' => $id,
            'discount' => json_encode(['discount' => $discount])
        ]);
    }

    /**
     * Remove key from JSONB
     */
    public function removeProductDiscount(string $id): bool
    {
        $stmt = $this->pdo->prepare("
            UPDATE products
            SET metadata = metadata - 'discount'
            WHERE id = :id
        ");
        return $stmt->execute(['id' => $id]);
    }

    /**
     * Complex JSONB query with multiple conditions
     */
    public function searchProducts(array $filters): array
    {
        $conditions = [];
        $params = [];

        if (isset($filters['brand'])) {
            $conditions[] = "metadata->>'brand' = :brand";
            $params['brand'] = $filters['brand'];
        }

        if (isset($filters['min_price'])) {
            $conditions[] = "(metadata->>'price')::numeric >= :min_price";
            $params['min_price'] = $filters['min_price'];
        }

        if (isset($filters['max_price'])) {
            $conditions[] = "(metadata->>'price')::numeric <= :max_price";
            $params['max_price'] = $filters['max_price'];
        }

        if (isset($filters['tag'])) {
            $conditions[] = "metadata->'tags' @> :tag::jsonb";
            $params['tag'] = json_encode([$filters['tag']]);
        }

        $where = !empty($conditions) ? 'WHERE ' . implode(' AND ', $conditions) : '';
        
        $stmt = $this->pdo->prepare("
            SELECT id, name, metadata
            FROM products
            {$where}
            ORDER BY (metadata->>'price')::numeric
        ");
        $stmt->execute($params);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
}
