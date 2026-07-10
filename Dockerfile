FROM python:3.15-rc-alpine

WORKDIR /app

COPY app.py /app

ENV LOG_FORMAT=json \
    MIN_INTERVAL=0.2 \
    MAX_INTERVAL=2.0 \
    ERROR_RATE=0.08 \
    WARN_RATE=0.15

RUN adduser -D loggen

USER loggen

ENTRYPOINT ["python", "app.py"]