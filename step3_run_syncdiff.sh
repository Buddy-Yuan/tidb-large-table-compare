#!/bin/bash

# 第三步：执行 sync_diff_inspector 比对

set -e

CONFIG_DIR="./syncdiff_config2/generated_configs"
LOG_DIR="./logs"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="$LOG_DIR/syncdiff_exec_$TIMESTAMP.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "${BLUE}${BOLD}[STEP]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

# 进度条显示
show_progress() {
    local current=$1
    local total=$2
    local table_name=$3
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((percentage * width / 100))
    local empty=$((width - filled))

    printf "\r"
    printf "["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' '-'
    printf "] %3d%% (%2d/%2d) %s" "$percentage" "$current" "$total" "$table_name"
}

# 检查 sync_diff_inspector 是否安装
if ! command -v sync_diff_inspector &> /dev/null; then
    log_error "sync_diff_inspector 未安装"
    log_error "请先安装 sync_diff_inspector 工具"
    exit 1
fi

# 检查配置文件目录
if [ ! -d "$CONFIG_DIR" ]; then
    log_error "配置文件目录不存在: $CONFIG_DIR"
    log_error "请先运行 run_syncdiff_config.sh 生成配置文件"
    exit 1
fi

# 创建日志目录
mkdir -p "$LOG_DIR"

# 打印横幅
echo -e "${BLUE}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           SyncDiff 执行工具                                ║"
echo "║           SyncDiff Executor                                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
log_info "日志文件: $LOG_FILE"
echo ""

# 统计配置文件数量
CONFIG_FILES=("$CONFIG_DIR"/*.toml)
TOTAL=${#CONFIG_FILES[@]}

if [ "$TOTAL" -eq 0 ]; then
    log_error "没有找到配置文件"
    exit 1
fi

log_info "找到 $TOTAL 个配置文件"
log_info "开始执行 sync_diff_inspector..."
echo ""

# 统计变量
SUCCESS_COUNT=0
FAILED_COUNT=0
FAILED_FILES=()
START_TIME=$(date +%s)

# 执行每个配置文件
for i in "${!CONFIG_FILES[@]}"; do
    CURRENT=$((i + 1))
    CONFIG_FILE_PATH="${CONFIG_FILES[$i]}"
    TABLE_NAME=$(basename "$CONFIG_FILE_PATH" .toml)

    show_progress "$CURRENT" "$TOTAL" "$TABLE_NAME"

    # 执行 sync_diff_inspector
    if sync_diff_inspector --config "$CONFIG_FILE_PATH" >> "$LOG_FILE" 2>&1; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        printf "\r${GREEN}✓${NC} %-40s 完成\n" "$TABLE_NAME"
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_FILES+=("$TABLE_NAME")
        printf "\r${RED}✗${NC} %-40s 失败\n" "$TABLE_NAME"
        log_error "$TABLE_NAME 执行失败，请查看日志: $LOG_FILE"
    fi
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 打印总结
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${NC}"
log_success "执行完成！"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════${NC}"
echo ""
log_info "总耗时: ${DURATION}秒 ($(($DURATION / 60))分$(($DURATION % 60))秒)"
log_info "成功: $SUCCESS_COUNT / $TOTAL"
if [ "$FAILED_COUNT" -gt 0 ]; then
    log_warn "失败: $FAILED_COUNT / $TOTAL"
    echo ""
    log_warn "失败的表:"
    for file in "${FAILED_FILES[@]}"; do
        echo -e "  ${RED}✗${NC} $file"
    done
fi
echo ""
log_info "详细日志: $LOG_FILE"
echo ""

# 收集并合并所有 summary.txt
FINAL_REPORT_FILE="$LOG_DIR/final_report_${TIMESTAMP}.txt"

# 读取输出目录配置
OUTPUT_BASE_DIR=$(grep "^output_dir" "./syncdiff_config2/config.toml" | cut -d'"' -f2)

# 查找所有包含 summary.txt 的目录，提取时间戳，只取最新的
SUMMARY_FILES=""

for summary_file in $(find "$OUTPUT_BASE_DIR" -name "summary.txt" -type f 2>/dev/null | sort); do
    dir_name=$(dirname "$summary_file")
    dir_basename=$(basename "$dir_name")

    # 提取时间戳（目录名最后一部分）
    timestamp=$(echo "$dir_basename" | awk -F'_' '{print $NF}')

    # 收集所有 summary.txt 文件及其时间戳
    SUMMARY_FILES="$SUMMARY_FILES$timestamp|$summary_file\n"
done

# 按时间戳排序，取最大时间戳的那些文件
if [ -n "$SUMMARY_FILES" ]; then
    LATEST_TIMESTAMP=$(echo -e "$SUMMARY_FILES" | sort -r | head -1 | cut -d'|' -f1)
    SUMMARY_FILES=$(echo -e "$SUMMARY_FILES" | grep "^${LATEST_TIMESTAMP}|" | cut -d'|' -f2)
fi

# 输出最终比对报告到标准输出和文件
{
echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}${BOLD}                    最终比对报告                                    ${NC}"
echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""

if [ -z "$SUMMARY_FILES" ]; then
    echo -e "${YELLOW}没有找到 summary.txt 文件${NC}"
else
    # 计数
    SUMMARY_COUNT=$(echo "$SUMMARY_FILES" | wc -l)
    echo -e "${GREEN}[INFO]${NC} 找到 $SUMMARY_COUNT 个 summary.txt 文件"
    echo ""

    # 合并所有表格
    echo "+-------------------+-----------+---------+-----------+"
    echo "|       TABLE       | STRUCTURE | UPCOUNT | DOWNCOUNT |"
    echo "+-------------------+-----------+---------+-----------+"

    TOTAL_UPCOUNT=0
    TOTAL_DOWNCOUNT=0
    TABLE_COUNT=0
    STRUCTURE_OK=0
    STRUCTURE_DIFF=0

    while IFS= read -r summary_file; do
        if [ -f "$summary_file" ]; then
            # 检查表结构是否一致
            STRUCTURE_STATUS="差异"
            if grep -q "The table structure and data in following tables are equivalent" "$summary_file"; then
                STRUCTURE_STATUS="一致"
                STRUCTURE_OK=$((STRUCTURE_OK + 1))
            else
                STRUCTURE_DIFF=$((STRUCTURE_DIFF + 1))
            fi

            # 提取表格行（匹配包含反引号的行，排除表头和分隔符）
            TABLE_INFO=$(grep '`' "$summary_file" | grep -v '^+' | grep -v 'TABLE' | head -1)

            if [ -n "$TABLE_INFO" ]; then
                # 提取表名、UPCOUNT、DOWNCOUNT
                TABLE_PART=$(echo "$TABLE_INFO" | awk -F'|' '{print $2}' | tr -d ' ')
                UPCOUNT=$(echo "$TABLE_INFO" | awk -F'|' '{print $3}' | tr -d ' ')
                DOWNCOUNT=$(echo "$TABLE_INFO" | awk -F'|' '{print $4}' | tr -d ' ')

                printf "| %-17s | %-9s | %7s | %9s |\n" "$TABLE_PART" "$STRUCTURE_STATUS" "$UPCOUNT" "$DOWNCOUNT"

                # 统计总数
                if [ -n "$UPCOUNT" ] && [ "$UPCOUNT" -eq "$UPCOUNT" ] 2>/dev/null; then
                    TOTAL_UPCOUNT=$((TOTAL_UPCOUNT + UPCOUNT))
                fi
                if [ -n "$DOWNCOUNT" ] && [ "$DOWNCOUNT" -eq "$DOWNCOUNT" ] 2>/dev/null; then
                    TOTAL_DOWNCOUNT=$((TOTAL_DOWNCOUNT + DOWNCOUNT))
                fi
                TABLE_COUNT=$((TABLE_COUNT + 1))
            fi
        fi
    done <<< "$SUMMARY_FILES"

    echo "+-------------------+-----------+---------+-----------+"
    echo ""
    echo -e "${GREEN}[INFO]${NC} 汇总统计: 共 $TABLE_COUNT 张表"
    echo "  结构一致: $STRUCTURE_OK 张"
    if [ "$STRUCTURE_DIFF" -gt 0 ]; then
        echo -e "  结构差异: ${RED}$STRUCTURE_DIFF${NC} 张"
    fi
    echo "  总数据量: $((TOTAL_UPCOUNT / 1000000))M 行"
    echo ""
fi
} | tee -a "$FINAL_REPORT_FILE"

# 如果有失败的，返回非零退出码
if [ "$FAILED_COUNT" -gt 0 ]; then
    exit 1
fi
