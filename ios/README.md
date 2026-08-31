# Slate for iOS

跟 macOS 版共用 `../Shared/` 的保險庫核心：同一套加密格式、同一份金鑰信封、
同一個同步客戶端。這個目錄只有介面。

## 需要 Xcode

這台機器目前只有 Command Line Tools，沒有 iOS SDK，所以這裡的程式碼寫好了但
還沒編過。裝好 Xcode 之後：

```bash
brew install xcodegen
```

```bash
cd ~/"AvalonLotus Projects"/Slate/ios && xcodegen generate && open Slate.xcodeproj
```

`project.yml` 已經把 `../Shared` 掛進 target，不需要複製檔案。第一次跑要在
Xcode 的 Signing & Capabilities 選你的 Apple ID。

## 已經寫好的部分

鎖定畫面走 Face ID 或 Touch ID，跟 macOS 一樣是解開安全區裡的金鑰而不是
比對通行碼；新裝置沒有 device wrap 時，鎖定畫面會出現備份密碼還原入口。
清單、編輯、設定三個畫面都在，設定裡可以設備份密碼與連上同步伺服器。

App 退到背景就上鎖，複製到剪貼簿的值 45 秒後由系統自動過期。

## 還沒做

自動填入（AutoFill Credential Provider extension）要另開一個 target，
系統才會在 Safari 與其他 App 的登入欄位提供 Slate 的帳號密碼。
