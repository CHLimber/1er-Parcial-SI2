FROM python:3.12-slim

# Sin esto, stdout se bufferea en bloques de 4KB adentro del contenedor (no es una TTY) y los
# print() de app/core/db.py y app/core/jobs.py tardan en aparecer en `docker compose logs`.
ENV PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

EXPOSE 8000

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
