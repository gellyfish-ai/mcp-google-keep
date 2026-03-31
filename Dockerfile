FROM python:3.12-slim

WORKDIR /app

COPY pyproject.toml .
COPY src/ src/
COPY README.md .
COPY LICENSE .

RUN pip install --no-cache-dir .

ENV HOST=0.0.0.0
ENV PORT=8204
ENV MCP_TRANSPORT=sse

EXPOSE 8204

CMD ["python", "-m", "server"]
