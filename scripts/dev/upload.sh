#!/bin/bash
# 一键上传脚本 - 使用 GitHub CLI

# 请先安装 gh: https://cli.github.com/
set -euo pipefail

echo "======================================"
echo "TeslaMate 中文 Dashboard 一键上传"
echo "======================================"
echo ""

# 检查 gh 是否安装
if ! command -v gh &> /dev/null; then
    echo "❌ 请先安装 GitHub CLI:"
    echo "   https://cli.github.com/"
    echo ""
    echo "安装命令:"
    echo "  macOS: brew install gh"
    echo "  Ubuntu: sudo apt install gh"
    echo "  Windows: winget install --id GitHub.cli"
    exit 1
fi

# 检查是否登录
if ! gh auth status &> /dev/null; then
    echo "🔐 请先登录 GitHub:"
    echo "   gh auth login"
    exit 1
fi

if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "❌ 当前目录不是 Git 仓库"
    exit 1
fi

if git remote get-url origin >/dev/null 2>&1; then
    echo "❌ 已存在 origin：$(git remote get-url origin)"
    echo "   为避免推错仓库，本脚本只处理尚未配置 origin 的新仓库。"
    exit 1
fi

REPO_NAME="teslamate-chinese-dashboards"

echo "将要创建仓库: $REPO_NAME"
echo "可见性: public（提交历史和当前跟踪文件都会公开并 push）"
echo ""

if [ ! -t 0 ]; then
    echo "❌ 非交互模式拒绝创建公开仓库"
    exit 1
fi
if ! read -r -p "确认公开发布？输入 public 继续: " confirm; then
    echo ""
    echo "❌ 输入已结束，已取消公开发布"
    exit 1
fi
if [ "$confirm" != "public" ]; then
    echo "已取消"
    exit 0
fi

# 创建仓库
echo "📦 创建 GitHub 仓库..."
if ! gh repo create "$REPO_NAME" \
        --public \
        --description "TeslaMate 中文 Grafana Dashboard - 简体中文汉化版" \
        --source=. \
        --remote=origin \
        --push; then
    echo "❌ GitHub 仓库创建或 push 失败"
    exit 1
fi

if ! REPO_URL=$(gh repo view --json url -q .url 2>/dev/null) || [ -z "$REPO_URL" ]; then
    echo "❌ push 已执行，但无法确认远端仓库地址；请运行 gh repo view 检查"
    exit 1
fi

echo ""
echo "======================================"
echo "✅ 完成！"
echo "======================================"
echo ""
echo "仓库地址: $REPO_URL"
echo ""
echo "下一步:"
echo "1. 访问仓库页面"
echo "2. 点击 Settings → Topics"
echo "3. 添加标签: teslamate, grafana, dashboard, chinese, i18n"
echo "4. 分享到 TeslaMate 社区"
