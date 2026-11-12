"""Counter service: keeps the page hit counter in Redis."""

import os

import redis
from flask import Flask

app = Flask(__name__)

# The Redis host comes from the environment; the default is the Compose service name.
# Timeouts are 1s so the whole call stays under web's 2s timeout.
# retry=None: no automatic retries. A retried INCR could count one hit twice.
db = redis.Redis(
    host=os.environ.get("REDIS_HOST", "redis"),
    socket_timeout=1,
    socket_connect_timeout=1,
    retry=None,
)


@app.post("/hit")
def hit():
    """Add one hit and return the new total. INCR is atomic in Redis."""
    try:
        count = db.incr("hits")
    except redis.RedisError:
        app.logger.exception("Redis call failed")
        return {"error": "Redis unavailable"}, 503
    return {"count": count}


@app.get("/healthz")
def healthz():
    """Liveness check for the Docker healthcheck. Does not touch Redis."""
    return "ok"
