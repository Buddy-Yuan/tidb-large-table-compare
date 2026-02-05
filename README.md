# SyncDiff 配置生成工具

自动从 TiDB 数据库查询大表并生成 syncdiff 配置文件。

## 功能说明

1. **步骤1**: 读取 `config.toml`，连接主库执行 `check_sql`，查询大于10亿行的表
2. **步骤2**: 根据查询结果和模板，为每个表生成独立的 toml 配置文件
3. **主控制**: 串行执行所有步骤，记录日志，显示进度

## 前置要求

- mysql 客户端（用于连接 TiDB）

### 安装 mysql 客户端

**macOS:**
```bash
brew install mysql-client
```

**Ubuntu/Debian:**
```bash
sudo apt-get install mysql-client
```

**CentOS/RHEL:**
```bash
sudo yum install mysql
```

## 文件结构

```
.
├── syncdiff_config2/
│   ├── config.toml              # 主配置文件
│   ├── my_database_users.toml   # 配置模板
│   ├── query_results.txt        # 查询结果（自动生成）
│   └── generated_configs/       # 生成的配置文件目录
├── logs/                        # 日志目录
├── step1_query_tables.sh        # 步骤1：查询数据库
├── step2_generate_configs.sh    # 步骤2：生成配置文件
└── run_syncdiff_config.sh       # 主控制脚本
```

## 使用方法

### 方式0：测试连接（推荐先执行）

```bash
./test_connection.sh
```

此脚本会测试：
- MySQL 客户端是否安装
- 数据库连接是否正常
- check_sql 查询是否正确

### 方式1：一键执行（推荐）

```bash
./run_syncdiff_config.sh
```

### 方式2：分步执行

```bash
# 步骤1：查询数据库
./step1_query_tables.sh

# 步骤2：生成配置文件
./step2_generate_configs.sh
```

## 配置说明

编辑 `syncdiff_config2/config.toml`：

```toml
# 主库配置
master_ip = "192.168.1.100"
master_port = 4000
master_user = "root"
# 密码加密方式：echo "明文密码" | base64
master_password = ""

# 备库配置
slave_ip = "192.168.1.101"
slave_port = 4000
slave_user = "root"
# 密码加密方式：echo "明文密码" | base64
slave_password = ""

# 检查SQL：查询大于10亿的表
check_sql = "select TABLE_SCHEMA,TABLE_NAME from information_schema.tables where TABLE_ROWS > 1000000000 and TIDB_PK_TYPE='NONCLUSTERED';"

# 其他配置
thread_count = 8
chunk_size = 5000
output_dir = "/tidbmgt/syncdiffoutput"
```

### 密码加密

为了安全起见，脚本支持 base64 加密的密码。

**加密方法：**
```bash
echo "你的明文密码" | base64
```

**示例：**
```bash
# 加密密码
echo "TiDB@2025.12!" | base64
# 输出：VGlEQDIyMjAyNS4xMiEh

# 将加密后的密码填入 config.toml
master_password = "VGlEQDIyMjAyNS4xMiEh"
```

**明文密码：**
如果不想加密，也可以直接填入明文密码（不推荐）。

## 输出说明

执行完成后：

1. `syncdiff_config2/query_results.txt` - 查询到的表列表
2. `syncdiff_config2/generated_configs/` - 生成的 toml 配置文件
   - 文件命名格式：`{schema_name}_{table_name}.toml`
3. `logs/syncdiff_YYYYMMDD_HHMMSS.log` - 执行日志

## 日志和进度

主控制脚本提供：

- 彩色输出（终端）
- 详细的日志记录（`logs/` 目录）
- 进度显示
- 防止重复运行（PID 文件）
- 异常处理和错误提示

## 下一步

生成的配置文件可用于 syncdiff 工具：

```bash
# 对单个表进行比对
syncdiff --config ./syncdiff_config2/generated_configs/{schema}_{table}.toml

# 批量比对
for file in ./syncdiff_config2/generated_configs/*.toml; do
  syncdiff --config "$file"
done
```

## 故障排查

### 1. MySQL 连接失败

**错误信息：**
```
[ERROR] 数据库查询失败:
ERROR 2003 (HY000): Can't connect to MySQL server on 'xxx' (111)
```

**解决方法：**
- 检查 IP 和端口是否正确
- 检查网络连通性：`ping <IP>`，`telnet <IP> <PORT>`
- 检查防火墙设置
- 确认 TiDB 服务正在运行

### 2. 权限不足

**错误信息：**
```
[ERROR] 数据库查询失败:
ERROR 1045 (28000): Access denied for user...
```

**解决方法：**
- 检查用户名和密码
- 确认用户有 `information_schema` 的 `SELECT` 权限
- 可以使用测试脚本：`./test_connection.sh`

### 3. SQL 查询错误

**错误信息：**
```
[ERROR] 数据库查询失败:
ERROR 1146 (42S02): Table 'xxx.tables' doesn't exist
```

**解决方法：**
- 确保 check_sql 中使用的是 `information_schema.tables`
- 检查查询语法是否正确
- 在 TiDB 中手动执行 SQL 验证

### 4. 没有找到符合条件的表

**警告信息：**
```
[WARN] 查询结果为空，没有找到大于10亿的表
```

**说明：**
- 这是正常情况，说明数据库中没有行数超过10亿的表
- 或者 `TIDB_PK_TYPE='NONCLUSTERED'` 的条件没有匹配到表
- 可以临时修改 check_sql 移除某些条件进行调试

### 5. 日志查看

所有执行日志保存在 `logs/` 目录：

```bash
# 查看最新日志
tail -f logs/syncdiff_*.log

# 查看错误日志
grep ERROR logs/syncdiff_*.log
```

## 注意事项

1. 确保 mysql 客户端已安装
2. 确保 config.toml 中的数据库连接信息正确
3. 确保 check_sql 查询返回两列：schema_name, table_name
4. check_sql 必须使用 `information_schema.tables`，不能只写 `tables`
5. 日志文件会自动轮转，按时间戳命名
6. 如果脚本异常退出，下次运行会自动清理旧的 PID 文件
7. 建议先运行 `test_connection.sh` 测试连接是否正常
