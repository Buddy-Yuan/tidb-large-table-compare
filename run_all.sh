#!/bin/bash

# 完整流程控制脚本：生成配置 + 执行比对

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOG_DIR="./logs"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="$LOG_DIR/syncdiff_full_$TIMESTAMP.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $@"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@"
}

log_step() {
    echo -e "${BLUE}${BOLD}[STEP]${NC} $@"
}

log_success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $@"
}

# 打印横幅
print_banner() {
    echo -e "${BLUE}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║       SyncDiff 完整流程工具                              ║"
    echo "║       Full Workflow: Generate Config + Execute               ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 步骤1：生成配置
step1_generate_config() {
    log_step "步骤 1/2: 生成 syncdiff 配置文件"
    echo ""

    if ./run_syncdiff_config.sh; then
        echo ""
        log_success "配置生成完成"
        echo ""
    else
        log_error "配置生成失败"
        exit 1
    fi
}

# 步骤2：执行比对
step2_execute_syncdiff() {
    log_step "步骤 2/2: 执行 syncdiff 比对"
    echo ""

    # 检查配置文件是否存在
    if [ ! -d "./syncdiff_config2/generated_configs" ] || [ -z "$(ls -A ./syncdiff_config2/generated_configs 2>/dev/null)" ]; then
        log_error "没有找到配置文件，请先生成配置"
        exit 1
    fi

    # 询问是否继续
    echo -e "${YELLOW}即将执行 syncdiff 比对，可能需要较长时间...${NC}"
    echo -e "${YELLOW}执行方式: 后台运行${NC}"
    read -p "是否继续？(y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "已取消"
        exit 0
    fi

    log_info "正在后台执行..."
    echo ""

    # 后台执行 step3
    nohup ./step3_run_syncdiff.sh > /dev/null 2>&1 &
    PID=$!

    # 保存 PID
    PID_FILE="$LOG_DIR/syncdiff_bg.pid"
    echo $PID > "$PID_FILE"

    echo -e "${GREEN}✓ syncdiff 已在后台启动${NC}"
    echo ""
    echo -e "进程 PID: ${BLUE}$PID${NC}"
    echo -e "PID 文件: $PID_FILE"
    echo ""
    echo -e "${YELLOW}查看执行日志:${NC}"
    echo -e "  tail -f $(ls -t $LOG_DIR/syncdiff_exec_*.log 2>/dev/null | head -1)"
    echo ""
    echo -e "${YELLOW}查看最终比对报告:${NC}"
    echo -e "  完成后查看: ${BLUE}ls -t $LOG_DIR/final_report_*.txt 2>/dev/null | head -1${NC}"
    echo ""
    echo -e "${YELLOW}停止进程:${NC}"
    echo -e "  kill $PID"
    echo -e "  或: kill \$(cat $PID_FILE)"
    echo ""
}

# 主函数
main() {
    print_banner
    step1_generate_config
    step2_execute_syncdiff

    # 后台执行，不输出完成信息
    log_info "后台任务已启动，请使用上述命令查看进度"
}

# 执行主函数
main "$@"
