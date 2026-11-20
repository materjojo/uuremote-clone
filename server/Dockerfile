FROM python:3.12-slim
WORKDIR /app
COPY server/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY server /app/server
USER 65534:65534
ENV UU_BIND=0.0.0.0 UU_PORT=8080
EXPOSE 8080
CMD ["python", "-m", "server.rendezvous"]
