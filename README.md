# Slate

macOS 上的 API Key 保險庫，兩個入口：桌面常駐卡片，以及選單列浮動面板。
兩者都是 iOS 小工具的長相——毛玻璃、連續圓角、彈簧動畫——都要 Touch ID 才開得了。

## 桌面卡片

停在系統小工具那一層的視窗，格線與尺寸不是猜的，是量真的：用
`CGWindowListCopyWindowInfo` 讀出桌面上既有小工具的視窗座標，得到
格子 180、間距 0、原點離可用區左緣 8 上緣 7，中型 360 × 180、大型 360 × 360。
每個小工具的視窗四邊各留 8 的陰影邊，可見卡片是 344 × 164、圓角 20。
Slate 完全照這組數字走，所以與系統小工具同排時邊緣對齊、大小一致。

拖曳時隱形格線會淡入顯示可放的位置，放手後吸附到最近的格點，座標記在
UserDefaults，重開還在原位。

鎖著時只有骨架佔位，不透露任何金鑰資訊；點一下過 Touch ID 就原地展開成
完整清單（三格高，上緣不動往下長），閒置 90 秒自動收合上鎖。右鍵選單列
圖示可以開關卡片。

因為它在桌面層，全螢幕 App 或視窗蓋住時看不到——這是桌面 widget 的本質，
要立刻取用就按 `⌥⌘K` 叫選單列面板。

## 安全模型

- 每一組金鑰用 AES-GCM 加密後存成單一檔案 `~/Library/Application Support/Slate/vault.dat`。
- 加密金鑰不落地。它由 Secure Enclave 內的 P256 私鑰與一組公開的對端公鑰做
  ECDH，再經 HKDF-SHA256 導出。
- Secure Enclave 私鑰無法被匯出，`enclave.key` 只是安全區加密過的封裝，
  複製到別台 Mac 也解不開。
- 私鑰的存取條件是 `[.privateKeyUsage]`，搭配
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`。這台 Mac 登入後，以這個帳號
  執行的程式都能透過 agent socket 讀到全部內容，不跳驗證。
- 驗證只擋畫面，而且一次執行只問一次。面板或桌面卡片第一次要顯示內容時跑
  `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`，之後收起、換保險庫、
  再打開都不再問。按鎖頭或 `⌘L` 收回，下次顯示再問一次。
- 按鎖頭或 `⌘L`、Mac 睡著、螢幕上鎖，都只收畫面。記憶體裡的內容留著，
  socket 照樣讀得到。清空只發生在換保險庫與結束 App。
- 首次升級到這個模型時，啟動會換一次金鑰，過程要驗證一次。新金鑰生在
  `enclave2.key`，每個信封加上一份新金鑰的 wrap，舊金鑰 `enclave.key` 與舊
  wrap 原地不動。全部驗證打得開才寫下 `enclave.format`，寫下去才算換過去。
  中途停在任何一點，這台仍照舊金鑰運作，下次啟動重跑。
- 複製到剪貼簿的金鑰標記為 `org.nspasteboard.ConcealedType`，45 秒後自動清空。

## 操作

| 動作 | 方式 |
| --- | --- |
| 展開桌面卡片 | 點卡片本身 |
| 開啟 / 收起面板 | 點選單列鑰匙圖示，或 `⌥⌘K` |
| 開關桌面卡片 | 右鍵選單列圖示 → 在桌面顯示卡片 |
| 新增金鑰 | `⌘N` 或右上角 `+` |
| 立即上鎖 | `⌘L` 或鑰匙列的鎖頭（只收畫面，腳本不受影響） |
| 開機時啟動 | 設定 → 開機時啟動 → 開啟 |
| 儲存 | `⌘S` |
| 返回 / 收起 | `Esc` |
| 結束程式 | 右鍵點選單列圖示 → 結束 |

## 目錄

| 目錄 | 內容 |
| --- | --- |
| `Shared/` | 三平台共用的核心：加密格式、金鑰信封、同步客戶端 |
| `Sources/` | macOS 介面：桌面卡片、浮動面板、選單列、代理 socket |
| `ios/` | iOS 介面，與 `Shared/` 共用核心，需要 Xcode 才能編譯 |
| `scripts/` | 建置、打包、預覽、自我測試 |
| `Tools/` | 命令列工具、離屏預覽、自我測試、標誌產生器 |

## 規格

保險庫格式寫在 `docs/`，三個平台的客戶端都以它為準：

| 文件 | 內容 |
| --- | --- |
| [docs/vault-format.md](docs/vault-format.md) | 保險庫加密格式、金鑰信封、各平台硬體金鑰對應、合併規則 |

## 建置

需要 Command Line Tools（不需要 Xcode）。

```bash
cd ~/"AvalonLotus Projects"/Slate && ./scripts/build.sh
```

產物在 `~/Library/Developer/Slate/Slate.app`。桌面是 iCloud 同步資料夾，
Finder 會寫入擴充屬性導致簽章失敗，所以建置輸出刻意放在同步範圍外。

安裝：

```bash
cp -R "$HOME/Library/Developer/Slate/Slate.app" /Applications/
```

## 命令列

`slate` 讓你自己的腳本取用保險庫。取值不需要驗證，也不必把 Slate 切到前景。
Slate 開著就向它取值，沒開就在指令自己的行程裡開保險庫。面板收著、螢幕鎖著、
Mac 剛睡醒，都不影響。

```bash
export OPENAI_API_KEY=$(slate get "正式環境")
```

`slate list` 列出條目，`slate user <名稱>` 取帳號，`slate json` 給程式讀。
`slate url <名稱> <網址>` 設定網址。
建置後執行檔在 `~/Library/Developer/Slate/bin/slate`，放進 PATH：

```bash
ln -sf "$HOME/Library/Developer/Slate/bin/slate" "$HOME/.local/bin/slate"
```

App 執行時會在 `~/Library/Application Support/Slate/agent.sock` 開一個
只有自己讀得到的 socket（權限 0600），結束時關閉。鎖著的時候它只回答解鎖
請求，取值一律要先解鎖。

## 自我測試

用真的 Secure Enclave 金鑰把保險庫檔案跑一次寫入 / 讀回，確認密文中不含明文、
權限是 600，跑完還原原本內容。需要按一次指紋。

```bash
cd ~/"AvalonLotus Projects"/Slate && ./scripts/selftest.sh
```

## 版面預覽

離屏渲染各畫面成 PNG，不需要開 App：

```bash
cd ~/"AvalonLotus Projects"/Slate && ./scripts/preview.sh
```

輸出在 `~/Library/Developer/Slate/preview/`。ImageRenderer 無法點陣化
輸入框與 ScrollView，前者會畫成黃色色塊，後者由 `ScrollContainer` 在預覽時
換成一般 VStack。

## 結構

| 檔案 | 內容 |
| --- | --- |
| `Sources/Crypto.swift` | Secure Enclave 金鑰、HKDF 導出、檔案路徑 |
| `Sources/Vault.swift` | 資料模型、解鎖狀態機、加解密存檔 |
| `Sources/Panel.swift` | NSPanel 浮動面板、定位、毛玻璃背景 |
| `Sources/DesktopCard.swift` | 桌面層卡片、鎖定面、展開動畫、閒置上鎖 |
| `Sources/RootView.swift` | 鎖定 / 清單 / 編輯三個畫面的切換 |
| `Sources/LockView.swift` | 指紋解鎖畫面 |
| `Sources/ListView.swift` | 金鑰清單與列元件 |
| `Sources/EditorView.swift` | 新增與編輯 |
| `Sources/Theme.swift` | 色票、品牌配色、按鈕樣式、動畫曲線 |
| `Sources/HotKey.swift` | Carbon 全域快捷鍵 |
| `Tools/icon-lab/main.swift` | 產生候選標誌與 AppIcon 來源圖 |
| `Tools/preview/main.swift` | 離屏版面預覽 |
| `Tools/selftest/main.swift` | 加解密往返自我測試 |

啟動時帶 `--open` 會直接彈出面板（`open -a Slate --args --open`），
平常不需要。
