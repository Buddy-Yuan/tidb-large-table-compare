#!/bin/bash

# 第二步：根据查询结果和模板生成 toml 配置文件

set -e

CONFIG_FILE="./syncdiff_config2/config.toml"
TEMPLATE_FILE="./syncdiff_config2/my_database_users.toml"
QUERY_RESULT_FILE="./syncdiff_config2/query_results.txt"
OUTPUT_DIR="./syncdiff_config2/generated_configs"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

    local decrypted=$(echo "$encrypted" | base64 -d 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$decrypted" ]; then
        echo "$decrypted"
    else
        echo "$encrypted"
    fi
}

# 检查模板文件是否存在
if [ ! -f "$TEMPLATE_FILE" ]; then
    log_error "模板文件不存在: $TEMPLATE_FILE"
    exit 1
fi

# 检查查询结果文件是否存在
if [ ! -f "$QUERY_RESULT_FILE" ]; then
    log_error "查询结果文件不存在: $QUERY_RESULT_FILE"
    log_error "请先运行 step1_query_tables.sh 获取查询结果"
    exit 1
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 生成时间戳
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
log_info "执行时间戳: $TIMESTAMP"

log_info "读取配置文件..."
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

THREAD_COUNT=$(grep "^thread_count" "$CONFIG_FILE" | awk '{print $3}')
CHUNK_SIZE=$(grep "^chunk_size" "$CONFIG_FILE" | awk '{print $3}')
OUTPUT_DIR_CONFIG=$(grep "^output_dir" "$CONFIG_FILE" | cut -d'"' -f2)

log_info "配置信息:"
log_info "  主库: ${MASTER_USER}@${MASTER_IP}:${MASTER_PORT}"
log_info "  备库: ${SLAVE_USER}@${SLAVE_IP}:${SLAVE_PORT}"
log_info "  基础输出目录: $OUTPUT_DIR_CONFIG"

# 统计需要生成的配置文件数量
TABLE_COUNT=$(wc -l < "$QUERY_RESULT_FILE")
log_info "将生成 $TABLE_COUNT 个 toml 配置文件"
log_info "  每个表的输出目录: {表名}_$TIMESTAMP"
echo ""

# 生成配置文件
CURRENT=0
while IFS=$'\t' read -r schema_name table_name rows; do
    CURRENT=$((CURRENT + 1))
    PROGRESS=$((CURRENT * 100 / TABLE_COUNT))

    # 文件名: schema_name_table_name.toml
    OUTPUT_FILE="$OUTPUT_DIR/${schema_name}_${table_name}.toml"

    # 为每个表创建带时间戳的独立输出目录
    TABLE_OUTPUT_DIR="${OUTPUT_DIR_CONFIG}/${schema_name}_${table_name}_${TIMESTAMP}"

    log_info "[$CURRENT/$TABLE_COUNT] 生成: ${schema_name}.${table_name} -> $OUTPUT_FILE"
    log_info "  输出目录: $TABLE_OUTPUT_DIR"

    # 使用 sed 替换模板中的变量
    sed -e "s/{{\.master_ip}}/$MASTER_IP/g" \
        -e "s/{{\.master_port}}/$MASTER_PORT/g" \
        -e "s/{{\.master_user}}/$MASTER_USER/g" \
        -e "s/{{\.master_password}}/$MASTER_PASSWORD/g" \
        -e "s/{{\.slave_ip}}/$SLAVE_IP/g" \
        -e "s/{{\.slave_port}}/$SLAVE_PORT/g" \
        -e "s/{{\.slave_user}}/$SLAVE_USER/g" \
        -e "s/{{\.slave_password}}/$SLAVE_PASSWORD/g" \
        -e "s/{{\.thread_count}}/$THREAD_COUNT/g" \
        -e "s/{{\.chunk_size}}/$CHUNK_SIZE/g" \
        -e "s|{{\.output_dir}}|$TABLE_OUTPUT_DIR|g" \
        -e "s/my_database\.users/${schema_name}.${table_name}/g" \
        "$TEMPLATE_FILE" > "$OUTPUT_FILE"

    if [ $? -eq 0 ]; then
        log_info "  ✓ 生成成功"
    else
        log_error "  ✗ 生成失败"
        exit1
    fi
    echo ""
done < "$QUERY_RESULT_FILE"

log_info "所有配置文件生成完成，保存在目录: $OUTPUT_DIR"
log_info "时间戳: $TIMESTAMP"
log_info "可以重复执行，每次使用新的时间戳目录"
echo ""

# 输出生成的文件列表
echo "生成的配置文件列表:"
ls -lh "$OUTPUT_DIR"/*.toml 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
