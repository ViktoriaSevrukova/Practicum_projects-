/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Севрюкова Виктория
 * Дата:
*/



-- Задача 1: Время активности объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
flats_cities AS (
SELECT
f.*,
CASE WHEN f.city_id = '6X8I' THEN 'Санкт-Петербург'
ELSE 'ЛенОбл'
END AS is_spb,
a.last_price::real / f.total_area AS meter_cost,--стоимость одного кв. метра
CASE WHEN a.days_exposition <= 30 THEN '1-30 days'
WHEN a.days_exposition <= 90 THEN '31-90 days'
WHEN a.days_exposition <= 180 THEN '91-180 days'
WHEN a.days_exposition > 180 THEN '181+ days'
ELSE 'non category'
END AS dayexp_cat
FROM real_estate.flats AS f
LEFT JOIN real_estate.advertisement AS a ON a.id = f.id
where first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31' and type_id = 'F8EM'
AND f.id IN (SELECT * FROM filtered_id)
)   
     SELECT  -- Основной запрос с подсчетом статистики
     is_spb,
     dayexp_cat,
COUNT(id) AS total_adv, --кол-во объявлений
(COUNT(id)::real / SUM(COUNT(id)) OVER(PARTITION BY is_spb) * 100)::numeric(4,2) AS total_ad,--доля объявлений в разрезе каждого региона
AVG(meter_cost)::numeric(8,2) AS avg_meter_cost, -- средняя стоимость квадратного метра 
AVG(total_area)::numeric(4,2) AS avg_total_area,-- средняя площадь недвижимости для каждого сегмента
PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms) AS median_rooms,--медиана кол-ва комнат
PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY balcony) AS median_balcony,--медиана кол-ва балконов
PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY floor) AS median_floor,--медиана этажности
(AVG(is_apartment)*100)::numeric(5,3) AS apartment_share
FROM flats_cities
GROUP BY is_spb, dayexp_cat
ORDER BY is_spb, total_adv;

 

-- Задача 2: Сезонность объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
filtered_id AS (
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND (
            (ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
             AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits))
            OR ceiling_height IS NULL
        )
),
flats_dates AS (
    SELECT
        f.id, 
        a.last_price::real / f.total_area AS meter_cost, -- Стоимость одного метра
        f.total_area, 
        EXTRACT(MONTH FROM a.first_day_exposition::date) AS start_month, -- Месяц публикации
        EXTRACT(MONTH FROM (a.first_day_exposition::date + INTERVAL'1 day' * a.days_exposition)) AS close_motnh -- Месяц снятия
    FROM real_estate.flats AS f
    LEFT JOIN real_estate.advertisement AS a ON a.id = f.id
    WHERE type_id = 'F8EM'        
        AND f.id IN (SELECT id FROM filtered_id)       
        AND EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018
),
pub_stats AS (
    SELECT
        start_month::int AS ad_month,
        COUNT(id) AS cnt_pub,--кол-во объявлений
        (COUNT(id)::real / SUM(COUNT(id)) OVER() * 100)::numeric(4,2) AS cnt_pub_share,
        AVG(meter_cost)::NUMERIC(8,2) AS avg_meter_pub,--сред стоимость кв метра
        AVG(total_area)::NUMERIC(5,2) AS avg_area_pub --сред площадь 
    FROM flats_dates
    GROUP BY ad_month
),
end_stats AS (
    SELECT
        close_motnh::int AS ad_month,
        COUNT(id) AS cnt_end,--кол-во объявлений
        (COUNT(id)::real / SUM(COUNT(id)) OVER() * 100)::numeric(4,2) AS cnt_end_share,
        AVG(meter_cost)::NUMERIC(8,2) AS avg_meter_end,--сред стоимость кв метра
        AVG(total_area)::NUMERIC(5,2) AS avg_area_end --сред площадь 
    FROM flats_dates
    -- Фильтруем объявления без даты снятия (т.е. активные)
    WHERE close_motnh IS NOT NULL
    GROUP BY ad_month
)
SELECT * --основной запрос
FROM pub_stats AS p
JOIN end_stats AS e ON p.ad_month = e.ad_month;

    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
   