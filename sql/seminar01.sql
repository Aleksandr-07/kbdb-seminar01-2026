-- =====================================================================
--  Семинар 1 — ваши решения
--  ФИО: Иванников А.Г.   Группа: ИУ1-72Б
--
--  Прогнать весь файл:  make run
--  Открыть консоль:     make psql
-- =====================================================================
set timezone = 'Europe/Moscow';

-- ---------------------------------------------------------------------
-- Часть 2.2. Осмотритесь — запишите ответы прямо здесь, в комментариях
-- ---------------------------------------------------------------------
-- Строк в таблицах:        station 3  unit 7  sensor 18  telemetry 40320  event 26  maintenance 11
-- Период телеметрии:       с 2026-09-02 00:00:00+03 по 2026-09-03 00:00:00+03 (сутки)
-- Значения sensor.kind:    temp, vibration, pressure, load
-- Значения event.severity: info, warning, alarm, unplanned_stop и «Alarm» (опечатка регистра: с заглавной буквы)
-- Датчики без измерений:   датчик id = 5 (находится на GPA-1, отсутствует в таблице телеметрии)
-- Агрегаты без датчиков:   GPA-4 (sensor_count = 0)
-- «Грязная» запись в maintenance (id и что не так): 
--   id = 2 (дубль записи 1 с фамилией с маленькой буквы «иванов» и кривыми полями)
--   id = 3 (инженер «И.», пустые запчасти и текст «см. предыдущую строку»)



-- ---------------------------------------------------------------------
-- Задача 1. Агрегаты и площадки
-- Ожидается: 7 строк; первыми идут P-1, P-2 (КС Восточная)
-- ---------------------------------------------------------------------
-- Задача 1
select u.id, u.model, s.name as station
from   unit u
join   station s on s.id = u.station_id
order  by s.name, u.id;


-- ---------------------------------------------------------------------
-- Задача 2. Сколько датчиков на агрегате
-- Ожидается: 7 строк; GPA-1 → 5, GPA-4 → 0
-- ---------------------------------------------------------------------
-- Задача 2
select u.id, u.model, count(s.id) as sensor_count
from   unit u
left join sensor s on s.unit_id = u.id
group  by u.id, u.model
order  by u.id;


-- ---------------------------------------------------------------------
-- Задача 3. Средняя температура за сутки (датчики kind = 'temp')
-- Ожидается: 4 строки; GPA-2 → 66.1
-- ---------------------------------------------------------------------
-- Задача 3
select u.id, u.model, round(avg(t.value)::numeric, 1) as avg_temp
from   unit u
join   sensor s on s.unit_id = u.id
join   telemetry t on t.sensor_id = s.id
where  s.kind = 'temp'
group  by u.id, u.model
order  by u.id;


-- ---------------------------------------------------------------------
-- Задача 4. Датчики температуры с максимумом > 85
-- Ожидается: 1 строка — TE-302 (GPA-2), ~88.3
-- ---------------------------------------------------------------------
-- Задача 4
select s.id, s.unit_id, s.kind, round(max(t.value)::numeric, 1) as max_value
from   sensor s
join   telemetry t on t.sensor_id = s.id
where  s.kind = 'temp'
group  by s.id, s.unit_id, s.kind
having max(t.value) > 85;


-- Задача 5. Почасовой профиль температуры подшипника GPA-2
-- Ожидается: 25 строк; 11:00 → 73.4, 13:00 → 83.8, 14:00 → 85.5
-- ---------------------------------------------------------------------
-- Задача 5
select date_trunc('hour', t.ts) as hour,
       round(avg(t.value)::numeric, 1) as avg_temp
from   telemetry t
join   sensor s on s.id = t.sensor_id
where  s.unit_id = 'GPA-2' and s.kind = 'temp'
group  by date_trunc('hour', t.ts)
order  by hour;


-- ---------------------------------------------------------------------
-- Задача 6. События по площадкам и severity
-- Ожидается: 10 строк «как есть». Почему не 9? Посмотрите на severity внимательно.
-- ---------------------------------------------------------------------
-- Задача 6
select s.name as station_name, e.severity, count(*) as cnt
from   event e
join   unit u on u.id = e.unit_id
join   station s on s.id = u.station_id
group  by s.name, e.severity
order  by s.name, e.severity;


-- ---------------------------------------------------------------------
-- Задача 7. Агрегаты без событий alarm / unplanned_stop
-- Ожидается: 5 агрегатов. Если у вас 6 — вы не учли регистр в severity.
-- ---------------------------------------------------------------------
-- Задача 7
select u.id, u.model
from   unit u
left join event e 
  on  e.unit_id = u.id 
 and  lower(trim(e.severity)) in ('alarm', 'unplanned_stop')
where  e.id is null
order  by u.id;


-- =====================================================================
--  Со звёздочкой (не влияют на балл)
-- =====================================================================

-- Задача 8*. Последнее измерение каждого датчика (17 строк)
-- Задача 8*
select distinct on (sensor_id) sensor_id, ts, value
from   telemetry
order  by sensor_id, ts desc;


-- Задача 9*. Часы, где средняя температура TE-302 выросла > 5 °C к предыдущему часу
-- Ожидается: 12:00 и 13:00
-- Задача 9*
with hourly as (
    select date_trunc('hour', ts) as hour,
           round(avg(value)::numeric, 1) as avg_temp
    from   telemetry
    where  sensor_id = 6
    group  by date_trunc('hour', ts)
),
calc as (
    select hour,
           avg_temp,
           lag(avg_temp) over (order by hour) as prev_temp
    from   hourly
)
select hour, avg_temp, prev_temp, round(avg_temp - prev_temp, 1) as diff
from   calc
where  avg_temp - prev_temp > 5
order  by hour;

-- Задача 10*. Ремонт в течение 48 ч после каждой внеплановой остановки
-- Ожидается: P-2 → через 30.8 ч, GPA-2 → через 4.7 ч
-- Задача 10*
select e.unit_id,
       e.ts as stop_ts,
       m.performed_at as maintenance_ts,
       round((extract(epoch from (m.performed_at - e.ts)) / 3600)::numeric, 1) as hours_after
from   event e
join   maintenance m
  on   m.unit_id = e.unit_id
 and   m.performed_at >= e.ts
 and   m.performed_at <= e.ts + interval '48 hours'
where  lower(trim(e.severity)) = 'unplanned_stop'
order  by e.ts;


-- Задача 11*. Дубли в maintenance (только SELECT!)
-- Задача 11*
with ranked as (
    select *,
           row_number() over (
               partition by unit_id, date_trunc('day', performed_at), lower(trim(notes))
               order by id
           ) as rn
    from   maintenance
)
select id, unit_id, performed_at, engineer, parts, notes
from   ranked
where  rn = 1
order  by id;