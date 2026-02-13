from fastapi import FastAPI, UploadFile, File
import camelot
import tempfile
import os
import pandas as pd

app = FastAPI()228


def normalize(text: str) -> str:
    if not isinstance(text, str):
        return ""
    return text.strip().lower()


def find_header_row(df: pd.DataFrame):
    """
    Ищем строку, где есть слово 'Параметр'
    """
    for idx, row in df.iterrows():
        joined = " ".join(str(cell) for cell in row)
        if "параметр" in joined.lower():
            return idx
    return None


def detect_columns(columns):
    """
    Определяем индексы колонок: имя / значение / единица
    """
    name_col = value_col = unit_col = None

    for i, col in enumerate(columns):
        col_norm = normalize(col)

        if "параметр" in col_norm:
            name_col = i
        elif "результ" in col_norm:
            value_col = i
        elif "ед" in col_norm or "изм" in col_norm:
            unit_col = i

    return name_col, value_col, unit_col


def merge_multiline_rows(df: pd.DataFrame, name_col: int, value_col: int, unit_col: int):
    """
    Объединяет многострочные ячейки в одну запись
    """
    merged_rows = []
    i = 0
    
    while i < len(df):
        row = df.iloc[i]
        name = str(row.iloc[name_col]).strip()
        value = str(row.iloc[value_col]).strip() if value_col is not None else ""
        unit = str(row.iloc[unit_col]).strip() if unit_col is not None else ""
        
        # Пропускаем пустые имена
        if not name or name.lower() == "nan":
            i += 1
            continue
        
        # Если значение пустое, смотрим следующую строку
        if not value or value.lower() == "nan":
            # Проверяем следующую строку
            if i + 1 < len(df):
                next_row = df.iloc[i + 1]
                next_name = str(next_row.iloc[name_col]).strip()
                next_value = str(next_row.iloc[value_col]).strip() if value_col is not None else ""
                next_unit = str(next_row.iloc[unit_col]).strip() if unit_col is not None else ""
                
                # Если следующая строка - продолжение (имя пустое, но есть значение)
                if (not next_name or next_name.lower() == "nan") and next_value and next_value.lower() != "nan":
                    value = next_value
                    if not unit or unit.lower() == "nan":
                        unit = next_unit
                    i += 2  # Пропускаем обе строки
                    merged_rows.append({"name": name, "value": value, "unit": unit})
                    continue
        
        # Обычная строка с полными данными
        if value and value.lower() != "nan":
            merged_rows.append({"name": name, "value": value, "unit": unit})
        
        i += 1
    
    return merged_rows


def extract_with_flavor(pdf_path: str, flavor: str):
    analytes = []

    tables = camelot.read_pdf(
        pdf_path,
        pages="all",
        flavor=flavor
    )

    print(f"\n📄 CAMELOT [{flavor.upper()}]: tables found = {len(tables)}")

    for table_index, table in enumerate(tables):
        df = table.df

        print(f"\n================ TABLE {table_index} RAW [{flavor}] =================")
        print(df.head(10))
        print("RAW COLUMNS:", df.columns.tolist())

        header_row = find_header_row(df)

        if header_row is None:
            print("❌ HEADER ROW WITH 'Параметр' NOT FOUND")
            continue

        new_header = df.iloc[header_row]
        data_df = df.iloc[header_row + 1:].copy()
        data_df.columns = new_header
        
        # Сбрасываем индекс для корректной работы iloc
        data_df = data_df.reset_index(drop=True)

        print(f"\n=========== TABLE {table_index} AFTER HEADER [{flavor}] =============")
        print(data_df.head(10))

        name_col, value_col, unit_col = detect_columns(data_df.columns)

        print("➡️ COLUMN MATCHING:")
        print(f"   name_col = {name_col}")
        print(f"   value_col = {value_col}")
        print(f"   unit_col = {unit_col}")

        if name_col is None or value_col is None:
            print("❌ REQUIRED COLUMNS NOT FOUND")
            continue

        # Объединяем многострочные записи
        merged_data = merge_multiline_rows(data_df, name_col, value_col, unit_col)
        
        for item in merged_data:
            analytes.append({
                "raw_name": item["name"],
                "value": item["value"],
                "unit": item["unit"]
            })

        print(f"✅ ANALYTES FOUND IN TABLE {table_index} [{flavor}]: {len(merged_data)}")

    print(f"\n🧪 TOTAL ANALYTES FOUND [{flavor.upper()}] = {len(analytes)}")
    return analytes


@app.post("/extract")
async def extract(file: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tmp:
        tmp.write(await file.read())
        pdf_path = tmp.name

    try:
        # 1️⃣ Пробуем lattice
        lattice_analytes = extract_with_flavor(pdf_path, flavor="lattice")

        if len(lattice_analytes) >= 10:
            print("🟢 USING LATTICE RESULT")
            return {
                "count": len(lattice_analytes),
                "analytes": lattice_analytes,
                "method": "lattice"
            }

        # 2️⃣ fallback на stream
        stream_analytes = extract_with_flavor(pdf_path, flavor="stream")

        print("🟡 USING STREAM RESULT")
        return {
            "count": len(stream_analytes),
            "analytes": stream_analytes,
            "method": "stream"
        }

    finally:
        os.remove(pdf_path)