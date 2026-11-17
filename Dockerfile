# syntax=docker/dockerfile:1.7
FROM python:3.12.16-slim-trixie

ARG VERSION=dev
ARG COMMIT_SHA=unknown
LABEL org.opencontainers.image.title="encontros-tech" \
      org.opencontainers.image.source="https://github.com/KubeDev/encontros-tech" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${COMMIT_SHA}"

ENV PATH="/app/.venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0 \
    UV_NO_INSTALLER_METADATA=1

RUN groupadd --system --gid 1001 app && \
    useradd --system --uid 1001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

# uv e o lockfile entram só como mount: não ficam em nenhuma camada da imagem
RUN --mount=from=ghcr.io/astral-sh/uv:0.13.8,source=/uv,target=/bin/uv \
    --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-dev --no-install-project

COPY --chown=app:app src/ /app/src/

WORKDIR /app/src
USER app

EXPOSE 8000

# Checagem TCP, espelhando o tcpSocket do Kubernetes: "/" consulta o banco (ADR 004)
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
  CMD ["python", "-c", "import socket; socket.create_connection(('127.0.0.1', 8000), timeout=2).close()"]

ENTRYPOINT ["gunicorn"]
CMD ["--bind", "0.0.0.0:8000", "--workers", "2", "--worker-class", "sync", "--access-logfile", "-", "main:app"]
