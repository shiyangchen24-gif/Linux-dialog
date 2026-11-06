#!/usr/bin/env bash
# 產生「AI 回覆」的模擬截圖（images/24、25_ai_reply_simulated*.png）。
# 畫面版面與 drug_manager.sh 的 AI 回覆相同，內容取自 tools/ai_reply_example.txt，
# 並非 AI 實際回覆。需要套件同 capture_screenshots.sh。
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export DISPLAY=:99 LANG=C.UTF-8
Xvfb :99 -screen 0 1600x1000x24 >/dev/null 2>&1 &
XVFB_PID=$!
trap 'tmux kill-session -t sim 2>/dev/null; kill $XVFB_PID 2>/dev/null' EXIT
sleep 1
tmux new-session -d -s sim -x 90 -y 26 "dialog --backtitle '藥品管理系統' --title 'AI 回覆（模擬範例）' \
    --exit-label '返回' --textbox '$ROOT/tools/ai_reply_example.txt' 22 80; sleep 100"
tmux set -g status off
xterm -geometry 90x26+0+0 -bw 0 -fa "DejaVu Sans Mono" -fd "Noto Sans Mono CJK TC" \
      -fs 13 -bg black -fg white -e "tmux attach -t sim" >/dev/null 2>&1 </dev/null &
sleep 2.5
snap() { sleep 0.8; import -window root /tmp/_raw.png
         convert /tmp/_raw.png -crop 990x572+2+2 +repage "$ROOT/images/$1.png"; }
snap 24_ai_reply_simulated                    # 上半部
tmux send-keys -t sim End; snap 25_ai_reply_simulated_2   # 捲到最下面
echo "已產生 images/24_ai_reply_simulated.png、25_ai_reply_simulated_2.png"
