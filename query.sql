-- Importing Data

CREATE TABLE events AS
SELECT 
	user_id,
	DATE_TRUNC('month', event_time) AS event_month,
	event_type,
	price,
	plan_type,
	is_promo,
	discount_percent
FROM read_csv_auto("C:\Users\Rushikesh\Desktop\Projects\Product\cohort\data.csv")
;

--------------------------------------------------------------------------------------------

-- Data Cleaning 

SELECT *
FROM events
;

SELECT DISTINCT price
FROM events
;

SELECT *
FROM events
WHERE price = 'error'
;

SELECT *
FROM events
WHERE price IS NULL
;

UPDATE events
SET price = 
    CASE 
        WHEN discount_percent = 0 AND LOWER(TRIM(plan_type)) = 'basic'
        THEN 10.0
        WHEN discount_percent = 0 AND LOWER(TRIM(plan_type)) = 'standard'
        THEN 20.0
        WHEN discount_percent = 0 AND LOWER(TRIM(plan_type)) = 'premium'
        THEN 30.0        
        WHEN discount_percent > 0 AND LOWER(TRIM(plan_type)) = 'basic'
        THEN 10 * (1 - discount_percent / 100.0)        
        WHEN discount_percent > 0 AND LOWER(TRIM(plan_type)) = 'standard'
        THEN 20 * (1 - discount_percent / 100.0)        
        WHEN discount_percent > 0 AND LOWER(TRIM(plan_type)) = 'premium'
        THEN 30 * (1 - discount_percent / 100.0)
        ELSE TRY_CAST(price AS DOUBLE)        
    END    
WHERE (price = 'error') OR (price IS NULL);

UPDATE events
SET price = CAST(price AS DOUBLE)
;

ALTER TABLE events
ALTER COLUMN price TYPE DOUBLE
;

SELECT DISTINCT discount_percent
FROM events
;

SELECT DISTINCT event_type
FROM events
;

SELECT DISTINCT plan_type
FROM events
;

SELECT DISTINCT event_month
FROM events
ORDER BY 1
;

SELECT *
FROM events
WHERE user_id IS NULL
;

SELECT *
FROM events
WHERE user_id = 105355
;

---------------------------------------------------------------------------

-- Descriptive Analysis

SELECT 
	COUNT(DISTINCT user_id)
FROM events;

SELECT 
	DISTINCT plan_type
FROM events;

SELECT 
	DISTINCT discount_percent
FROM events;

SELECT
	MIN(event_month) AS Start,
	MAX(event_month) AS End
FROM events;

SELECT
	event_month,
	SUM(is_promo)
FROM events
GROUP BY event_month;

---------------------------------------------------------------------------

-- Total Revenue Cohort

WITH user_cohort AS (
    SELECT
        user_id,
        MIN(event_month) AS cohort_month
    FROM events
    GROUP BY user_id
),
cohort_data AS (
    SELECT
        e.user_id,
        c.cohort_month,
        e.event_month,
        e.price,
        DATE_DIFF('month', c.cohort_month, e.event_month) AS cohort_month_index
    FROM events e
    JOIN user_cohort c
    ON e.user_id = c.user_id
)
SELECT
    cohort_month,
    cohort_month_index,
    SUM(price) AS total_revenue
FROM cohort_data
GROUP BY cohort_month, cohort_month_index
ORDER BY cohort_month, cohort_month_index;

---------------------------------------------------------------------------

-- ARPU Cohort

WITH user_cohort AS (
    SELECT
        user_id,
        MIN(event_month) AS cohort_month
    FROM events
    GROUP BY user_id
),
cohort_data AS (
    SELECT
        e.user_id,
        e.event_month,
        e.price,
        c.cohort_month,
        DATE_DIFF('month', c.cohort_month, e.event_month) AS cohort_month_index
    FROM events e
    JOIN user_cohort c
    ON e.user_id = c.user_id
),
revenue_cohort AS (
    SELECT
        cohort_month,
        cohort_month_index,
        SUM(price) AS total_revenue
    FROM cohort_data
    GROUP BY cohort_month, cohort_month_index
),
cohort_size AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT user_id) AS total_users
    FROM user_cohort
    GROUP BY cohort_month
)
SELECT
    r.cohort_month,
    r.cohort_month_index,
    r.total_revenue * 1.0 / c.total_users AS arpu
FROM revenue_cohort r
JOIN cohort_size c
ON r.cohort_month = c.cohort_month
ORDER BY r.cohort_month, r.cohort_month_index;

---------------------------------------------------------------------------

-- Retention Cohort

WITH user_cohort AS (
    SELECT
        user_id,
        MIN(event_month) AS cohort_month
    FROM events
    GROUP BY user_id
),
cohort_purchases AS(
	SELECT
		e.user_id,
		e.event_month,
		u.cohort_month
	FROM events e
	JOIN user_cohort u
	ON e.user_id = u.user_id
),
retention_base AS (
    SELECT
        user_id,
        cohort_month,
        event_month,
        DATE_DIFF('month', cohort_month, event_month) AS cohort_month_index
    FROM cohort_purchases
),
retention_counts AS (
    SELECT
        cohort_month,
        cohort_month_index,
        COUNT(DISTINCT user_id) AS active_users
    FROM retention_base
    GROUP BY cohort_month, cohort_month_index
),
cohort_size AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT user_id) AS total_users
    FROM user_cohort
    GROUP BY cohort_month
)
SELECT
    r.cohort_month,
    r.cohort_month_index,
    r.active_users,
    c.total_users,
    r.active_users * 1.0 / c.total_users AS retention_rate
FROM retention_counts r
JOIN cohort_size c
ON r.cohort_month = c.cohort_month
ORDER BY r.cohort_month, r.cohort_month_index;

---------------------------------------------------------------------------

-- Life Time Value (LTV) Cohort

WITH user_cohort AS (
    SELECT
        user_id,
        MIN(event_month) AS cohort_month
    FROM events
    GROUP BY user_id
),
cohort_data AS (
    SELECT
        e.user_id,
        e.event_month,
        e.price,
        c.cohort_month,
        DATE_DIFF('month', c.cohort_month, e.event_month) AS cohort_month_index
    FROM events e
    JOIN user_cohort c
    ON e.user_id = c.user_id
),
revenue_cohort AS (
    SELECT
        cohort_month,
        cohort_month_index,
        SUM(price) AS total_revenue
    FROM cohort_data
    GROUP BY cohort_month, cohort_month_index
),
cohort_size AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT user_id) AS total_users
    FROM user_cohort
    GROUP BY cohort_month
)
SELECT
    r.cohort_month,
    r.cohort_month_index,
    r.total_revenue * 1.0 / c.total_users AS arpu,
    SUM(total_revenue * 1.0 / total_users) OVER (
        PARTITION BY r.cohort_month
        ORDER BY cohort_month_index) AS ltv    
FROM revenue_cohort r
JOIN cohort_size c
ON r.cohort_month = c.cohort_month
ORDER BY r.cohort_month, r.cohort_month_index;

---------------------------------------------------------------------------

-- Retention Cohort By Plan

WITH plan_type AS (
	SELECT *
	FROM events
	WHERE plan_type = 'premium'
),
user_cohort AS (
    SELECT
        user_id,
        MIN(event_month) AS cohort_month
    FROM plan_type
    GROUP BY user_id
),
cohort_purchases AS(
	SELECT
		e.user_id,
		e.event_month,
		u.cohort_month
	FROM plan_type e
	JOIN user_cohort u
	ON e.user_id = u.user_id
),
retention_base AS (
    SELECT
        user_id,
        cohort_month,
        event_month,
        DATE_DIFF('month', cohort_month, event_month) AS cohort_month_index
    FROM cohort_purchases
),
retention_counts AS (
    SELECT
        cohort_month,
        cohort_month_index,
        COUNT(DISTINCT user_id) AS active_users
    FROM retention_base
    GROUP BY cohort_month, cohort_month_index
),
cohort_size AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT user_id) AS total_users
    FROM user_cohort
    GROUP BY cohort_month
)
SELECT
    r.cohort_month,
    r.cohort_month_index,
    r.active_users,
    c.total_users,
    r.active_users * 1.0 / c.total_users AS retention_rate
FROM retention_counts r
JOIN cohort_size c
ON r.cohort_month = c.cohort_month
ORDER BY r.cohort_month, r.cohort_month_index;


-------------------------------------------------------------------------

-- LTV Cohort By Plan

WITH plan_type AS(
	SELECT *
	FROM events
	WHERE plan_type = 'premium'
),
user_cohort AS (
    SELECT
        user_id,
        MIN(event_month) AS cohort_month
    FROM plan_type
    GROUP BY user_id
),
cohort_data AS (
    SELECT
        e.user_id,
        e.event_month,
        e.price,
        c.cohort_month,
        DATE_DIFF('month', c.cohort_month, e.event_month) AS cohort_month_index
    FROM plan_type e
    JOIN user_cohort c
    ON e.user_id = c.user_id
),
revenue_cohort AS (
    SELECT
        cohort_month,
        cohort_month_index,
        SUM(price) AS total_revenue
    FROM cohort_data
    GROUP BY cohort_month, cohort_month_index
),
cohort_size AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT user_id) AS total_users
    FROM user_cohort
    GROUP BY cohort_month
)
SELECT
    r.cohort_month,
    r.cohort_month_index,
    SUM(total_revenue * 1.0 / total_users) OVER (
        PARTITION BY r.cohort_month
        ORDER BY cohort_month_index) AS ltv    
FROM revenue_cohort r
JOIN cohort_size c
ON r.cohort_month = c.cohort_month
ORDER BY r.cohort_month, r.cohort_month_index;
