#!/usr/bin/env bash
# Transcrição local de clipes de vídeo/áudio usando Whisper (openai-whisper / faster-whisper)
# Substitui a necessidade de GROQ_API_KEY no kit claude-editing-skills.
# Uso: ./transcribe-local.sh <arquivo_de_video_ou_audio> [modelo] [idioma]
# Modelos: tiny, base, small, medium, large (padrão: base)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$SCRIPT_DIR/kit"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()  { printf '\033[32m✓\033[0m %s\n' "$*"; }
err() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; }

INPUT="${1:?Uso: $0 <arquivo_de_video_ou_audio> [modelo] [idioma]}"
MODEL="${2:-base}"
LANGUAGE="${3:-pt}"

VALID_MODELS="tiny base small medium large"
if ! echo "$VALID_MODELS" | tr ' ' '\n' | grep -qx "$MODEL"; then
  err "Modelo inválido '$MODEL'. Use: $VALID_MODELS"
  exit 1
fi

if [ ! -f "$INPUT" ]; then
  err "Arquivo não encontrado: $INPUT"
  exit 1
fi

# Extrai áudio se for vídeo
EXT="${INPUT##*.}"
AUDIO_FILE="$INPUT"
if echo "mp4 mkv mov webm avi m4v" | tr ' ' '\n' | grep -qix "$EXT"; then
  say "Extraindo áudio do vídeo..."
  AUDIO_FILE="${INPUT%.*}.wav"
  ffmpeg -hide_banner -loglevel error -i "$INPUT" -ac 1 -ar 16000 -y "$AUDIO_FILE" 2>&1 || { err "Falha ao extrair áudio"; exit 1; }
  ok "Áudio extraído: $AUDIO_FILE"
fi

# Tenta faster-whisper primeiro (mais rápido), depois openai-whisper
say "Transcrevendo com Whisper local (modelo: $MODEL, idioma: $LANGUAGE)..."
if python3 -c "import faster_whisper" 2>/dev/null; then
  python3 - <<PYEOF "$AUDIO_FILE" "$MODEL" "$LANGUAGE"
import sys, json
from faster_whisper import WhisperModel
audio, model, lang = sys.argv[1], sys.argv[2], sys.argv[3]
model_obj = WhisperModel(model, device="cpu", compute_type="int8")
segments, info = model_obj.transcribe(audio, language=lang, word_timestamps=True)
result = {
  "language": info.language,
  "duration": info.duration,
  "segments": [
    {"start": s.start, "end": s.end, "text": s.text,
     "words": [{"word": w.word, "start": w.start, "end": w.end} for w in (s.words or [])]}
    for s in segments
  ]
}
out = audio.rsplit(".", 1)[0] + ".json"
with open(out, "w", encoding="utf-8") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
print(out)
PYEOF
  TRANSCRIPT=$(python3 - <<PYEOF "$AUDIO_FILE" "$MODEL" "$LANGUAGE"
import sys
from faster_whisper import WhisperModel
audio, model, lang = sys.argv[1], sys.argv[2], sys.argv[3]
model_obj = WhisperModel(model, device="cpu", compute_type="int8")
segments, info = model_obj.transcribe(audio, language=lang)
for s in segments:
    print(s.text.strip())
PYEOF
  )
elif python3 -c "import whisper" 2>/dev/null; then
  python3 - <<PYEOF "$AUDIO_FILE" "$MODEL" "$LANGUAGE"
import sys, json
import whisper
audio, model, lang = sys.argv[1], sys.argv[2], sys.argv[3]
model_obj = whisper.load_model(model)
result = model_obj.transcribe(audio, language=lang, word_timestamps=True)
out = audio.rsplit(".", 1)[0] + ".json"
with open(out, "w", encoding="utf-8") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
print(out)
PYEOF
  TRANSCRIPT=$(python3 -c "
import whisper, sys
model = whisper.load_model('$MODEL')
result = model.transcribe('$AUDIO_FILE', language='$LANGUAGE')
print(result['text'].strip())
")
else
  err "Nem faster-whisper nem openai-whisper estão instalados"
  exit 1
fi

ok "Transcrição concluída:"
echo "$TRANSCRIPT"

# Gera SRT simples
SRT_FILE="${AUDIO_FILE%.*}.srt"
python3 - <<PYEOF "$AUDIO_FILE" "$SRT_FILE"
import sys, json
audio, srt = sys.argv[1], sys.argv[2]
json_file = audio.rsplit(".", 1)[0] + ".json"
try:
    with open(json_file, encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    sys.exit(0)

def fmt(t):
    h = int(t // 3600); m = int((t % 3600) // 60); s = int(t % 60); ms = int((t % 1) * 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

with open(srt, "w", encoding="utf-8") as f:
    for i, seg in enumerate(data["segments"], 1):
        f.write(f"{i}\n{fmt(seg['start'])} --> {fmt(seg['end'])}\n{seg['text'].strip()}\n\n")
PYEOF
ok "SRT gerado: $SRT_FILE"

# Limpa áudio extraído se não era o original
if [ "$AUDIO_FILE" != "$INPUT" ]; then
  rm -f "$AUDIO_FILE"
fi

say "Pronto. Arquivos: ${AUDIO_FILE%.*}.json e $SRT_FILE"
