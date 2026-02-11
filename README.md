# PowerShell Profile 設定檔

這是一個增強的 PowerShell 設定檔，提供了更好的命令列體驗、快捷鍵綁定、自動完成功能和實用的自訂函數。
原始版本來自 [Will 保哥](https://blog.miniasp.com/post/2021/11/24/PowerShell-prompt-with-Oh-My-Posh-and-Windows-Terminal)，並增加了以下常用功能。

## 功能概覽

### 🎯 主要功能
- **PSReadLine 增強** - 提供命令歷史記錄、預測輸入和智能編輯功能
- **自訂快捷鍵** - 類似 Bash 的快捷鍵操作（Ctrl+D, Ctrl+W, Ctrl+E, Ctrl+A 等）
- **智能括號配對** - 自動配對引號、括號和大括號
- **自動完成** - 支援 winget、dotnet 和 npm 的參數自動完成
- **GitHub Copilot CLI** - 整合 GitHub Copilot CLI 的快速命令別名
- **實用函數** - 包含密碼生成、快捷導航、開發工具別名等
- **美化終端** - 使用 oh-my-posh 和 Terminal-Icons 美化外觀

### 📦 內建自訂函數
| 函數 | 功能說明 |
|------|---------|
| `hosts` | 以管理員權限開啟 Windows hosts 檔案 |
| `cdw` | 快速切換到工作目錄 (D:\Repository) |
| `New-Password` | 生成密碼學安全的隨機密碼 |
| `c` | GitHub Copilot CLI 快速命令（支援互動模式與實驗性工具） |
| `codi` | 開啟 Visual Studio Code Insiders |

---

## 設定說明

### PSReadLine 設定

#### 基本設定
```powershell
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Windows
```

- **PredictionSource History**: 使用命令歷史記錄作為預測來源
- **PredictionViewStyle ListView**: 以列表方式顯示預測建議
- **EditMode Windows**: 使用 Windows 風格的編輯模式

#### 快捷鍵設定

| 快捷鍵 | 功能 | 說明 |
|-------|------|------|
| `Ctrl+D` | 退出 PowerShell | 類似 Linux/macOS 的 `exit` 快捷鍵 |
| `Ctrl+W` | 刪除前一個單字 | 快速刪除游標前的單字 |
| `Ctrl+E` | 移動到行尾 | 快速移動游標到命令列末端 |
| `Ctrl+A` | 移動到行首 | 快速移動游標到命令列開頭 |
| `F7` | 命令歷史記錄 | 以視窗方式瀏覽和搜尋命令歷史 |
| `F1` | 命令說明 | 開啟當前命令的說明文件 |

#### 智能輸入功能

**智能引號配對**
- 自動配對單引號 (`'`) 和雙引號 (`"`)
- 當選取文字時，會自動在選取範圍加上引號

**智能括號配對**
- 自動配對小括號 `()`、中括號 `[]`、大括號 `{}`
- 支援文字選取時的括號包圍功能

**智能退格**
- 刪除配對的引號和括號
- 更智能的字元刪除行為

### 自動完成設定

#### Winget 自動完成
```powershell
Register-ArgumentCompleter -Native -CommandName winget
```
- 提供 winget 指令的參數自動完成功能
- 支援套件名稱和命令選項的智能建議

#### .NET CLI 自動完成
```powershell
Register-ArgumentCompleter -Native -CommandName dotnet
```
- 提供 dotnet 指令的參數自動完成功能
- 支援專案範本、套件和命令選項的建議

#### NPM 自動完成
```powershell
Register-ArgumentCompleter -Native -CommandName npm
```
- 提供 npm 指令的基本自動完成功能
- 支援常用命令如 `run`、`install`、`start`
- 支援 `npm run` 後的 script 名稱自動完成

### 終端美化設定

#### Terminal-Icons
```powershell
Import-Module -Name Terminal-Icons
```
- 為檔案和資料夾添加彩色圖示
- 增強檔案列表的視覺效果

#### Oh-My-Posh 主題
```powershell
oh-my-posh init pwsh --config "~/.ohmyposhv3-will.omp.json"
```
- 載入自訂的 oh-my-posh 主題配置
- 提供美化的命令提示字元

---

## 自訂函數

### 🔧 系統工具函數

#### `hosts`
**功能**: 快速開啟 Windows hosts 檔案進行編輯

**使用方法**:
```powershell
hosts
```

**說明**: 
- 直接在記事本中開啟 `C:\Windows\System32\drivers\etc\hosts` 檔案
- 方便快速修改主機名稱解析設定

#### `cdw`
**功能**: 快速切換到工作目錄

**使用方法**:
```powershell
cdw
```

**說明**: 
- 快速切換到 `D:\Repository` 目錄
- 可根據個人需求修改目標路徑

### 🔐 密碼生成函數

#### `New-Password`
**功能**: 生成安全的隨機密碼

**使用方法**:
```powershell
# 生成預設長度(10字元)的密碼
New-Password

# 生成指定長度的密碼
New-Password -Length 16

# 生成密碼並轉換為 SecureString
New-Password -Length 12 -ConvertToSecureString
```

**參數說明**:
- `-Length`: 密碼長度 (8-255 字元，預設 10)
- `-CharacterSet`: 字元集合 (預設包含大小寫字母、數字、特殊符號)
- `-ConvertToSecureString`: 轉換為 SecureString 格式

**功能特色**:
- 使用密碼學安全的隨機數生成器
- 確保每個字元集至少包含一個字元
- 支援自訂字元集合
- Fisher-Yates 演算法進行字元隨機排列

### 🛠️ 開發工具函數

#### `c`
**功能**: GitHub Copilot CLI 的簡化別名

**使用方法**:
```powershell
# 開啟 GitHub Copilot CLI 互動模式
c

# 使用 GitHub Copilot CLI 執行指令
c "如何列出所有 git 分支"

# 允許所有工具（包含實驗性工具）
c -y "如何部署應用程式"
```

**參數說明**:
- 無參數: 開啟 Copilot CLI 互動模式（帶 banner）
- `-y`: 允許所有工具（包含實驗性工具），並將剩餘參數傳遞給 Copilot
- 其他參數: 直接傳遞給 `copilot` 指令

**說明**: 
- 簡化 GitHub Copilot CLI 的使用
- 自動加上 `--banner` 參數以顯示橫幅
- 支援實驗性工具的快速啟用

#### `codi`
**功能**: 開啟 Visual Studio Code Insiders

**使用方法**:
```powershell
# 開啟當前目錄
codi .

# 開啟指定檔案
codi myfile.txt

# 開啟指定目錄
codi "C:\MyProject"
```

**說明**: 
- `code-insiders` 指令的簡化別名
- 支援所有 VS Code 的命令列參數

---

## 安裝和使用

### 前置需求

1. **PowerShell 7.0+** (建議使用最新版本)
2. **PSReadLine 模組**
3. **Terminal-Icons 模組**
4. **oh-my-posh** (用於終端美化)

### 安裝步驟

1. **安裝必要模組**:
   ```powershell
   Install-Module PSReadLine -Force
   Install-Module Terminal-Icons -Force
   ```

2. **安裝 oh-my-posh**:
   ```powershell
   winget install JanDeDobbeleer.OhMyPosh
   ```

3. **複製設定檔**:
   將 `Microsoft.PowerShell_profile.ps1` 複製到你的 PowerShell 設定檔目錄:
   ```powershell
   # 查看設定檔路徑
   $PROFILE
   
   # 複製設定檔到正確位置
   Copy-Item Microsoft.PowerShell_profile.ps1 $PROFILE
   ```

4. **設定 oh-my-posh 主題** (可選):
   確保 `~/.ohmyposhv3-will.omp.json` 主題檔案存在，或修改設定檔中的主題路徑

### 自訂設定

- **修改工作目錄**: 編輯 `cdw` 函數中的路徑
- **調整快捷鍵**: 根據個人喜好修改 `Set-PSReadlineKeyHandler` 設定
- **自訂主題**: 修改 oh-my-posh 的設定檔路徑
- **添加函數**: 在設定檔末尾添加自訂函數

---

## 疑難排解

### 常見問題

1. **模組載入失敗**:
   - 確保已安裝必要的模組
   - 檢查執行原則設定: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

2. **oh-my-posh 無法載入**:
   - 確認 oh-my-posh 已正確安裝
   - 檢查主題檔案路徑是否正確

3. **自動完成無效**:
   - 重新啟動 PowerShell
   - 檢查相關工具 (winget, dotnet, npm) 是否已安裝

### 效能最佳化

- 設定檔載入時間過長時，可以考慮移除不常用的功能
- 定期清理命令歷史記錄檔案
- 使用 `Measure-Command` 測量載入時間

---

## 貢獻和回饋

如果你有任何建議或發現問題，歡迎開啟 issue 或提交 pull request。

## 授權

此專案採用 MIT 授權條款。
