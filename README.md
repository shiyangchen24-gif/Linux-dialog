# 學習筆記：用 Linux `dialog` 建立藥品管理介面

- 姓名：＿＿＿＿＿＿　學號：＿＿＿＿＿＿
- 日期：2026-11-06
- 環境：Ubuntu 24.04、Bash、dialog 1.3-20240101、curl、jq（AI 助理功能使用）

---

## 一、作業目標

用 Bash 和 `dialog` 套件，在終端機中寫出一個有圖形化選單的**藥品管理系統**。系統要能新增、列出、查詢、修改庫存和刪除藥品，也要能提醒庫存不足和快要過期的藥品。另外，我加入了 **AI 藥品助理**：透過 Claude API 分析庫存並回答問題。

我最後完成的檔案：

| 檔案 | 內容 |
|------|------|
| `drug_manager.sh` | 主程式 |
| `drugs.sample.db` | 我建立的 5 筆範例藥品資料 |
| `images/` | 執行過程的截圖 |
| `tools/capture_screenshots.sh` | 我用來自動截圖的腳本 |

> AI 助理功能需要 Claude API 金鑰，金鑰以環境變數設定，不放在專案中。

---

## 系統流程圖

### 圖 1 系統整體流程

```text
              +----------------------+
              |  ./drug_manager.sh   |
              +----------------------+
                         |
                         v
              +----------------------+
              | 管理員登入           |
              | --passwordbox        |
              +----------------------+
                         |
                         v
                  < 密碼正確？ >
                   |          |
                  否          是
                   |          |
                   v          v
       +--------------+  +--------------+
       | 登入失敗     |  | 載入進度條   |
       | 程式結束     |  | --gauge      |
       +--------------+  +--------------+
                                |
                                v
               +--------------------------------+
   +---------->|        主選單 (--menu)         |
   |           +--------------------------------+
   |                            |
   |       +--------------------+
   |       |
   |       +-- 1 新增藥品 --> --form --> --radiolist --> --calendar
   |       |                  --> 寫入 drugs.db --> --msgbox
   |       |
   |       +-- 2 藥品清單 --> 讀取 drugs.db --> pad() 排版 --> --textbox
   |       |
   |       +-- 3 查詢藥品 --> --inputbox --> grep 搜尋 --> --msgbox
   |       |
   |       +-- 4 修改庫存 --> --menu 選藥品 --> --menu IN/OUT
   |       |                  --> --inputbox 數量 --> awk 更新 --> --msgbox
   |       |
   |       +-- 5 刪除藥品 --> --menu 選藥品 --> --yesno 確認
   |       |                  --> grep -v 刪除 --> --msgbox
   |       |
   |       +-- 6 效期警示 --> date 計算日期 --> 分類 --> --textbox
   |       |
   |       +-- 7 AI 助理  --> （見圖 2）
   |       |
   |       +-- 0 離開系統 --> --yesno --是--> 清除畫面、刪除暫存檔、結束
   |       |                      |
   |       |                      否
   |       |                      |
   +-------+<---------------------+
       (每個功能執行完都回到主選單)
```

### 圖 2 AI 藥品助理流程（選單 7）

```text
              +----------------------+
              |   選單 7 AI 助理     |
              +----------------------+
                         |
                         v
               < curl、jq 已安裝？ > --否--> --msgbox 提示安裝 --> 回主選單
                         |
                        是
                         v
               < 已設定 API 金鑰？ > --否--> --msgbox 說明設定方式 --> 回主選單
                         |
                        是
                         v
              +----------------------+
              | --menu 選擇問題      |
              | 1~3 常用問題         |
              | 4 自行輸入           |
              +----------------------+
                         |
                         v  （選 4 時再開 --inputbox 輸入問題）
              +----------------------+
              | --infobox            |
              | 「AI 分析中」        |
              +----------------------+
                         |
                         v
              +----------------------+
              | jq 組 JSON：         |
              | 問題 + 今天日期      |
              | + drugs.db 全部資料  |
              +----------------------+
                         |
                         v
              +----------------------+          +------------------+
              | curl 呼叫 Claude API | -------> |    Claude API    |
              |                      | <------- |                  |
              +----------------------+          +------------------+
                         |
                         v
                  < 回應結果？ >
                         |
          +--------------+--------------+
          |              |              |
     連線失敗或     AI 拒絕回答       成功
      API 錯誤           |              |
          |              |              v
          |              |      jq 取出 text 區塊
          |              |              |
          v              v              v
    顯示錯誤原因   提示換個問法     AI 的回答
          |              |              |
          +--------------+--------------+
                         |
                         v
              +----------------------+
              | --textbox 顯示結果   |
              +----------------------+
                         |
                         v
                     回主選單

   ※ AI 只讀取資料、提供建議，不會修改 drugs.db
```

### 圖 3 dialog 如何把使用者輸入存進變數

```text
   choice=$(dialog --menu ... 3>&1 1>&2 2>&3)

   交換前（預設）                   交換後
   ---------------------            ------------------------------------
   stdout(1) --> 畫面               fd 3      --> $( )   (先記住原本的 stdout)
   stderr(2) --> 使用者輸入         stdout(1) --> stderr --> 終端機畫面
                                    stderr(2) --> fd 3   --> $( ) --> 變數

        +--------+   畫面 (1->2)    +----------+
        | dialog | ---------------> |  終端機  |
        |        |                  +----------+
        |        |   輸入 (2->3)    +----------+
        |        | ---------------> | 變數     |
        +--------+                  | $choice  |
                                    +----------+
```

（純文字版：[`docs/flowchart.txt`](docs/flowchart.txt)）

---

## 二、建立過程

### 步驟 1：安裝 dialog

一開始系統裡沒有 `dialog`，我先安裝：

```bash
sudo apt update
sudo apt install -y dialog
dialog --version          # 確認安裝成功，顯示 Version: 1.3-20240101
```

因為介面要顯示中文，我也確認終端機使用 UTF-8 語系：

```bash
export LANG=C.UTF-8
```

### 步驟 2：先弄懂 dialog 的基本用法

我先查了 `man dialog`，整理出所有元件的共同格式：

```bash
dialog [共用選項] --元件類型 "提示文字" 高度 寬度 [其他參數]
```

**最重要的觀念：怎麼把使用者輸入存進變數？**

如果直接寫 `name=$(dialog --inputbox "名稱" 8 40)`，變數會是空的，畫面也顯示不出來。因為 dialog 把**畫面**輸出到 stdout，把**使用者輸入**輸出到 stderr。所以要把兩者交換：

```bash
name=$(dialog --inputbox "名稱" 8 40 3>&1 1>&2 2>&3)
```

- `3>&1`：先用 fd 3 記住原本的 stdout（也就是 `$( )` 會抓的地方）
- `1>&2`：stdout 改送到 stderr，畫面才會出現在終端機
- `2>&3`：stderr（使用者輸入）送到 fd 3，被 `$( )` 抓到

另外，按鈕的結果是用結束代碼 `$?` 判斷：

| `$?` | 代表 |
|------|------|
| 0 | 按 OK / Yes |
| 1 | 按 Cancel / No |
| 255 | 按 ESC |

所以我在程式裡大量使用 `... || return`，使用者按取消就回到上一層。

### 步驟 3：設計資料格式

為了不用另外裝資料庫，我把藥品資料存在純文字檔 `drugs.db`，一行一筆，用 `|` 分隔：

```
編號|藥品名稱|類別|數量|單位|有效期限|存放位置
D001|普拿疼|成藥|120|盒|2027-08-31|A-01
D002|阿莫西林|處方藥|15|盒|2027-03-15|B-02
D003|胃藥錠|指示藥|60|瓶|2026-12-20|A-03
D004|嗎啡注射液|管制藥品|8|支|2027-01-10|C-01
D005|維他命C|保健食品|200|罐|2026-10-01|D-05
```

日期用 `YYYY-MM-DD` 格式，之後判斷是否過期時，可以直接用字串比大小。

### 步驟 4：寫程式的設定區和共用函式

```bash
#!/usr/bin/env bash
export LANG=${LANG:-C.UTF-8}

APP_TITLE="藥品管理系統"
DB_FILE="${DB_FILE:-$(dirname "$0")/drugs.db}"
ADMIN_PASS="${ADMIN_PASS:-admin123}"
LOW_STOCK=20          # 低於 20 算庫存不足
EXPIRE_DAYS=90        # 90 天內到期要提醒
TMP=$(mktemp)
trap 'rm -f "$TMP"; clear' EXIT   # 程式結束時刪除暫存檔、清除畫面

touch "$DB_FILE"

next_id() {   # 自動產生下一個編號 D001、D002...
    local last
    last=$(cut -d'|' -f1 "$DB_FILE" | sed 's/^D//' | sort -n | tail -1)
    printf "D%03d" $(( 10#${last:-0} + 1 ))
}

msg() {       # 共用的訊息框
    dialog --backtitle "$APP_TITLE" --title "$1" --msgbox "$2" 14 50
}
```

`10#` 是為了避免 `008` 這種數字被 Bash 當成八進位而出錯。

### 步驟 5：登入畫面（`--passwordbox`）

```bash
login() {
    local pass
    pass=$(dialog --backtitle "$APP_TITLE" --title "管理員登入" \
        --insecure --passwordbox "請輸入管理員密碼：" 8 40 3>&1 1>&2 2>&3) || exit 0
    if [ "$pass" != "$ADMIN_PASS" ]; then
        msg "登入失敗" "密碼錯誤，程式結束。"
        exit 1
    fi
}
```

加上 `--insecure` 後，輸入密碼時會顯示 `*`，使用者比較知道自己打了幾個字。

### 步驟 6：載入進度條（`--gauge`）

`--gauge` 會從 stdin 讀數字（0～100）來更新進度，所以我用 `for` 迴圈產生數字，再用管線傳進去：

```bash
loading() {
    for i in 0 20 40 60 80 100; do
        echo "$i"; sleep 0.3
    done | dialog --backtitle "$APP_TITLE" --title "系統啟動" \
        --gauge "正在載入藥品資料庫..." 8 50 0
}
```

### 步驟 7：主選單（`--menu`）

主選單放在 `while true` 迴圈裡，每個功能做完都會回到主選單：

```bash
main_menu() {
    local choice
    while true; do
        choice=$(dialog --backtitle "$APP_TITLE" --title "主選單" \
            --cancel-label "離開" \
            --menu "請選擇功能（↑↓ 移動，Enter 確認）：" 17 50 8 \
            1 "新增藥品"  2 "藥品清單"  3 "查詢藥品" \
            4 "修改庫存（進貨/領用）"  5 "刪除藥品" \
            6 "庫存與效期警示"  7 "AI 藥品助理"  0 "離開系統" \
            3>&1 1>&2 2>&3) || choice=0
        case "$choice" in
            1) add_drug ;;     2) list_drugs ;;   3) search_drug ;;
            4) update_stock ;; 5) delete_drug ;;  6) alert_report ;;
            7) ai_assistant ;;
            0) dialog --backtitle "$APP_TITLE" --title "離開" \
                   --yesno "確定要離開藥品管理系統嗎？" 7 40 && break ;;
        esac
    done
}
```

### 步驟 8：新增藥品（`--form` + `--radiolist` + `--calendar`）

我把新增藥品拆成三個畫面，順便練習三種元件。

**(1) `--form` 填基本資料**：每個欄位要 8 個參數（標籤、標籤位置、預設值、輸入框位置、輸入框寬度、最大長度）。送出後每欄各輸出一行，所以我用 `read` 一行一行讀：

```bash
form=$(dialog --title "新增藥品" \
    --form "請填寫藥品資料（↑↓ 切換欄位）：" 14 60 4 \
    "藥品名稱：" 1 1 ""   1 14 30 40 \
    "數    量：" 2 1 ""   2 14 10 10 \
    "單    位：" 3 1 "盒" 3 14 10 10 \
    "存放位置：" 4 1 ""   4 14 20 30 \
    3>&1 1>&2 2>&3) || return
{ read -r name; read -r qty; read -r unit; read -r loc; } <<< "$form"

# 檢查：名稱不能空白，數量要是數字
if [ -z "$name" ] || ! [[ "$qty" =~ ^[0-9]+$ ]]; then
    msg "輸入錯誤" "藥品名稱不可空白，數量必須為正整數。"; return
fi
```

**(2) `--radiolist` 選類別**（只能單選，用空白鍵勾選）：

```bash
cat=$(dialog --title "藥品類別" \
    --radiolist "請選擇「$name」的類別（空白鍵選取）：" 14 50 5 \
    "處方藥" "需醫師處方" on   "指示藥" "需藥師指示" off \
    "成藥" "可自行購買" off    "管制藥品" "需特別管理" off \
    "保健食品" "非藥品類" off \
    3>&1 1>&2 2>&3) || return
```

**(3) `--calendar` 選有效期限**：預設回傳格式是 `日/月/年`，我加上 `--date-format` 改成 `YYYY-MM-DD`，才能和資料檔格式一致：

```bash
exp=$(dialog --title "有效期限" --date-format "%Y-%m-%d" \
    --calendar "請選擇「$name」的有效期限：" 0 0 3>&1 1>&2 2>&3) || return

id=$(next_id)
echo "$id|$name|$cat|$qty|$unit|$exp|$loc" >> "$DB_FILE"
```

### 步驟 9：藥品清單（`--textbox`）

`--textbox` 是用來顯示檔案的，所以我先把表格寫到暫存檔 `$TMP`，再顯示出來。

**遇到的問題：中文表格對不齊。**
我一開始用 `printf "%-18s"` 排欄位，結果中文那幾欄全部歪掉。原因是 `printf` 按「字元數」補空白，但中文字在終端機上佔 **2 格**。後來我寫了一個 `pad` 函式，用 `wc -L` 算出實際的顯示寬度再補空白，就對齊了：

```bash
pad() {   # pad "文字" 寬度
    local w
    w=$(printf '%s' "$1" | wc -L)
    printf '%s%*s' "$1" $(( $2 > w ? $2 - w : 0 )) ""
}

list_drugs() {
    {
        echo "$(pad 編號 6)$(pad 藥品名稱 16)$(pad 類別 10)$(pad 數量 6)$(pad 單位 6)$(pad 有效期限 12)位置"
        printf -- '-%.0s' {1..64}; echo
        while IFS='|' read -r id name cat qty unit exp loc; do
            [ -n "$id" ] && echo "$(pad "$id" 6)$(pad "$name" 16)$(pad "$cat" 10)$(pad "$qty" 6)$(pad "$unit" 6)$(pad "$exp" 12)$loc"
        done < "$DB_FILE"
        echo; echo "共 $(grep -c . "$DB_FILE") 筆藥品資料"
    } > "$TMP"
    dialog --title "藥品清單" --exit-label "返回" --textbox "$TMP" 20 76
}
```

### 步驟 10：查詢藥品（`--inputbox`）

用 `grep -i` 找關鍵字，再用 `awk` 排版成比較好讀的格式：

```bash
key=$(dialog --title "查詢藥品" \
    --inputbox "請輸入藥品名稱、編號或類別關鍵字：" 8 50 3>&1 1>&2 2>&3) || return
result=$(grep -i -- "$key" "$DB_FILE" | \
    awk -F'|' '{printf "[%s] %s\n   類別:%s  數量:%s %s\n   期限:%s  位置:%s\n\n",$1,$2,$3,$4,$5,$6,$7}')
[ -z "$result" ] && result="查無符合「$key」的藥品。"
dialog --title "查詢結果：$key" --msgbox "$result" 18 60
```

### 步驟 11：修改庫存（動態產生選單）

這裡要讓使用者從**現有的藥品**中選一個，所以選單內容不能寫死。我先寫一個函式輸出「編號、說明」交錯的清單，再用 `mapfile` 讀成陣列，丟給 `--menu`：

```bash
drug_items() {
    while IFS='|' read -r id name cat qty unit exp loc; do
        [ -n "$id" ] && printf '%s\n%s\n' "$id" "$name (庫存 $qty $unit)"
    done < "$DB_FILE"
}

mapfile -t items < <(drug_items)
id=$(dialog --title "修改庫存" --menu "請選擇要異動的藥品：" 16 60 8 \
    "${items[@]}" 3>&1 1>&2 2>&3) || return
```

選完藥品、異動類型（進貨 IN／領用 OUT）、數量之後，用 `awk` 改第 4 欄的數量。領用時如果數量不夠，就跳出提示，不扣庫存：

```bash
if [ "$action" = "IN" ]; then
    newqty=$(( qty + amount ))
else
    newqty=$(( qty - amount ))
    [ "$newqty" -lt 0 ] && { msg "庫存不足" "目前庫存只有 $qty，無法領用 $amount。"; return; }
fi
awk -F'|' -v OFS='|' -v id="$id" -v q="$newqty" '$1==id{$4=q}1' \
    "$DB_FILE" > "$TMP" && cat "$TMP" > "$DB_FILE"
```

### 步驟 12：庫存與效期警示

用 `date` 算出今天和 90 天後的日期，再逐筆檢查藥品：

```bash
today=$(date +%Y-%m-%d)
limit=$(date -d "+$EXPIRE_DAYS days" +%Y-%m-%d)
# 數量 < 20          → 庫存不足
# 期限 < today       → 已過期
# today ≤ 期限 ≤ limit → 即將到期
```

因為日期格式是 `YYYY-MM-DD`，所以直接用 `[[ "$exp" < "$today" ]]` 比較字串就可以，不必轉換成數字。

### 步驟 13：刪除藥品（`--yesno`）

刪除比較危險，所以我加上 `--defaultno`，讓游標預設停在「No」，避免使用者不小心按 Enter 就刪掉：

```bash
if dialog --title "確認刪除" --defaultno \
    --yesno "確定要刪除「$id $name」嗎？\n此動作無法復原！" 8 45; then
    grep -v "^$id|" "$DB_FILE" > "$TMP"; cat "$TMP" > "$DB_FILE"
    msg "刪除完成" "已刪除：$id $name"
fi
```

### 步驟 14：AI 藥品助理（呼叫 Claude API）

主程式完成後，我再加入 AI 助理功能。概念是把**問題和目前的藥品資料**一起送給 AI，再把 AI 的回答用 dialog 顯示出來：

```
dialog 選單／輸入框 → Bash 變數 → jq 組 JSON → curl 呼叫 Claude API → jq 取出回答 → dialog --textbox 顯示
```

**(1) 安裝套件、設定金鑰**

```bash
sudo apt install -y curl jq
export ANTHROPIC_API_KEY="你的金鑰"     # 金鑰不寫進程式，也不上傳 GitHub
```

我在設定區多加一個變數，方便以後換模型：

```bash
AI_MODEL="${AI_MODEL:-claude-opus-5-5}"
```

**(2) 寫 `ai_ask` 函式：組 JSON、呼叫 API、取出回答**

```bash
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
```

幾個設計重點：

- **用 `jq -n --arg` 組 JSON**：問題和藥品資料裡有中文、引號、換行。如果直接用字串拼接，JSON 很容易壞掉；`jq` 會自動處理跳脫字元。`--rawfile` 可以把整個 `drugs.db` 讀成一個字串。
- **把今天日期一起送出**：AI 本身不知道今天幾號，有了日期才能判斷藥品是否過期。
- **`system` 提示**：限制 AI 只根據資料回答、用繁體中文，而且不要用 Markdown，因為 `--textbox` 不會轉換 Markdown，`**` 這類符號會直接顯示出來。
- **`effort: "low"`**：這類問答不需要深度推理，回應比較快，費用也比較低。
- **`fallbacks: "default"`**（搭配 `anthropic-beta` 標頭）：AI 因安全機制拒絕回答時，伺服器會自動改用其他模型再試。
- **錯誤處理**：分成連線失敗、AI 拒絕回答、API 錯誤（例如金鑰錯誤）三種情況，都會顯示可以看懂的訊息，不會讓程式當掉。

**(3) 寫 `ai_assistant` 介面函式**

```bash
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

    # --infobox 顯示後不等按鍵，直接往下執行，適合當「處理中」提示
    dialog --backtitle "$APP_TITLE" --title "AI 藥品助理" \
        --infobox "AI 分析中，請稍候...\n\n問題：$question" 7 64
    ai_ask "$question" > "$TMP"
    dialog --backtitle "$APP_TITLE" --title "AI 回覆" \
        --exit-label "返回" --textbox "$TMP" 20 76
}
```

- 我先提供 3 個常用問題，不用每次打字；也保留「自行輸入」的選項。
- 呼叫 API 需要幾秒鐘，所以先用 `--infobox` 顯示「AI 分析中」。它和 `--msgbox` 的差別是不會等使用者按鍵。
- **AI 只負責回答，不會修改 `drugs.db`**。藥品資料關係到用藥安全，進貨、領用、刪除還是要由人操作並確認。

### 步驟 15：程式進入點

檔案最後依序呼叫三個函式：

```bash
login
loading
main_menu
```

完整程式碼請見 [`drug_manager.sh`](drug_manager.sh)。

---

## 三、執行過程與截圖

### 準備與啟動

```bash
chmod +x drug_manager.sh          # 給執行權限
cp drugs.sample.db drugs.db       # 載入範例資料
./drug_manager.sh
```

### 1. 輸入管理員密碼 `admin123`

![登入](images/01_login.png)

### 2. 登入後顯示載入進度條

![載入進度](images/02_loading.png)

### 3. 進入主選單

![主選單](images/03_main_menu.png)

### 4. 新增藥品：填入「布洛芬止痛錠」、數量 50、位置 B-03

![新增表單](images/04_add_form.png)

### 5. 用空白鍵把類別選為「指示藥」

![選擇類別](images/05_category.png)

### 6. 按 PgDn 翻到 2027 年 7 月，選擇有效期限

![選擇日期](images/06_calendar.png)

### 7. 新增成功，系統自動編號為 D006

![新增成功](images/07_add_success.png)

### 8. 查看藥品清單，D006 已經加入，表格也對齊了

![藥品清單](images/08_list.png)

### 9. 查詢：輸入關鍵字「處方」

![輸入關鍵字](images/09_search_input.png)

### 10. 查到 D002 阿莫西林

![查詢結果](images/10_search_result.png)

### 11. 修改庫存：選擇 D002 阿莫西林

![選擇藥品](images/11_stock_select.png)

### 12. 選擇「OUT 領用」

![異動類型](images/12_stock_type.png)

### 13. 輸入數量 5

![輸入數量](images/13_stock_amount.png)

### 14. 庫存從 15 變成 10

![異動完成](images/14_stock_result.png)

### 15. 查看警示：剛領用後只剩 10 盒的阿莫西林出現在「庫存不足」

畫面中也列出已過期的維他命C，以及 90 天內到期的胃藥錠和嗎啡注射液。

![警示報表](images/15_alert.png)

### 16. 刪除藥品：選擇剛剛新增的 D006

![選擇刪除](images/16_delete_select.png)

### 17. 確認刪除（預設在 No，我按 ← 移到 Yes）

![確認刪除](images/17_delete_confirm.png)

### 18. 刪除完成

![刪除完成](images/18_delete_done.png)

### 19. 選擇 0 離開系統，按 Yes 結束程式

![離開](images/19_exit.png)

### 20～23. AI 藥品助理（實際執行）

**沒有設定 API 金鑰時**，選 `7` 會顯示設定方式，不會出錯：

![未設定金鑰](images/20_ai_no_key.png)

**設定金鑰後**，重新啟動程式，選 `7` 進入 AI 助理的問題選單：

![AI 問題選單](images/21_ai_menu.png)

選「4 自行輸入問題」，輸入「哪些藥品需要優先補貨？」：

![輸入問題](images/22_ai_input.png)

送出後先顯示「AI 分析中」，接著用 `--textbox` 顯示回覆。下面這張截圖是**使用無效金鑰測試錯誤處理**的結果：API 回傳的錯誤訊息被讀出並正常顯示，按「返回」就能回到主選單，程式不會當掉。

![API 錯誤處理](images/23_ai_reply.png)

> 使用有效金鑰時，這個畫面會顯示 AI 的分析內容。之後只要設定好金鑰，再執行 `./tools/capture_screenshots.sh`，就會自動重新截出 AI 實際回覆的畫面。

### 24～25. AI 回覆畫面（模擬範例）

> ⚠️ **以下兩張是模擬畫面，不是 AI 實際回覆。** 因為製作筆記時沒有可用的 API 金鑰，我依照範例資料寫了一份「預期的回答」（[`tools/ai_reply_example.txt`](tools/ai_reply_example.txt)），用和程式相同的 `--textbox` 版面顯示，方便說明功能完成後的樣子。

模擬情境：選「4 自行輸入問題」，輸入「哪些藥品需要優先補貨？」。根據範例資料，預期 AI 會指出：
- **D004 嗎啡注射液**只剩 8 支，而且管制藥品採購較費時，應最優先補貨
- **D002 阿莫西林**剩 15 盒，低於安全存量 20
- 另外提醒 **D005 維他命C** 已過期、**D003 胃藥錠**即將到期

![AI 回覆模擬（上半部）](images/24_ai_reply_simulated.png)

回覆超過一個畫面時，可以用 ↑↓ 或 PgDn 捲動，右下角顯示目前位置的百分比：

![AI 回覆模擬（下半部）](images/25_ai_reply_simulated_2.png)

模擬畫面的產生方式：

```bash
./tools/simulate_ai_reply.sh
```

實際使用時，AI 的用字和排版每次都可能不同，但會根據同一份藥品資料回答。

---

## 四、遇到的問題與解決方法

### 實際執行時遇到的問題

| 問題 | 原因 | 解決方法 |
|------|------|---------|
| 中文表格欄位歪掉 | `printf %-Ns` 按字元數補空白，但中文字佔 2 格 | 自己寫 `pad()`，用 `wc -L` 算顯示寬度 |
| 「新增成功」訊息只顯示一半，右下角出現 85% | `--msgbox` 高度設 10 太小，內容被截斷 | 把高度改成 14 |

### 寫程式前查資料先注意到的地方

| 要注意的地方 | 原因 | 做法 |
|------|------|---------|
| 取不到使用者輸入 | dialog 把輸入送到 stderr，`$( )` 只抓 stdout | 加上 `3>&1 1>&2 2>&3` 交換 |
| 日期格式不一致 | `--calendar` 預設回傳 `日/月/年` | 加上 `--date-format "%Y-%m-%d"` |
| 編號 `008`、`009` 會算錯 | 開頭是 0 的數字，Bash 會當成八進位 | 改用 `$(( 10#$last + 1 ))` |
| 送給 AI 的 JSON 格式壞掉 | 問題和資料含中文、引號、換行，字串拼接容易出錯 | 用 `jq -n --arg` / `--rawfile` 組 JSON |
| AI 回應不一定只有文字 | 回應的 `content` 是陣列，可能還有 thinking 區塊 | 用 `jq` 篩選 `type == "text"` 的區塊 |
| AI 回答中的 `**粗體**` 會原樣顯示 | `--textbox` 只顯示純文字 | 在 system 提示中要求不使用 Markdown |
| 金鑰外洩風險 | 金鑰寫進程式碼會跟著上傳 GitHub | 改用環境變數 `ANTHROPIC_API_KEY` |

## 五、心得

1. 原本以為終端機只能做文字指令，用了 `dialog` 才發現 Shell Script 也能做出有選單、表單、日曆的介面，而且只需要一個套件。
2. 學到最重要的觀念是 **stdout / stderr 和檔案描述子**。`3>&1 1>&2 2>&3` 要把每個 fd 的指向畫出來才比較好理解。
3. 處理中文時要注意「字元數」和「顯示寬度」不一樣，這是我之前沒想過的。
4. 加入 AI 助理後發現，Shell Script 不只能做介面，也能透過 `curl` + `jq` 串接網路 API。最重要的是把 AI 定位成「提供建議」，資料修改還是由人確認，這在藥品管理這種需要安全的情境很重要。
5. 每個 dialog 元件的參數順序都不太一樣（特別是 `--form` 每欄要 8 個參數），寫之前查 `man dialog` 可以少走很多冤枉路。
6. 之後可以再改進的地方：
   - 用 `--checklist` 一次刪除多筆
   - 把每次進貨／領用寫進紀錄檔，再用 `--tailbox` 查看歷史
   - 改用 `sqlite3` 存資料，支援更複雜的查詢

---

## 附錄：本次用到的 dialog 元件整理

| 元件 | 語法 | 回傳 | 我用在哪裡 |
|------|------|------|-----------|
| `--passwordbox` | `--passwordbox 文字 高 寬` | 輸入的字串 | 登入 |
| `--gauge` | `指令 \| dialog --gauge 文字 高 寬 %` | 無 | 載入進度 |
| `--menu` | `--menu 文字 高 寬 列數 tag 說明 ...` | 選中的 tag | 主選單、選藥品 |
| `--form` | `--form 文字 高 寬 表單高 [每欄 8 個參數]` | 每欄一行 | 新增藥品 |
| `--radiolist` | `--radiolist 文字 高 寬 列數 tag 說明 on/off ...` | 選中的 tag | 藥品類別 |
| `--calendar` | `--calendar 文字 高 寬` | 日期 | 有效期限 |
| `--textbox` | `--textbox 檔案 高 寬` | 無 | 清單、警示 |
| `--inputbox` | `--inputbox 文字 高 寬` | 輸入的字串 | 查詢、數量 |
| `--msgbox` | `--msgbox 文字 高 寬` | 無 | 各種提示訊息 |
| `--yesno` | `--yesno 文字 高 寬` | 結束代碼 0／1 | 刪除、離開確認 |
| `--infobox` | `--infobox 文字 高 寬` | 無（不等按鍵） | AI 分析中提示 |

> 截圖是用 `tools/capture_screenshots.sh` 自動擷取的：在虛擬螢幕（Xvfb）中開 xterm 執行程式，用 `tmux send-keys` 模擬按鍵，再用 ImageMagick 的 `import` 截圖。
