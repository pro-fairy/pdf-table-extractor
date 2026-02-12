FROM python:3.11-slim

RUN apt-get update -o Acquire::ForceIPv4=true && \
    apt-get install -y --no-install-recommends \
        ghostscript \
        python3-tk \
        libgl1 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
