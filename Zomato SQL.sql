-- Create Database
CREATE DATABASE zomato_analytics;
USE zomato_analytics;

-- KPI 1: Build a Data Model 
-- (Country, Currency, Main -> staging -> restaurants fact table)
CREATE TABLE country (
    CountryID   INT PRIMARY KEY,
    CountryName VARCHAR(100)
);

CREATE TABLE currency (
    CurrencyName VARCHAR(50) PRIMARY KEY,
    USD_Rate     DECIMAL(10,6)
);

-- Staging table 
CREATE TABLE main_staging (
    RestaurantID          VARCHAR(50),
    RestaurantName        VARCHAR(255),
    CountryCode           VARCHAR(50),
    City                  VARCHAR(100),
    Address                VARCHAR(500),
    Locality               VARCHAR(255),
    LocalityVerbose        VARCHAR(255),
    Longitude               VARCHAR(50),
    Latitude                VARCHAR(50),
    Cuisines                VARCHAR(500),
    Currency                 VARCHAR(100),
    Has_Table_booking         VARCHAR(50),
    Has_Online_delivery       VARCHAR(50),
    Is_delivering_now         VARCHAR(50),
    Switch_to_order_menu      VARCHAR(50),
    Price_range               VARCHAR(50),
    Votes                     VARCHAR(50),
    Average_Cost_for_two       VARCHAR(100),
    Rating                     VARCHAR(50),
    Year_Opening                VARCHAR(50),
    Month_Opening                VARCHAR(50),
    Day_Opening                  VARCHAR(50)
);
 
 -- Load raw CSVs
LOAD DATA LOCAL INFILE 'C:/Users/saksh/Downloads/ZOMATO ANALYTICS/ZOMATO ANALYTICS/country.csv'
INTO TABLE country
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'C:/Users/saksh/Downloads/ZOMATO ANALYTICS/ZOMATO ANALYTICS/currency.csv'
INTO TABLE currency
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'C:/Users/saksh/Downloads/ZOMATO ANALYTICS/ZOMATO ANALYTICS/main.csv'
INTO TABLE main_staging
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(
    RestaurantID, RestaurantName, CountryCode, City, Address, Locality,
    LocalityVerbose, Longitude, Latitude, Cuisines, Currency,
    Has_Table_booking, Has_Online_delivery, Is_delivering_now,
    Switch_to_order_menu, Price_range, Votes, Average_Cost_for_two,
    Rating, Year_Opening, Month_Opening, Day_Opening
);

-- Row count checks 
SELECT COUNT(*) FROM country;         
SELECT COUNT(*) FROM currency;        
SELECT COUNT(*) FROM main_staging;   

-- Build the fact table
CREATE TABLE restaurants AS
SELECT
    CAST(RestaurantID AS UNSIGNED)              AS RestaurantID,
    RestaurantName,
    CAST(CountryCode AS UNSIGNED)               AS CountryCode,
    City,
    Address,
    Locality,
    LocalityVerbose,
    CAST(Longitude AS DECIMAL(15,10))           AS Longitude,
    CAST(Latitude AS DECIMAL(15,10))            AS Latitude,
    NULLIF(TRIM(Cuisines), '')                  AS Cuisines,
    Currency,
    Has_Table_booking,
    Has_Online_delivery,
    Is_delivering_now,
    Switch_to_order_menu,
    CAST(Price_range AS UNSIGNED)               AS Price_range,
    CAST(Votes AS UNSIGNED)                     AS Votes,
    CAST(Average_Cost_for_two AS DECIMAL(12,2)) AS Average_Cost_for_two,
    CAST(Rating AS DECIMAL(3,2))                AS Rating,
    STR_TO_DATE(
        CONCAT(Year_Opening, '-', Month_Opening, '-', Day_Opening),
        '%Y-%m-%d'
    ) AS DateKey_Opening
FROM main_staging;

SELECT COUNT(*) FROM restaurants;  
SELECT MIN(DateKey_Opening), MAX(DateKey_Opening) FROM restaurants;  -- 2010-01-01 to 2018-12-28

-- Relational integrity: primary key + foreign keys ---
ALTER TABLE restaurants ADD PRIMARY KEY (RestaurantID);
 
ALTER TABLE restaurants MODIFY CountryCode INT;
ALTER TABLE restaurants ADD FOREIGN KEY (CountryCode) REFERENCES country(CountryID);
 
ALTER TABLE restaurants MODIFY Currency VARCHAR(50);
ALTER TABLE restaurants ADD FOREIGN KEY (Currency) REFERENCES currency(CurrencyName);

-- KPI 2: Build a Calendar Table using DateKey_Opening
SET SESSION cte_max_recursion_depth = 5000;   -- default 1000 is too low for ~3285 days
 
CREATE TABLE calendar AS
WITH RECURSIVE date_range AS (
    SELECT MIN(DateKey_Opening) AS dt FROM restaurants
    UNION ALL
    SELECT dt + INTERVAL 1 DAY
    FROM date_range
    WHERE dt + INTERVAL 1 DAY <= (SELECT MAX(DateKey_Opening) FROM restaurants)
)
SELECT
    dt AS DateKey,
    YEAR(dt)                                              AS Year,
    MONTH(dt)                                             AS MonthNo,
    MONTHNAME(dt)                                         AS MonthFullName,
    CONCAT('Q', QUARTER(dt))                              AS Quarter,
    DATE_FORMAT(dt, '%Y-%b')                              AS YearMonth,
    DAYOFWEEK(dt)                                         AS WeekdayNo,      -- 1=Sun ... 7=Sat
    DAYNAME(dt)                                           AS WeekdayName,
    CONCAT('FM', ((MONTH(dt) + 8) MOD 12) + 1)            AS FinancialMonth, -- Apr=FM1 ... Mar=FM12
    CONCAT('FQ', FLOOR(((MONTH(dt) + 8) MOD 12) / 3) + 1) AS FinancialQuarter
FROM date_range;
 
ALTER TABLE calendar ADD PRIMARY KEY (DateKey);
 
SELECT COUNT(*) FROM calendar;   

ALTER TABLE restaurants ADD COLUMN Avg_Cost_USD DECIMAL(15,2);
 -- KPI 3: Convert Average Cost for two into USD
UPDATE restaurants r
JOIN currency c ON r.Currency = c.CurrencyName
SET r.Avg_Cost_USD = r.Average_Cost_for_two * c.USD_Rate;
 
SELECT COUNT(*) FROM restaurants WHERE Avg_Cost_USD IS NULL;  

-- KPI 4: Number of Restaurants based on City and Country
SELECT
    co.CountryName,
    r.City,
    COUNT(*) AS Restaurant_Count
FROM restaurants r
JOIN country co ON r.CountryCode = co.CountryID
GROUP BY co.CountryName, r.City
ORDER BY Restaurant_Count DESC;
 
-- Country-level rollup
SELECT
    co.CountryName,
    COUNT(*) AS Restaurant_Count
FROM restaurants r
JOIN country co ON r.CountryCode = co.CountryID
GROUP BY co.CountryName
ORDER BY Restaurant_Count DESC;

-- KPI 5: Number of Restaurants opening based on Year, Quarter, Month
SELECT
    cal.Year,
    cal.Quarter,
    cal.MonthFullName,
    cal.MonthNo,
    COUNT(r.RestaurantID) AS Restaurants_Opened
FROM restaurants r
JOIN calendar cal ON r.DateKey_Opening = cal.DateKey
GROUP BY cal.Year, cal.Quarter, cal.MonthFullName, cal.MonthNo
ORDER BY cal.Year, cal.MonthNo;
 
-- Year-level trend
SELECT
    cal.Year,
    COUNT(r.RestaurantID) AS Restaurants_Opened
FROM restaurants r
JOIN calendar cal ON r.DateKey_Opening = cal.DateKey
GROUP BY cal.Year
ORDER BY cal.Year;

-- KPI 6: Count of Restaurants based on Average Ratings
SELECT
    CASE
        WHEN Rating = 1.00 AND Votes = 0 THEN 'Not Rated'
        WHEN Rating < 2.5      THEN 'Poor (0-2.5)'
        WHEN Rating < 3.5      THEN 'Average (2.5-3.5)'
        WHEN Rating < 4.0      THEN 'Good (3.5-4.0)'
        WHEN Rating < 4.5      THEN 'Very Good (4.0-4.5)'
        ELSE 'Excellent (4.5-5)'
    END AS Rating_Band,
    COUNT(*) AS Restaurant_Count
FROM restaurants
GROUP BY Rating_Band
ORDER BY MIN(Rating);

-- KPI 7: Price buckets based on Average Price
SELECT
    CASE
        WHEN Avg_Cost_USD < 2     THEN 'Under $2'
        WHEN Avg_Cost_USD < 5     THEN '$2 - $5'
        WHEN Avg_Cost_USD < 10    THEN '$5 - $10'
        WHEN Avg_Cost_USD < 15    THEN '$10 - $15'
        WHEN Avg_Cost_USD < 25    THEN '$15 - $25'
        WHEN Avg_Cost_USD < 50    THEN '$25 - $50'
        ELSE '$50+'
    END AS Cost_Bucket,
    COUNT(*) AS Restaurant_Count
FROM restaurants
GROUP BY Cost_Bucket
ORDER BY MIN(Avg_Cost_USD);

-- KPI 8: Percentage of Restaurants based on Has_Table_booking
SELECT
    Has_Table_booking,
    COUNT(*) AS Restaurant_Count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM restaurants), 2) AS Pct
FROM restaurants
GROUP BY Has_Table_booking;

-- KPI 9: Percentage of Restaurants based on Has_Online_delivery
SELECT
    Has_Online_delivery,
    COUNT(*) AS Restaurant_Count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM restaurants), 2) AS Pct
FROM restaurants
GROUP BY Has_Online_delivery;

-- KPI 10: Charts based on Cuisines, City, Ratings
SELECT Cuisines, COUNT(*) AS Restaurant_Count
FROM restaurants
WHERE Cuisines IS NOT NULL
GROUP BY Cuisines
ORDER BY Restaurant_Count DESC
LIMIT 20;
 
-- City-level rating and cost profile
SELECT
    City,
    COUNT(*) AS Restaurant_Count,
    ROUND(AVG(Rating), 2) AS Avg_Rating,
    ROUND(AVG(Avg_Cost_USD), 2) AS Avg_Cost_USD
FROM restaurants
GROUP BY City
ORDER BY Restaurant_Count DESC
LIMIT 15;
 
 -- Ratings distribution
SELECT
    CASE
        WHEN Rating = 1.00 AND Votes = 0 THEN 'Not Rated'
        WHEN Rating < 2.5      THEN 'Poor (0-2.5)'
        WHEN Rating < 3.5      THEN 'Average (2.5-3.5)'
        WHEN Rating < 4.0      THEN 'Good (3.5-4.0)'
        WHEN Rating < 4.5      THEN 'Very Good (4.0-4.5)'
        ELSE 'Excellent (4.5-5)'
    END AS Rating_Band,
    COUNT(*) AS Restaurant_Count
FROM restaurants
GROUP BY Rating_Band
ORDER BY MIN(Rating);