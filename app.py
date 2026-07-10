#!/usr/bin/env python3
"""
Random Log Generator
Generates realistic-looking application/access logs at a configurable rate.
Useful for practicing with Fluentd, Filebeat, Promtail/Loki, ELK, CloudWatch Logs, etc.
"""

import json
import logging
import os
import random
import sys
import time
import uuid
from datetime import datetime, timezone

# ---- Config via environment variables ----
LOG_FORMAT = os.getenv("LOG_FORMAT", "json").lower()       # json | apache | plain
MIN_INTERVAL = float(os.getenv("MIN_INTERVAL", "0.2"))     # seconds between logs
MAX_INTERVAL = float(os.getenv("MAX_INTERVAL", "2.0"))
ERROR_RATE = float(os.getenv("ERROR_RATE", "0.08"))        # probability of ERROR/5xx
WARN_RATE = float(os.getenv("WARN_RATE", "0.15"))          # probability of WARN/4xx
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

SERVICES = ["auth-service", "payment-service", "order-service", "inventory-service", "notification-service", "alert-service"]
ENDPOINTS = ["/api/v1/login", "/api/v1/orders", "/api/v1/payments", "/api/v1/users", "/api/v1/inventory", "/health"]
METHODS = ["GET", "POST", "PUT", "DELETE"]
STATUS_OK = [200, 200, 200, 201, 204]
STATUS_WARN = [400, 401, 403, 404, 429]
STATUS_ERROR = [500, 502, 503, 504]

MESSAGES_INFO = [
    "Request processed successfully",
    "Cache hit for key",
    "User session created",
    "Background job completed",
    "Health check passed",
]
MESSAGES_WARN = [
    "Rate limit approaching threshold",
    "Deprecated endpoint accessed",
    "Retrying failed connection",
    "Slow query detected",
    "Invalid input received",
]
MESSAGES_ERROR = [
    "Database connection timeout",
    "Unhandled exception in request handler",
    "Downstream service unavailable",
    "Payment gateway timeout",
    "Out of memory warning triggered",
]

IPS = [f"10.0.{random.randint(0,5)}.{random.randint(2,254)}" for _ in range(20)]

logger = logging.getLogger("log-generator")

def pick_level():
    r = random.random()
    if r < ERROR_RATE:
        level = "ERROR"
    elif r < ERROR_RATE + WARN_RATE:
        level = "WARN"
    else:
        level = "INFO"

    logger.debug("pick_level() -> %s (r=%0.4f)", level, r)
    return level


def build_json_log():
    level = pick_level()
    status = random.choice(STATUS_ERROR) if level == "ERROR" else (
        random.choice(STATUS_WARN) if level == "WARN" else random.choice(STATUS_OK)
    )
    message = {
        "ERROR": random.choice(MESSAGES_ERROR),
        "WARN": random.choice(MESSAGES_WARN),
        "INFO": random.choice(MESSAGES_INFO),
    }[level]

    log_record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": level,
        "service": random.choice(SERVICES),
        "trace_id": str(uuid.uuid4()),
        "method": random.choice(METHODS),
        "endpoint": random.choice(ENDPOINTS),
        "status_code": status,
        "latency_ms": round(random.uniform(2, 1200), 2),
        "client_ip": random.choice(IPS),
        "message": message,
    }
    logger.debug("build_json_log() -> %s", log_record)
    return log_record


def build_apache_log():
    ip = random.choice(IPS)
    ts = datetime.now().strftime("%d/%b/%Y:%H:%M:%S +0000")
    method = random.choice(METHODS)
    endpoint = random.choice(ENDPOINTS)
    level = pick_level()
    status = random.choice(STATUS_ERROR) if level == "ERROR" else (
        random.choice(STATUS_WARN) if level == "WARN" else random.choice(STATUS_OK)
    )
    size = random.randint(200, 15000)
    log_line = f'{ip} - - [{ts}] "{method} {endpoint} HTTP/1.1" {status} {size}'
    logger.debug("build_apache_log() -> %s", log_line)
    return log_line


def build_plain_log():
    level = pick_level()
    service = random.choice(SERVICES)
    message = {
        "ERROR": random.choice(MESSAGES_ERROR),
        "WARN": random.choice(MESSAGES_WARN),
        "INFO": random.choice(MESSAGES_INFO),
    }[level]
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"{ts} [{level}] {service}: {message}"
    logger.debug("build_plain_log() -> %s", log_line)
    return log_line


def main():
    log_level = getattr(logging, LOG_LEVEL, logging.INFO)
    logging.basicConfig(stream=sys.stdout, level=log_level, format="%(asctime)s %(levelname)s %(message)s")
    logger.info("Starting log generator | format=%s min_interval=%s max_interval=%s error_rate=%s warn_rate=%s",
                LOG_FORMAT, MIN_INTERVAL, MAX_INTERVAL, ERROR_RATE, WARN_RATE)
    logger.debug("Debug enabled. LOG_LEVEL=%s", LOG_LEVEL)

    while True:
        if LOG_FORMAT == "apache":
            line = build_apache_log()
        elif LOG_FORMAT == "plain":
            line = build_plain_log()
        else:
            line = json.dumps(build_json_log())

        logger.debug("Generated log line: %s", line)
        print(line, flush=True)
        time.sleep(random.uniform(MIN_INTERVAL, MAX_INTERVAL))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
