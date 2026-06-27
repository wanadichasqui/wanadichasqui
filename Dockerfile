# --- Stage 1: Builder ---
FROM rust:1.80-slim-bookworm AS builder

# Instalar dependencias necesarias para compilar dependencias C (como sqlite/ring si hiciera falta)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/wanadi-chasqui

# Copiar el código fuente completo del workspace
COPY . .

# Compilar el binario del mix‑node en modo release
RUN cargo build --release --bin mix_node

# --- Stage 2: Runtime ---
FROM debian:bookworm-slim

# Instalar dependencias de ejecución básicas (como ca-certificates)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Crear directorio de datos para la base de datos sqlite
RUN mkdir -p /data

# Copiar el binario construido desde la etapa de compilación
COPY --from=builder /usr/src/wanadi-chasqui/target/release/mix_node /usr/local/bin/mix_node

# Exponer el puerto por defecto
EXPOSE 8000

# Parámetros de entorno por defecto
ENV WANADI_HOST=0.0.0.0
ENV WANADI_PORT=8000
ENV WANADI_BLOB_DB=/data/mix_node_blobs.db

# Volumen persistente para almacenamiento local de blobs
VOLUME ["/data"]

# Comando de ejecución
CMD ["/usr/local/bin/mix_node"]
