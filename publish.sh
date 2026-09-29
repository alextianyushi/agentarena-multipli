#!/usr/bin/env bash
# 清掉原有 commit 历史，把 agentarena-multipli 作为一个全新仓库推到你的 GitHub
# 需要：git、gh（brew install gh），并已执行 gh auth login
# 用法：cd ~/agentarena-multipli && bash publish.sh [仓库名]
set -euo pipefail
cd "$(dirname "$0")"
NAME=${1:-agentarena-multipli}
VISIBILITY=--public   # ⚠️ 公开仓库；以后放入 PoC 或漏洞细节前请改成 --private（HackenProof 禁止公开披露）

# 1. 删除所有嵌套的 .git（官方 repo 历史和子模块），依赖作为普通文件提交
find . -mindepth 2 -name .git -prune -exec rm -rf {} +
rm -f .gitmodules Barebones-MultipliVault/.gitmodules
rm -rf .git

# 2. 忽略编译产物
cat > .gitignore <<'G'
out/
cache/
broadcast/
.env
.DS_Store
G

# 3. 全新提交
git init -q -b main
git add -A
git commit -q -m "Multipli v2 audit workspace

- Barebones-MultipliVault @ 3c37f80f (v2), history removed
- OZ-upgradeable pinned to 6b9adf75 to match on-chain deployment (evm cancun)
- test/poc/ForkBase.t.sol: Avalanche fork PoC base"
git log --oneline

# 4. 在你的账号下创建仓库并推送
gh repo create "$NAME" $VISIBILITY --source=. --remote=origin --push
