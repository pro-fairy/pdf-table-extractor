# Pipeline обработки данных

> Последнее обновление: 2026-02-15

## Общая схема (Full version)

```
1. Загрузка PDF
2. Парсинг файла
3. Нормализация JSON
4. PostgreSQL логика
5. Вывод JSON с причинами
6. Вывод клиенту в "человеческом" виде
```

## Детальный pipeline (MVP)

### Этап 1: Загрузка PDF
- Клиент загружает PDF через сайт (Tilda)
- Endpoint: POST /extract
- Принимаем только оригинальные PDF (не сканы)

### Этап 2: Парсинг файла
- Текущая реализация: app/main.py (Camelot + pdfplumber)
- Двойная стратегия: lattice → stream (fallback)

**Извлекаем из шапки (MVP):**
- Имя пациента
- Пол пациента

**Извлекаем из таблицы (для каждого параметра):**
- Название параметра (raw_name)
- Результат (value)
- Единица измерения (unit)

**НЕ извлекаем (MVP):**
- Референсные значения из PDF (у нас свои в БД)
- Возраст (не используется в MVP)
- Состояния (беременность и т.д.)

**Обрезаем при парсинге:**
- Символы ▲ и ▼ (сами определяем HIGH/LOW)

**Выход этапа 2:**
```json
{
  "patient": {
    "name": "Козловская Анастасия Викторовна",
    "sex": "female"
  },
  "analytes": [
    {"raw_name": "Гемоглобин (Hb)", "value": "143.00", "unit": "г/л"},
    {"raw_name": "Эритроциты (RBC)", "value": "4.24", "unit": "10¹²/л"}
  ]
}
```

### Этап 3: Нормализация

**3a. Нормализация названий показателей:**
```
raw_name из PDF → analyte_aliases.raw_name_normalized → analyte_id
```
Пример: "Гемоглобин (Hb)" → normalized: "гемоглобинhb" → analyte_id=5

**3b. Нормализация единиц измерения:**
```
unit из PDF → unit_aliases → проверяем: базовая или нет?
  → Если базовая → используем value как есть
  → Если не базовая → конвертируем: value × коэффициент
```
Пример: Гемоглобин в ммоль/л → конвертируем в г/л

**3c. Нормализация пола:**
```
"Муж." / "М" / "мужской" → "male"
"Жен." / "Ж" / "женский" → "female"
```

**Выход этапа 3:**
```json
{
  "patient": {
    "name": "Козловская Анастасия Викторовна",
    "sex": "female"
  },
  "analytes": [
    {"analyte_id": 5, "value": 143.0, "unit_id": 3},
    {"analyte_id": 2, "value": 4.24, "unit_id": 7}
  ]
}
```

### Этап 4: PostgreSQL логика

**4a. Поиск референса:**
```sql
SELECT ref_min, ref_max
FROM reference_ranges
WHERE analyte_id = ? AND sex = ? (или 'any')
```
В MVP: без age и conditions.

**4b. Сравнение с допуском ±5%:**
```
effective_max = ref_max × 1.05
effective_min = ref_min × 0.95

value > effective_max → HIGH
value < effective_min → LOW
иначе → NORMAL
```

**4c. Поиск причин (для HIGH/LOW):**
```sql
SELECT acr.cause_id, acr.weight, c.code, c.name_ru, c.description, c.severity_level
FROM analyte_cause_rules acr
JOIN causes c ON c.id = acr.cause_id
WHERE acr.analyte_id = ? AND acr.direction = ?  -- 'HIGH' или 'LOW'
```

**4d. Агрегация весов:**
Суммируем weight для одинаковых cause_id по всем отклонённым показателям.

### Этап 5: Формирование JSON с причинами

```json
{
  "patient": {
    "name": "Козловская Анастасия Викторовна",
    "sex": "female"
  },
  "deviations": [
    {"analyte_code": "hemoglobin", "analyte_name_ru": "Гемоглобин", "direction": "HIGH", "value": 165.0, "ref_min": 117.0, "ref_max": 155.0}
  ],
  "causes": [
    {
      "code": "inflammation",
      "name_ru": "Воспаление",
      "description": "Описание и рекомендации...",
      "severity_level": "MEDIUM",
      "total_weight": 1.4,
      "contributing_analytes": [
        {"code": "hemoglobin", "name_ru": "Гемоглобин", "direction": "HIGH"},
        {"code": "wbc", "name_ru": "Лейкоциты", "direction": "HIGH"}
      ]
    }
  ]
}
```

### Этап 6: Вывод клиенту

JSON из этапа 5 обрабатывается AI-агентом или шаблонизатором для формирования красивого, понятного текста.

**Используемые поля для вывода:**
- `causes.name_ru` — название причины (заголовок)
- `causes.description` — описание причины (что это, что делать)
- `contributing_analytes` — какие показатели повлияли
- `severity_level` — для сортировки по важности

## Таблицы БД, участвующие в каждом этапе

| Этап | Таблицы |
|------|---------|
| 3a. Нормализация названий | analytes, analyte_aliases |
| 3b. Нормализация единиц | units, unit_aliases |
| 4a. Поиск референса | reference_ranges |
| 4c. Поиск причин | analyte_cause_rules, causes |

**НЕ используются в MVP:**
- conditions
- reference_range_conditions
