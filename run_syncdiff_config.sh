#!/bin/bash

# 主控制脚本：串行执行所有步骤，支持日志和进度汇报

set -e

# 脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 配置
CONFIG_FILE="./syncdiff_config2/config.toml"
LOG_DIR="./logs"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="$LOG_DIR/syncdiff_$TIMESTAMP.log"
PID_FILE="$LOG_DIR/syncdiff.pid"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# 日志函数
log() {
    local level=$1
    shift
    local msg="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${msg}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $@" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $@" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "${BLUE}${BOLD}[STEP]${NC} $@" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $@" | tee -a "$LOG_FILE"
}

# 进度条显示
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((percentage * width / 100))
    local empty=$((width - filled))

    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' '-'
    printf "] %d%% (%d/%d)" "$percentage" "$current" "$total"
}

# 清理函数
cleanup() {
    if [ -f "$PID_FILE" ]; then
        rm -f "$PID_FILE"
    fi
}

# 信号处理
trap cleanup EXIT INT TERM

# 检查 PID 文件，防止重复运行
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        log_error "程序已在运行中 (PID: $OLD_PID)"
        exit 1
    else
        log_warn "检测到异常退出的 PID 文件，清理后继续"
        rm -f "$PID_FILE"
    fi
fi

# 保存当前 PID
echo $$ > "$PID_FILE"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 打印横幅
print_banner() {
    echo -e "${BLUE}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║           SyncDiff 配置生成工具                            ║"
    echo "║           SyncDiff Config Generator                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    log_info "日志文件: $LOG_FILE"
    echo ""
}

# 检查环境
check_environment() {
    log_step "检查环境..."

    # 检查配置文件
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
    log_info "✓ 配置文件存在"

    # 检查必需的脚本
    local scripts=("step1_query_tables.sh" "step2_generate_configs.sh")
    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            log_error "脚本文件不存在: $script"
            exit 1
        fi
        chmod +x "$script"
        log_info "✓ $script 存在且已设置执行权限"
    done

    # 检查 mysql 客户端
    if ! command -v mysql &> /dev/null; then
        log_error "mysql 客户端未安装"
        log_error "macOS: brew install mysql-client"
        log_error "Ubuntu: sudo apt-get install mysql-client"
        exit 1
    fi
    log_info "✓ mysql 客户端已安装"

    echo ""
}

# 执行步骤1：查询数据库
execute_step1() {
    log_step "步骤 1/2: 查询数据库获取需要检查的表"
    echo ""

    local start_time=$(date +%s)

    if ./step1_query_tables.sh; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "步骤 1 完成 (耗时: ${duration}秒)"
        echo ""

        # 检查是否有结果
        if [ -f "./syncdiff_config2/query_results.txt" ]; then
            local table_count=$(wc -l < "./syncdiff_config2/query_results.txt")
            log_info "找到 $table_count 个需要检查的表"
            if [ "$table_count" -eq 0 ]; then
                log_warn "没有找到需要检查的表，程序退出"
                exit 0
            fi
        else
            log_warn "未找到查询结果文件，可能是没有符合条件的表"
            exit 0
        fi
    else
        log_error "步骤 1 失败"
        exit 1
    fi
}

# 执行步骤2：生成配置文件
execute_step2() {
    log_step "步骤 2/2: 生成 toml 配置文件"
    echo ""

    # 智能清理：删除不在当前查询结果中的旧配置文件
    local config_dir="./syncdiff_config2/generated_configs"
    if [ -d "$config_dir" ]; then
        log_info "检查并清理旧配置文件..."

        # 获取当前查询结果中的表名列表
        local current_tables=""
        while IFS=$'\t' read -r schema_name table_name; do
            current_tables="${current_tables}${schema_name}_${table_name} "
        done < "./syncdiff_config2/query_results.txt"

        # 遍历旧的配置文件，清理不在查询结果中的
        for old_toml in "$config_dir"/*.toml; do
            if [ -f "$old_toml" ]; then
                local old_table=$(basename "$old_toml" .toml)
                # 如果旧表名不在当前查询结果中，删除该配置文件
                if [[ ! " $current_tables " =~ " ${old_table} " ]]; then
                    rm -f "$old_toml"
                    log_info "  清理旧配置: $old_table"
                fi
            fi
        done
        log_info "✓ 清理完成"
    fi
    echo ""

    local start_time=$(date +%s)

    if ./step2_generate_configs.sh; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "步骤 2 完成 (耗时: ${duration}秒)"
        echo ""

        # 显示生成的文件
        local config_dir="./syncdiff_config2/generated_configs"
        if [ -d "$config_dir" ]; then
            local file_count=$(ls -1 "$config_dir"/*.toml 2>/dev/null | wc -l)
            log_info "生成了 $file_count 个配置文件"
            log_info "配置文件目录: $config_dir"
        fi
    else
        log_error "步骤 2 失败"
        exit 1
    fi
}

# 打印总结
print_summary() {
    local total_start_time=$1
    local total_end_time=$(date +%s)
    local total_duration=$((total_end_time - total_start_time))

    echo ""
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${NC}"
    log_success "所有步骤执行完成！"
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo ""
    log_info "总耗时: ${total_duration}秒"
    log_info "日志文件: $LOG_FILE"

    if [ -d "./syncdiff_config2/generated_configs" ]; then
        echo ""
        log_info "生成的配置文件:"
        ls -lh ./syncdiff_config2/generated_configs/*.toml 2>/dev/null | awk '{printf "  %-50s %8s\n", $9, $5}'
    fi

}

# 主函数
main() {
    local start_time=$(date +%s)

    print_banner
    check_environment
    execute_step1
    execute_step2
    print_summary "$start_time"

    # 清理 PID 文件
    rm -f "$PID_FILE"
}

# 执行主函数
main "$@"
