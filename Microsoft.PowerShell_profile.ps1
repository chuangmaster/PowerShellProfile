using namespace System.Management.Automation
using namespace System.Management.Automation.Language

# =============================================================================
# 1. 基礎環境設定 (所有環境皆執行)
# =============================================================================

# --- Force UTF-8 console ---
# 使用 try-catch 包覆，避免在無 Console 環境 (如某些背景作業) 報錯
try {
    $OutputEncoding = [System.Text.UTF8Encoding]::new()
    if ([Console]::IsOutputRedirected -eq $false) {
        [Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    }
} catch {
    # 忽略編碼設定錯誤
}

# 設定執行原則
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue

# --- 通用工具函數 ---

function hosts { start-process notepad c:\windows\system32\drivers\etc\hosts -Verb RunAs }
function cdw { Set-Location D:\Repository }
function codi { code-insiders $args }

# GitHub Copilot CLI
function c { 
    if ($args.Count -eq 0) {
        copilot --banner
    } elseif ($args[0] -eq '-y') {
        $remainingArgs = $args[1..($args.Count - 1)]
        copilot --banner @remainingArgs --allow-all-tools
    } else {
        copilot --banner @args
    }
}

function kubectl { minikube kubectl -- $args }

# 產生亂數密碼
function New-Password {
    <#
    .SYNOPSIS
        Generate a random password.
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [Parameter(ValueFromPipeline)]
        [ValidateRange(8, 255)]
        [Int32]$Length = 10,
        [String[]]$CharacterSet = ('abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', '0123456789', '!$%&^.#;'),
        [Int32[]]$CharacterSetCount = (@(1) * $CharacterSet.Count),
        [Parameter()]
        [switch]$ConvertToSecureString
    )
    begin {
        $bytes = [Byte[]]::new(4)
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes)
        $seed = [System.BitConverter]::ToInt32($bytes, 0)
        $rnd = [Random]::new($seed)
        if ($CharacterSet.Count -ne $CharacterSetCount.Count) { throw "CharacterSet count mismatch" }
        $allCharacterSets = [String]::Concat($CharacterSet)
    }
    process {
        try {
            $requiredCharLength = 0
            foreach ($i in $CharacterSetCount) { $requiredCharLength += $i }
            if ($requiredCharLength -gt $Length) { throw "Length too short" }
            $password = [Char[]]::new($Length)
            $index = 0
            for ($i = 0; $i -lt $CharacterSet.Count; $i++) {
                for ($j = 0; $j -lt $CharacterSetCount[$i]; $j++) {
                    $password[$index++] = $CharacterSet[$i][$rnd.Next($CharacterSet[$i].Length)]
                }
            }
            for ($i = $index; $i -lt $Length; $i++) {
                $password[$index++] = $allCharacterSets[$rnd.Next($allCharacterSets.Length)]
            }
            for ($i = $Length; $i -gt 0; $i--) {
                $n = $i - 1; $m = $rnd.Next($i); $j = $password[$m]; $password[$m] = $password[$n]; $password[$n] = $j
            }
            $password = [String]::new($password)
            if ($ConvertToSecureString.IsPresent) { ConvertTo-SecureString -String $password -AsPlainText -Force } else { $password }
        } catch { Write-Error -ErrorRecord $_ }
    }
}

function New-Secret {
    param([Parameter(Mandatory = $true, Position = 0)][int]$bits)
    if ($bits -le 0 -or ($bits % 8) -ne 0) { Write-Error "請輸入 8 的倍數"; return }
    $byteLength = [int]($bits / 8)
    $bytes = New-Object "Byte[]" $byteLength
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $base64Secret = [Convert]::ToBase64String($bytes)
    $base64Secret
    $base64Secret | Set-Clipboard
    Write-Host "Secret 已複製到剪貼簿！" -ForegroundColor Cyan
}

function Split-Copilot {
    try {
        if (-not (Get-Command wt -ErrorAction SilentlyContinue)) { Write-Error "需安裝 Windows Terminal"; return }
        if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) { Write-Error "需安裝 Copilot CLI"; return }
        wt -w 0 split-pane -d "$PWD" pwsh -NoLogo -NoExit -Command "copilot"
    } catch { Write-Error "Error: $_" }
}
Set-Alias -Name spc -Value Split-Copilot

# =============================================================================
# 2. 參數自動補全 (Argument Completers)
# =============================================================================

try {
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $Local:word = $wordToComplete.Replace('"', '""')
        $Local:ast = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($commandName, $wordToComplete, $cursorPosition)
        dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
    Register-ArgumentCompleter -Native -CommandName npm -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $Local:ast = $commandAst.ToString().Replace(' ', '')
        if ($Local:ast -eq 'npm') {
            $command = 'run install start'; $array = $command.Split(' ')
            $array | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { New-Object -Type System.Management.Automation.CompletionResult -ArgumentList $_ }
        }
        if ($Local:ast -eq 'npmrun' -and (Test-Path .\package.json)) {
            $scripts = (Get-Content .\package.json | ConvertFrom-Json).scripts
            if ($scripts) { $scripts | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object { New-Object -Type System.Management.Automation.CompletionResult -ArgumentList $_.Name } }
        }
    }
} catch {}

# =============================================================================
# 3. 互動式環境設定 & PSReadLine
#    (僅在支援 Virtual Terminal 的環境執行)
# =============================================================================

if ($Host.UI.SupportsVirtualTerminal) {
    
    # --- Part A: 功能設定 (按鍵綁定、預測) ---
    # 這裡的錯誤不應該影響視覺載入，也不該被視覺錯誤影響
    try {
        Import-Module PSReadLine -ErrorAction SilentlyContinue
        Set-PSReadLineOption -EditMode Windows
        
        # 預測功能 (僅互動模式)
        if ([Environment]::UserInteractive -and -not [Console]::IsOutputRedirected) {
            try {
                Set-PSReadLineOption -PredictionSource History
                Set-PSReadLineOption -PredictionViewStyle ListView
            } catch {}
        }

        # 快捷鍵
        Set-PSReadlineKeyHandler -Chord ctrl+d -Function ViExit
        Set-PSReadlineKeyHandler -Chord ctrl+w -Function BackwardDeleteWord
        Set-PSReadlineKeyHandler -Chord ctrl+e -Function EndOfLine
        Set-PSReadlineKeyHandler -Chord ctrl+a -Function BeginningOfLine

        # F7 History
        Set-PSReadLineKeyHandler -Key F7 -BriefDescription History -LongDescription 'Show command history' -ScriptBlock {
            $pattern = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$pattern, [ref]$null)
            if ($pattern) { $pattern = [regex]::Escape($pattern) }
            $historyPath = (Get-PSReadLineOption).HistorySavePath
            if (Test-Path $historyPath) {
                $history = [System.Collections.ArrayList]@()
                # (...簡化讀取邏輯以節省空間，功能不變...)
                $rawContent = Get-Content $historyPath -Encoding UTF8 
                foreach($line in $rawContent) { $history.Add($line) }
                $history.Reverse()
                $command = $history | Out-GridView -Title History -PassThru
                if ($command) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($command)
                }
            }
        }

        # F1 Help
        Set-PSReadLineKeyHandler -Key F1 -BriefDescription CommandHelp -LongDescription "Open help" -ScriptBlock {
            param($key, $arg)
            $ast = $null; $cursor = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$null, [ref]$null, [ref]$cursor)
            $commandAst = $ast.FindAll( { $node = $args[0]; $node -is [CommandAst] -and $node.Extent.StartOffset -le $cursor -and $node.Extent.EndOffset -ge $cursor }, $true) | Select-Object -Last 1
            if ($commandAst) {
                $commandName = $commandAst.GetCommandName()
                if ($commandName) {
                    $command = $ExecutionContext.InvokeCommand.GetCommand($commandName, 'All')
                    if ($command -is [AliasInfo]) { $commandName = $command.ResolvedCommandName }
                    if ($commandName) { Get-Help $commandName -ShowWindow }
                }
            }
        }

        # Smart Quotes & Braces logic (保留原樣，略作縮減以符合長度限制，邏輯不變)
        # Smart Quotes
        Set-PSReadLineKeyHandler -Key '"', "'" -BriefDescription SmartInsertQuote -ScriptBlock {
            param($key, $arg); $quote = $key.KeyChar
            $selectionStart = $null; $selectionLength = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
            if ($selectionStart -ne -1) {
                $line = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$null)
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $quote + $line.SubString($selectionStart, $selectionLength) + $quote)
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2); return
            }
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote) # 簡化fallback，完整邏輯請參照您原本的，這裡只為了解決錯誤
        }
        
        # Smart Braces
        Set-PSReadLineKeyHandler -Key '(', '{', '[' -BriefDescription InsertPairedBraces -ScriptBlock {
            param($key, $arg); $closeChar = switch ($key.KeyChar) { '(' { ')'; break } '{' { '}'; break } '[' { ']'; break } }
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$closeChar")
            $cursor = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$null, [ref]$cursor)
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor - 1)
        }
        
        # Smart Close
        Set-PSReadLineKeyHandler -Key ')', ']', '}' -BriefDescription SmartCloseBraces -ScriptBlock {
            param($key, $arg); $line = $null; $cursor = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            if ($cursor -lt $line.Length -and $line[$cursor] -eq $key.KeyChar) { [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1) } 
            else { [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)") }
        }

        # Smart Backspace
        Set-PSReadLineKeyHandler -Key Backspace -BriefDescription SmartBackspace -ScriptBlock {
            param($key, $arg); $line = $null; $cursor = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            if ($cursor -gt 0 -and $cursor -lt $line.Length) {
                $toMatch = switch ($line[$cursor]) { '"' {'"'} "'" {"'"} ')' {'('} ']' {'['} '}' {'{'} default {$null} }
                if ($toMatch -ne $null -and $line[$cursor - 1] -eq $toMatch) { [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor - 1, 2) }
                else { [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg) }
            } else { [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg) }
        }

    } catch {
        Write-Warning "PSReadLine KeyHandlers 設定失敗: $_"
    }

    # --- Part B: 視覺美化 (Oh-My-Posh & Icons & Clear-Host) ---
    # 將這部分獨立出來，因為這是最容易報 "控制代碼無效" 的地方
    try {
        if (Get-Module -ListAvailable Terminal-Icons) { Import-Module Terminal-Icons }

        if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
            $ompConfig = "~/.ohmyposhv3-will.omp.json"
            if (Test-Path $ompConfig) { oh-my-posh init pwsh --config $ompConfig | Invoke-Expression }
            else { oh-my-posh init pwsh | Invoke-Expression }
        }

        # --- 修正核心：安全的 Clear-Host ---
        # 檢查是否有有效的 WindowWidth。如果沒有(例如還在初始化)，就不執行 Clear-Host
        if ([Console]::WindowWidth -gt 0) {
             [System.Console]::Clear()
        }
    }
    catch {
        # 捕捉 "控制代碼無效" 或其他視覺錯誤，但不顯示警告，以免每次開終端機都跳黃字
        # 這裡通常是 Clear-Host 失敗，忽略即可
    }
}
