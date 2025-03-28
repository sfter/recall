#!/bin/bash

# 脚本名称：recall.sh
# 用途：交互式菜单驱动的 Recall CLI 自动化脚本

# 定义变量
REPO_URL="https://github.com/recallnet/rust-recall.git"
INSTALL_DIR="$HOME/rust-recall"
ENV_FILE="$HOME/.recall_env"
TEST_FILE="$HOME/test.txt"
TEST_KEY="testfile"
TRANSFER_AMOUNT="0.1"

# 检查 Recall CLI 是否已安装
check_installation() {
    if command -v recall &> /dev/null; then
        echo "检测到 Recall CLI 已安装，版本："
        recall --version
        return 0
    fi
    return 1
}

# 检查依赖是否安装
install_dependencies() {
    echo "检查依赖..."
    if ! command -v git &> /dev/null; then
        echo "未找到 Git，正在安装..."
        sudo apt update && sudo apt install -y git
    fi
    if ! command -v make &> /dev/null; then
        echo "未找到 Make，正在安装..."
        sudo apt update && sudo apt install -y make
    fi
    if ! command -v cargo &> /dev/null; then
        echo "未找到 Rust/Cargo，正在安装..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    if ! command -v jq &> /dev/null; then
        echo "未找到 jq，正在安装..."
        sudo apt update && sudo apt install -y jq
    fi
}

# 安装 Recall CLI
install_recall() {
    echo "克隆 Recall 仓库..."
    if [ -d "$INSTALL_DIR" ]; then
        echo "目录已存在，更新代码..."
        cd "$INSTALL_DIR" && git pull
    else
        git clone "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
    fi

    echo "编译并安装 Recall CLI..."
    make install

    if [ $? -eq 0 ]; then
        echo "安装成功！验证版本..."
        recall --version
    else
        echo "安装失败，请检查错误信息。"
        exit 1
    fi
}

# 配置环境变量
configure_env() {
    echo "现在配置环境变量..."

    # 输入私钥（隐藏输入）
    read -s -p "请输入您的 RECALL_PRIVATE_KEY（输入时不会显示）： " PRIVATE_KEY
    echo "" # 换行
    if [ -z "$PRIVATE_KEY" ]; then
        echo "错误：私钥不能为空！"
        exit 1
    fi

    # 选择网络
    echo "请选择网络（输入编号）："
    echo "1. testnet（默认测试网）"
    echo "2. mainnet（主网）"
    echo "3. devnet（开发网）"
    echo "4. localnet（本地网，注意：已弃用）"
    read -p "您的选择 [1-4，默认 1]： " NETWORK_CHOICE

    case $NETWORK_CHOICE in
        2) NETWORK="mainnet" ;;
        3) NETWORK="devnet" ;;
        4) NETWORK="localnet" ;;
        ""|1|*) NETWORK="testnet" ;;
    esac
    echo "已选择网络：$NETWORK"

    # 创建环境变量文件
    echo "保存环境变量到 $ENV_FILE..."
    cat > "$ENV_FILE" << EOL
export RECALL_PRIVATE_KEY=$PRIVATE_KEY
export RECALL_NETWORK=$NETWORK
EOL

    # 加载环境变量
    echo "加载环境变量..."
    source "$ENV_FILE"
}

# 验证 CLI
verify_cli() {
    echo "验证 Recall CLI..."
    if recall --help &> /dev/null; then
        echo "Recall CLI 配置完成！可以开始使用：recall --help"
    else
        echo "验证失败，请检查输入的私钥或网络配置。"
        exit 1
    fi
}

# 自动加载环境变量（如果存在）
auto_load_env() {
    if [ -f "$ENV_FILE" ]; then
        echo "检测到环境变量文件 $ENV_FILE，自动加载..."
        source "$ENV_FILE"
        echo "环境变量加载成功：RECALL_PRIVATE_KEY=$RECALL_PRIVATE_KEY, RECALL_NETWORK=$RECALL_NETWORK"
    else
        echo "未找到环境变量文件 $ENV_FILE，请选择选项 2 配置环境变量。"
    fi
}

# 创建存储桶
create_bucket() {
    echo "创建存储桶..."
    BUCKET_OUTPUT=$(recall bucket create)
    if [ $? -eq 0 ]; then
        BUCKET_ADDRESS=$(echo "$BUCKET_OUTPUT" | jq -r '.address')
        echo "存储桶创建成功，地址：$BUCKET_ADDRESS"
        echo "$BUCKET_ADDRESS" > /tmp/recall_bucket_address
    else
        echo "存储桶创建失败，请检查错误信息。"
        exit 1
    fi
}

# 获取存储桶地址
get_bucket_address() {
    if [ -f /tmp/recall_bucket_address ]; then
        BUCKET_ADDRESS=$(cat /tmp/recall_bucket_address)
        if [ -z "$BUCKET_ADDRESS" ]; then
            echo "错误：未找到存储桶地址，请先创建存储桶。"
            exit 1
        fi
    else
        echo "错误：未找到存储桶地址，请先创建存储桶。"
        exit 1
    fi
}

# 生成目标地址（用于转账）
generate_target_address() {
    echo "生成目标地址（用于转账）..."
    TARGET_OUTPUT=$(recall account create)
    if [ $? -eq 0 ]; then
        TARGET_ADDRESS=$(echo "$TARGET_OUTPUT" | jq -r '.address')
        echo "目标地址生成成功：$TARGET_ADDRESS"
        echo "$TARGET_ADDRESS" > /tmp/recall_target_address
    else
        echo "目标地址生成失败，请检查错误信息。"
        exit 1
    fi
}

# 获取目标地址
get_target_address() {
    if [ -f /tmp/recall_target_address ]; then
        TARGET_ADDRESS=$(cat /tmp/recall_target_address)
        if [ -z "$TARGET_ADDRESS" ]; then
            echo "错误：未找到目标地址，请先生成目标地址。"
            exit 1
        fi
    else
        echo "错误：未找到目标地址，请先生成目标地址。"
        exit 1
    fi
}

# 转账
transfer_funds() {
    get_target_address
    echo "执行转账（金额：$TRANSFER_AMOUNT）..."
    recall account transfer --to "$TARGET_ADDRESS" "$TRANSFER_AMOUNT"
    if [ $? -eq 0 ]; then
        echo "转账成功！"
    else
        echo "转账失败，请检查余额或网络配置。"
        exit 1
    fi
}

# 上传文件
upload_file() {
    get_bucket_address
    echo "创建测试文件..."
    echo "Hello, Recall!" > "$TEST_FILE"

    echo "上传文件到存储桶..."
    recall bucket add --address "$BUCKET_ADDRESS" --key "$TEST_KEY" "$TEST_FILE"
    if [ $? -eq 0 ]; then
        echo "文件上传成功！"
    else
        echo "文件上传失败，请检查信用或余额。"
        exit 1
    fi
}

# 下载文件
download_file() {
    get_bucket_address
    echo "下载文件以验证..."
    recall bucket get --address "$BUCKET_ADDRESS" "$TEST_KEY"
    if [ $? -eq 0 ]; then
        echo "文件下载成功！"
    else
        echo "文件下载失败，请检查存储桶或键。"
        exit 1
    fi
}

# 检查信用并购买
check_and_buy_credit() {
    echo "检查信用..."
    if [ -z "$RECALL_PRIVATE_KEY" ]; then
        echo "错误：RECALL_PRIVATE_KEY 未设置，请先配置环境变量（选项 2）。"
        exit 1
    fi
    CREDIT_INFO=$(recall account info --private-key "$RECALL_PRIVATE_KEY" | jq -r '.credit.credit_free')
    if [ $? -ne 0 ]; then
        echo "获取信用信息失败，请检查网络或私钥配置。"
        exit 1
    fi
    if [ "$CREDIT_INFO" == "0" ]; then
        echo "信用为 0，购买信用（10 单位）..."
        recall account credit buy --amount 10
        if [ $? -eq 0 ]; then
            echo "信用购买成功！"
        else
            echo "信用购买失败，请检查余额。"
            exit 1
        fi
    else
        echo "信用充足：$CREDIT_INFO"
    fi
}

# 检查账户信息
check_account() {
    echo "检查账户信息..."
    if [ -z "$RECALL_PRIVATE_KEY" ]; then
        echo "错误：RECALL_PRIVATE_KEY 未设置，请先配置环境变量（选项 2）。"
        exit 1
    fi
    recall account info --private-key "$RECALL_PRIVATE_KEY"
    if [ $? -ne 0 ]; then
        echo "获取账户信息失败，请检查网络或私钥。"
        exit 1
    fi
}

# 交互式菜单
show_menu() {
    while true; do
        clear
        echo "=== Recall CLI 自动化脚本 ==="
        echo "1. 安装 Recall CLI"
        echo "2. 配置环境变量"
        echo "3. 检查信用并购买"
        echo "4. 创建存储桶"
        echo "5. 生成转账目标地址"
        echo "6. 执行转账"
        echo "7. 上传文件到存储桶"
        echo "8. 下载文件以验证"
        echo "9. 检查账户信息"
        echo "0. 退出"
        echo "======================="
        read -p "请选择操作 [0-9]： " choice

        case $choice in
            1)
                install_dependencies
                install_recall
                press_any_key
                ;;
            2)
                configure_env
                verify_cli
                press_any_key
                ;;
            3)
                check_and_buy_credit
                press_any_key
                ;;
            4)
                create_bucket
                press_any_key
                ;;
            5)
                generate_target_address
                press_any_key
                ;;
            6)
                transfer_funds
                press_any_key
                ;;
            7)
                upload_file
                press_any_key
                ;;
            8)
                download_file
                press_any_key
                ;;
            9)
                check_account
                press_any_key
                ;;
            0)
                echo "退出脚本..."
                exit 0
                ;;
            *)
                echo "无效选择，请输入 0-9。"
                press_any_key
                ;;
        esac
    done
}

# 按任意键继续
press_any_key() {
    read -p "按任意键继续..." -n1
}

# 主流程
echo "欢迎使用 Recall CLI 自动化脚本！"

# 检查是否已安装
if ! check_installation; then
    install_dependencies
    install_recall
fi

# 自动加载环境变量
auto_load_env

# 显示菜单
show_menu
