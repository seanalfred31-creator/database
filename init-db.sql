-- Initialize database with JSONB examples

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Sample table with JSONB column
CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    metadata JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- GIN index for JSONB queries
CREATE INDEX idx_products_metadata ON products USING GIN (metadata);

-- Sample data
INSERT INTO products (name, metadata) VALUES
    ('Laptop', '{"brand": "Dell", "specs": {"cpu": "i7", "ram": "16GB", "storage": "512GB SSD"}, "price": 999.99, "tags": ["electronics", "computers"]}'),
    ('Phone', '{"brand": "Apple", "specs": {"model": "iPhone 14", "storage": "256GB"}, "price": 899.99, "tags": ["electronics", "mobile"]}'),
    ('Headphones', '{"brand": "Sony", "specs": {"type": "wireless", "battery": "30h"}, "price": 299.99, "tags": ["electronics", "audio"]}');

-- Table for connection pooling examples
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id INTEGER NOT NULL,
    data JSONB NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sessions_user_id ON sessions(user_id);
CREATE INDEX idx_sessions_expires_at ON sessions(expires_at);
