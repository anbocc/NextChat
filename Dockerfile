# 第一阶段：基础镜像
FROM node:18-alpine AS base

# 第二阶段：安装 Node.js 依赖
FROM base AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn config set registry 'https://registry.npmmirror.com/' && \
    yarn install

# 第三阶段：Python 依赖安装
FROM python:3.12-alpine AS py-deps
WORKDIR /app
COPY requirements.txt .
RUN apk add --no-cache gcc musl-dev python3-dev && \
    pip install --no-cache-dir -r requirements.txt

# 第四阶段：前端构建
FROM base AS builder
RUN apk update && apk add --no-cache git
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN yarn build

# 第五阶段：最终运行镜像
FROM base AS runner
WORKDIR /app

# 安装运行时依赖
RUN apk add --no-cache \
    python3 \
    py3-pip \
    proxychains-ng \
    libstdc++ \
    && ln -sf python3 /usr/bin/python

# 从构建阶段复制文件
# 1. 复制 Python 依赖
COPY --from=py-deps /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=py-deps /usr/local/bin /usr/local/bin

# 2. 复制 Node.js 构建结果
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.next/server ./.next/server
COPY --from=builder /app/main.py .
COPY --from=builder /app/app/mcp/mcp_config.default.json ./app/mcp/mcp_config.json

# 设置环境变量
ENV PYTHONPATH=/usr/local/lib/python3.12/site-packages \
    PROXY_URL="" \
    OPENAI_API_KEY="" \
    GOOGLE_API_KEY="" \
    CODE="" \
    ENABLE_MCP="true"

# 创建必要目录并设置权限
RUN mkdir -p /app/app/mcp && chmod 777 /app/app/mcp

EXPOSE 3000

# 启动命令（支持代理和直接连接）
CMD if [ -n "$PROXY_URL" ]; then \
    echo "使用代理: $PROXY_URL" && \
    protocol=$(echo $PROXY_URL | cut -d: -f1) && \
    host=$(echo $PROXY_URL | cut -d/ -f3 | cut -d: -f1) && \
    port=$(echo $PROXY_URL | cut -d: -f3) && \
    printf "strict_chain\nproxy_dns\n[ProxyList]\n%s %s %s\n" $protocol $host $port > /etc/proxychains.conf && \
    proxychains -f /etc/proxychains.conf node server.js; \
else \
    echo "直接连接" && \
    python main.py & \
    node server.js; \
fi
