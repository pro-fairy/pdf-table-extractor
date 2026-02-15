-- ============================================================================
-- PDF Table Extractor - PostgreSQL Database Schema
-- ============================================================================
-- Медицинская экспертная система для интерпретации лабораторных анализов
--
-- Архитектура: 9 таблиц с нормализацией названий и вероятностной моделью
-- ============================================================================

-- DROP SCHEMA public;

CREATE SCHEMA public AUTHORIZATION pg_database_owner;

-- ============================================================================
-- SEQUENCES
-- ============================================================================

CREATE SEQUENCE public.analyte_aliases_id_seq
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 2147483647
	START 1
	CACHE 1
	NO CYCLE;

CREATE SEQUENCE public.analyte_cause_rules_id_seq
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 2147483647
	START 1
	CACHE 1
	NO CYCLE;

CREATE SEQUENCE public.analytes_id_seq
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 2147483647
	START 1
	CACHE 1
	NO CYCLE;

CREATE SEQUENCE public.causes_id_seq
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 2147483647
	START 1
	CACHE 1
	NO CYCLE;

CREATE SEQUENCE public.conditions_id_seq
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 2147483647
	START 1
	CACHE 1
	NO CYCLE;

CREATE SEQUENCE public.reference_ranges_id_seq
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 2147483647
	START 1
	CACHE 1
	NO CYCLE;

CREATE SEQUENCE public.unit_aliases_id_seq
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 2147483647
	START 1
	CACHE 1
	NO CYCLE;

CREATE SEQUENCE public.units_id_seq
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 2147483647
	START 1
	CACHE 1
	NO CYCLE;

-- ============================================================================
-- BASE TABLES (Справочники)
-- ============================================================================

-- Таблица 1: Показатели анализов (эталонные названия)
-- Примеры: total_bilirubin, hemoglobin, glucose
CREATE TABLE public.analytes (
	id serial4 NOT NULL,
	code text NOT NULL,              -- Код показателя (англ., уникальный)
	name_ru text NOT NULL,           -- Русское название
	description text NULL,           -- Описание
	CONSTRAINT analytes_code_key UNIQUE (code),
	CONSTRAINT analytes_pkey PRIMARY KEY (id)
);

-- Таблица 2: Единицы измерения (эталонные)
-- Примеры: mmol_l, g_l, percent
CREATE TABLE public.units (
	id serial4 NOT NULL,
	code text NOT NULL,              -- Код единицы (англ., уникальный)
	name_ru text NOT NULL,           -- Русское название (мкмоль/л, г/л)
	description text NULL,
	CONSTRAINT units_code_key UNIQUE (code),
	CONSTRAINT units_pkey PRIMARY KEY (id)
);

-- Таблица 3: Состояния пациента (беременность, детство, и т.д.)
CREATE TABLE public.conditions (
	id serial4 NOT NULL,
	code text NOT NULL,              -- Код состояния
	name_ru text NOT NULL,           -- Русское название
	description text NULL,
	CONSTRAINT conditions_code_key UNIQUE (code),
	CONSTRAINT conditions_pkey PRIMARY KEY (id)
);

-- Таблица 4: Медицинские причины отклонений
CREATE TABLE public.causes (
	id serial4 NOT NULL,
	code text NOT NULL,              -- Код причины
	name_ru text NOT NULL,           -- Русское название
	description text NULL,
	severity_level text NOT NULL,    -- Уровень критичности
	CONSTRAINT causes_code_key UNIQUE (code),
	CONSTRAINT causes_pkey PRIMARY KEY (id),
	CONSTRAINT causes_severity_level_check CHECK ((severity_level = ANY (ARRAY['LOW'::text, 'MEDIUM'::text, 'HIGH'::text, 'CRITICAL'::text])))
);

-- ============================================================================
-- ALIAS TABLES (Нормализация названий из PDF)
-- ============================================================================

-- Таблица 5: Альтернативные названия показателей
-- Связь: многие-ко-многим (один показатель может иметь много названий)
-- Примеры: "Билирубин общ.", "Билирубин общий", "Bilirubin total" → total_bilirubin
CREATE TABLE public.analyte_aliases (
	id serial4 NOT NULL,
	analyte_id int4 NOT NULL,        -- FK к эталонному показателю
	raw_name text NOT NULL,          -- Название как в PDF
	raw_name_normalized text NOT NULL, -- Нормализованное (lowercase, без пробелов)
	CONSTRAINT analyte_aliases_pkey PRIMARY KEY (id),
	CONSTRAINT analyte_aliases_analyte_id_fkey FOREIGN KEY (analyte_id) REFERENCES public.analytes(id) ON DELETE CASCADE
);

-- Таблица 6: Альтернативные названия единиц измерения
-- Примеры: "мкмоль/л", "мкМ/л", "µmol/L" → mmol_l
CREATE TABLE public.unit_aliases (
	id serial4 NOT NULL,
	unit_id int4 NOT NULL,           -- FK к эталонной единице
	raw_unit text NOT NULL,          -- Единица как в PDF
	raw_unit_normalized text NOT NULL, -- Нормализованная
	CONSTRAINT unit_aliases_pkey PRIMARY KEY (id),
	CONSTRAINT unit_aliases_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id) ON DELETE CASCADE
);

-- ============================================================================
-- REFERENCE RANGES (Медицинские нормы)
-- ============================================================================

-- Таблица 7: Референсные значения (что считается нормой)
-- Контекстные нормы: зависят от показателя, единицы, пола, возраста
CREATE TABLE public.reference_ranges (
	id serial4 NOT NULL,
	analyte_id int4 NOT NULL,        -- Какой показатель
	unit_id int4 NOT NULL,           -- В каких единицах
	sex text NOT NULL,               -- Пол: male, female, any
	age_min int4 NULL,               -- Минимальный возраст (NULL = без ограничений)
	age_max int4 NULL,               -- Максимальный возраст (NULL = без ограничений)
	ref_min numeric NULL,            -- Минимальное значение нормы
	ref_max numeric NULL,            -- Максимальное значение нормы
	CONSTRAINT reference_ranges_pkey PRIMARY KEY (id),
	CONSTRAINT reference_ranges_sex_check CHECK ((sex = ANY (ARRAY['male'::text, 'female'::text, 'any'::text]))),
	CONSTRAINT reference_ranges_analyte_id_fkey FOREIGN KEY (analyte_id) REFERENCES public.analytes(id),
	CONSTRAINT reference_ranges_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id)
);

-- Таблица 8: Связь референсов с условиями
-- Многие-ко-многим: один референс может применяться при нескольких условиях
-- Пример: reference_range_id=12, condition_id=1 (беременность) → этот референс только для беременных
CREATE TABLE public.reference_range_conditions (
	reference_range_id int4 NOT NULL,
	condition_id int4 NOT NULL,
	CONSTRAINT reference_range_conditions_pkey PRIMARY KEY (reference_range_id, condition_id),
	CONSTRAINT reference_range_conditions_condition_id_fkey FOREIGN KEY (condition_id) REFERENCES public.conditions(id) ON DELETE CASCADE,
	CONSTRAINT reference_range_conditions_reference_range_id_fkey FOREIGN KEY (reference_range_id) REFERENCES public.reference_ranges(id) ON DELETE CASCADE
);

-- ============================================================================
-- MEDICAL LOGIC (Вероятностная модель диагностики)
-- ============================================================================

-- Таблица 9: Правила связи показателей с причинами
-- Вероятностная модель: "Если показатель X повышен → возможна причина Y с весом W"
-- Примеры:
--   analyte_id=1 (билирубин), direction=HIGH, cause_id=3 (проблемы печени), weight=0.8
--   analyte_id=1 (билирубин), direction=HIGH, cause_id=5 (гемолиз), weight=0.6
CREATE TABLE public.analyte_cause_rules (
	id serial4 NOT NULL,
	analyte_id int4 NOT NULL,        -- Какой показатель
	direction text NOT NULL,         -- Направление отклонения: HIGH или LOW
	cause_id int4 NOT NULL,          -- Возможная причина
	weight numeric NULL,             -- Вес вероятности (0.0 - 1.0)
	"comment" text NULL,             -- Комментарий
	CONSTRAINT analyte_cause_rules_direction_check CHECK ((direction = ANY (ARRAY['HIGH'::text, 'LOW'::text]))),
	CONSTRAINT analyte_cause_rules_pkey PRIMARY KEY (id),
	CONSTRAINT analyte_cause_rules_weight_check CHECK (((weight >= (0)::numeric) AND (weight <= (1)::numeric))),
	CONSTRAINT analyte_cause_rules_analyte_id_fkey FOREIGN KEY (analyte_id) REFERENCES public.analytes(id),
	CONSTRAINT analyte_cause_rules_cause_id_fkey FOREIGN KEY (cause_id) REFERENCES public.causes(id)
);

-- ============================================================================
-- INDEXES (для оптимизации запросов)
-- ============================================================================
-- TODO: Добавить индексы на внешние ключи для производительности:
-- CREATE INDEX idx_analyte_aliases_analyte_id ON analyte_aliases(analyte_id);
-- CREATE INDEX idx_analyte_aliases_normalized ON analyte_aliases(raw_name_normalized);
-- CREATE INDEX idx_unit_aliases_unit_id ON unit_aliases(unit_id);
-- CREATE INDEX idx_unit_aliases_normalized ON unit_aliases(raw_unit_normalized);
-- CREATE INDEX idx_reference_ranges_lookup ON reference_ranges(analyte_id, unit_id, sex);
-- CREATE INDEX idx_analyte_cause_rules_lookup ON analyte_cause_rules(analyte_id, direction);

-- ============================================================================
-- POTENTIAL IMPROVEMENTS
-- ============================================================================
-- 1. Добавить UNIQUE constraint на нормализованные алиасы:
--    UNIQUE(analyte_id, raw_name_normalized) для избежания дубликатов
--
-- 2. Создать таблицу condition_aliases (как для analytes и units):
--    CREATE TABLE condition_aliases (
--      id serial PRIMARY KEY,
--      condition_id int REFERENCES conditions(id) ON DELETE CASCADE,
--      raw_condition text NOT NULL,
--      raw_condition_normalized text NOT NULL
--    );
--
-- 3. Добавить audit fields (created_at, updated_at) для отслеживания изменений
