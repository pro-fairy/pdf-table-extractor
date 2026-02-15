# Архитектура базы данных

> Последнее обновление: 2026-02-15
> DDL схема: database/schema.sql

## Подключение

- **Сервер:** 165.227.175.252
- **Контейнер:** medical-postgres (PostgreSQL 15)
- **БД:** medical_analysis_mvp
- **User:** medical_user
- **Инструмент управления:** DBeaver (у Ивана на MacBook)

## Обзор таблиц (9 штук)

### Активно используются в MVP:

| Таблица | Описание | Роль в MVP |
|---------|----------|------------|
| `analytes` | Справочник показателей | Нормализация названий |
| `analyte_aliases` | Альтернативные названия | Fuzzy matching из PDF |
| `units` | Справочник единиц измерения | Определение базовой единицы |
| `unit_aliases` | Альтернативные единицы | Определение + конвертация |
| `reference_ranges` | Референсные значения (нормы) | Сравнение (только по полу в MVP) |
| `causes` | Причины отклонений | Вывод клиенту |
| `analyte_cause_rules` | Связь показатель → причина | Медицинская логика (веса) |

### НЕ используются в MVP:

| Таблица | Описание | Почему отложена |
|---------|----------|-----------------|
| `conditions` | Состояния пациента | Большинство PDF не содержат состояний |
| `reference_range_conditions` | Связь референсов с условиями | Зависит от conditions |

## Детальное описание таблиц

### 1. analytes — Справочник показателей
"Какие показатели знает система"

```sql
analytes:
  id          serial PRIMARY KEY
  code        text UNIQUE        -- машинный код (total_bilirubin)
  name_ru     text               -- русское название (Билирубин общий)
  description text               -- описание
```

Примеры: hemoglobin, wbc, rbc, total_bilirubin, alt, ast

### 2. analyte_aliases — Альтернативные названия
"Как показатель может называться в реальных PDF"

```sql
analyte_aliases:
  id                    serial PRIMARY KEY
  analyte_id            int FK → analytes(id) CASCADE
  raw_name              text    -- как в PDF ("Гемоглобин (Hb)")
  raw_name_normalized   text    -- нормализованное ("гемоглобинhb")
```

Связь многие-к-одному: несколько raw_name → один analyte_id.
Пример:
- "Билирубин общий" → total_bilirubin
- "Общий билирубин" → total_bilirubin
- "Total Bilirubin" → total_bilirubin

### 3. units — Справочник единиц измерения
"Какие единицы понимает система"

```sql
units:
  id          serial PRIMARY KEY
  code        text UNIQUE        -- машинный код (g_l, umol_l)
  name_ru     text               -- русское название (г/л)
  description text               -- описание
```

### 4. unit_aliases — Альтернативные единицы
"Как единица может быть написана в PDF"

```sql
unit_aliases:
  id                    serial PRIMARY KEY
  unit_id               int FK → units(id) CASCADE
  raw_unit              text    -- как в PDF ("мкмоль/л")
  raw_unit_normalized   text    -- нормализованное ("мкмольл")
```

**MVP изменение:** планируется добавить поле для конвертации (коэффициент),
чтобы приводить все единицы к базовой. Детали TBD.

### 5. reference_ranges — Референсные значения
"Медицинская норма для конкретных условий"

```sql
reference_ranges:
  id          serial PRIMARY KEY
  analyte_id  int FK → analytes(id)
  unit_id     int FK → units(id)    -- в MVP всегда базовая единица
  sex         text CHECK (male/female/any)
  age_min     int NULL              -- не используется в MVP
  age_max     int NULL              -- не используется в MVP
  ref_min     numeric               -- нижняя граница нормы
  ref_max     numeric               -- верхняя граница нормы
```

**MVP:** поиск только по analyte_id + sex. Поля age_min/age_max оставлены для будущего.

### 6. causes — Причины отклонений
"Что может вызывать отклонения"

```sql
causes:
  id              serial PRIMARY KEY
  code            text UNIQUE        -- машинный код (liver_dysfunction)
  name_ru         text               -- UI-название ("Нарушение функции печени")
  description     text               -- описание для клиента
  severity_level  text CHECK (LOW/MEDIUM/HIGH/CRITICAL)
```

**Важные поля для вывода клиенту:**
- `name_ru` — заголовок причины
- `description` — описание + рекомендации
- `severity_level` — для сортировки по важности

### 7. analyte_cause_rules — Медицинская логика
"Если показатель X повышен/понижен → возможна причина Y с весом W"

```sql
analyte_cause_rules:
  id          serial PRIMARY KEY
  analyte_id  int FK → analytes(id)
  direction   text CHECK (HIGH/LOW)
  cause_id    int FK → causes(id)
  weight      numeric (0.0-1.0)     -- сила связи
  comment     text                  -- комментарий
```

Для одного analyte_id + direction может быть НЕСКОЛЬКО причин.
Пример:
- hemoglobin + HIGH → inflammation (0.6)
- hemoglobin + HIGH → dehydration (0.4)

### 8. conditions — Состояния пациента (НЕ MVP)

```sql
conditions:
  id          serial PRIMARY KEY
  code        text UNIQUE        -- pregnancy, diabetes
  name_ru     text
  description text
```

### 9. reference_range_conditions — Связь референсов с условиями (НЕ MVP)

```sql
reference_range_conditions:
  reference_range_id  int FK → reference_ranges(id) CASCADE
  condition_id        int FK → conditions(id) CASCADE
  PRIMARY KEY (reference_range_id, condition_id)
```

## Схема связей

```
analytes ←── analyte_aliases (FK: analyte_id)
units ←── unit_aliases (FK: unit_id)
analytes + units → reference_ranges (FK: analyte_id, unit_id)
reference_ranges ↔ conditions (через reference_range_conditions) [НЕ MVP]
analytes + direction → causes (через analyte_cause_rules)
```

## MVP изменения (запланировано)

1. **Конвертация единиц** — добавить механизм конвертации в базовую единицу (коэффициент)
2. **Убрать unit_id из reference_ranges** — или оставить но всегда базовая единица
3. **age_min/age_max** — оставить в схеме, заполнять NULL в MVP
4. **conditions** — таблицы остаются, но не используются
5. **Индексы** — добавить на FK и нормализованные поля
6. **UNIQUE constraints** — на analyte_aliases(raw_name_normalized), unit_aliases(raw_unit_normalized)

## Текущее состояние данных

На 2026-02-15 все таблицы пустые (0 строк). БД создана, схема развёрнута, данных нет.
Заполнение данными — одна из ключевых задач.

## Историческое примечание

Изначальная архитектура (до 2026-02-15) предусматривала:
- Полный учёт conditions в pipeline
- Разные записи reference_ranges для разных единиц измерения
- Извлечение возраста и состояний из шапки PDF

Упрощено для MVP: только пол, конвертация единиц, без conditions.
