# 使用 Linux `dialog` 建立藥品管理介面 — 逐步教學

本教學用 Bash 搭配 `dialog` 套件，在終端機中做出一個有選單、表單、日曆、進度條的**藥品管理系統**。每一步都附上執行畫面和對應的語法。

| 檔案 | 說明 |
|------|------|
| [`drug_manager.sh`](drug_manager.sh) | 主程式（完整原始碼） |
| [`drugs.sample.db`](drugs.sample.db) | 範例藥品資料 |
| [`images/`](images/) | 各步驟截圖 |
| [`tools/capture_screenshots.sh`](tools/capture_screenshots.sh) | 自動重新產生所有截圖的腳本 |

---

## 目錄

1. [環境準備](#步驟-1環境準備)
2. [dialog 基本語法觀念](#步驟-2dialog-基本語法觀念)
3. [程式骨架與資料格式](#步驟-3程式骨架與資料格式)
4. [管理員登入 `--passwordbox`](#步驟-4管理員登入---passwordbox)
5. [載入進度條 `--gauge`](#步驟-5載入進度條---gauge)
6. [主選單 `--menu`](#步驟-6主選單---menu)
7. [新增藥品 `--form` / `--radiolist` / `--calendar`](#步驟-7新增藥品---form----radiolist----calendar)
8. [藥品清單 `--textbox`](#步驟-8藥品清單---textbox)
9. [查詢藥品 `--inputbox`](#步驟-9查詢藥品---inputbox)
10. [修改庫存（進貨／領用）](#步驟-10修改庫存進貨領用)
11. [庫存與效期警示](#步驟-11庫存與效期警示)
12. [刪除藥品 `--yesno`](#步驟-12刪除藥品---yesno)
13. [離開系統](#步驟-13離開系統)
14. [執行方式總結](#步驟-14執行方式總結)
15. [附錄：常用 dialog 元件速查表](#附錄常用-dialog-元件速查表)

---

## 步驟 1：環境準備

安裝 `dialog`（Debian / Ubuntu）：

```bash
sudo apt update
sudo apt install -y dialog
```

其他發行版：

```bash
sudo dnf install -y dialog      # Fedora / RHEL / Rocky
sudo pacman -S dialog           # Arch
```

確認安裝成功：

```bash
dialog --version
# Version: 1.3-20240101
```

> **中文顯示**：終端機要使用 UTF-8 語系，否則中文會變亂碼。
> ```bash
> export LANG=C.UTF-8      # 或 zh_TW.UTF-8
> ```

---

## 步驟 2：dialog 基本語法觀念

所有 dialog 元件的格式都一樣：

```bash
dialog [共用選項] --<元件類型> "提示文字" <高度> <寬度> [元件專屬參數...]
```

常用的共用選項：

| 選項 | 作用 |
|------|------|
| `--backtitle "文字"` | 螢幕最上方的背景標題 |
| `--title "文字"` | 對話框的標題 |
| `--ok-label` / `--cancel-label` / `--exit-label` | 自訂按鈕文字 |
| `--defaultno` | `yesno` 預設停在「No」 |
| `--insecure` | 密碼框輸入時顯示 `*` |

### 重點：怎麼取得使用者輸入？

dialog 把**畫面輸出到 stdout**，把**使用者的選擇／輸入輸出到 stderr**。要把結果存進變數，就要交換 stdout 和 stderr：

```bash
result=$(dialog --inputbox "請輸入：" 8 40 3>&1 1>&2 2>&3)
```

- `3>&1`：建立 fd 3，指向目前的 stdout（也就是 `$( )` 會捕捉的地方）
- `1>&2`：把 stdout 導到 stderr → 畫面仍會顯示在終端機
- `2>&3`：把 stderr 導到 fd 3 → 使用者的輸入被 `$( )` 捕捉

### 結束代碼 (exit status)

| `$?` | 意義 |
|------|------|
| `0` | 按下 OK / Yes |
| `1` | 按下 Cancel / No |
| `255` | 按下 ESC |

所以可以寫成 `result=$(dialog ...) || return`，使用者按「取消」就直接返回上一層。

---

## 步驟 3：程式骨架與資料格式

藥品資料存在純文字檔 `drugs.db` 中，每行一筆，以 `|` 分隔：

```
編號|藥品名稱|類別|數量|單位|有效期限|存放位置
D001|普拿疼|成藥|120|盒|2027-08-31|A-01
D002|阿莫西林|處方藥|15|盒|2027-03-15|B-02
D003|胃藥錠|指示藥|60|瓶|2026-12-20|A-03
D004|嗎啡注射液|管制藥品|8|支|2027-01-10|C-01
D005|維他命C|保健食品|200|罐|2026-10-01|D-05
```

建立 `drug_manager.sh`，先寫好設定區和共用函式：

```bash
#!/usr/bin/env bash
export LANG=${LANG:-C.UTF-8}

APP_TITLE="藥品管理系統"
DB_FILE="${DB_FILE:-$(dirname "$0")/drugs.db}"
ADMIN_PASS="${ADMIN_PASS:-admin123}"
LOW_STOCK=20          # 低於此數量視為庫存不足
EXPIRE_DAYS=90        # 幾天內到期視為即將到期
TMP=$(mktemp)
trap 'rm -f "$TMP"; clear' EXIT   # 結束時刪暫存檔並清除畫面

touch "$DB_FILE"

# 自動產生下一個編號 D001, D002, ...
next_id() {
    local last
    last=$(cut -d'|' -f1 "$DB_FILE" | sed 's/^D//' | sort -n | tail -1)
    printf "D%03d" $(( 10#${last:-0} + 1 ))
}

# 共用訊息框
msg() {   # msg "標題" "內容"
    dialog --backtitle "$APP_TITLE" --title "$1" --msgbox "$2" 14 50
}

# 依「顯示寬度」補空白（中文字佔 2 格，printf 的 %-10s 會對不齊）
pad() {   # pad "文字" 寬度
    local w
    w=$(printf '%s' "$1" | wc -L)
    printf '%s%*s' "$1" $(( $2 > w ? $2 - w : 0 )) ""
}

# 產生 menu 用的「tag 說明」清單
drug_items() {
    while IFS='|' read -r id name cat qty unit exp loc; do
        [ -n "$id" ] && printf '%s\n%s\n' "$id" "$name (庫存 $qty $unit)"
    done < "$DB_FILE"
}
```

> 💡 `pad()` 用 `wc -L` 算出字串在終端機上的**顯示寬度**。中文字佔 2 格，所以用 `printf "%-10s"` 排表格會歪掉，改用 `pad` 才對得齊。

---

## 步驟 4：管理員登入 `--passwordbox`

**語法**

```bash
dialog --passwordbox "提示文字" <高> <寬> [預設值]
```

**程式碼**

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

**執行畫面**（加上 `--insecure`，輸入的字元會顯示成 `*`）

![管理員登入](images/01_login.png)

---

## 步驟 5：載入進度條 `--gauge`

**語法**

```bash
<輸出 0~100 數字的指令> | dialog --gauge "提示文字" <高> <寬> <起始百分比>
```

`--gauge` 從 stdin 讀取數字來更新進度。

**程式碼**

```bash
loading() {
    for i in 0 20 40 60 80 100; do
        echo "$i"
        sleep 0.3
    done | dialog --backtitle "$APP_TITLE" --title "系統啟動" \
        --gauge "正在載入藥品資料庫..." 8 50 0
}
```

**執行畫面**

![載入進度條](images/02_loading.png)

---

## 步驟 6：主選單 `--menu`

**語法**

```bash
dialog --menu "提示文字" <高> <寬> <選單可見列數> \
    tag1 "說明1" \
    tag2 "說明2" ...
```

使用者選擇後，回傳的是 **tag**（這裡是 `1`~`6`、`0`）。

**程式碼**

```bash
main_menu() {
    local choice
    while true; do
        choice=$(dialog --backtitle "$APP_TITLE" --title "主選單" \
            --cancel-label "離開" \
            --menu "請選擇功能（↑↓ 移動，Enter 確認）：" 16 50 7 \
            1 "新增藥品" \
            2 "藥品清單" \
            3 "查詢藥品" \
            4 "修改庫存（進貨/領用）" \
            5 "刪除藥品" \
            6 "庫存與效期警示" \
            0 "離開系統" \
            3>&1 1>&2 2>&3) || choice=0

        case "$choice" in
            1) add_drug ;;
            2) list_drugs ;;
            3) search_drug ;;
            4) update_stock ;;
            5) delete_drug ;;
            6) alert_report ;;
            0) dialog --backtitle "$APP_TITLE" --title "離開" \
                   --yesno "確定要離開藥品管理系統嗎？" 7 40 && break ;;
        esac
    done
}
```

**執行畫面**（可以用 ↑↓ 移動，也可以直接按數字鍵跳到該項）

![主選單](images/03_main_menu.png)

---

## 步驟 7：新增藥品 `--form` / `--radiolist` / `--calendar`

新增藥品分三個畫面：**表單 → 類別單選 → 日曆選日期**。

### 7-1 表單 `--form`

**語法**

```bash
dialog --form "提示文字" <高> <寬> <表單高度> \
    "標籤" <標籤列> <標籤欄> "預設值" <輸入列> <輸入欄> <輸入框寬> <最大長度> \
    ...
```

每個欄位要 8 個參數。送出後每個欄位的值各佔**一行**輸出。

**程式碼**

```bash
form=$(dialog --backtitle "$APP_TITLE" --title "新增藥品" \
    --form "請填寫藥品資料（↑↓ 切換欄位）：" 14 60 4 \
    "藥品名稱：" 1 1 ""   1 14 30 40 \
    "數    量：" 2 1 ""   2 14 10 10 \
    "單    位：" 3 1 "盒" 3 14 10 10 \
    "存放位置：" 4 1 ""   4 14 20 30 \
    3>&1 1>&2 2>&3) || return

# 一行一行讀進變數
{ read -r name; read -r qty; read -r unit; read -r loc; } <<< "$form"

# 輸入檢查
if [ -z "$name" ] || ! [[ "$qty" =~ ^[0-9]+$ ]]; then
    msg "輸入錯誤" "藥品名稱不可空白，數量必須為正整數。"
    return
fi
```

**執行畫面**

![新增藥品表單](images/04_add_form.png)

### 7-2 類別單選 `--radiolist`

**語法**

```bash
dialog --radiolist "提示文字" <高> <寬> <清單列數> \
    tag "說明" on|off \
    ...
```

用**空白鍵**選取，只能選一個（多選請用 `--checklist`）。

**程式碼**

```bash
cat=$(dialog --backtitle "$APP_TITLE" --title "藥品類別" \
    --radiolist "請選擇「$name」的類別（空白鍵選取）：" 14 50 5 \
    "處方藥"   "需醫師處方" on \
    "指示藥"   "需藥師指示" off \
    "成藥"     "可自行購買" off \
    "管制藥品" "需特別管理" off \
    "保健食品" "非藥品類"   off \
    3>&1 1>&2 2>&3) || return
```

**執行畫面**

![選擇類別](images/05_category.png)

### 7-3 有效期限 `--calendar`

**語法**

```bash
dialog --date-format "%Y-%m-%d" --calendar "提示文字" <高> <寬> [日 月 年]
```

高、寬填 `0 0` 會自動調整大小。不加 `--date-format` 時回傳的格式是 `日/月/年`。

| 按鍵 | 作用 |
|------|------|
| ← → ↑ ↓ | 移動日期 |
| PgUp / PgDn | 上一個月 / 下一個月 |
| Tab | 切換「月」「年」「日期」欄位 |

**程式碼**

```bash
exp=$(dialog --backtitle "$APP_TITLE" --title "有效期限" \
    --date-format "%Y-%m-%d" \
    --calendar "請選擇「$name」的有效期限：" 0 0 \
    3>&1 1>&2 2>&3) || return

id=$(next_id)
echo "$id|$name|$cat|$qty|$unit|$exp|$loc" >> "$DB_FILE"
msg "新增成功" "已新增藥品：\n\n編號：$id\n名稱：$name\n類別：$cat\n數量：$qty $unit\n期限：$exp"
```

**執行畫面**（按 PgDn 往後翻到 2027 年 7 月）

![選擇有效期限](images/06_calendar.png)

### 7-4 新增結果 `--msgbox`

**語法**

```bash
dialog --msgbox "訊息內容（可用 \n 換行）" <高> <寬>
```

![新增成功](images/07_add_success.png)

---

## 步驟 8：藥品清單 `--textbox`

**語法**

```bash
dialog --textbox <檔案路徑> <高> <寬>
```

`--textbox` 顯示整個文字檔，內容超過畫面時可以捲動。做法是先把報表寫進暫存檔，再用 `--textbox` 顯示。

**程式碼**

```bash
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
```

**執行畫面**（剛新增的 D006 已出現在清單中）

![藥品清單](images/08_list.png)

---

## 步驟 9：查詢藥品 `--inputbox`

**語法**

```bash
dialog --inputbox "提示文字" <高> <寬> [預設值]
```

**程式碼**

```bash
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
```

**執行畫面**：輸入關鍵字「處方」

![輸入查詢關鍵字](images/09_search_input.png)

**查詢結果**

![查詢結果](images/10_search_result.png)

---

## 步驟 10：修改庫存（進貨／領用）

這個功能把多個元件串在一起：**動態選單 → 固定選單 → 輸入框 → 訊息框**。

### 10-1 動態產生選單

`--menu` 的項目可以來自陣列。用 `mapfile` 把 `drug_items` 的輸出（一行 tag、一行說明）讀進陣列，再用 `"${items[@]}"` 展開：

```bash
mapfile -t items < <(drug_items)
id=$(dialog --backtitle "$APP_TITLE" --title "修改庫存" \
    --menu "請選擇要異動的藥品：" 16 60 8 "${items[@]}" \
    3>&1 1>&2 2>&3) || return
```

![選擇要異動的藥品](images/11_stock_select.png)

### 10-2 選擇異動類型

```bash
action=$(dialog --backtitle "$APP_TITLE" --title "異動類型" \
    --menu "請選擇異動類型：" 10 40 2 \
    "IN"  "進貨（增加庫存）" \
    "OUT" "領用（減少庫存）" \
    3>&1 1>&2 2>&3) || return
```

![選擇異動類型](images/12_stock_type.png)

### 10-3 輸入數量並更新資料

```bash
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

# 用 awk 改第 4 欄（數量）
awk -F'|' -v OFS='|' -v id="$id" -v q="$newqty" '$1==id{$4=q}1' \
    "$DB_FILE" > "$TMP" && cat "$TMP" > "$DB_FILE"
msg "異動完成" "$(cut -d'|' -f2 <<< "$line")\n\n原庫存：$qty\n異動量：$action $amount\n新庫存：$newqty"
```

![輸入異動數量](images/13_stock_amount.png)

**結果**：阿莫西林領用 5 盒，庫存 15 → 10

![異動完成](images/14_stock_result.png)

---

## 步驟 11：庫存與效期警示

用 `date` 算出今天和 90 天後的日期，再把每筆藥品分成「庫存不足」「已過期」「即將到期」三類。日期是 `YYYY-MM-DD` 格式，所以可以直接用字串比較 `[[ "$a" < "$b" ]]`。

```bash
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
```

**執行畫面**（截圖日期為 2026-11-06）

![庫存與效期警示](images/15_alert.png)

---

## 步驟 12：刪除藥品 `--yesno`

**語法**

```bash
dialog [--defaultno] --yesno "問題" <高> <寬>
# Yes → $? = 0，No → $? = 1
```

`--yesno` 不輸出文字，直接用 `if` 判斷結束代碼。刪除屬於危險操作，所以加上 `--defaultno`，讓游標預設停在「No」。

**程式碼**

```bash
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
```

**選擇要刪除的藥品**

![選擇要刪除的藥品](images/16_delete_select.png)

**確認刪除**（預設停在 No，這裡按 ← 移到 Yes 後確認）

![確認刪除](images/17_delete_confirm.png)

**刪除完成**

![刪除完成](images/18_delete_done.png)

---

## 步驟 13：離開系統

主選單選 `0`（或按「離開」按鈕），會跳出 `--yesno` 確認；選 Yes 就 `break` 跳出 `while` 迴圈。`trap ... EXIT` 會清除畫面並刪除暫存檔。

![離開確認](images/19_exit.png)

最後在檔案尾端寫上程式進入點：

```bash
login
loading
main_menu
```

---

## 步驟 14：執行方式總結

```bash
# 1. 下載專案
git clone https://github.com/shiyangchen24-gif/Linux-dialog.git
cd Linux-dialog

# 2. 安裝 dialog
sudo apt install -y dialog

# 3. 準備範例資料（不做這步就從空資料庫開始）
cp drugs.sample.db drugs.db

# 4. 給執行權限並執行
chmod +x drug_manager.sh
./drug_manager.sh            # 預設密碼：admin123

# 自訂密碼或資料檔位置
ADMIN_PASS=mypass DB_FILE=/path/to/my.db ./drug_manager.sh
```

### 操作按鍵

| 按鍵 | 作用 |
|------|------|
| ↑ ↓ | 移動選項 / 切換表單欄位 |
| 數字鍵 | 在選單中直接跳到該項 |
| 空白鍵 | radiolist / checklist 勾選 |
| Tab | 在選單與按鈕之間切換 |
| ← → | 切換 OK / Cancel 按鈕 |
| Enter | 確認 |
| ESC | 取消 / 返回 |

### 重新產生截圖（選用）

所有截圖都是用 [`tools/capture_screenshots.sh`](tools/capture_screenshots.sh) 自動產生：在虛擬螢幕 (Xvfb) 中用 xterm + tmux 執行程式，透過 `tmux send-keys` 模擬按鍵，再用 ImageMagick 的 `import` 擷取畫面。

```bash
sudo apt install -y dialog tmux xvfb xterm imagemagick fonts-noto-cjk fonts-dejavu
./tools/capture_screenshots.sh
```

---

## 附錄：常用 dialog 元件速查表

| 元件 | 語法 | 回傳 | 本專案用途 |
|------|------|------|-----------|
| `--msgbox` | `--msgbox 文字 高 寬` | 無 | 成功／錯誤訊息 |
| `--yesno` | `--yesno 文字 高 寬` | 結束代碼 0/1 | 刪除確認、離開確認 |
| `--inputbox` | `--inputbox 文字 高 寬 [預設]` | 輸入字串 | 查詢、數量 |
| `--passwordbox` | `--passwordbox 文字 高 寬` | 輸入字串 | 登入 |
| `--menu` | `--menu 文字 高 寬 列數 tag 說明 ...` | 選中的 tag | 主選單、選藥品 |
| `--radiolist` | `--radiolist 文字 高 寬 列數 tag 說明 on/off ...` | 選中的 tag | 藥品類別 |
| `--checklist` | `--checklist 文字 高 寬 列數 tag 說明 on/off ...` | 多個 tag | （可延伸使用） |
| `--form` | `--form 文字 高 寬 表單高 [8 個參數/欄] ...` | 每欄一行 | 新增藥品 |
| `--calendar` | `--calendar 文字 高 寬 [日 月 年]` | 日期 | 有效期限 |
| `--gauge` | `... \| --gauge 文字 高 寬 [%]` | 無 | 載入進度 |
| `--textbox` | `--textbox 檔案 高 寬` | 無 | 清單、警示報表 |

### 可以繼續延伸的方向

- 用 `--checklist` 一次刪除多筆藥品
- 把資料庫換成 `sqlite3`，支援更複雜的查詢
- 每次進貨／領用都寫一筆紀錄到 `history.log`，再用 `--tailbox` 檢視異動歷史
- 用 `--fselect` 選擇 CSV 檔，批次匯入藥品
