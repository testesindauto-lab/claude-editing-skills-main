#!/usr/bin/env bash
# Automatiza a instalação/atualização do pacote claude-editing-skills (alisolanki/claude-editing-skills-main)
# e valida que todas as 11 skills estão ativas no ~/.claude/skills/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://github.com/alisolanki/claude-editing-skills-main.git"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()  { printf '\033[32m✓\033[0m %s\n' "$*"; }
err() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Falta dependência: $1"; return 1; }
}

say "=== Automação: claude-editing-skills ==="

# 1. Dependências
say "Verificando dependências..."
need_cmd ffmpeg   || exit 1
need_cmd node     || exit 1
need_cmd npx      || exit 1
need_cmd python3  || exit 1
need_cmd git      || exit 1

# VP9 é necessário para as skills de cutout (behind-the-person, explainer)
ffmpeg -hide_banner -encoders 2>&1 | grep -q libvpx-vp9 \
  && ok "ffmpeg com libvpx-vp9 (VP9) disponível" \
  || { err "ffmpeg sem suporte a libvpx-vp9; cutouts podem falhar"; }

python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' \
  && ok "Python 3.9+ OK" \
  || { err "Python 3.9+ é necessário"; exit 1; }

# 2. Clona ou atualiza o repositório
if [ -d "$ROOT/.git" ]; then
  say "Atualizando repositório existente..."
  git -C "$ROOT" pull --ff-only 2>&1 || { err "Falha ao dar pull no repositório"; exit 1; }
else
  say "Clonando repositório..."
  rm -rf "$ROOT"
  git clone "$REPO_URL" "$ROOT" 2>&1 || { err "Falha ao clonar o repositório"; exit 1; }
fi
ok "Repositório em $ROOT"

# 3. Executa o install oficial (links as skills + setup do kit)
say "Executando install oficial..."
bash "$ROOT/install.sh" "$@" 2>&1 || { err "Falha no install.sh"; exit 1; }

# 4. Valida que as 11 skills estão linkadas
say "Validando skills instaladas..."
EXPECTED=(behind-the-person explainer orbit-reel picture-stack ranking-list scene-switch shape-shift split-screen storytelling trial-reels visual-notes)
ALL_OK=1
for skill in "${EXPECTED[@]}"; do
  if [ -L "$SKILLS_DIR/$skill" ]; then
    ok "skill /$skill linkada"
  else
    err "skill /$skill NÃO encontrada em $SKILLS_DIR/$skill"
    ALL_OK=0
  fi
done

if [ "$ALL_OK" -eq 1 ]; then
  say "=== Concluído: 11 skills instaladas e validadas ==="
else
  err "=== Algumas skills não foram instaladas corretamente ==="
  exit 1
fi

echo
echo "Transcrição local: use kit/transcribe-local.sh <video> [modelo] [idioma]"
echo "Exemplo: bash kit/transcribe-local.sh meu_video.mp4 base pt"
echo
echo "Use as skills no Claude Code: /trial-reels, /split-screen, /ranking-list, etc."
