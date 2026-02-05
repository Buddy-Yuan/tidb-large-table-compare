#!/bin/bash

# 从 config.toml 生成 my_database_users.toml
# 读取 config.toml 中的配置，替换到 my_database_users.toml 模板

CONFIG_FILE="./syncdiff_config2/config.toml"
OUTPUT_FILE="./syncdiff_config2/my_database_users.toml"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件不存在: $CONFIG_FILE"
    exit 1
fi

# 读取配置文件中的变量
MASTER_IP=$(grep "^master_ip" "$CONFIG_FILE" | cut -d'"' -f2)
MASTER_PORT=$(grep "^master_port" "$CONFIG_FILE" | awk '{print $3}')
MASTER_USER=$(grep "^master_user" "$CONFIG_FILE" | cut -d'"' -f2)
MASTER_PASSWORD=$(grep "^master_password" "$CONFIG_FILE" | cut -d'"' -f2)

SLAVE_IP=$(grep "^slave_ip" "$CONFIG_FILE" | cut -d'"' -f2)
SLAVE_PORT=$(grep "^slave_port" "$CONFIG_FILE" | awk '{print $3}')
SLAVE_USER=$(grep "^slave_user" "$CONFIG_FILE" | cut -d'"' -f2)
SLAVE_PASSWORD=$(grep "^slave_password" "$CONFIG_FILE" | cut -d'"' -f2)

CHECK_SQL=$(grep "^check_sql" "$CONFIG_FILE" | cut -d'"' -f2)
THREAD_COUNT=$(grep "^thread_count" "$CONFIG_FILE" | awk '{print $3}')
CHUNK_SIZE=$(grep "^chunk_size" "$CONFIG_FILE" | awk '{print $3}')
EXPORT_FIX_SQL=$(grep "^export_fix_sql" "$CONFIG_FILE" | awk '{print $3}')
OUTPUT_DIR=$(grep "^output_dir" "$CONFIG_FILE" | cut -d'"' -f2)

# 从 SQL 中提取数据库名和表名
TABLE_NAME=$(echo "$CHECK_SQL" | grep -oP 'FROM\s+\K[\w.]+' | head -1)
DATABASE=$(echo "$TABLE_NAME" | cut -d'.' -f1)
TABLE=$(echo "$TABLE_NAME" | cut -d'.' -f2)

if [ "$DATABASE" == "$TABLE" ] || [ -z "$DATABASE" ]; then
    DATABASE="my_database"
    TABLE="users"
fi

# 生成 my_database_users.toml
cat > "$OUTPUT_FILE" << EOF
# Diff Configuration for $DATABASE.$TABLE
# 从 config.toml 自动生成

######################### Global config #########################
check-thread-count = $THREAD_COUNT

export-fix-sql = $EXPORT_FIX_SQL

check-struct-only = false

######################### Datasource config #########################
[data-sources]
[data-sources.tidbmaster]
    host = "$MASTER_IP"
    port = $MASTER_PORT
    user = "$MASTER_USER"
    password = "$MASTER_PASSWORD"
    snapshot = "auto"
    sql-hint-use-index = "auto"
    session.tidb_opt_prefer_range_scan = 1

[data-sources.tidbbak]
    host = "$SLAVE_IP"
    port = $SLAVE_PORT
    user = "$SLAVE_USER"
    password = "$SLAVE_PASSWORD"
    snapshot = "auto"
    sql-hint-use-index = "auto"
    session.tidb_opt_prefer_range_scan = 1
    session.tidb_enable_external_ts_read = 0

######################### Task config #########################
[task]
    output-dir = "$OUTPUT_DIR"
    source-instances = ["tidbmaster"]
    target-instance = "tidbbak"
    target-check-tables = ["$DATABASE.$TABLE"]
    target-configs = ["config1"]

[table-configs.config1]
    target-tables = ["$DATABASE.$TABLE"]
    chunk-size = $CHUNK_SIZE
    range = "1 = 1"
EOF

echo "✅ 已从 config.toml 生成 my_database_users.toml"
echo ""
echo "配置信息:"
echo "  主库: $MASTER_USER@$MASTER_IP:$MASTER_PORT"
echo "  备库: $SLAVE_USER@$SLAVE_IP:$SLAVE_PORT"
echo "  SQL: $CHECK_SQL"
echo "  线程数: $THREAD_COUNT"
echo ""
echo "生成的文件: $OUTPUT_FILE"
