<?php

namespace App;

use Doctrine\ORM\Mapping as ORM;
use Doctrine\DBAL\Types\Types;

/**
 * Doctrine entity with JSONB support
 * 
 * @ORM\Entity
 * @ORM\Table(name="products", indexes={
 *     @ORM\Index(name="idx_products_metadata", columns={"metadata"}, options={"using": "gin"})
 * })
 */
#[ORM\Entity]
#[ORM\Table(name: 'products')]
class ProductEntity
{
    #[ORM\Id]
    #[ORM\Column(type: Types::GUID)]
    #[ORM\GeneratedValue(strategy: 'NONE')]
    private string $id;

    #[ORM\Column(type: Types::STRING, length: 255)]
    private string $name;

    #[ORM\Column(type: Types::JSON)]
    private array $metadata;

    #[ORM\Column(type: Types::DATETIME_IMMUTABLE)]
    private \DateTimeImmutable $createdAt;

    public function __construct(string $name, array $metadata)
    {
        $this->id = \Ramsey\Uuid\Uuid::uuid4()->toString();
        $this->name = $name;
        $this->metadata = $metadata;
        $this->createdAt = new \DateTimeImmutable();
    }

    public function getId(): string
    {
        return $this->id;
    }

    public function getName(): string
    {
        return $this->name;
    }

    public function setName(string $name): self
    {
        $this->name = $name;
        return $this;
    }

    public function getMetadata(): array
    {
        return $this->metadata;
    }

    public function setMetadata(array $metadata): self
    {
        $this->metadata = $metadata;
        return $this;
    }

    public function getBrand(): ?string
    {
        return $this->metadata['brand'] ?? null;
    }

    public function getPrice(): ?float
    {
        return $this->metadata['price'] ?? null;
    }

    public function setPrice(float $price): self
    {
        $this->metadata['price'] = $price;
        return $this;
    }

    public function getTags(): array
    {
        return $this->metadata['tags'] ?? [];
    }

    public function addTag(string $tag): self
    {
        if (!in_array($tag, $this->getTags())) {
            $this->metadata['tags'][] = $tag;
        }
        return $this;
    }

    public function getSpecs(): array
    {
        return $this->metadata['specs'] ?? [];
    }

    public function setSpec(string $key, mixed $value): self
    {
        if (!isset($this->metadata['specs'])) {
            $this->metadata['specs'] = [];
        }
        $this->metadata['specs'][$key] = $value;
        return $this;
    }
}

/**
 * Doctrine repository with JSONB queries
 */
class ProductRepository
{
    private $entityManager;

    public function __construct($entityManager)
    {
        $this->entityManager = $entityManager;
    }

    /**
     * Find products by brand using DQL
     */
    public function findByBrand(string $brand): array
    {
        $dql = "SELECT p FROM App\ProductEntity p 
                WHERE JSON_GET_TEXT(p.metadata, 'brand') = :brand";
        
        return $this->entityManager
            ->createQuery($dql)
            ->setParameter('brand', $brand)
            ->getResult();
    }

    /**
     * Find products by price range using native SQL
     */
    public function findByPriceRange(float $min, float $max): array
    {
        $sql = "SELECT * FROM products 
                WHERE (metadata->>'price')::numeric BETWEEN :min AND :max";
        
        $conn = $this->entityManager->getConnection();
        $stmt = $conn->prepare($sql);
        $result = $stmt->executeQuery(['min' => $min, 'max' => $max]);
        
        return $result->fetchAllAssociative();
    }

    /**
     * Find products with specific tag
     */
    public function findByTag(string $tag): array
    {
        $sql = "SELECT * FROM products 
                WHERE metadata->'tags' @> :tag::jsonb";
        
        $conn = $this->entityManager->getConnection();
        $stmt = $conn->prepare($sql);
        $result = $stmt->executeQuery(['tag' => json_encode([$tag])]);
        
        return $result->fetchAllAssociative();
    }

    /**
     * Complex search with multiple filters
     */
    public function search(array $filters): array
    {
        $qb = $this->entityManager->createQueryBuilder();
        $qb->select('p')->from(ProductEntity::class, 'p');

        if (isset($filters['brand'])) {
            $qb->andWhere("JSON_GET_TEXT(p.metadata, 'brand') = :brand")
               ->setParameter('brand', $filters['brand']);
        }

        if (isset($filters['min_price'])) {
            $qb->andWhere("CAST(JSON_GET_TEXT(p.metadata, 'price') AS DECIMAL) >= :min_price")
               ->setParameter('min_price', $filters['min_price']);
        }

        if (isset($filters['max_price'])) {
            $qb->andWhere("CAST(JSON_GET_TEXT(p.metadata, 'price') AS DECIMAL) <= :max_price")
               ->setParameter('max_price', $filters['max_price']);
        }

        return $qb->getQuery()->getResult();
    }

    /**
     * Get price statistics
     */
    public function getPriceStatistics(): array
    {
        $sql = "SELECT 
                    COUNT(*) as total_products,
                    AVG((metadata->>'price')::numeric) as avg_price,
                    MIN((metadata->>'price')::numeric) as min_price,
                    MAX((metadata->>'price')::numeric) as max_price
                FROM products";
        
        $conn = $this->entityManager->getConnection();
        return $conn->executeQuery($sql)->fetchAssociative();
    }

    /**
     * Update product price using JSONB operations
     */
    public function updatePrice(string $id, float $newPrice): void
    {
        $sql = "UPDATE products 
                SET metadata = jsonb_set(metadata, '{price}', :price::jsonb)
                WHERE id = :id";
        
        $conn = $this->entityManager->getConnection();
        $conn->executeStatement($sql, [
            'id' => $id,
            'price' => json_encode($newPrice)
        ]);
    }

    /**
     * Bulk update - add discount to products
     */
    public function addDiscountToBrand(string $brand, float $discount): int
    {
        $sql = "UPDATE products 
                SET metadata = metadata || :discount::jsonb
                WHERE metadata->>'brand' = :brand";
        
        $conn = $this->entityManager->getConnection();
        return $conn->executeStatement($sql, [
            'brand' => $brand,
            'discount' => json_encode(['discount' => $discount])
        ]);
    }

    /**
     * Get all unique tags
     */
    public function getAllTags(): array
    {
        $sql = "SELECT DISTINCT jsonb_array_elements_text(metadata->'tags') as tag
                FROM products
                ORDER BY tag";
        
        $conn = $this->entityManager->getConnection();
        $result = $conn->executeQuery($sql);
        
        return array_column($result->fetchAllAssociative(), 'tag');
    }

    /**
     * Count products per brand
     */
    public function countByBrand(): array
    {
        $sql = "SELECT 
                    metadata->>'brand' as brand,
                    COUNT(*) as product_count
                FROM products
                GROUP BY metadata->>'brand'
                ORDER BY product_count DESC";
        
        $conn = $this->entityManager->getConnection();
        return $conn->executeQuery($sql)->fetchAllAssociative();
    }
}

/**
 * Example usage
 */
class DoctrineExamples
{
    private $entityManager;
    private $repository;

    public function __construct($entityManager)
    {
        $this->entityManager = $entityManager;
        $this->repository = new ProductRepository($entityManager);
    }

    /**
     * Create product with Doctrine
     */
    public function createProduct(): ProductEntity
    {
        $product = new ProductEntity('Gaming Laptop', [
            'brand' => 'ASUS',
            'specs' => [
                'cpu' => 'AMD Ryzen 9',
                'gpu' => 'RTX 4080',
                'ram' => '32GB',
                'storage' => '2TB SSD'
            ],
            'price' => 2499.99,
            'tags' => ['electronics', 'computers', 'gaming']
        ]);

        $this->entityManager->persist($product);
        $this->entityManager->flush();

        return $product;
    }

    /**
     * Update product metadata
     */
    public function updateProduct(string $id): void
    {
        $product = $this->entityManager->find(ProductEntity::class, $id);
        
        if ($product) {
            $product->setPrice(2299.99);
            $product->setSpec('warranty', '3 years');
            $product->addTag('premium');
            
            $this->entityManager->flush();
        }
    }

    /**
     * Query examples
     */
    public function queryExamples(): array
    {
        // Find by brand
        $asusProducts = $this->repository->findByBrand('ASUS');

        // Price range
        $midRange = $this->repository->findByPriceRange(500, 1500);

        // By tag
        $gaming = $this->repository->findByTag('gaming');

        // Complex search
        $results = $this->repository->search([
            'brand' => 'Dell',
            'min_price' => 800,
            'max_price' => 1200
        ]);

        // Statistics
        $stats = $this->repository->getPriceStatistics();

        return [
            'asus_products' => $asusProducts,
            'mid_range' => $midRange,
            'gaming' => $gaming,
            'search_results' => $results,
            'statistics' => $stats
        ];
    }
}
