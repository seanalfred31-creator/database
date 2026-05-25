# Exercise 4: Real-World Scenarios

Apply JSONB and connection pooling to practical use cases.

## Scenario 1: E-commerce Product Catalog

Build a flexible product catalog that handles varying attributes.

### Requirements
- Products have different attributes based on category
- Support filtering by any attribute
- Track price history
- Handle product variants

### Schema Design

```sql
CREATE TABLE products (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sku VARCHAR(50) UNIQUE NOT NULL,
  name VARCHAR(255) NOT NULL,
  category VARCHAR(100) NOT NULL,
  attributes JSONB NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_products_attributes ON products USING GIN (attributes);
CREATE INDEX idx_products_price ON products (((attributes->>'price')::numeric));
```

### Sample Data

```sql
-- Electronics
INSERT INTO products (sku, name, category, attributes) VALUES
('LAPTOP-001', 'Gaming Laptop', 'electronics', '{
  "brand": "ASUS",
  "price": 1499.99,
  "specs": {
    "cpu": "Intel i7",
    "ram": "16GB",
    "storage": "512GB SSD",
    "gpu": "RTX 3060"
  },
  "warranty": "2 years",
  "in_stock": true,
  "variants": [
    {"ram": "16GB", "price": 1499.99},
    {"ram": "32GB", "price": 1799.99}
  ]
}');

-- Clothing
INSERT INTO products (sku, name, category, attributes) VALUES
('SHIRT-001', 'Cotton T-Shirt', 'clothing', '{
  "brand": "Nike",
  "price": 29.99,
  "sizes": ["S", "M", "L", "XL"],
  "colors": ["black", "white", "blue"],
  "material": "100% cotton",
  "care": "Machine wash cold",
  "in_stock": true
}');
```

### Tasks

1. **Find all products in a price range**
```sql
SELECT * FROM products 
WHERE (attributes->>'price')::numeric BETWEEN 50 AND 500;
```

2. **Search by brand across categories**
```sql
SELECT category, name, attributes->>'brand' as brand, attributes->>'price' as price
FROM products
WHERE attributes->>'brand' = 'Nike'
ORDER BY category;
```

3. **Find products with specific specs**
```sql
SELECT * FROM products
WHERE attributes->'specs'->>'cpu' LIKE '%i7%';
```

4. **Update prices by category**
```sql
UPDATE products
SET attributes = jsonb_set(
  attributes,
  '{price}',
  ((attributes->>'price')::numeric * 1.1)::text::jsonb
)
WHERE category = 'electronics';
```

5. **Add sale price to all products**
```sql
UPDATE products
SET attributes = attributes || jsonb_build_object(
  'sale_price',
  ((attributes->>'price')::numeric * 0.9)::numeric(10,2)
);
```

## Scenario 2: User Session Management

Implement flexible session storage with connection pooling.

### Requirements
- Store arbitrary session data
- Fast session lookup
- Automatic expiration
- Handle high concurrency

### Schema Design

```sql
CREATE TABLE sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_key VARCHAR(255) UNIQUE NOT NULL,
  user_id INTEGER,
  data JSONB NOT NULL DEFAULT '{}',
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sessions_key ON sessions(session_key);
CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_expires ON sessions(expires_at);
CREATE INDEX idx_sessions_data ON sessions USING GIN (data);
```

### Tasks

1. **Create session with data**
```sql
INSERT INTO sessions (session_key, user_id, data, expires_at)
VALUES (
  'sess_' || gen_random_uuid(),
  123,
  '{
    "cart": [
      {"product_id": "prod-1", "quantity": 2},
      {"product_id": "prod-2", "quantity": 1}
    ],
    "preferences": {
      "theme": "dark",
      "language": "en"
    },
    "last_page": "/products/laptop"
  }',
  NOW() + INTERVAL '1 hour'
);
```

2. **Update cart in session**
```sql
UPDATE sessions
SET data = jsonb_set(
  data,
  '{cart}',
  data->'cart' || '[{"product_id": "prod-3", "quantity": 1}]'::jsonb
),
updated_at = NOW()
WHERE session_key = 'sess_xxx';
```

3. **Clean expired sessions**
```sql
DELETE FROM sessions WHERE expires_at < NOW();
```

4. **Get active sessions per user**
```sql
SELECT 
  user_id,
  COUNT(*) as session_count,
  MAX(updated_at) as last_activity
FROM sessions
WHERE expires_at > NOW()
GROUP BY user_id
HAVING COUNT(*) > 1;
```

### Connection Pooling Strategy

```php
// PHP implementation
class SessionManager {
    private $pooledConnection;
    
    public function get($sessionKey) {
        $stmt = $this->pooledConnection->prepare("
            SELECT data FROM sessions 
            WHERE session_key = :key 
            AND expires_at > NOW()
        ");
        $stmt->execute(['key' => $sessionKey]);
        return $stmt->fetch();
    }
    
    public function set($sessionKey, $data, $ttl = 3600) {
        $stmt = $this->pooledConnection->prepare("
            INSERT INTO sessions (session_key, data, expires_at)
            VALUES (:key, :data::jsonb, NOW() + INTERVAL ':ttl seconds')
            ON CONFLICT (session_key) 
            DO UPDATE SET data = :data::jsonb, updated_at = NOW()
        ");
        $stmt->execute([
            'key' => $sessionKey,
            'data' => json_encode($data),
            'ttl' => $ttl
        ]);
    }
}
```

## Scenario 3: Analytics Event Tracking

Store and query flexible event data.

### Schema Design

```sql
CREATE TABLE events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_type VARCHAR(100) NOT NULL,
  user_id INTEGER,
  properties JSONB NOT NULL DEFAULT '{}',
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_events_type ON events(event_type);
CREATE INDEX idx_events_user ON events(user_id);
CREATE INDEX idx_events_timestamp ON events(timestamp);
CREATE INDEX idx_events_properties ON events USING GIN (properties);

-- Partition by month for better performance
CREATE TABLE events_2024_03 PARTITION OF events
FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
```

### Tasks

1. **Track page view**
```sql
INSERT INTO events (event_type, user_id, properties)
VALUES (
  'page_view',
  123,
  '{
    "page": "/products/laptop",
    "referrer": "https://google.com",
    "device": "desktop",
    "browser": "Chrome"
  }'
);
```

2. **Track purchase**
```sql
INSERT INTO events (event_type, user_id, properties)
VALUES (
  'purchase',
  123,
  '{
    "order_id": "ORD-12345",
    "total": 1499.99,
    "items": [
      {"product_id": "LAPTOP-001", "quantity": 1, "price": 1499.99}
    ],
    "payment_method": "credit_card"
  }'
);
```

3. **Analyze conversion funnel**
```sql
WITH funnel AS (
  SELECT 
    user_id,
    MAX(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END) as viewed,
    MAX(CASE WHEN event_type = 'add_to_cart' THEN 1 ELSE 0 END) as added_to_cart,
    MAX(CASE WHEN event_type = 'checkout' THEN 1 ELSE 0 END) as checked_out,
    MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) as purchased
  FROM events
  WHERE timestamp >= NOW() - INTERVAL '7 days'
  GROUP BY user_id
)
SELECT 
  SUM(viewed) as total_views,
  SUM(added_to_cart) as added_to_cart,
  SUM(checked_out) as checked_out,
  SUM(purchased) as purchased,
  ROUND(SUM(added_to_cart)::numeric / SUM(viewed) * 100, 2) as cart_rate,
  ROUND(SUM(purchased)::numeric / SUM(viewed) * 100, 2) as conversion_rate
FROM funnel;
```

4. **Top products by revenue**
```sql
SELECT 
  item->>'product_id' as product_id,
  COUNT(*) as purchase_count,
  SUM((item->>'price')::numeric * (item->>'quantity')::integer) as total_revenue
FROM events,
  jsonb_array_elements(properties->'items') as item
WHERE event_type = 'purchase'
  AND timestamp >= NOW() - INTERVAL '30 days'
GROUP BY item->>'product_id'
ORDER BY total_revenue DESC
LIMIT 10;
```

## Scenario 4: Multi-tenant SaaS Configuration

Store per-tenant settings and features.

### Schema Design

```sql
CREATE TABLE tenants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(100) UNIQUE NOT NULL,
  config JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_tenants_config ON tenants USING GIN (config);
```

### Sample Data

```sql
INSERT INTO tenants (name, slug, config) VALUES
('Acme Corp', 'acme', '{
  "plan": "enterprise",
  "features": {
    "api_access": true,
    "custom_domain": true,
    "sso": true,
    "max_users": 100
  },
  "limits": {
    "api_calls_per_day": 100000,
    "storage_gb": 1000
  },
  "branding": {
    "logo_url": "https://cdn.example.com/acme-logo.png",
    "primary_color": "#0066cc",
    "custom_domain": "app.acme.com"
  },
  "integrations": {
    "slack": {"enabled": true, "webhook": "https://..."},
    "stripe": {"enabled": true, "api_key": "sk_..."}
  }
}');
```

### Tasks

1. **Check feature availability**
```sql
SELECT name, config->'features'->>'api_access' as has_api
FROM tenants
WHERE config->'features'->>'api_access' = 'true';
```

2. **Update plan limits**
```sql
UPDATE tenants
SET config = jsonb_set(
  config,
  '{limits,api_calls_per_day}',
  '200000'::jsonb
)
WHERE slug = 'acme';
```

3. **Enable feature for all enterprise tenants**
```sql
UPDATE tenants
SET config = jsonb_set(
  config,
  '{features,advanced_analytics}',
  'true'::jsonb,
  true
)
WHERE config->>'plan' = 'enterprise';
```

## Challenge: Build a Complete System

Combine all scenarios into a working application:

1. Product catalog with JSONB attributes
2. Session management with connection pooling
3. Event tracking for analytics
4. Multi-tenant configuration

Requirements:
- Handle 1000+ concurrent users
- Sub-100ms query response times
- Efficient connection pooling
- Proper indexing strategy
- Clean API design

Deliverables:
- Database schema with indexes
- API endpoints (PHP or Ruby)
- Connection pooling configuration
- Performance benchmarks
- Documentation
