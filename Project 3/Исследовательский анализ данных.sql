/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: 
 * Дата: 
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:

WITH counts AS (
    SELECT
        COUNT(*) AS count_all, --общее количество игроков, зарегистрированных в игре
        SUM(CASE WHEN payer = 1 THEN 1 ELSE 0 END) AS count_payer --количество платящих игроков
    FROM fantasy.users
)
SELECT
    count_all,
    count_payer,
   ROUND(count_payer::NUMERIC / (count_all), 3) AS pay --доля платящих игроков от общего количества пользователей, зарегистрированных в игре
FROM counts;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:

  SELECT r.race,
       SUM(CASE WHEN u.payer = 1 THEN 1 ELSE 0 END) AS count_payer,-- количество платящих игроков этой расы
       COUNT(*) AS count_reg,--общее количество зарегистрированных игроков этой расы
       (CAST(SUM(CASE WHEN u.payer = 1 THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*))::NUMERIC(10,2) AS pay --доля платящих игроков среди всех зарегистрированных игроков этой расы
FROM fantasy.users AS u
LEFT JOIN fantasy.race AS r ON u.race_id = r.race_id
GROUP BY r.race
ORDER BY pay DESC;

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:

SELECT 
      COUNT(amount) AS count_amount, --общее количество покупок
      SUM(amount) AS total_amount, --суммарная стоимость всех покупок
      MIN(amount) AS min_amount, --минимальная стоимость покупки 
      MAX(amount) AS max_amount, --максимальная стоимость покупки
      AVG(amount) AS avg_amount, --среднее значение стоимости покупки
      PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY amount) AS mediana_amount, --медиану для стоимости покупки
      STDDEV(amount) AS std_amount --стандартное отклонение стоимости покупки
FROM fantasy.events;

-- 2.2: Аномальные нулевые покупки:
Вариант 1.

SELECT i.game_items,
       COUNT(e.amount) AS count_amount, --кол-во покупок с нулевой стоимостью
       ROUND(COUNT(e.amount)::NUMERIC / COUNT(*),2) AS amo --доля покупок с нулевой стоимостью от общего числа
FROM fantasy.events AS e
JOIN fantasy.items AS i ON e.item_code = i.item_code
WHERE e.amount = 0
GROUP BY i.game_items;-- фильтр, когда стоимость составляет о

Вариант 2.

SELECT
COUNT(transaction_id) AS null_orders,
(SELECT COUNT(transaction_id) FROM fantasy.events) AS total_orders,
(COUNT(transaction_id)::numeric / (SELECT COUNT(transaction_id) FROM fantasy.events))
FROM fantasy.events
WHERE amount = 0;


-- 2.3: Популярные эпические предметы:

WITH orders_stat AS (
SELECT
COUNT(DISTINCT id) AS total_payers,  -- общее количество игроков
COUNT(transaction_id) AS total_orders --кол-во транзакций покупателей
FROM fantasy.events
WHERE amount > 0
)
SELECT
i.game_items AS game_item, --название эпического предмета
COUNT(e.transaction_id) AS total_orders,
(COUNT(e.transaction_id)::real / (SELECT total_orders FROM orders_stat)*100)::numeric(6,4) AS order_share, -- % продажи каждого предмета от всех продаж
(COUNT(DISTINCT e.id)::real / (SELECT total_payers FROM orders_stat)*100)::numeric(6,4) AS player_share --% игроков, совершивших хотя бы один раз покупку этого предмета
FROM  fantasy.events AS e
LEFT JOIN fantasy.items AS i ON e.item_code = i.item_code
WHERE e.amount > 0
GROUP BY i.game_items
ORDER BY total_orders DESC
LIMIT 10;

-- Часть 2. Решение ad hoc-задачи
-- Задача: Зависимость активности игроков от расы персонажа:

WITH CTE1 AS (  -- общее количество игроков по расам
    SELECT r.race_id,
           COUNT(u.id) AS total_players
    FROM fantasy.users AS u
    JOIN fantasy.race AS r ON u.race_id = r.race_id
    GROUP BY r.race_id
),
CTE2 AS (  -- игроки, совершившие хотя бы одну покупку
    SELECT DISTINCT u.id, u.race_id
    FROM fantasy.events AS e
    JOIN fantasy.users AS u ON e.id = u.id
    WHERE e.amount > 0
),
CTE3 AS (  -- количество игроков, совершивших хотя бы одну покупку по расам
    SELECT race_id,
           COUNT(DISTINCT id) AS buying_players_count
    FROM CTE2
    GROUP BY race_id
),
CTE4 AS (  -- количество платящих игроков среди тех, кто покупал
    SELECT u.race_id,
           COUNT(DISTINCT u.id) AS pay_count
    FROM fantasy.users AS u
    JOIN CTE2 AS c2 ON u.id = c2.id
    WHERE u.payer = 1
    GROUP BY u.race_id
),
CTE5 AS (  -- статистика по покупкам
    SELECT u.race_id,
           COUNT(e.transaction_id) AS total_purchases,
           SUM(e.amount) AS total_amount
    FROM fantasy.events AS e
    JOIN fantasy.users AS u ON e.id = u.id
    WHERE e.amount > 0
    GROUP BY u.race_id
)
SELECT
    r.race,
    c1.total_players,
    c3.buying_players_count,
    ROUND(c3.buying_players_count::numeric / c1.total_players, 3) AS buying_players_share,  -- доля покупающих от всех
    ROUND(c4.pay_count::numeric / c3.buying_players_count, 3) AS pay_share,                 -- доля платящих среди покупающих
    ROUND(c5.total_purchases::numeric / c3.buying_players_count, 2) AS avg_purchases_per_buyer, -- среднее число покупок на игрока
    ROUND(c5.total_amount::numeric / c5.total_purchases, 2) AS avg_value_per_purchase,          -- средняя стоимость одной покупки
    ROUND(c5.total_amount::numeric / c3.buying_players_count, 2) AS avg_total_spent_per_buyer   -- средняя общая сумма на игрока
FROM CTE1  AS c1
LEFT JOIN CTE3 c3 ON c1.race_id = c3.race_id
LEFT JOIN CTE4 c4 ON c1.race_id = c4.race_id
LEFT JOIN CTE5 c5 ON c1.race_id = c5.race_id
LEFT JOIN fantasy.race r ON r.race_id = c1.race_id
ORDER BY r.race;





     
  
  












