FROM python:3.13.18-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY data_probe.py .

# Amazon's public RDS root certificates, to verify the database's TLS certificate; the checksum
# pins the content, and --chmod makes it readable by the non-root user. The directory already
# exists, because --chmod would also apply to any parent it had to create.
ADD --chmod=644 --checksum=sha256:90a6f1a7978a1b1b096dca6c57511ca48d3b8cf052f8e704baf358f34ea2f21b \
    https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /etc/ssl/certs/rds-global-bundle.pem

USER 10001
ENTRYPOINT ["python", "data_probe.py"]
