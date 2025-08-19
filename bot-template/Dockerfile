FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    BOT_PORT=8080

WORKDIR /app

# Install system dependencies and uv
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir uv

# Install Python dependencies with uv
COPY pyproject.toml .
RUN uv pip install --system --no-cache -r pyproject.toml

# Copy application
COPY . .

# Create non-root user
RUN useradd -m bot && chown -R bot:bot /app
USER bot

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:${BOT_PORT}/health || exit 1

CMD ["python", "-m", "app"]
