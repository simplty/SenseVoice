#!/bin/bash
# 通用Docker项目部署脚本
# 支持多种项目类型的自动化部署

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
}

# 加载项目配置
load_config() {
    # 检查 docker-compose.yml 是否存在
    if [[ -f "docker-compose.yml" ]]; then
        COMPOSE_FILE="docker-compose.yml"
        USE_COMPOSE="true"
    elif [[ -f "docker-compose.yaml" ]]; then
        COMPOSE_FILE="docker-compose.yaml"
        USE_COMPOSE="true"
    else
        log_error "未找到 docker-compose.yml 文件"
        log_info "本脚本只支持通过 docker-compose.yml 进行部署"
        exit 1
    fi
    
    # 从 docker-compose.yml 解析配置
    parse_compose_config
    
    # 环境变量可以覆盖配置
    PROJECT_NAME="${DEPLOY_PROJECT_NAME:-$PROJECT_NAME}"
    IMAGE_NAME="${DEPLOY_IMAGE_NAME:-$IMAGE_NAME}"
    CONTAINER_NAME="${DEPLOY_CONTAINER_NAME:-$CONTAINER_NAME}"
    PORT="${DEPLOY_PORT:-$PORT}"
    VERSION="${DEPLOY_VERSION:-$VERSION}"
    HEALTH_CHECK_PATH="${DEPLOY_HEALTH_PATH:-$HEALTH_CHECK_PATH}"
    
    HEALTH_CHECK_URL="http://localhost:${PORT}${HEALTH_CHECK_PATH}"
    
    log_debug "项目配置："
    log_debug "  PROJECT_NAME=$PROJECT_NAME"
    log_debug "  IMAGE_NAME=$IMAGE_NAME"
    log_debug "  CONTAINER_NAME=$CONTAINER_NAME"
    log_debug "  PORT=$PORT"
    log_debug "  PROJECT_TYPE=$PROJECT_TYPE"
    log_debug "  USE_COMPOSE=$USE_COMPOSE"
}

# 从 docker-compose.yml 解析配置
parse_compose_config() {
    log_debug "从 $COMPOSE_FILE 解析配置"
    
    # 获取第一个服务名作为项目名
    local first_service=$(docker-compose -f "$COMPOSE_FILE" config --services 2>/dev/null | head -n 1)
    
    if [[ -z "$first_service" ]]; then
        log_error "无法从 $COMPOSE_FILE 获取服务配置"
        exit 1
    fi
    
    # 设置项目信息
    PROJECT_NAME="$first_service"
    PROJECT_TYPE="docker-compose"
    
    # 解析镜像名
    IMAGE_NAME=$(docker-compose -f "$COMPOSE_FILE" config 2>/dev/null | grep -A 10 "^  $first_service:" | grep "image:" | head -n 1 | sed 's/.*image: *//g' | cut -d':' -f1)
    if [[ -z "$IMAGE_NAME" ]]; then
        IMAGE_NAME="$PROJECT_NAME"
    fi
    
    # 解析版本号
    VERSION=$(docker-compose -f "$COMPOSE_FILE" config 2>/dev/null | grep -A 10 "^  $first_service:" | grep "image:" | head -n 1 | sed 's/.*image: *//g' | cut -d':' -f2)
    if [[ -z "$VERSION" || "$VERSION" == "$IMAGE_NAME" ]]; then
        VERSION="latest"
    fi
    
    # 解析容器名
    CONTAINER_NAME=$(docker-compose -f "$COMPOSE_FILE" config 2>/dev/null | grep -A 20 "^  $first_service:" | grep "container_name:" | head -n 1 | sed 's/.*container_name: *//g')
    if [[ -z "$CONTAINER_NAME" ]]; then
        CONTAINER_NAME="$PROJECT_NAME"
    fi
    
    # 解析端口映射
    local port_mapping=$(docker-compose -f "$COMPOSE_FILE" config 2>/dev/null | grep -A 20 "^  $first_service:" | grep -A 10 "ports:" | grep -E "^ *- " | head -n 1 | sed 's/.*- *"*//g' | sed 's/"*$//g')
    if [[ -n "$port_mapping" ]]; then
        PORT=$(echo "$port_mapping" | cut -d':' -f1)
    else
        PORT="8000"  # 默认端口
    fi
    
    # 解析健康检查路径
    local health_test=$(docker-compose -f "$COMPOSE_FILE" config 2>/dev/null | grep -A 20 "^  $first_service:" | grep -A 10 "healthcheck:" | grep "test:" | head -n 1)
    if [[ -n "$health_test" ]] && echo "$health_test" | grep -q "/health"; then
        HEALTH_CHECK_PATH="/health"
    else
        HEALTH_CHECK_PATH="/health"  # 默认路径
    fi
    
    log_debug "解析结果："
    log_debug "  first_service=$first_service"
    log_debug "  IMAGE_NAME=$IMAGE_NAME"
    log_debug "  VERSION=$VERSION"
    log_debug "  CONTAINER_NAME=$CONTAINER_NAME"
    log_debug "  PORT=$PORT"
    log_debug "  HEALTH_CHECK_PATH=$HEALTH_CHECK_PATH"
}

# 显示帮助
show_help() {
    cat << EOF
${CYAN}Docker Compose 项目部署脚本${NC}

用法: $0 [命令] [选项]

${YELLOW}说明:${NC}
  本脚本只支持通过 docker-compose.yml 文件进行部署
  所有配置信息都从 docker-compose.yml 中自动解析

${YELLOW}命令:${NC}
  build           构建Docker镜像
  run             运行容器
  deploy          构建并运行
  stop            停止容器
  restart         重启容器
  rebuild         强制重新构建并启动
  force-pull      强制从远程拉取代码并处理后续操作
  logs            查看日志
  shell           进入容器shell
  clean           清理容器和镜像
  reload          热重载配置
  health          健康检查
  config          显示当前配置
  menu            显示操作菜单

${YELLOW}选项:${NC}
  -p, --port PORT       覆盖端口映射
  -n, --name NAME       覆盖容器名称
  -v, --version VER     覆盖镜像版本
  -e, --env-file FILE   环境变量文件
  --upload              上传脚本到 FTP 服务器
  --debug               启用调试输出
  -h, --help            显示帮助

${YELLOW}示例:${NC}
  $0                           # 显示操作菜单
  $0 deploy                    # 从 docker-compose.yml 部署项目
  $0 run -p 8080               # 覆盖端口为8080运行
  $0 rebuild --debug           # 调试模式重新构建
  $0 force-pull                # 强制拉取代码并选择后续操作
  $0 logs -f                   # 实时查看日志
  $0 --upload                  # 上传脚本到 FTP 服务器

${YELLOW}环境变量:${NC}
  DEPLOY_PROJECT_NAME          # 覆盖项目名称
  DEPLOY_IMAGE_NAME            # 覆盖镜像名称
  DEPLOY_CONTAINER_NAME        # 覆盖容器名称
  DEPLOY_PORT                  # 覆盖端口号
  DEBUG=true                   # 启用调试输出
  SCRIPT_FTP_URL               # FTP 完整 URL (推荐)
  SCRIPT_FTP_HOST              # FTP 服务器地址
  SCRIPT_FTP_USER              # FTP 用户名
  SCRIPT_FTP_PASS              # FTP 密码
  SCRIPT_FTP_PATH              # FTP 上传路径

${YELLOW}配置来源优先级:${NC}
  1. 命令行参数 (最高)
  2. 环境变量
  3. docker-compose.yml 解析 (默认)
EOF
}

# 显示操作菜单
show_menu() {
    clear
    echo -e "${CYAN}=== Docker Compose 项目部署管理 ===${NC}"
    echo -e "${GREEN}项目: $PROJECT_NAME${NC}"
    echo -e "${GREEN}镜像: $IMAGE_NAME:$VERSION${NC}"
    echo -e "${GREEN}容器: $CONTAINER_NAME${NC}"
    echo -e "${GREEN}端口: $PORT (宿主机映射端口)${NC}"
    echo -e "${GREEN}配置: $COMPOSE_FILE${NC}"
    echo ""
    echo -e "${YELLOW}请选择操作 (最常用操作在前三个):${NC}"
    echo "1. 📥 强制拉取远程代码"
    echo "2. 🔄 重启服务 (包含运行容器功能)"
    echo "3. 🚀 部署项目 (构建+启动，包含重新构建功能)"
    echo "4. 📋 查看日志"
    echo "5. 🐚 进入容器Shell"
    echo "6. ❤️  健康检查"
    echo "7. ⚙️  显示配置"
    echo "8. 🗑️  清理容器镜像"
    echo "9. ⏹️  停止容器"
    echo "0. 退出"
    echo ""
    read -p "请输入选项编号: " choice
    
    case $choice in
        1)
            force_pull_with_options
            pause_and_menu
            ;;
        2)
            restart_service
            pause_and_menu
            ;;
        3)
            deploy
            pause_and_menu
            ;;
        4)
            echo "按 Ctrl+C 退出日志查看"
            sleep 2
            show_logs -f --tail 100
            show_menu
            ;;
        5)
            enter_shell
            show_menu
            ;;
        6)
            health_check
            pause_and_menu
            ;;
        7)
            show_config
            pause_and_menu
            ;;
        8)
            cleanup
            pause_and_menu
            ;;
        9)
            stop_container
            pause_and_menu
            ;;
        0)
            log_info "再见！"
            exit 0
            ;;
        *)
            log_error "无效选项，请重新选择"
            sleep 1
            show_menu
            ;;
    esac
}

# 暂停并返回菜单
pause_and_menu() {
    echo ""
    read -p "按 Enter 键返回主菜单..." 
    show_menu
}

# 显示当前配置
show_config() {
    cat << EOF
${CYAN}当前项目配置 (从 docker-compose.yml 解析):${NC}
  项目名称: ${GREEN}$PROJECT_NAME${NC}
  镜像名称: ${GREEN}$IMAGE_NAME:$VERSION${NC}
  容器名称: ${GREEN}$CONTAINER_NAME${NC}
  端口映射: ${GREEN}$PORT${NC}
  健康检查: ${GREEN}$HEALTH_CHECK_URL${NC}
  配置文件: ${GREEN}$COMPOSE_FILE${NC}
  部署方式: ${GREEN}docker-compose${NC}
  
EOF
}

# 构建镜像
build_image() {
    if [[ "$USE_COMPOSE" == "true" ]]; then
        log_info "使用 docker-compose 构建镜像"
        docker-compose -f "$COMPOSE_FILE" build
    else
        log_info "构建Docker镜像: $IMAGE_NAME:$VERSION"
        
        # 构建参数
        local build_args=(
            -f "$DOCKERFILE"
            -t "$IMAGE_NAME:$VERSION"
            --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            --build-arg VCS_REF="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
            --build-arg VERSION="$VERSION"
            --build-arg PROJECT_TYPE="$PROJECT_TYPE"
        )
        
        # 添加自定义构建参数
        if [[ -n "${BUILD_ARGS:-}" ]]; then
            IFS=' ' read -ra ARGS <<< "$BUILD_ARGS"
            for arg in "${ARGS[@]}"; do
                build_args+=(--build-arg "$arg")
            done
        fi
        
        docker build "${build_args[@]}" .
    fi
    
    log_success "镜像构建完成"
}

# 停止并删除现有容器
stop_container() {
    if [[ "$USE_COMPOSE" == "true" ]]; then
        if [[ -f "$COMPOSE_FILE" ]]; then
            log_info "停止 docker-compose 服务"
            docker-compose -f "$COMPOSE_FILE" down
        fi
    else
        if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
            log_info "停止现有容器: $CONTAINER_NAME"
            docker stop "$CONTAINER_NAME" >/dev/null 2>&1
            docker rm "$CONTAINER_NAME" >/dev/null 2>&1
            log_success "容器已停止"
        fi
    fi
}

# 运行容器
run_container() {
    if [[ "$USE_COMPOSE" == "true" ]]; then
        log_info "使用 docker-compose 启动服务"
        docker-compose -f "$COMPOSE_FILE" up -d
    else
        local env_file_opt=""
        if [[ -n "$ENV_FILE" ]] && [[ -f "$ENV_FILE" ]]; then
            env_file_opt="--env-file $ENV_FILE"
            log_info "使用环境文件: $ENV_FILE"
        fi
        
        log_info "启动容器: $CONTAINER_NAME"
        log_info "端口映射: $PORT -> 容器端口"
        log_info "镜像: $IMAGE_NAME:$VERSION"
        
        # 基本运行参数
        local run_args=(
            -d
            --name "$CONTAINER_NAME"
            --restart unless-stopped
            -p "$PORT:$(get_internal_port)"
        )
        
        # 添加环境文件
        if [[ -n "$env_file_opt" ]]; then
            run_args+=($env_file_opt)
        fi
        
        # 添加资源限制
        if [[ -n "${MEMORY_LIMIT:-}" ]]; then
            run_args+=(--memory="$MEMORY_LIMIT")
        fi
        if [[ -n "${CPU_LIMIT:-}" ]]; then
            run_args+=(--cpus="$CPU_LIMIT")
        fi
        
        # 添加常见的卷挂载
        add_common_volumes run_args
        
        # 添加自定义运行参数
        if [[ -n "${CUSTOM_RUN_ARGS:-}" ]]; then
            IFS=' ' read -ra ARGS <<< "$CUSTOM_RUN_ARGS"
            run_args+=("${ARGS[@]}")
        fi
        
        run_args+=("$IMAGE_NAME:$VERSION")
        
        docker run "${run_args[@]}"
    fi
    
    log_success "容器已启动"
}

# 获取内部端口
get_internal_port() {
    # 从 docker-compose.yml 解析内部端口
    local port_mapping=$(docker-compose -f "$COMPOSE_FILE" config 2>/dev/null | grep -A 20 "^  $(get_main_service):" | grep -A 10 "ports:" | grep -E "^ *- " | head -n 1 | sed 's/.*- *"*//g' | sed 's/"*$//g')
    if [[ -n "$port_mapping" ]]; then
        echo "$port_mapping" | cut -d':' -f2
    else
        echo "8000"  # 默认内部端口
    fi
}

# 添加常见的卷挂载
add_common_volumes() {
    local -n arr=$1
    
    # 日志目录
    if [[ -d "logs" ]]; then
        arr+=(-v "$(pwd)/logs:/app/logs")
    fi
    
    # 配置目录
    if [[ -d "config" ]]; then
        arr+=(-v "$(pwd)/config:/app/config:ro")
    fi
    
    # 数据目录
    if [[ -d "data" ]]; then
        arr+=(-v "$(pwd)/data:/app/data")
    fi
    
    # 项目特定的卷挂载
    case "$PROJECT_TYPE" in
        "nodejs")
            if [[ -d "public" ]]; then
                arr+=(-v "$(pwd)/public:/app/public:ro")
            fi
            ;;
        "python")
            if [[ -d "static" ]]; then
                arr+=(-v "$(pwd)/static:/app/static:ro")
            fi
            ;;
    esac
}

# 健康检查
health_check() {
    log_info "执行健康检查..."
    log_debug "健康检查URL: $HEALTH_CHECK_URL"
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -f -s "$HEALTH_CHECK_URL" >/dev/null 2>&1; then
            log_success "健康检查通过 ✓"
            
            # 显示服务信息
            echo ""
            log_info "服务信息:"
            local response=$(curl -s "$HEALTH_CHECK_URL" 2>/dev/null || echo '{"status":"unknown"}')
            echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
            
            return 0
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo ""
    log_error "健康检查失败"
    log_warning "请检查服务是否正常启动，或者健康检查路径是否正确"
    return 1
}

# 查看日志
show_logs() {
    if [[ "$USE_COMPOSE" == "true" ]]; then
        docker-compose -f "$COMPOSE_FILE" logs "$@"
    else
        docker logs "$@" "$CONTAINER_NAME"
    fi
}

# 进入容器shell
enter_shell() {
    if [[ "$USE_COMPOSE" == "true" ]]; then
        log_info "进入主服务容器shell..."
        docker-compose -f "$COMPOSE_FILE" exec "$(get_main_service)" /bin/bash 2>/dev/null || \
        docker-compose -f "$COMPOSE_FILE" exec "$(get_main_service)" /bin/sh
    else
        if ! docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
            log_error "容器未运行: $CONTAINER_NAME"
            exit 1
        fi
        
        log_info "进入容器shell..."
        docker exec -it "$CONTAINER_NAME" /bin/bash 2>/dev/null || \
        docker exec -it "$CONTAINER_NAME" /bin/sh
    fi
}

# 获取主服务名称（用于docker-compose）
get_main_service() {
    if [[ -f "$COMPOSE_FILE" ]]; then
        # 尝试从 docker-compose 文件中获取第一个服务名
        docker-compose -f "$COMPOSE_FILE" config --services 2>/dev/null | head -n 1
    else
        echo "app"  # 默认服务名
    fi
}

# 热重载
hot_reload() {
    if [[ "$USE_COMPOSE" == "true" ]]; then
        log_info "重启 docker-compose 服务..."
        docker-compose -f "$COMPOSE_FILE" restart
    else
        if ! docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
            log_error "容器未运行: $CONTAINER_NAME"
            exit 1
        fi
        
        log_info "发送热重载信号..."
        docker exec "$CONTAINER_NAME" kill -USR1 1 2>/dev/null || \
        docker restart "$CONTAINER_NAME"
    fi
    log_success "热重载完成"
}

# 强制拉取代码并提供选项
force_pull_with_options() {
    log_warning "警告：此操作将强制从远程拉取代码并覆盖本地所有更改，包括未提交的文件和未跟踪的文件。"
    read -p "是否继续？(y/n): " confirm
    
    if [[ "$confirm" != "y" ]]; then
        log_info "操作已取消。"
        return 0
    fi
    
    # 检查是否在git仓库中
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "当前目录不是git仓库"
        return 1
    fi
    
    log_info "正在清理本地更改..."
    git reset --hard HEAD
    git clean -fd
    
    log_info "正在从远程拉取最新代码..."
    if git pull; then
        log_success "远程代码拉取成功，本地已更新"
    else
        log_error "远程代码拉取失败，请检查错误信息"
        return 1
    fi
    
    # 修改文件权限
    log_info "正在修改文件权限..."
    find . -type d -exec chmod 755 {} \; 2>/dev/null || true
    find . -type f -exec chmod 644 {} \; 2>/dev/null || true
    
    # 给脚本文件添加执行权限
    chmod +x *.sh 2>/dev/null || true
    chmod +x scripts/*.sh 2>/dev/null || true
    
    log_success "代码拉取和权限设置完成"
    
    # 提供后续选项
    echo ""
    log_info "请选择后续操作:"
    echo "1. 重启服务 (不重新构建镜像)"
    echo "2. 重新构建镜像并重启服务"
    echo "3. 仅退出，不执行后续操作"
    read -p "请输入选项编号 (1-3): " choice
    
    case $choice in
        1)
            log_info "正在重启服务..."
            restart_service
            ;;
        2)
            log_info "正在重新构建镜像并重启服务..."
            rebuild_service
            ;;
        3)
            log_info "代码拉取完成，退出操作"
            return 0
            ;;
        *)
            log_warning "无效选项，默认重启服务"
            restart_service
            ;;
    esac
}

# 强制重新构建
rebuild_service() {
    log_info "开始强制重新构建服务..."
    
    # 停止现有容器
    stop_container
    
    if [[ "$USE_COMPOSE" == "true" ]]; then
        log_info "强制重新构建 docker-compose 镜像"
        docker-compose -f "$COMPOSE_FILE" build --no-cache
        docker-compose -f "$COMPOSE_FILE" up -d
    else
        # 清理旧镜像
        if docker images -q "$IMAGE_NAME:$VERSION" | grep -q .; then
            log_info "删除旧镜像: $IMAGE_NAME:$VERSION"
            docker rmi "$IMAGE_NAME:$VERSION" 2>/dev/null || true
        fi
        
        # 强制重新构建（不使用缓存）
        log_info "强制重新构建Docker镜像（不使用缓存）"
        local build_args=(
            --no-cache
            -f "$DOCKERFILE"
            -t "$IMAGE_NAME:$VERSION"
            --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            --build-arg VCS_REF="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
            --build-arg VERSION="$VERSION"
            --build-arg PROJECT_TYPE="$PROJECT_TYPE"
        )
        
        docker build "${build_args[@]}" .
        
        # 启动新容器
        run_container
    fi
    
    if [[ $? -eq 0 ]]; then
        log_success "镜像重新构建完成"
    else
        log_error "镜像构建失败"
        exit 1
    fi
    
    # 健康检查
    if health_check; then
        log_success "服务重新构建并启动成功 🚀"
        show_status
    else
        log_error "服务启动失败"
        show_logs --tail 50
        exit 1
    fi
}

# 清理
cleanup() {
    log_warning "清理容器和镜像..."
    
    if [[ "$USE_COMPOSE" == "true" ]]; then
        docker-compose -f "$COMPOSE_FILE" down --rmi all --volumes --remove-orphans 2>/dev/null || true
    else
        # 停止并删除容器
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
        
        # 删除镜像
        docker rmi "$IMAGE_NAME:$VERSION" 2>/dev/null || true
    fi
    
    # 清理未使用的镜像
    docker image prune -f
    
    log_success "清理完成"
}

# 重启服务
restart_service() {
    log_info "重启服务..."
    stop_container
    run_container
    
    if health_check; then
        log_success "服务重启成功"
        show_status
    else
        log_error "服务重启失败"
        exit 1
    fi
}

# 显示状态
show_status() {
    echo ""
    log_info "容器状态:"
    
    docker-compose -f "$COMPOSE_FILE" ps
    
    echo ""
    log_info "访问地址:"
    echo "  应用地址: http://localhost:$PORT"
    echo "  健康检查: $HEALTH_CHECK_URL"
    echo "  API文档: http://localhost:$PORT/docs"
    echo "  ReDoc: http://localhost:$PORT/redoc"
}

# 完整部署
deploy() {
    log_info "开始部署项目: $PROJECT_NAME"
    show_config
    
    # 构建镜像
    build_image
    
    # 停止现有容器
    stop_container
    
    # 启动新容器
    run_container
    
    # 健康检查
    if health_check; then
        log_success "部署成功 🚀"
        show_status
        
        echo ""
        log_info "常用命令:"
        echo "  查看日志: $0 logs -f"
        echo "  热重载:   $0 reload"
        echo "  进入容器: $0 shell"
        echo "  停止服务: $0 stop"
        echo "  查看状态: $0 config"
    else
        log_error "部署失败"
        show_logs --tail 50
        exit 1
    fi
}

# 主函数
main() {
    # 加载配置
    load_config
    
    # 如果没有参数，显示交互菜单
    if [[ $# -eq 0 ]]; then
        show_menu
        return 0
    fi
    
    local command="$1"
    
    case "$command" in
        build)
            build_image
            ;;
        run)
            run_container
            health_check
            ;;
        deploy)
            deploy
            ;;
        stop)
            stop_container
            ;;
        restart)
            restart_service
            ;;
        rebuild)
            rebuild_service
            ;;
        force-pull)
            force_pull_with_options
            ;;
        logs)
            shift
            show_logs "$@"
            ;;
        shell)
            enter_shell
            ;;
        reload)
            hot_reload
            ;;
        health)
            health_check
            ;;
        status)
            show_status
            ;;
        config)
            show_config
            ;;
        menu)
            show_menu
            ;;
        clean)
            cleanup
            ;;
        -h|--help|help)
            show_help
            ;;
        *)
            log_error "未知命令: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 上传脚本到 FTP 服务器
upload_script() {
    log_info "🚀 准备上传 deploy.sh 到 FTP 服务器..."
    
    # 检查 .env 文件是否存在
    if [ ! -f ".env" ]; then
        log_error "缺少.env文件或.env中没有SCRIPT_FTP配置"
        exit 1
    fi
    
    # 加载环境变量
    source ".env"
    
    # 初始化 FTP 配置变量
    SCRIPT_FTP_HOST="${SCRIPT_FTP_HOST:-}"
    SCRIPT_FTP_USER="${SCRIPT_FTP_USER:-}"
    SCRIPT_FTP_PASS="${SCRIPT_FTP_PASS:-}"
    SCRIPT_FTP_PATH="${SCRIPT_FTP_PATH:-}"
    SCRIPT_FTP_URL="${SCRIPT_FTP_URL:-}"
    
    # 检查是否有任何 SCRIPT_FTP 配置
    if [ -z "$SCRIPT_FTP_URL" ] && [ -z "$SCRIPT_FTP_HOST" ] && [ -z "$SCRIPT_FTP_USER" ] && [ -z "$SCRIPT_FTP_PASS" ]; then
        log_error "缺少.env文件或.env中没有SCRIPT_FTP配置"
        exit 1
    fi
    
    # 如果设置了完整的 FTP URL，解析各个组件
    if [ -n "$SCRIPT_FTP_URL" ]; then
        log_info "✅ 检测到完整的 FTP URL 配置"
        
        # 解析 FTP URL: ftp://user:pass@host:port/path
        case "$SCRIPT_FTP_URL" in
            ftp://*)
                # 移除 ftp:// 前缀
                temp_url="${SCRIPT_FTP_URL#ftp://}"
                
                # 检查是否包含认证信息
                case "$temp_url" in
                    *@*)
                        # 提取认证信息 (user:pass)
                        auth_part="${temp_url%%@*}"
                        remaining="${temp_url#*@}"
                        
                        # 分离用户名和密码
                        SCRIPT_FTP_USER="${auth_part%%:*}"
                        SCRIPT_FTP_PASS="${auth_part#*:}"
                        
                        # 处理主机和路径
                        case "$remaining" in
                            */*)
                                # 包含路径
                                host_port="${remaining%%/*}"
                                SCRIPT_FTP_PATH="/${remaining#*/}"
                                ;;
                            *)
                                # 不包含路径
                                host_port="$remaining"
                                SCRIPT_FTP_PATH="/srv/deploy.sh"
                                ;;
                        esac
                        
                        # 处理端口号
                        SCRIPT_FTP_HOST="$host_port"
                        
                        log_info "   用户: $SCRIPT_FTP_USER"
                        log_info "   主机: $SCRIPT_FTP_HOST"
                        log_info "   路径: $SCRIPT_FTP_PATH"
                        ;;
                    *)
                        log_error "❌ FTP URL 格式错误，缺少认证信息"
                        log_error "   应为: ftp://user:pass@host:port/path"
                        exit 1
                        ;;
                esac
                ;;
            *)
                log_error "❌ FTP URL 格式错误，应为: ftp://user:pass@host:port/path"
                exit 1
                ;;
        esac
    fi
    
    # 显示使用的配置
    if [ -n "$SCRIPT_FTP_HOST" ]; then
        # 显示时去掉协议部分，只显示主机地址
        FTP_HOST_DISPLAY=$(echo "$SCRIPT_FTP_HOST" | sed 's|^ftp://||')
        log_info "✅ 使用配置的 FTP 服务器: $FTP_HOST_DISPLAY"
    fi
    
    if [ -n "$SCRIPT_FTP_USER" ]; then
        log_info "✅ 使用配置的 FTP 用户: $SCRIPT_FTP_USER"
    fi
    
    if [ -n "$SCRIPT_FTP_PASS" ]; then
        log_info "✅ 使用配置的 FTP 密码"
    fi
    
    # 设置默认上传路径
    if [ -z "$SCRIPT_FTP_PATH" ]; then
        SCRIPT_FTP_PATH="/srv/deploy.sh"
    fi
    log_info "📁 上传路径: $SCRIPT_FTP_PATH"
    
    # 检查当前脚本文件
    SCRIPT_FILE="$0"
    if [ ! -f "$SCRIPT_FILE" ]; then
        log_error "❌ 错误: 无法找到脚本文件 $SCRIPT_FILE"
        exit 1
    fi
    
    # 获取文件大小
    FILE_SIZE=$(stat -f%z "$SCRIPT_FILE" 2>/dev/null || stat -c%s "$SCRIPT_FILE" 2>/dev/null)
    log_info "📄 文件信息: $(basename "$SCRIPT_FILE") ($FILE_SIZE 字节)"
    
    # 使用 curl 上传文件到 FTP
    log_info "🔄 正在上传..."
    
    # 构建 FTP URL
    # 检查 SCRIPT_FTP_HOST 是否已经包含协议
    case "$SCRIPT_FTP_HOST" in
        ftp://*)
            # 已经包含协议，直接使用
            FTP_URL="${SCRIPT_FTP_HOST%/}${SCRIPT_FTP_PATH}"
            ;;
        *)
            # 不包含协议，添加 ftp://
            FTP_URL="ftp://$SCRIPT_FTP_HOST$SCRIPT_FTP_PATH"
            ;;
    esac
    
    # 执行上传
    curl -T "$SCRIPT_FILE" \
         --user "$SCRIPT_FTP_USER:$SCRIPT_FTP_PASS" \
         --ftp-create-dirs \
         --progress-bar \
         "$FTP_URL" 2>&1 | tee /tmp/deploy_ftp_upload.log
    
    UPLOAD_RESULT=${PIPESTATUS[0]}
    
    if [ $UPLOAD_RESULT -eq 0 ]; then
        echo ""
        log_success "✅ 上传成功！"
        # 显示时去掉协议部分
        FTP_HOST_DISPLAY=$(echo "$SCRIPT_FTP_HOST" | sed 's|^ftp://||')
        log_info "   服务器: $FTP_HOST_DISPLAY"
        log_info "   路径: $SCRIPT_FTP_PATH"
        log_info "   文件大小: $FILE_SIZE 字节"
    else
        echo ""
        log_error "❌ 上传失败"
        log_error "错误日志:"
        cat /tmp/deploy_ftp_upload.log
        echo ""
        log_warning "💡 可能的原因:"
        log_warning "   1. FTP 服务器地址或端口不正确"
        log_warning "   2. 用户名或密码错误"
        log_warning "   3. 没有上传权限"
        log_warning "   4. 网络连接问题"
        exit 1
    fi
    
    # 清理临时文件
    rm -f /tmp/deploy_ftp_upload.log
    
    exit 0
}

# 参数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -n|--name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -e|--env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        --upload)
            upload_script
            ;;
        --debug)
            DEBUG="true"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# 执行主函数
main "$@"