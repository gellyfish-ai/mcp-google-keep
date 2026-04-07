FROM python:3.12-slim

WORKDIR /app

# Install deps first for layer caching
COPY pyproject.toml README.md LICENSE ./
COPY src/ src/
RUN pip install --no-cache-dir .

# Non-root user
RUN useradd -r -s /bin/false mcp
USER mcp

ENV HOST=0.0.0.0
ENV PORT=8204
ENV MCP_TRANSPORT=sse

EXPOSE 8204

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8204/sse')" || exit 1

CMD ["python", "-m", "server"]
