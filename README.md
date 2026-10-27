# MediaShelf（LuminaAI）

跨 **macOS / iOS** 的本機 + NAS 媒體瀏覽器初版。

- **區網**：SMB 為主
- **外出**：WebDAV 為備援
- **核心能力**：來源管理、增量掃描索引、縮圖佇列、媒體庫網格 / 資料夾瀏覽 / 檢視器

## 專案結構

```
Package.swift                 SwiftPM：MediaShelfCore + mediashelf-cli
Sources/MediaShelfCore/      領域模型、Local/SMB/WebDAV、索引、縮圖
Sources/MediaShelfCLI/       命令列 demo / 本機掃描
Apps/MediaShelf/             SwiftUI App（Mac + iPhone）
Tests/MediaShelfCoreTests/   單元測試
```

## 快速驗證（CLI）

```bash
swift test
swift run mediashelf-cli demo
swift run mediashelf-cli scan-local /path/to/photos
```

`demo` 會連上內建的 **模擬 SMB share**（不需真 NAS），掃描圖片/影片並產生縮圖快取。

## 在 Mac 開啟 App

```bash
./scripts/bootstrap-xcode.sh
open Apps/MediaShelf/MediaShelf.xcodeproj
```

若尚未安裝 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

1. Xcode → New Multiplatform App（SwiftUI）→ 名稱 `MediaShelf`
2. Add Local Package → 選本 repo 根目錄 → 加入 `MediaShelfCore`
3. 用 `Apps/MediaShelf/MediaShelf/` 內的原始碼取代範本

## 新增真實來源

App 內「新增來源」：

| 類型 | URI 範例 | 場景 |
|------|----------|------|
| SMB | `smb://nas.local/media` | 家用區網 |
| WebDAV | `https://nas.example.com/webdav/media` | 外出（HTTPS） |
| 本機 | `/Users/you/Pictures` | 本機磁碟 |

> 初版 SMB 使用可替換的 `SMBTransport`；預設是 `SimulatedSMBTransport` 方便開發 UI。下一步可接 [AMSMB2](https://github.com/amosavian/AMSMB2) 打真 NAS。WebDAV 已走真實 `URLSession` PROPFIND/GET。

## 架構摘要

```
UI (SwiftUI)
  → LibraryService
      → MediaSource (Local / SMB / WebDAV)
      → MediaIndexer → MediaIndexStore (index.json)
      → ThumbnailService → Thumbs/
```

## 版本定位

這是 **MVP 骨架**：可跑通來源 → 掃描 → 索引 → 縮圖 → 瀏覽流程。尚未包含真實影片解碼播放、ImageIO 縮圖、Keychain、以及 AMSMB2 實機連線。
