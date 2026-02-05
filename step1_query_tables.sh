#!/bin/bash

# 第一步：读取 config.toml 并连接数据库查询大于10亿的表

set -e  # 遇到错误立即退出

CONFIG_FILE="./syncdiff_config2/config.toml"
OUTPUT_DIR="./syncdiff_config2"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 密码解密函数（base64）
decrypt_password() {
    local encrypted="$1"

    if [ -z "$encrypted" ]; then
        echo ""
        return
    fi

    # 尝试 base64 解密
    local decrypted=$(echo "$encrypted" | base64 -d 2>&1)
    local decrypt_status=$?

    if [ $decrypt_status -eq 0 ] && [ -n "$decrypted" ]; then
        echo "$decrypted"
    else
        # 解密失败，返回原值（可能已经是明文）
        echo "$encrypted"
    fi
}

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "配置文件不存在: $CONFIG_FILE"
    exit 1
fi

# 检查 mysql 客户端是否存在
if ! command -v mysql &> /dev/null; then
    log_error "mysql 客户端未安装，请先安装 mysql 客户端"
    log_error "macOS: brew install mysql-client"
    log_error "Ubuntu: sudo apt-get install mysql-client"
    exit 1
fi

log_info "读取配置文件: $CONFIG_FILE"

# 读取配置文件中的变量
MASTER_IP=$(grep "^master_ip" "$CONFIG_FILE" | cut -d'"' -f2)
MASTER_PORT=$(grep "^master_port" "$CONFIG_FILE" | awk '{print $3}')
MASTER_USER=$(grep "^master_user" "$CONFIG_FILE" | cut -d'"' -f2)
MASTER_PASSWORD_ENCRYPTED=$(grep "^master_password" "$CONFIG_FILE" | cut -d'"' -f2)
MASTER_PASSWORD=$(decrypt_password "$MASTER_PASSWORD_ENCRYPTED")

SLAVE_IP=$(grep "^slave_ip" "$CONFIG_FILE" | cut -d'"' -f2)
SLAVE_PORT=$(grep "^slave_port" "$CONFIG_FILE" | awk '{print $3}')
SLAVE_USER=$(grep "^slave_user" "$CONFIG_FILE" | cut -d'"' -f2)
SLAVE_PASSWORD_ENCRYPTED=$(grep "^slave_password" "$CONFIG_FILE" | cut -d'"' -f2)
SLAVE_PASSWORD=$(decrypt_password "$SLAVE_PASSWORD_ENCRYPTED")

# 调试：显示解密后的密码（只显示前几个字符，隐藏其余）
if [ -n "$MASTER_PASSWORD" ]; then
    log_info "主库密码解密: ${MASTER_PASSWORD:0:4}****"
else
    log_error "主库密码为空，请检查配置"
fi

if [ -n "$SLAVE_PASSWORD" ]; then
    log_info "备库密码解密: ${SLAVE_PASSWORD:0:4}****"
else
    log_error "备库密码为空，请检查配置"
fi

CHECK_SQL=$(grep "^check_sql" "$CONFIG_FILE" | cut -d'"' -f2)
THREAD_COUNT=$(grep "^thread_count" "$CONFIG_FILE" | awk '{print $3}')
CHUNK_SIZE=$(grep "^chunk_size" "$CONFIG_FILE" | awk '{print $3}')
OUTPUT_DIR=$(grep "^output_dir" "$CONFIG_FILE" | cut -d'"' -f2)

# 验证必需的配置项
if [ -z "$MASTER_IP" ] || [ -z "$MASTER_PORT" ] || [ -z "$MASTER_USER" ] || [ -z "$CHECK_SQL" ]; then
    log_error "配置文件中缺少必要的配置项"
    exit 1
fi

log_info "配置信息:"
log_info "  主库: ${MASTER_USER}@${MASTER_IP}:${MASTER_PORT}"
log_info "  备库: ${SLAVE_USER}@${SLAVE_IP}:${SLAVE_PORT}"
log_info "  检查线程数: ${THREAD_COUNT}"
log_info "  Chunk大小: ${CHUNK_SIZE}"

# 连接数据库并执行查询
log_info "连接主库并执行查询..."

# 将查询结果保存到临时文件
TEMP_RESULT_FILE=$(mktemp)

mysql -h "$MASTER_IP" -P "$MASTER_PORT" -u "$MASTER_USER" -p"$MASTER_PASSWORD" \
    --default-character-set=utf8mb4 --skip-column-names -N -e "$CHECK_SQL" \
    > "$TEMP_RESULT_FILE" 2>&1

if [ $? -ne 0 ]; then
    log_error "数据库查询失败:"
    cat "$TEMP_RESULT_FILE"
    rm -f "$TEMP_RESULT_FILE"
    exit 1
fi

# 检查查询结果
if [ ! -s "$TEMP_RESULT_FILE" ]; then
    log_warn "查询结果为空，没有找到大于10亿的表"
    rm -f "$TEMP_RESULT_FILE"
    exit 0
fi

# 生成结果文件（schema_name\ttable_name）
RESULT_FILE="./syncdiff_config2/query_results.txt"

# 清空结果文件
> "$RESULT_FILE"

# 处理查询结果（只取前两列：schema_name, table_name）
TABLE_COUNT=0
while IFS=$'\t' read -r schema_name table_name rows; do
    # 跳过 MySQL 警告行
    if [[ "$schema_name" == mysql:* ]]; then
        continue
    fi
    echo "${schema_name}	${table_name}" >> "$RESULT_FILE"
    log_info "  - ${schema_name}.${table_name}"
    TABLE_COUNT=$((TABLE_COUNT + 1))
done < "$TEMP_RESULT_FILE"

log_info "找到 $TABLE_COUNT 个需要检查的表"

# 清理临时文件
rm -f "$TEMP_RESULT_FILE"

log_info "查询完成，结果已保存到: $RESULT_FILE"

# 输出查询结果到标准输出，方便其他脚本使用
cat "$RESULT_FILE"
