# Vega API.
#
# Multi-stage so the runtime image carries no build tooling and no uv. The
# service holds HMRC credentials and a database role; the less that ships
# alongside it, the smaller the thing an attacker lands in.

FROM python:3.12-slim-bookworm AS builder

COPY --from=ghcr.io/astral-sh/uv:0.5 /uv /usr/local/bin/uv

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /app

# Dependencies first, in their own layer: they change far less often than the
# source, so a code change does not reinstall the world.
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --no-dev

COPY src ./src
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev


FROM python:3.12-slim-bookworm AS runtime

# Not root. A container process that does not need to write to its own image
# should not be able to.
RUN groupadd --system vega && useradd --system --gid vega --create-home vega

WORKDIR /app
COPY --from=builder --chown=vega:vega /app/.venv /app/.venv
COPY --from=builder --chown=vega:vega /app/src /app/src

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER vega
EXPOSE 8080

# /health deliberately does not touch the database, so a slow query cannot take
# the service out of rotation for the wrong reason.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=4).status==200 else 1)"

CMD ["uvicorn", "vega_api.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080"]
