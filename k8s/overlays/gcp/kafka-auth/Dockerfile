FROM python:3.12.12-slim

RUN useradd --uid 10001 --create-home kafka-auth \
    && pip install --no-cache-dir 'google-auth[requests,urllib3]>=2.40.3,<3'
COPY kafka_gcp_credentials_server.py /opt/kafka-auth/server.py
USER 10001:10001
CMD ["python", "/opt/kafka-auth/server.py"]
