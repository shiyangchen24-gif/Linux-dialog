#!/usr/bin/env bash
# 自動截圖腳本：在虛擬螢幕 (Xvfb) 中以 xterm + tmux 執行 drug_manager.sh，
# 用 tmux send-keys 模擬按鍵，並以 ImageMagick import 擷取每個步驟的畫面。
# 需要套件：dialog tmux xvfb xterm imagemagick fonts-noto-cjk fonts-dejavu
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMG="$ROOT/images"
export DISPLAY=:99 LANG=C.UTF-8
mkdir -p "$IMG"

Xvfb :99 -screen 0 1600x1000x24 >/dev/null 2>&1 &
XVFB_PID=$!
trap 'tmux kill-session -t drug 2>/dev/null; kill $XVFB_PID 2>/dev/null' EXIT
sleep 1

start_app() {   # start_app [環境變數設定]
    pkill -f "xterm -geometry 90x26" 2>/dev/null || true
    tmux kill-session -t drug 2>/dev/null || true
    cp "$ROOT/drugs.sample.db" "$ROOT/drugs.db"
    tmux new-session -d -s drug -x 90 -y 26 "cd '$ROOT' && env -u ANTHROPIC_API_KEY $1 ./drug_manager.sh; sleep 1000"
    tmux set -g status off
    xterm -geometry 90x26+0+0 -bw 0 -fa "DejaVu Sans Mono" -fd "Noto Sans Mono CJK TC" \
          -fs 13 -bg black -fg white -e "tmux attach -t drug" >/dev/null 2>&1 </dev/null &
    sleep 2
}
start_app

k()    { tmux send-keys -t drug "$@"; sleep 0.4; }          # 送出按鍵
t()    { tmux send-keys -t drug -l "$1"; sleep 0.4; }       # 送出文字
snap() { sleep "${2:-0.8}"; import -window root /tmp/_raw.png
         convert /tmp/_raw.png -crop 990x572+2+2 +repage "$IMG/$1.png"; }

t "admin123";                                   snap 01_login
tmux send-keys -t drug Enter;                   snap 02_loading 0.7
sleep 2;                                        snap 03_main_menu
k Enter; sleep 0.5
t "布洛芬止痛錠"; k Down; t "50"; k Down; k Down; t "B-03"; snap 04_add_form
k Enter; k Down; k Space;                       snap 05_category
k Enter; sleep 0.5; for i in $(seq 10); do k NPage; done; snap 06_calendar
k Enter;                                        snap 07_add_success
k Enter
k 2; k Enter;                                   snap 08_list
k Enter
k 3; k Enter; t "處方";                         snap 09_search_input
k Enter;                                        snap 10_search_result
k Enter
k 4; k Enter; k Down;                           snap 11_stock_select
k Enter; k Down;                                snap 12_stock_type
k Enter; t "5";                                 snap 13_stock_amount
k Enter;                                        snap 14_stock_result
k Enter
k 6; k Enter;                                   snap 15_alert
k Enter
k 7; k Enter;                                   snap 20_ai_no_key
k Enter
k 5; k Enter; k End;                            snap 16_delete_select
k Enter; k Left;                                snap 17_delete_confirm
k Enter;                                        snap 18_delete_done
k Enter
k 0; k Enter;                                   snap 19_exit
k Enter

# 第二輪：設定 API 金鑰後的 AI 助理畫面
# 若環境中有真正的 ANTHROPIC_API_KEY 就用它（可截到 AI 實際回覆）；
# 沒有的話用無效金鑰，示範錯誤處理畫面。
start_app "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-invalid-demo-key}"
t "admin123"; k Enter; sleep 2.5
k 7; k Enter;                                   snap 21_ai_menu
k 4; k Enter; t "哪些藥品需要優先補貨？";       snap 22_ai_input
tmux send-keys -t drug Enter; sleep 1
while tmux capture-pane -p -t drug | grep -q "AI 分析中"; do sleep 1; done
                                                snap 23_ai_reply
k Enter; k 0; k Enter; k Enter
echo "截圖完成：$IMG"
