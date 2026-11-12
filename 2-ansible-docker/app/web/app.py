"""Web service: serves the Hello World page and reports each hit to the counter service."""

import http.client
import json
import os
import urllib.request

from flask import Flask

app = Flask(__name__)

# The counter URL comes from the environment; the default uses the Compose service name.
COUNTER_URL = os.environ.get("COUNTER_URL", "http://counter:8000/hit")

# The call to counter is internal, so it must never go through HTTP_PROXY.
NO_PROXY_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))

PAGE = """<!doctype html>
<html>
  <head><title>Hello World</title></head>
  <body>
    <h1>Hello World</h1>
    <p>This page has been viewed {count} times.</p>
  </body>
</html>
"""


@app.get("/")
def index():
    """Count this visit in the counter service and show the total."""
    try:
        hit_request = urllib.request.Request(COUNTER_URL, method="POST")
        with NO_PROXY_OPENER.open(hit_request, timeout=2) as response:
            # int() makes sure only a number is put into the HTML.
            count = int(json.load(response)["count"])
    except (OSError, http.client.HTTPException, ValueError, KeyError, TypeError):
        # OSError: network errors, timeouts, HTTP errors. HTTPException: broken response.
        # ValueError/KeyError/TypeError: response is not {"count": <number>}.
        app.logger.exception("Counter service call failed")
        return "Counter service unavailable", 503
    return PAGE.format(count=count)


@app.get("/healthz")
def healthz():
    """Liveness check for the Docker healthcheck. Does not call the counter."""
    return "ok"
