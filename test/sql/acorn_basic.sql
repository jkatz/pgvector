-- Test basic ACORN-1 functionality with INCLUDE columns

-- Create test table
CREATE TABLE acorn_test_items (
    id serial PRIMARY KEY,
    embedding vector(3),
    category text,
    price integer
);

-- Insert test data
INSERT INTO acorn_test_items (embedding, category, price) VALUES
    ('[1,2,3]', 'electronics', 100),
    ('[2,3,4]', 'books', 20),
    ('[3,4,5]', 'electronics', 150),
    ('[4,5,6]', 'books', 30),
    ('[5,6,7]', 'electronics', 200),
    ('[6,7,8]', 'clothing', 50),
    ('[1,1,1]', 'electronics', 90),
    ('[2,2,2]', 'books', 25),
    ('[3,3,3]', 'electronics', 140),
    ('[4,4,4]', 'clothing', 60);

-- Create HNSW index with INCLUDE columns
CREATE INDEX ON acorn_test_items USING hnsw (embedding vector_l2_ops) INCLUDE (category, price);

-- Test 1: Single equality predicate on category
SELECT id, category, price
FROM acorn_test_items
WHERE category = 'electronics'
ORDER BY embedding <-> '[2,2,2]'
LIMIT 3;

-- Test 2: Multiple predicates (category AND price)
SELECT id, category, price
FROM acorn_test_items
WHERE category = 'electronics' AND price < 175
ORDER BY embedding <-> '[4,4,4]'
LIMIT 2;

-- Test 3: Predicate with no matches
SELECT id
FROM acorn_test_items
WHERE category = 'furniture'
ORDER BY embedding <-> '[1,1,1]'
LIMIT 5;

-- Test 4: No predicates (should work like regular HNSW)
SELECT id
FROM acorn_test_items
ORDER BY embedding <-> '[5,5,5]'
LIMIT 3;

-- Test 5: Predicate on INCLUDE column (price)
SELECT id, category, price
FROM acorn_test_items
WHERE price > 100
ORDER BY embedding <-> '[3,3,3]'
LIMIT 3;

-- Test 6: Different category
SELECT id, category
FROM acorn_test_items
WHERE category = 'books'
ORDER BY embedding <-> '[3,3,3]'
LIMIT 2;

-- Clean up
DROP TABLE acorn_test_items;
