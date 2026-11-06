#!/usr/bin/env bash
# ============================================================
#  藥品管理系統 (Drug Management System) — 使用 Linux dialog 建立
#  資料格式 (drugs.db)，每行一筆，以 | 分隔：
#     編號|藥品名稱|類別|數量|單位|有效期限(YYYY-MM-DD)|存放位置
# ============================================================

export LANG=${LANG:-C.UTF-8}

# ---------- 基本設定 ----------
APP_TITLE="藥品管理系統"
DB_FILE="${DB_FILE:-$(dirname "$0")/drugs.db}"
ADMIN_PASS="${ADMIN_PASS:-admin123}"
LOW_STOCK=20          # 低於此數量視為庫存不足
EXPIRE_DAYS=90        # 幾天內到期視為即將到期
AI_MODEL="${AI_MODEL:-claude-opus-5-5}"   # AI 助理使用的模型
TMP=$(mktemp)
trap 'rm -f "$TMP"; clear' EXIT

touch "$DB_FILE"

# ---------- 共用函式 ----------
next_id() {
    local last
    last=$(cut -d'|' -f1 "$DB_FILE" | sed 's/^D//' | sort -n | tail -1)
    printf "D%03d" $(( 10#${last:-0} + 1 ))
}

msg() {   # msg "標題" "內容"
    dialog --backtitle "$APP_TITLE" --title "$1" --msgbox "$2" 14 50
}

# 依「顯示寬度」補空白（中文字佔 2 格，printf 的 %-10s 會對不齊）
pad() {   # pad "文字" 寬度
    local w
    w=$(printf '%s' "$1" | wc -L)
    printf '%s%*s' "$1" $(( $2 > w ? $2 - w : 0 )) ""
}

# 產生「編號 名稱」清單，給 menu / radiolist 使用
drug_items() {
    while IFS='|' read -r id name cat qty unit exp loc; do
        [ -n "$id" ] && printf '%s\n%s\n' "$id" "$name (庫存 $qty $unit)"
    done < "$DB_FILE"
}

# ---------- 1. 登入 ----------
login() {
    local pass
    pass=$(dialog --backtitle "$APP_TITLE" --title "管理員登入" \
        --insecure --passwordbox "請輸入管理員密碼：" 8 40 3>&1 1>&2 2>&3) || exit 0
    if [ "$pass" != "$ADMIN_PASS" ]; then
        msg "登入失敗" "密碼錯誤，程式結束。"
        exit 1
    fi
}

# ---------- 2. 載入進度條 ----------
loading() {
    for i in 0 20 40 60 80 100; do
        echo "$i"
        sleep 0.3
    done | dialog --backtitle "$APP_TITLE" --title "系統啟動" \
        --gauge "正在載入藥品資料庫..." 8 50 0
}

# ---------- 3. 新增藥品 ----------
add_drug() {
    local form name qty unit loc cat exp id
    form=$(dialog --backtitle "$APP_TITLE" --title "新增藥品" \
        --form "請填寫藥品資料（↑↓ 切換欄位）：" 14 60 4 \
        "藥品名稱：" 1 1 "" 1 14 30 40 \
        "數    量：" 2 1 "" 2 14 10 10 \
        "單    位：" 3 1 "盒" 3 14 10 10 \
        "存放位置：" 4 1 "" 4 14 20 30 \
        3>&1 1>&2 2>&3) || return
    { read -r name; read -r qty; read -r unit; read -r loc; } <<< "$form"

    if [ -z "$name" ] || ! [[ "$qty" =~ ^[0-9]+$ ]]; then
        msg "輸入錯誤" "藥品名稱不可空白，數量必須為正整數。"
        return
    fi

    cat=$(dialog --backtitle "$APP_TITLE" --title "藥品類別" \
        --radiolist "請選擇「$name」的類別（空白鍵選取）：" 14 50 5 \
        "處方藥"   "需醫師處方" on \
        "指示藥"   "需藥師指示" off \
        "成藥"     "可自行購買" off \
        "管制藥品" "需特別管理" off \
        "保健食品" "非藥品類"   off \
        3>&1 1>&2 2>&3) || return

    exp=$(dialog --backtitle "$APP_TITLE" --title "有效期限" \
        --date-format "%Y-%m-%d" \
        --calendar "請選擇「$name」的有效期限：" 0 0 \
        3>&1 1>&2 2>&3) || return

    id=$(next_id)
    echo "$id|$name|$cat|$qty|$unit|$exp|$loc" >> "$DB_FILE"
    msg "新增成功" "已新增藥品：\n\n編號：$id\n名稱：$name\n類別：$cat\n數量：$qty $unit\n期限：$exp"
}

# ---------- 4. 藥品清單 ----------
list_drugs() {
    {
        echo "$(pad 編號 6)$(pad 藥品名稱 16)$(pad 類別 10)$(pad 數量 6)$(pad 單位 6)$(pad 有效期限 12)位置"
        printf -- '-%.0s' {1..64}; echo
        while IFS='|' read -r id name cat qty unit exp loc; do
            [ -n "$id" ] && echo "$(pad "$id" 6)$(pad "$name" 16)$(pad "$cat" 10)$(pad "$qty" 6)$(pad "$unit" 6)$(pad "$exp" 12)$loc"
        done < "$DB_FILE"
        echo
        echo "共 $(grep -c . "$DB_FILE") 筆藥品資料"
    } > "$TMP"
    dialog --backtitle "$APP_TITLE" --title "藥品清單" \
        --exit-label "返回" --textbox "$TMP" 20 76
}

# ---------- 5. 查詢藥品 ----------
search_drug() {
    local key result
    key=$(dialog --backtitle "$APP_TITLE" --title "查詢藥品" \
        --inputbox "請輸入藥品名稱、編號或類別關鍵字：" 8 50 \
        3>&1 1>&2 2>&3) || return
    [ -z "$key" ] && return
    result=$(grep -i -- "$key" "$DB_FILE" | \
        awk -F'|' '{printf "[%s] %s\n   類別:%s  數量:%s %s\n   期限:%s  位置:%s\n\n",$1,$2,$3,$4,$5,$6,$7}')
    [ -z "$result" ] && result="查無符合「$key」的藥品。"
    dialog --backtitle "$APP_TITLE" --title "查詢結果：$key" --msgbox "$result" 18 60
}

# ---------- 6. 修改庫存（進貨 / 領用） ----------
update_stock() {
    local id action amount line qty newqty
    [ -s "$DB_FILE" ] || { msg "提示" "目前沒有藥品資料。"; return; }
    mapfile -t items < <(drug_items)
    id=$(dialog --backtitle "$APP_TITLE" --title "修改庫存" \
        --menu "請選擇要異動的藥品：" 16 60 8 "${items[@]}" \
        3>&1 1>&2 2>&3) || return

    action=$(dialog --backtitle "$APP_TITLE" --title "異動類型" \
        --menu "請選擇異動類型：" 10 40 2 \
        "IN"  "進貨（增加庫存）" \
        "OUT" "領用（減少庫存）" \
        3>&1 1>&2 2>&3) || return

    amount=$(dialog --backtitle "$APP_TITLE" --title "異動數量" \
        --inputbox "請輸入數量：" 8 40 3>&1 1>&2 2>&3) || return
    [[ "$amount" =~ ^[0-9]+$ ]] || { msg "輸入錯誤" "數量必須為正整數。"; return; }

    line=$(grep "^$id|" "$DB_FILE")
    qty=$(cut -d'|' -f4 <<< "$line")
    if [ "$action" = "IN" ]; then
        newqty=$(( qty + amount ))
    else
        newqty=$(( qty - amount ))
        [ "$newqty" -lt 0 ] && { msg "庫存不足" "目前庫存只有 $qty，無法領用 $amount。"; return; }
    fi
    awk -F'|' -v OFS='|' -v id="$id" -v q="$newqty" '$1==id{$4=q}1' \
        "$DB_FILE" > "$TMP" && cat "$TMP" > "$DB_FILE"
    msg "異動完成" "$(cut -d'|' -f2 <<< "$line")\n\n原庫存：$qty\n異動量：$action $amount\n新庫存：$newqty"
}

# ---------- 7. 刪除藥品 ----------
delete_drug() {
    local id name
    [ -s "$DB_FILE" ] || { msg "提示" "目前沒有藥品資料。"; return; }
    mapfile -t items < <(drug_items)
    id=$(dialog --backtitle "$APP_TITLE" --title "刪除藥品" \
        --menu "請選擇要刪除的藥品：" 16 60 8 "${items[@]}" \
        3>&1 1>&2 2>&3) || return
    name=$(grep "^$id|" "$DB_FILE" | cut -d'|' -f2)
    if dialog --backtitle "$APP_TITLE" --title "確認刪除" --defaultno \
        --yesno "確定要刪除「$id $name」嗎？\n此動作無法復原！" 8 45; then
        grep -v "^$id|" "$DB_FILE" > "$TMP"; cat "$TMP" > "$DB_FILE"
        msg "刪除完成" "已刪除：$id $name"
    fi
}

# ---------- 8. 庫存 / 效期警示 ----------
alert_report() {
    local today limit c
    today=$(date +%Y-%m-%d)
    limit=$(date -d "+$EXPIRE_DAYS days" +%Y-%m-%d)
    {
        echo "【庫存不足】(數量 < $LOW_STOCK)"
        c=0
        while IFS='|' read -r id name cat qty unit exp loc; do
            [ -n "$id" ] && [ "$qty" -lt "$LOW_STOCK" ] && { echo "  $(pad "$id" 6)$(pad "$name" 14)剩 $qty $unit"; c=1; }
        done < "$DB_FILE"; [ $c = 0 ] && echo "  無"
        echo
        echo "【已過期】(早於 $today)"
        c=0
        while IFS='|' read -r id name cat qty unit exp loc; do
            [ -n "$id" ] && [[ "$exp" < "$today" ]] && { echo "  $(pad "$id" 6)$(pad "$name" 14)期限 $exp"; c=1; }
        done < "$DB_FILE"; [ $c = 0 ] && echo "  無"
        echo
        echo "【即將到期】($EXPIRE_DAYS 天內，至 $limit)"
        c=0
        while IFS='|' read -r id name cat qty unit exp loc; do
            [ -n "$id" ] && ! [[ "$exp" < "$today" ]] && ! [[ "$exp" > "$limit" ]] && { echo "  $(pad "$id" 6)$(pad "$name" 14)期限 $exp"; c=1; }
        done < "$DB_FILE"; [ $c = 0 ] && echo "  無"
    } > "$TMP"
    dialog --backtitle "$APP_TITLE" --title "庫存與效期警示" \
        --exit-label "返回" --textbox "$TMP" 20 60
}

# ---------- 9. AI 藥品助理 ----------
# 把問題和目前的藥品資料送到 Claude API，回答只顯示給使用者看，
# 不會修改 drugs.db（進貨、領用、刪除仍需人工操作）。
ai_ask() {   # ai_ask "問題" → 輸出 AI 的回答文字
    local body resp
    body=$(jq -n --arg model "$AI_MODEL" --arg q "$1" \
        --rawfile db "$DB_FILE" --arg today "$(date +%F)" '{
        model: $model,
        max_tokens: 4000,
        output_config: {effort: "low"},
        fallbacks: "default",
        system: "你是藥局庫存管理助理。只根據提供的藥品資料回答，使用繁體中文，回答精簡、條列清楚，不使用 Markdown 語法。涉及用藥或醫療判斷時，提醒以醫師或藥師判斷為準。",
        messages: [{role: "user",
            content: ("今天日期：" + $today
                + "\n藥品資料（編號|名稱|類別|數量|單位|有效期限|位置）：\n" + $db
                + "\n問題：" + $q)}]
    }')

    resp=$(curl -s --max-time 120 https://api.anthropic.com/v1/messages \
        -H "Content-Type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2026-10-21" \
        -H "anthropic-beta: server-side-fallback-2026-07-01" \
        -d "$body") || { echo "連線失敗，請檢查網路。"; return 1; }

    if [ "$(jq -r '.stop_reason // empty' <<< "$resp" 2>/dev/null)" = "refusal" ]; then
        echo "AI 無法回答這個問題，請換個方式提問。"
        return 1
    fi
    # 回應的 content 可能含 thinking 區塊，只取 type 為 text 的部分
    jq -r '.content[]? | select(.type == "text") | .text' <<< "$resp" 2>/dev/null | grep . \
        || { echo "呼叫失敗：$(jq -r '.error.message // "無法解析回應"' <<< "$resp" 2>/dev/null)"; return 1; }
}

ai_assistant() {
    local question
    for cmd in curl jq; do
        command -v "$cmd" >/dev/null || { msg "缺少套件" "AI 助理需要 $cmd，請先安裝：\n\nsudo apt install -y curl jq"; return; }
    done
    if [ -z "$ANTHROPIC_API_KEY" ]; then
        msg "尚未設定 API 金鑰" "請先在終端機設定 Claude API 金鑰再啟動程式：\n\nexport ANTHROPIC_API_KEY=\"你的金鑰\"\n./drug_manager.sh"
        return
    fi

    question=$(dialog --backtitle "$APP_TITLE" --title "AI 藥品助理" \
        --menu "請選擇常用問題，或選「自行輸入」：" 14 64 5 \
        1 "分析目前庫存，列出需要優先補貨的藥品" \
        2 "列出已過期和即將到期的藥品，並建議處理方式" \
        3 "管制藥品的庫存管理要注意什麼" \
        4 "自行輸入問題" \
        3>&1 1>&2 2>&3) || return
    case "$question" in
        1) question="分析目前庫存，列出需要優先補貨的藥品並說明原因" ;;
        2) question="列出已過期和即將到期的藥品，並建議處理方式" ;;
        3) question="根據目前資料，管制藥品的庫存管理要注意什麼" ;;
        4) question=$(dialog --backtitle "$APP_TITLE" --title "AI 藥品助理" \
               --inputbox "請輸入問題：" 8 60 3>&1 1>&2 2>&3) || return
           [ -z "$question" ] && return ;;
    esac

    dialog --backtitle "$APP_TITLE" --title "AI 藥品助理" \
        --infobox "AI 分析中，請稍候...\n\n問題：$question" 7 64
    ai_ask "$question" > "$TMP"
    dialog --backtitle "$APP_TITLE" --title "AI 回覆" \
        --exit-label "返回" --textbox "$TMP" 22 80
}

# ---------- 主選單 ----------
main_menu() {
    local choice
    while true; do
        choice=$(dialog --backtitle "$APP_TITLE" --title "主選單" \
            --cancel-label "離開" \
            --menu "請選擇功能（↑↓ 移動，Enter 確認）：" 17 50 8 \
            1 "新增藥品" \
            2 "藥品清單" \
            3 "查詢藥品" \
            4 "修改庫存（進貨/領用）" \
            5 "刪除藥品" \
            6 "庫存與效期警示" \
            7 "AI 藥品助理" \
            0 "離開系統" \
            3>&1 1>&2 2>&3) || choice=0

        case "$choice" in
            1) add_drug ;;
            2) list_drugs ;;
            3) search_drug ;;
            4) update_stock ;;
            5) delete_drug ;;
            6) alert_report ;;
            7) ai_assistant ;;
            0) dialog --backtitle "$APP_TITLE" --title "離開" \
                   --yesno "確定要離開藥品管理系統嗎？" 7 40 && break ;;
        esac
    done
}

# ---------- 程式進入點 ----------
login
loading
main_menu
