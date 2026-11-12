FROM python:3.12.16-slim-trixie

# No .pyc files in the image; logs go straight to the container output.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Dependencies first: this layer stays cached when only app.py changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy only the code file (nothing else from the build folder gets into the image).
COPY app.py .

# Run as an unprivileged system user created for this app.
RUN useradd --system --no-create-home --shell /usr/sbin/nologin app
USER app

EXPOSE 8000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--access-logfile", "-", "app:app"]
