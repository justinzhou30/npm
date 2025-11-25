#!/bin/bash

set -e  # 遇到错误立即退出

# --- 强制指定稳定版本 (不再依赖 API 获取) ---
FIXED_VERSION="v2.29.1"

echo "🧹 [1/5] 清理旧的损坏文件..."
# 这一步非常重要，删除那个包含 "Not Found" 的文本文件
if [ -f /usr/local/bin/docker-compose ]; then
    sudo rm -f /usr/local/bin/docker-compose
    echo "   已删除旧文件"
fi

echo "🚀 [2/5] 检查 Docker 是否安装..."
if ! command -v docker &> /dev/null; then
    echo "🔹 未检测到 Docker，正在安装..."
    curl -fsSL https://get.docker.com | bash
    systemctl enable --now docker
else
    echo "✅ Docker 已安装"
fi

echo "🚀 [3/5] 安装 Docker Compose (Aarch64/x86通用)..."

# 获取架构
ARCH=$(uname -m)
case $ARCH in
    x86_64|amd64)
        COMPOSE_ARCH="x86_64"
        ;;
    aarch64|arm64)
        COMPOSE_ARCH="aarch64"
        ;;
    *)
        echo "❌ 致命错误：不支持的架构 $ARCH"
        exit 1
        ;;
esac

echo "🔹 识别架构为: $COMPOSE_ARCH"
echo "🔹 使用版本: $FIXED_VERSION"

# 构造下载链接
DOWNLOAD_URL="https://github.com/docker/compose/releases/download/$FIXED_VERSION/docker-compose-linux-$COMPOSE_ARCH"

echo "⬇️ 正在下载: $DOWNLOAD_URL"

# 关键修改：
# -L: 允许跳转
# -f: 如果是 404 错误，直接失败，不要写入文件！
if sudo curl -L -f "$DOWNLOAD_URL" -o /usr/local/bin/docker-compose; then
    sudo chmod +x /usr/local/bin/docker-compose
    echo "✅ 下载成功"
else
    echo "❌ 下载失败！可能是网络连接 GitHub 困难。"
    echo "   尝试使用 Docker 插件版作为替代..."
    
    # 备选方案：如果是 Linux，docker 官方脚本通常已经安装了 docker-compose-plugin
    if docker compose version &> /dev/null; then
        echo "🔹 检测到系统原生 docker compose 插件，创建别名..."
        echo '#!/bin/bash' > /usr/local/bin/docker-compose
        echo 'docker compose "$@"' >> /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        echo "✅ 已通过别名修复"
    else
        echo "❌ 无法安装 Docker Compose，请检查网络。"
        exit 1
    fi
fi

# 再次验证
echo "🔎 验证安装..."
if /usr/local/bin/docker-compose version; then
    echo "✅ 验证通过！"
else
    echo "❌ 验证失败，文件可能依然损坏。"
    exit 1
fi

echo "🚀 [4/5] 创建 Nginx Proxy Manager 目录..."
mkdir -p /etc/docker/npm
cd /etc/docker/npm

# --- 交互输入 ---
read -rp "请输入 HTTP 端口（默认80）: " PORT_HTTP
PORT_HTTP=${PORT_HTTP:-80}

read -rp "请输入 管理面板端口（默认81）: " PORT_PANEL
PORT_PANEL=${PORT_PANEL:-81}

read -rp "请输入 HTTPS 端口（默认443）: " PORT_HTTPS
PORT_HTTPS=${PORT_HTTPS:-443}

echo "🚀 [5/5] 生成并启动..."
cat > docker-compose.yml <<EOF
services:
  npm:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '${PORT_HTTP}:80'
      - '${PORT_PANEL}:81'
      - '${PORT_HTTPS}:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF

# 网络优化
if [ -f /etc/gai.conf ]; then
    sed -i 's/^#\s*precedence ::ffff:0:0\/96 100/precedence ::ffff:0:0\/96 100/' /etc/gai.conf || true
else
    echo "precedence ::ffff:0:0/96 100" >> /etc/gai.conf
fi
systemctl restart docker || true

/usr/local/bin/docker-compose up -d

echo "========================================"
echo "✅ 全部完成！"
IP=$(hostname -I | awk '{print $1}')
echo "🔹 面板地址: http://${IP}:$PORT_PANEL"
echo "========================================"
