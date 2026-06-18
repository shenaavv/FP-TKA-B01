FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first (for layer caching)
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app.py .

# Create non-root user for security
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser
USER appuser

# Expose port
EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:5000/health || exit 1

# Run Gunicorn
# Workers formula: (2 x vCPU) + 1 = (2 x 2) + 1 = 5, kita pakai 4 untuk hemat RAM
# Threads: 2 per worker → total concurrency = 4 workers x 2 threads = 8
CMD ["sh", "-c", "gunicorn \
    --workers ${GUNICORN_WORKERS:-4} \
    --threads ${GUNICORN_THREADS:-2} \
    --worker-class ${GUNICORN_WORKER_CLASS:-gthread} \
    --timeout ${GUNICORN_TIMEOUT:-120} \
    --bind 0.0.0.0:5000 \
    --access-logfile - \
    --error-logfile - \
    --log-level info \
    app:app"]
