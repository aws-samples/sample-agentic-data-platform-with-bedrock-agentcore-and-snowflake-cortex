-- ============================================================
-- Script 2: Data Setup
-- Creates tables and inserts demo data.
-- Run this script after 1_environment_setup.sql.
-- ============================================================

USE ROLE FRAUD_DETECTION_RL;
USE DATABASE FRAUD_DETECTION_DB;
USE SCHEMA FRAUD_DETECTION_SCHEMA;
USE WAREHOUSE FRAUD_DETECTION_WH;

-- =====================
-- Tables
-- =====================

CREATE OR REPLACE TABLE customers (
    customer_id VARCHAR PRIMARY KEY,
    customer_name VARCHAR NOT NULL,
    email VARCHAR NOT NULL,
    phone VARCHAR NOT NULL,
    account_created_date DATE NOT NULL,
    typical_location VARCHAR NOT NULL,
    average_transaction_amount FLOAT NOT NULL,
    transaction_count INTEGER NOT NULL
);

CREATE OR REPLACE TABLE transactions (
    transaction_id VARCHAR PRIMARY KEY,
    customer_id VARCHAR NOT NULL,
    transaction_date TIMESTAMP_NTZ NOT NULL,
    amount FLOAT NOT NULL,
    merchant_name VARCHAR NOT NULL,
    merchant_category VARCHAR NOT NULL,
    transaction_type VARCHAR NOT NULL,
    ip_address VARCHAR NOT NULL,
    device_id VARCHAR NOT NULL,
    status VARCHAR NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE OR REPLACE TABLE fraud_patterns (
    pattern_id VARCHAR PRIMARY KEY,
    pattern_name VARCHAR NOT NULL,
    pattern_type VARCHAR NOT NULL,
    risk_score INTEGER NOT NULL,
    description VARCHAR NOT NULL
);

CREATE OR REPLACE TABLE merchant_blacklist (
    merchant_name VARCHAR PRIMARY KEY,
    blacklist_date DATE NOT NULL,
    reason VARCHAR NOT NULL,
    fraud_reports INTEGER NOT NULL
);

-- =====================
-- Seed Data
-- =====================

-- Customers (20 customers)
INSERT INTO customers VALUES
    ('C001', 'Martha Rivera', 'martha.rivera@example.com', '+1-555-0101', '2022-01-15', 'New York, US', 150.00, 45),
    ('C002', 'John Stiles', 'john.stiles@example.com', '+44-20-5550102', '2021-06-20', 'London, UK', 200.00, 62),
    ('C003', 'Mateo Jackson', 'mateo.jackson@example.com', '+81-3-5550103', '2023-03-10', 'Tokyo, JP', 500.00, 28),
    ('C004', 'Saanvi Sarkar', 'saanvi.sarkar@example.com', '+33-1-5550104', '2020-11-05', 'Paris, FR', 300.00, 91),
    ('C005', 'Ana Carolina Silva', 'ana.carolina.silva@example.com', '+61-2-5550105', '2022-08-22', 'Sydney, AU', 175.00, 37),
    ('C006', 'Carlos Salazar', 'carlos.salazar@example.com', '+1-555-0106', '2021-03-14', 'Los Angeles, US', 220.00, 55),
    ('C007', 'Wang Xiulan', 'wang.xiulan@example.com', '+82-2-5550107', '2022-05-30', 'Seoul, KR', 180.00, 41),
    ('C008', 'Arnav Desai', 'arnav.desai@example.com', '+49-30-5550108', '2020-09-18', 'Berlin, DE', 350.00, 78),
    ('C009', 'Shirley Rodriguez', 'shirley.rodriguez@example.com', '+81-6-5550109', '2023-01-25', 'Osaka, JP', 275.00, 19),
    ('C010', 'Richard Roe', 'richard.roe@example.com', '+1-555-0110', '2019-12-01', 'Chicago, US', 400.00, 112),
    ('C011', 'Nikhil Jayashankar', 'nikhil.jayashankar@example.com', '+91-22-5550111', '2022-07-08', 'Mumbai, IN', 125.00, 33),
    ('C012', 'Diego Ramirez', 'diego.ramirez@example.com', '+34-91-5550112', '2021-11-19', 'Madrid, ES', 260.00, 58),
    ('C013', 'Zhang Wei', 'zhang.wei@example.com', '+86-21-5550113', '2023-06-02', 'Shanghai, CN', 310.00, 22),
    ('C014', 'Terry Whitlock', 'terry.whitlock@example.com', '+1-555-0114', '2020-04-27', 'Houston, US', 190.00, 87),
    ('C015', 'Sofía Martínez', 'sofia.martinez@example.com', '+39-06-5550115', '2022-10-11', 'Rome, IT', 230.00, 44),
    ('C016', 'Jane Doe', 'jane.doe@example.com', '+33-4-5550116', '2021-08-03', 'Lyon, FR', 280.00, 66),
    ('C017', 'Paulo Santos', 'paulo.santos@example.com', '+353-1-5550117', '2023-02-14', 'Dublin, IE', 160.00, 15),
    ('C018', 'Efua Owusu', 'efua.owusu@example.com', '+55-11-5550118', '2020-06-30', 'Sao Paulo, BR', 340.00, 95),
    ('C019', 'Akua Mansa', 'akua.mansa@example.com', '+82-51-5550119', '2022-12-05', 'Busan, KR', 200.00, 38),
    ('C020', 'Li Juan', 'li.juan@example.com', '+46-8-5550120', '2021-09-22', 'Stockholm, SE', 290.00, 52);

-- Transactions: Normal activity
INSERT INTO transactions VALUES
    -- Alice (C001) - typical New York shopper, avg ~$150
    ('T001', 'C001', '2024-01-15T10:30:00', 120.50, 'AnyCompany Online Retail', 'Electronics', 'online', '203.0.113.10', 'DEV001', 'completed'),
    ('T002', 'C001', '2024-01-18T09:15:00', 45.99, 'Example Organic Grocer', 'Grocery', 'in-store', '203.0.113.10', 'DEV001', 'completed'),
    ('T003', 'C001', '2024-01-22T14:20:00', 89.00, 'AnyCompany Retail', 'Retail', 'in-store', '203.0.113.10', 'DEV001', 'completed'),
    ('T004', 'C001', '2024-02-01T11:00:00', 210.00, 'Example Electronics', 'Electronics', 'online', '203.0.113.10', 'DEV001', 'completed'),
    ('T005', 'C001', '2024-02-10T16:45:00', 32.50, 'AnyCompany Coffee Shop', 'Food & Drink', 'in-store', '203.0.113.10', 'DEV001', 'completed'),
    ('T006', 'C001', '2024-02-14T19:30:00', 175.00, 'Example Casual Dining', 'Restaurant', 'in-store', '203.0.113.10', 'DEV001', 'completed'),

    -- Bob (C002) - London-based, avg ~$200
    ('T007', 'C002', '2024-01-15T11:00:00', 185.00, 'Example Luxury Department Store', 'Retail', 'in-store', '198.51.100.20', 'DEV002', 'completed'),
    ('T008', 'C002', '2024-01-15T18:00:00', 210.00, 'AnyCompany Supermarket', 'Grocery', 'in-store', '198.51.100.20', 'DEV002', 'completed'),
    ('T009', 'C002', '2024-01-20T10:30:00', 65.00, 'AnyCompany Pharmacy', 'Pharmacy', 'in-store', '198.51.100.20', 'DEV002', 'completed'),
    ('T010', 'C002', '2024-01-28T13:15:00', 320.00, 'Example Department Store', 'Retail', 'online', '198.51.100.20', 'DEV002', 'completed'),
    ('T011', 'C002', '2024-02-05T09:00:00', 150.00, 'Example Supermarket', 'Grocery', 'in-store', '198.51.100.20', 'DEV002', 'completed'),
    ('T012', 'C002', '2024-02-12T17:30:00', 88.50, 'AnyCompany Noodle Bar', 'Restaurant', 'in-store', '198.51.100.20', 'DEV002', 'completed'),

    -- Charlie (C003) - Tokyo, higher spender avg ~$500
    ('T013', 'C003', '2024-01-15T14:00:00', 450.00, 'AnyCompany Electronics', 'Electronics', 'online', '203.0.113.50', 'DEV005', 'completed'),
    ('T014', 'C003', '2024-01-19T11:30:00', 380.00, 'AnyCompany Fashion', 'Retail', 'in-store', '203.0.113.50', 'DEV005', 'completed'),
    ('T015', 'C003', '2024-01-25T16:00:00', 620.00, 'Example Camera Store', 'Electronics', 'in-store', '203.0.113.50', 'DEV005', 'completed'),
    ('T016', 'C003', '2024-02-02T10:00:00', 95.00, 'Example Convenience Store', 'Convenience', 'in-store', '203.0.113.50', 'DEV005', 'completed'),
    ('T017', 'C003', '2024-02-08T20:00:00', 550.00, 'Example Gaming Store', 'Electronics', 'online', '203.0.113.50', 'DEV005', 'completed'),

    -- Diana (C004) - Paris, avg ~$300
    ('T018', 'C004', '2024-01-15T16:30:00', 275.00, 'AnyCompany Department Store', 'Retail', 'in-store', '198.51.100.80', 'DEV008', 'completed'),
    ('T019', 'C004', '2024-01-20T12:00:00', 340.00, 'AnyCompany Department Store', 'Retail', 'in-store', '198.51.100.80', 'DEV008', 'completed'),
    ('T020', 'C004', '2024-01-27T09:45:00', 55.00, 'AnyCompany Supermarket', 'Grocery', 'in-store', '198.51.100.80', 'DEV008', 'completed'),
    ('T021', 'C004', '2024-02-03T14:30:00', 420.00, 'Example Department Store', 'Retail', 'in-store', '198.51.100.80', 'DEV008', 'completed'),
    ('T022', 'C004', '2024-02-09T18:15:00', 190.00, 'AnyCompany Electronics', 'Electronics', 'online', '198.51.100.80', 'DEV008', 'completed'),
    ('T023', 'C004', '2024-02-15T11:00:00', 310.00, 'AnyCompany Beauty Store', 'Beauty', 'in-store', '198.51.100.80', 'DEV008', 'completed'),

    -- Eve (C005) - Sydney, avg ~$175
    ('T024', 'C005', '2024-01-16T08:30:00', 125.00, 'AnyCompany Supermarket', 'Grocery', 'in-store', '103.25.40.50', 'DEV010', 'completed'),
    ('T025', 'C005', '2024-01-23T15:00:00', 200.00, 'Example Retail', 'Retail', 'in-store', '103.25.40.50', 'DEV010', 'completed'),
    ('T026', 'C005', '2024-02-01T10:15:00', 160.00, 'AnyCompany Electronics', 'Electronics', 'in-store', '103.25.40.50', 'DEV010', 'completed'),
    ('T027', 'C005', '2024-02-07T13:45:00', 85.00, 'Example Supermarket', 'Grocery', 'in-store', '103.25.40.50', 'DEV010', 'completed'),

    -- Frank (C006) - LA, avg ~$220
    ('T028', 'C006', '2024-01-16T10:00:00', 250.00, 'AnyCompany Electronics', 'Electronics', 'in-store', '203.0.113.60', 'DEV011', 'completed'),
    ('T029', 'C006', '2024-01-21T14:30:00', 180.00, 'Example Supermarket', 'Grocery', 'in-store', '203.0.113.60', 'DEV011', 'completed'),
    ('T030', 'C006', '2024-01-29T09:00:00', 310.00, 'Example Department Store', 'Retail', 'in-store', '203.0.113.60', 'DEV011', 'completed'),
    ('T031', 'C006', '2024-02-04T17:00:00', 75.00, 'Example Burger Chain', 'Restaurant', 'in-store', '203.0.113.60', 'DEV011', 'completed'),
    ('T032', 'C006', '2024-02-11T12:30:00', 195.00, 'AnyCompany Outdoor Retail', 'Sporting Goods', 'online', '203.0.113.60', 'DEV011', 'completed'),

    -- Grace (C007) - Seoul, avg ~$180
    ('T033', 'C007', '2024-01-17T11:00:00', 160.00, 'AnyCompany Department Store', 'Retail', 'in-store', '211.234.100.10', 'DEV012', 'completed'),
    ('T034', 'C007', '2024-01-24T15:30:00', 220.00, 'Example Electronics', 'Electronics', 'in-store', '211.234.100.10', 'DEV012', 'completed'),
    ('T035', 'C007', '2024-02-01T09:45:00', 95.00, 'Example Supermarket', 'Grocery', 'in-store', '211.234.100.10', 'DEV012', 'completed'),
    ('T036', 'C007', '2024-02-08T18:00:00', 140.00, 'Example Beauty Store', 'Beauty', 'in-store', '211.234.100.10', 'DEV012', 'completed'),

    -- Hank (C008) - Berlin, avg ~$350
    ('T037', 'C008', '2024-01-17T10:00:00', 400.00, 'AnyCompany Electronics', 'Electronics', 'in-store', '185.220.100.10', 'DEV013', 'completed'),
    ('T038', 'C008', '2024-01-22T14:00:00', 280.00, 'AnyCompany Online Fashion', 'Retail', 'online', '185.220.100.10', 'DEV013', 'completed'),
    ('T039', 'C008', '2024-01-30T11:30:00', 120.00, 'AnyCompany Discount Grocery', 'Grocery', 'in-store', '185.220.100.10', 'DEV013', 'completed'),
    ('T040', 'C008', '2024-02-06T16:00:00', 510.00, 'Example Department Store', 'Retail', 'in-store', '185.220.100.10', 'DEV013', 'completed'),
    ('T041', 'C008', '2024-02-13T09:30:00', 350.00, 'Example Electronics', 'Electronics', 'in-store', '185.220.100.10', 'DEV013', 'completed'),

    -- Iris (C009) - Osaka, avg ~$275
    ('T042', 'C009', '2024-01-18T13:00:00', 300.00, 'Example Camera Store', 'Electronics', 'in-store', '203.0.113.55', 'DEV014', 'completed'),
    ('T043', 'C009', '2024-01-26T10:30:00', 180.00, 'Example Department Store', 'Retail', 'in-store', '203.0.113.55', 'DEV014', 'completed'),
    ('T044', 'C009', '2024-02-03T15:00:00', 250.00, 'AnyCompany Department Store', 'Retail', 'in-store', '203.0.113.55', 'DEV014', 'completed'),

    -- Jack (C010) - Chicago, avg ~$400
    ('T045', 'C010', '2024-01-16T09:00:00', 380.00, 'AnyCompany Department Store', 'Retail', 'in-store', '203.0.113.70', 'DEV015', 'completed'),
    ('T046', 'C010', '2024-01-20T14:00:00', 450.00, 'Example Wholesale Club', 'Wholesale', 'in-store', '203.0.113.70', 'DEV015', 'completed'),
    ('T047', 'C010', '2024-01-28T11:30:00', 290.00, 'AnyCompany Hardware', 'Home Improvement', 'in-store', '203.0.113.70', 'DEV015', 'completed'),
    ('T048', 'C010', '2024-02-05T16:00:00', 520.00, 'AnyCompany Home Goods', 'Home Furnishing', 'online', '203.0.113.70', 'DEV015', 'completed'),
    ('T049', 'C010', '2024-02-10T10:00:00', 175.00, 'Example Supermarket', 'Grocery', 'in-store', '203.0.113.70', 'DEV015', 'completed'),
    ('T050', 'C010', '2024-02-14T19:00:00', 410.00, 'Example Fine Dining', 'Restaurant', 'in-store', '203.0.113.70', 'DEV015', 'completed'),

    -- Karen (C011) - Mumbai, avg ~$125
    ('T051', 'C011', '2024-01-17T10:30:00', 90.00, 'Example Online Marketplace', 'Electronics', 'online', '49.36.100.10', 'DEV016', 'completed'),
    ('T052', 'C011', '2024-01-25T14:00:00', 150.00, 'Example Electronics', 'Electronics', 'in-store', '49.36.100.10', 'DEV016', 'completed'),
    ('T053', 'C011', '2024-02-02T09:00:00', 60.00, 'AnyCompany Grocery', 'Grocery', 'in-store', '49.36.100.10', 'DEV016', 'completed'),
    ('T054', 'C011', '2024-02-09T16:30:00', 110.00, 'Example Online Fashion', 'Retail', 'online', '49.36.100.10', 'DEV016', 'completed'),

    -- Leo (C012) - Madrid, avg ~$260
    ('T055', 'C012', '2024-01-18T11:00:00', 230.00, 'AnyCompany Department Store', 'Retail', 'in-store', '88.26.100.10', 'DEV017', 'completed'),
    ('T056', 'C012', '2024-01-26T15:30:00', 310.00, 'Example Fashion', 'Retail', 'in-store', '88.26.100.10', 'DEV017', 'completed'),
    ('T057', 'C012', '2024-02-04T10:00:00', 85.00, 'Example Supermarket', 'Grocery', 'in-store', '88.26.100.10', 'DEV017', 'completed'),
    ('T058', 'C012', '2024-02-11T18:00:00', 275.00, 'Example Fashion', 'Retail', 'online', '88.26.100.10', 'DEV017', 'completed'),

    -- Mia (C013) - Shanghai, avg ~$310
    ('T059', 'C013', '2024-01-19T10:00:00', 280.00, 'AnyCompany Electronics', 'Electronics', 'online', '116.228.100.10', 'DEV018', 'completed'),
    ('T060', 'C013', '2024-01-27T14:30:00', 350.00, 'AnyCompany Online Marketplace', 'Retail', 'online', '116.228.100.10', 'DEV018', 'completed'),
    ('T061', 'C013', '2024-02-05T11:00:00', 190.00, 'AnyCompany Fresh Market', 'Grocery', 'in-store', '116.228.100.10', 'DEV018', 'completed'),

    -- Noah (C014) - Houston, avg ~$190
    ('T062', 'C014', '2024-01-16T12:00:00', 165.00, 'AnyCompany Retail', 'Retail', 'in-store', '203.0.113.80', 'DEV019', 'completed'),
    ('T063', 'C014', '2024-01-23T09:30:00', 220.00, 'Example Sporting Goods', 'Sporting Goods', 'in-store', '203.0.113.80', 'DEV019', 'completed'),
    ('T064', 'C014', '2024-01-31T15:00:00', 140.00, 'Example Supermarket', 'Grocery', 'in-store', '203.0.113.80', 'DEV019', 'completed'),
    ('T065', 'C014', '2024-02-07T11:00:00', 195.00, 'Example Hardware', 'Home Improvement', 'in-store', '203.0.113.80', 'DEV019', 'completed'),
    ('T066', 'C014', '2024-02-13T17:30:00', 250.00, 'Example Casual Dining', 'Restaurant', 'in-store', '203.0.113.80', 'DEV019', 'completed'),

    -- Olivia (C015) - Rome, avg ~$230
    ('T067', 'C015', '2024-01-19T10:30:00', 200.00, 'AnyCompany Department Store', 'Retail', 'in-store', '151.38.100.10', 'DEV020', 'completed'),
    ('T068', 'C015', '2024-01-27T14:00:00', 260.00, 'AnyCompany Luxury Outlet', 'Luxury', 'in-store', '151.38.100.10', 'DEV020', 'completed'),
    ('T069', 'C015', '2024-02-04T09:00:00', 75.00, 'AnyCompany Supermarket', 'Grocery', 'in-store', '151.38.100.10', 'DEV020', 'completed'),
    ('T070', 'C015', '2024-02-12T16:00:00', 310.00, 'AnyCompany Cosmetics', 'Retail', 'in-store', '151.38.100.10', 'DEV020', 'completed');

-- Transactions: More normal activity for remaining customers
INSERT INTO transactions VALUES
    -- Paul (C016) - Lyon, avg ~$280
    ('T071', 'C016', '2024-01-18T10:00:00', 250.00, 'AnyCompany Supermarket', 'Grocery', 'in-store', '198.51.100.90', 'DEV021', 'completed'),
    ('T072', 'C016', '2024-01-25T14:30:00', 320.00, 'Example Sporting Goods', 'Sporting Goods', 'in-store', '198.51.100.90', 'DEV021', 'completed'),
    ('T073', 'C016', '2024-02-02T11:00:00', 180.00, 'Example Electronics', 'Electronics', 'in-store', '198.51.100.90', 'DEV021', 'completed'),
    ('T074', 'C016', '2024-02-10T17:00:00', 290.00, 'Example Hardware', 'Home Improvement', 'in-store', '198.51.100.90', 'DEV021', 'completed'),

    -- Quinn (C017) - Dublin, avg ~$160
    ('T075', 'C017', '2024-01-20T09:30:00', 130.00, 'AnyCompany Department Store', 'Retail', 'in-store', '87.32.100.10', 'DEV022', 'completed'),
    ('T076', 'C017', '2024-01-28T13:00:00', 180.00, 'Example Department Store EU', 'Retail', 'in-store', '87.32.100.10', 'DEV022', 'completed'),
    ('T077', 'C017', '2024-02-06T10:00:00', 55.00, 'AnyCompany Supermarket', 'Grocery', 'in-store', '87.32.100.10', 'DEV022', 'completed'),

    -- Rita (C018) - Sao Paulo, avg ~$340
    ('T078', 'C018', '2024-01-17T11:30:00', 300.00, 'Example Online Retail', 'Electronics', 'in-store', '177.70.100.10', 'DEV023', 'completed'),
    ('T079', 'C018', '2024-01-24T15:00:00', 400.00, 'AnyCompany Fashion', 'Retail', 'in-store', '177.70.100.10', 'DEV023', 'completed'),
    ('T080', 'C018', '2024-02-01T09:00:00', 150.00, 'AnyCompany Supermarket', 'Grocery', 'in-store', '177.70.100.10', 'DEV023', 'completed'),
    ('T081', 'C018', '2024-02-08T14:00:00', 380.00, 'AnyCompany Home Appliances', 'Electronics', 'in-store', '177.70.100.10', 'DEV023', 'completed'),
    ('T082', 'C018', '2024-02-15T18:30:00', 270.00, 'AnyCompany Steakhouse', 'Restaurant', 'in-store', '177.70.100.10', 'DEV023', 'completed'),

    -- Sam (C019) - Busan, avg ~$200
    ('T083', 'C019', '2024-01-19T10:00:00', 170.00, 'Example Department Store', 'Retail', 'in-store', '211.234.100.20', 'DEV024', 'completed'),
    ('T084', 'C019', '2024-01-27T14:30:00', 240.00, 'Example Online Marketplace', 'Electronics', 'online', '211.234.100.20', 'DEV024', 'completed'),
    ('T085', 'C019', '2024-02-05T11:00:00', 80.00, 'AnyCompany Convenience Store', 'Convenience', 'in-store', '211.234.100.20', 'DEV024', 'completed'),
    ('T086', 'C019', '2024-02-12T16:00:00', 210.00, 'Example Department Store', 'Retail', 'in-store', '211.234.100.20', 'DEV024', 'completed'),

    -- Tina (C020) - Stockholm, avg ~$290
    ('T087', 'C020', '2024-01-18T09:00:00', 260.00, 'AnyCompany Fashion', 'Retail', 'in-store', '83.233.100.10', 'DEV025', 'completed'),
    ('T088', 'C020', '2024-01-26T13:30:00', 340.00, 'AnyCompany Home Furnishings', 'Home Furnishing', 'in-store', '83.233.100.10', 'DEV025', 'completed'),
    ('T089', 'C020', '2024-02-03T10:00:00', 110.00, 'AnyCompany Supermarket', 'Grocery', 'in-store', '83.233.100.10', 'DEV025', 'completed'),
    ('T090', 'C020', '2024-02-11T15:00:00', 300.00, 'Example Department Store', 'Retail', 'in-store', '83.233.100.10', 'DEV025', 'completed');

-- =====================
-- Suspicious / Fraudulent Transactions
-- =====================

-- Alice (C001): Unusually large purchase + different IP (geographic mismatch)
INSERT INTO transactions VALUES
    ('T101', 'C001', '2024-01-15T12:00:00', 2500.00, 'Example Luxury Watches', 'Jewelry', 'online', '203.0.113.30', 'DEV001', 'completed'),
    ('T102', 'C001', '2024-01-15T13:00:00', 175.00, 'Example Electronics', 'Electronics', 'online', '41.190.2.22', 'DEV003', 'completed'),
    ('T103', 'C001', '2024-02-20T03:15:00', 3200.00, 'AnyCompany Luxury Jewelry', 'Jewelry', 'online', '41.190.2.22', 'DEV003', 'completed'),
    ('T104', 'C001', '2024-02-20T03:18:00', 1800.00, 'AnyCompany Financial Services', 'Jewelry', 'online', '41.190.2.22', 'DEV003', 'completed'),

-- Bob (C002): Blacklisted merchant + large amount
    ('T105', 'C002', '2024-01-15T14:30:00', 500.00, 'AnyCompany Fraudulent Lending Services', 'Financial Services', 'online', '198.51.100.60', 'DEV002', 'completed'),
    ('T106', 'C002', '2024-02-18T02:00:00', 750.00, 'AnyCompany Fraudulent Marketplace', 'Marketplace', 'online', '198.51.100.60', 'DEV002', 'completed'),
    ('T107', 'C002', '2024-02-18T02:05:00', 900.00, 'Example Shell Trading Co', 'Marketplace', 'online', '198.51.100.60', 'DEV002', 'completed'),

-- Charlie (C003): Blacklisted merchant + massive amount anomaly
    ('T108', 'C003', '2024-01-15T15:00:00', 1000.00, 'AnyCompany Fraudulent Crypto Exchange', 'Cryptocurrency', 'online', '203.0.113.70', 'DEV005', 'completed'),
    ('T109', 'C003', '2024-01-15T17:00:00', 5000.00, 'AnyCompany Luxury Jewelry', 'Jewelry', 'online', '203.0.113.90', 'DEV005', 'completed'),
    ('T110', 'C003', '2024-02-22T04:30:00', 8500.00, 'AnyCompany Fraudulent Crypto Exchange', 'Cryptocurrency', 'online', '103.78.200.15', 'DEV030', 'completed'),

-- Eve (C005): Failed retry pattern (card testing)
    ('T111', 'C005', '2024-01-15T19:00:00', 150.00, 'AnyCompany Online Retail', 'Retail', 'online', '103.25.40.55', 'DEV010', 'failed'),
    ('T112', 'C005', '2024-01-15T19:02:00', 150.00, 'AnyCompany Online Retail', 'Retail', 'online', '103.25.40.55', 'DEV010', 'failed'),
    ('T113', 'C005', '2024-01-15T19:05:00', 150.00, 'AnyCompany Online Retail', 'Retail', 'online', '103.25.40.55', 'DEV010', 'completed'),
    ('T114', 'C005', '2024-02-25T22:10:00', 50.00, 'Example Counterfeit Storefront', 'Retail', 'online', '103.25.40.55', 'DEV010', 'failed'),
    ('T115', 'C005', '2024-02-25T22:11:00', 50.00, 'Example Counterfeit Storefront', 'Retail', 'online', '103.25.40.55', 'DEV010', 'failed'),
    ('T116', 'C005', '2024-02-25T22:12:00', 25.00, 'Example Counterfeit Storefront', 'Retail', 'online', '103.25.40.55', 'DEV010', 'failed'),
    ('T117', 'C005', '2024-02-25T22:14:00', 25.00, 'Example Counterfeit Storefront', 'Retail', 'online', '103.25.40.55', 'DEV010', 'completed'),

-- Frank (C006): Rapid-fire transactions from different IP (velocity + geo mismatch)
    ('T118', 'C006', '2024-02-20T01:00:00', 500.00, 'AnyCompany Electronics', 'Electronics', 'online', '185.100.87.44', 'DEV030', 'completed'),
    ('T119', 'C006', '2024-02-20T01:02:00', 480.00, 'Example Electronics', 'Electronics', 'online', '185.100.87.44', 'DEV030', 'completed'),
    ('T120', 'C006', '2024-02-20T01:04:00', 520.00, 'AnyCompany Electronics', 'Electronics', 'online', '185.100.87.44', 'DEV030', 'completed'),
    ('T121', 'C006', '2024-02-20T01:06:00', 490.00, 'Example Electronics', 'Electronics', 'online', '185.100.87.44', 'DEV030', 'completed'),
    ('T122', 'C006', '2024-02-20T01:08:00', 510.00, 'AnyCompany Electronics', 'Electronics', 'online', '185.100.87.44', 'DEV030', 'completed'),

-- Hank (C008): Geographic mismatch - Berlin customer transacting from Nigeria
    ('T123', 'C008', '2024-02-19T05:00:00', 2000.00, 'Example Electronics Scam Shop', 'Electronics', 'online', '41.58.100.10', 'DEV030', 'completed'),
    ('T124', 'C008', '2024-02-19T05:15:00', 1500.00, 'AnyCompany Fraudulent Gold Market', 'Jewelry', 'online', '41.58.100.10', 'DEV030', 'completed'),
    ('T125', 'C008', '2024-02-19T05:30:00', 3000.00, 'AnyCompany Online Retail', 'Marketplace', 'online', '41.58.100.10', 'DEV030', 'completed'),

-- Jack (C010): Massive spending spree way above average
    ('T126', 'C010', '2024-02-18T23:00:00', 4500.00, 'AnyCompany Luxury Jewelry', 'Jewelry', 'online', '203.0.113.70', 'DEV015', 'completed'),
    ('T127', 'C010', '2024-02-18T23:10:00', 6200.00, 'Example Luxury Watches', 'Jewelry', 'online', '203.0.113.70', 'DEV015', 'completed'),
    ('T128', 'C010', '2024-02-18T23:20:00', 3800.00, 'AnyCompany Luxury Outlet', 'Luxury', 'online', '203.0.113.70', 'DEV015', 'completed'),

-- Karen (C011): Blacklisted merchant + amount anomaly (avg $125, now $2000+)
    ('T129', 'C011', '2024-02-21T04:00:00', 2000.00, 'AnyCompany Fraudulent Crypto Exchange', 'Cryptocurrency', 'online', '49.36.100.10', 'DEV016', 'completed'),
    ('T130', 'C011', '2024-02-21T04:05:00', 1500.00, 'AnyCompany Fraudulent Lending Services', 'Financial Services', 'online', '49.36.100.10', 'DEV016', 'completed'),

-- Leo (C012): Device change + unusual time + different location
    ('T131', 'C012', '2024-02-23T03:30:00', 1800.00, 'Example Phishing Storefront', 'Retail', 'online', '41.190.2.50', 'DEV031', 'completed'),
    ('T132', 'C012', '2024-02-23T03:35:00', 2200.00, 'AnyCompany Fraudulent Data Market', 'Marketplace', 'online', '41.190.2.50', 'DEV031', 'completed'),

-- Mia (C013): Rapid small transactions (card testing pattern)
    ('T133', 'C013', '2024-02-24T10:00:00', 1.00, 'Example Test Merchant A', 'Retail', 'online', '116.228.100.10', 'DEV018', 'completed'),
    ('T134', 'C013', '2024-02-24T10:01:00', 1.00, 'Example Test Merchant B', 'Retail', 'online', '116.228.100.10', 'DEV018', 'completed'),
    ('T135', 'C013', '2024-02-24T10:02:00', 2.00, 'Example Test Merchant C', 'Retail', 'online', '116.228.100.10', 'DEV018', 'completed'),
    ('T136', 'C013', '2024-02-24T10:03:00', 1.50, 'Example Test Merchant D', 'Retail', 'online', '116.228.100.10', 'DEV018', 'completed'),
    ('T137', 'C013', '2024-02-24T10:10:00', 4500.00, 'Example Luxury Watches', 'Jewelry', 'online', '116.228.100.10', 'DEV018', 'completed'),

-- Noah (C014): Multiple failed attempts then success at blacklisted merchant
    ('T138', 'C014', '2024-02-22T21:00:00', 300.00, 'AnyCompany Fraudulent Marketplace', 'Marketplace', 'online', '203.0.113.80', 'DEV019', 'failed'),
    ('T139', 'C014', '2024-02-22T21:02:00', 300.00, 'AnyCompany Fraudulent Marketplace', 'Marketplace', 'online', '203.0.113.80', 'DEV019', 'failed'),
    ('T140', 'C014', '2024-02-22T21:05:00', 250.00, 'AnyCompany Fraudulent Marketplace', 'Marketplace', 'online', '203.0.113.80', 'DEV019', 'completed'),

-- Rita (C018): Unusual international transaction from different continent
    ('T141', 'C018', '2024-02-25T06:00:00', 5500.00, 'Example Counterfeit Luxury Goods', 'Luxury', 'online', '95.173.100.10', 'DEV032', 'completed'),
    ('T142', 'C018', '2024-02-25T06:10:00', 3200.00, 'AnyCompany Fraudulent Jewelry', 'Jewelry', 'online', '95.173.100.10', 'DEV032', 'completed'),

-- Tina (C020): Velocity attack - many transactions in minutes
    ('T143', 'C020', '2024-02-26T02:00:00', 290.00, 'Example Shell Trading Co', 'Marketplace', 'online', '185.100.87.44', 'DEV033', 'completed'),
    ('T144', 'C020', '2024-02-26T02:01:00', 290.00, 'Example Shell Trading Co', 'Marketplace', 'online', '185.100.87.44', 'DEV033', 'completed'),
    ('T145', 'C020', '2024-02-26T02:02:00', 290.00, 'Example Shell Trading Co', 'Marketplace', 'online', '185.100.87.44', 'DEV033', 'completed'),
    ('T146', 'C020', '2024-02-26T02:03:00', 290.00, 'Example Shell Trading Co', 'Marketplace', 'online', '185.100.87.44', 'DEV033', 'completed'),
    ('T147', 'C020', '2024-02-26T02:04:00', 290.00, 'Example Shell Trading Co', 'Marketplace', 'online', '185.100.87.44', 'DEV033', 'completed'),
    ('T148', 'C020', '2024-02-26T02:05:00', 290.00, 'Example Shell Trading Co', 'Marketplace', 'online', '185.100.87.44', 'DEV033', 'completed');

-- Fraud Patterns
INSERT INTO fraud_patterns VALUES
    ('FP001', 'Rapid Transactions', 'velocity', 20, 'Multiple transactions in a short time window indicating automated or fraudulent activity'),
    ('FP002', 'Large Amount Anomaly', 'amount', 25, 'Transaction amount significantly exceeds the customer''s typical spending pattern'),
    ('FP003', 'Geographic Mismatch', 'geographic', 30, 'Transaction originates from a location inconsistent with the customer''s typical location'),
    ('FP004', 'Example Blacklisted Merchant', 'merchant', 35, 'Transaction involves a merchant flagged for fraudulent or suspicious activity'),
    ('FP005', 'Device Change', 'device', 15, 'Transaction made from a different device than the customer''s usual device'),
    ('FP006', 'Failed Retry Pattern', 'behavioral', 20, 'Multiple failed transaction attempts followed by a successful one, indicating card testing'),
    ('FP007', 'Micro-Transaction Testing', 'behavioral', 25, 'Series of very small transactions used to validate stolen card details before a large purchase'),
    ('FP008', 'Late Night Anomaly', 'temporal', 15, 'Transactions occurring at unusual hours for the customer''s timezone');

-- Merchant blocklist (expanded)
INSERT INTO merchant_blacklist VALUES
    ('AnyCompany Fraudulent Lending Services', '2023-09-15', 'Predatory lending and identity theft', 156),
    ('AnyCompany Fraudulent Crypto Exchange', '2023-11-20', 'Cryptocurrency fraud scheme', 89),
    ('Example Counterfeit Storefront', '2024-01-05', 'Counterfeit goods and card skimming', 234),
    ('AnyCompany Fraudulent Marketplace', '2023-07-10', 'Stolen goods marketplace and payment fraud', 312),
    ('Example Shell Trading Co', '2023-12-01', 'Shell company used for money laundering', 178),
    ('AnyCompany Fraudulent Data Market', '2024-01-20', 'Marketplace linked to stolen credit card data', 445),
    ('AnyCompany Financial Services', '2023-10-30', 'Advance-fee fraud and fake gold sales', 67),
    ('Example Phishing Storefront', '2024-02-01', 'Phishing storefront harvesting card details', 203),
    ('AnyCompany Fraudulent Gold Market', '2023-08-25', 'International wire fraud and fake merchandise', 124),
    ('Example Counterfeit Luxury Goods', '2024-01-15', 'Counterfeit luxury goods and card cloning', 98),
    ('AnyCompany Fraudulent Jewelry', '2023-06-18', 'Jewelry fraud and chargeback abuse', 187),
    ('Example Electronics Scam Shop', '2024-02-10', 'Electronics scam with non-delivery of goods', 56);

-- ============================================================
-- Done! Tables created and seeded with demo data.
-- 20 customers, 148 transactions (90 normal + 58 suspicious),
-- 8 fraud patterns, 12 blacklisted merchants.
-- ============================================================
