# Slate 保險庫格式 v3

跨平台的唯一真理。macOS、iOS、Android 三個客戶端各自實作這份規格，
產出的檔案必須能互相打開。任何一邊改動格式都要先改這份文件。

格式與語言、平台、同步方式無關。它只定義兩樣東西：保險庫怎麼加密，
以及那把加密金鑰怎麼被包起來。

## 一、兩個檔案

| 檔案 | 內容 | 是否為密文 |
| --- | --- | --- |
| `keys.json` | 金鑰信封，記錄庫金鑰被誰包了幾份 | 是（每份 wrap 都是密文） |
| `vault.dat` | 保險庫本體 | 是 |

兩個檔案永遠成對移動。備份與換機，複製的都是這兩個檔案。

## 二、庫金鑰

`K` = 256 位元隨機值，由第一次建庫的裝置產生，用作業系統的密碼學亂數源
（macOS/iOS `SecRandomCopyBytes`、Android `SecureRandom`）。

`K` 本身永遠不落地，只以被包過的形式存在 `keys.json` 裡。

## 三、vault.dat

    vault.dat = AES-256-GCM(K, plaintext)

密文的位元組排列固定為：

    nonce (12 bytes) || ciphertext || tag (16 bytes)

這正好是 Apple CryptoKit `AES.GCM.SealedBox.combined` 的排列。Android 端用
`Cipher.getInstance("AES/GCM/NoPadding")`，`GCMParameterSpec` 標籤長度 128 位元，
輸出即為 `ciphertext || tag`，前面自行接上 nonce。

Additional authenticated data 不使用，三端一律留空。

`plaintext` 是 UTF-8 編碼的 JSON 文件：

```json
{
  "formatVersion": 3,
  "updatedAt": "2026-08-27T14:18:00Z",
  "items": [ ... ]
}
```

## 四、條目

```json
{
  "id": "8B1F1B0E-9C2A-4E77-9A5E-2D0C2D9E5A31",
  "kind": "apiKey",
  "name": "正式環境",
  "provider": "OpenAI",
  "username": "",
  "secret": "EXAMPLE-…",
  "note": "只開 charges 權限",
  "createdAt": "2026-08-01T09:12:33Z",
  "updatedAt": "2026-08-27T14:18:00Z",
  "deletedAt": null
}
```

`id` 是 UUID，大寫字串，跨裝置永久不變，是合併的依據。

`kind` 目前只有 `apiKey` 與 `login` 兩個值。讀到不認識的值時保留原字串、
以 `apiKey` 的樣子呈現，不得丟棄該筆——這條規則讓舊版客戶端不會吃掉新版資料。

所有時間一律 ISO 8601、UTC、秒為單位、結尾 `Z`。不使用平台預設的時間編碼
（Swift 的 reference date、Java 的 epoch millis 都不行），因為三端必須逐字節一致。

`deletedAt` 有值代表墓碑：條目已刪除，但保留 id 與時間戳供同步比對，
其餘欄位一律清空為空字串。墓碑在 90 天後可由任一客戶端實際移除。

## 五、keys.json

```json
{
  "formatVersion": 3,
  "kdf": {
    "algorithm": "PBKDF2-HMAC-SHA256",
    "rounds": 600000,
    "salt": "base64(32 bytes)"
  },
  "wraps": [
    {
      "type": "device",
      "id": "3F2A…",
      "label": "MacBook Air",
      "platform": "macos",
      "blob": "base64"
    },
    {
      "type": "passphrase",
      "blob": "base64"
    }
  ]
}
```

`wraps` 是陣列，同一把 `K` 可以被包很多份。每台裝置一份 device wrap，
備份密碼一份 passphrase wrap。新裝置加入時用備份密碼解出 `K`，再用自己的硬體金鑰
包一份塞進陣列。移除一台裝置就是刪掉那一筆。

每個 `blob` 都是 `AES-256-GCM(wrappingKey, K)`，位元組排列與 `vault.dat` 相同。

至少要有一份 passphrase wrap，否則保險庫無法跨裝置——建庫流程必須強制設定備份密碼。

備份密碼是整台機器一組，不是每個保險庫一組。設定時對每一個保險庫各自產生
salt、各自算出包裝金鑰，再把該庫的 `K` 包一份寫回自己的 `keys.json`；金鑰仍然
互相獨立，只有輸入的那串字共用。移除時一併從所有保險庫刪除。

## 六、包裝金鑰怎麼來

### passphrase wrap

    wrappingKey = PBKDF2-HMAC-SHA256(passphrase, kdf.salt, kdf.rounds, 32 bytes)

`passphrase` 先做 Unicode NFC 正規化再轉 UTF-8，否則同一組密碼在不同鍵盤
輸入法下會導出不同金鑰。`rounds` 下限 600000，可以往上調，調整後要重新
產生所有 passphrase wrap。

### device wrap，Apple 平台

Secure Enclave 只做 P-256 金鑰協商，不能直接加解密，所以多一層 ECDH：

1. 建庫時產生 Secure Enclave P-256 金鑰，存取條件 `.privateKeyUsage + .userPresence`，
   金鑰封裝 blob 存在本機 `enclave.key`。
2. 同時產生一組軟體 P-256 金鑰，只保留公鑰，存在本機 `peer.pub`。
3. `shared = ECDH(SE私鑰, peer公鑰)`
4. `wrappingKey = HKDF-SHA256(shared, salt: "com.avalonlotus.slate.hkdf.v1", info: "", 32 bytes)`

第 3 步會觸發 Touch ID 或 Face ID。`enclave.key` 與 `peer.pub` 屬於單一裝置，
永遠不進同步、不進備份，換機一律靠備份密碼重建。

### device wrap，Android

Android Keystore 可以直接持有 AES 金鑰，不需要 ECDH：

1. `KeyGenParameterSpec` 產生 AES-256 金鑰，設定 `setUserAuthenticationRequired(true)`、
   `setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG)`，有 StrongBox 就開
   `setIsStrongBoxBacked(true)`。
2. 這把金鑰就是 `wrappingKey`，用 BiometricPrompt 授權後直接 GCM 加解密 `K`。

alias 固定為 `slate.device.v1`。使用者更換或新增指紋會使金鑰失效，此時該裝置
退回備份密碼流程，重新產生 device wrap。

## 七、開庫流程

1. 讀 `keys.json`。
2. 找到本機的 device wrap，用硬體金鑰解出 `K`（觸發生物辨識）。
3. 找不到本機 wrap 時，要求備份密碼，用 passphrase wrap 解出 `K`，
   接著立刻補一份自己的 device wrap 寫回 `keys.json`。
4. 用 `K` 解 `vault.dat`。

失敗一律視為認證失敗，不得回報「密碼錯誤」與「檔案損毀」以外的細節。

## 八、版本

`formatVersion` 只在不相容變更時遞增。客戶端讀到比自己新的版本要拒絕寫入、
只允許唯讀開啟，避免把新欄位洗掉。

v2（僅 macOS 曾使用）與 v3 的差異：v2 的 wrap 是兩個固定欄位而非陣列、
時間用平台預設編碼、沒有墓碑。v2 檔案由 macOS 客戶端在開庫時就地升級。
