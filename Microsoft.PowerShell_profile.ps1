using namespace System.Management.Automation
using namespace System.Management.Automation.Language

# =============================================================================
# 0. 初始化錯誤收集器 (這段是新增的關鍵)
# =============================================================================
$Global:ProfileErrors = [System.Collections.ArrayList]::new()

function Record-ProfileError {
    param($Message, $Exception)
    $Global:ProfileErrors.Add("[$(Get-Date -Format 'HH:mm:ss')] $Message : $($Exception.Message)") | Out-Null
}

# 這是一個診斷工具，覺得怪怪的時候打 Test-Profile 就能看到錯誤
function Test-Profile {
    if ($Global:ProfileErrors.Count -eq 0) {
        Write-Host "✅ Profile 載入完美，沒有發生任何錯誤。" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Profile 載入過程發生了 $($Global:ProfileErrors.Count) 個錯誤：" -ForegroundColor Yellow
        foreach ($err in $Global:ProfileErrors) {
            Write-Host $err -ForegroundColor Red
        }
        Write-Host "`n提示: 若看到 '控制代碼無效' 或 'CursorPosition' 錯誤，通常是 VS Code 初始化視窗過慢導致，可忽略。" -ForegroundColor Gray
    }
}

# =============================================================================
# 1. 基礎環境設定
# =============================================================================

try {
    $OutputEncoding = [Console]::InputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
} catch {
    Record-ProfileError "編碼設定失敗" $_
}

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue

# --- 通用工具函數 ---
function hosts { start-process notepad c:\windows\system32\drivers\etc\hosts -Verb RunAs }
function cdw { Set-Location D:\Repository }
function codi { code-insiders $args }

# GitHub Copilot CLI
function c { 
    if ($args.Count -eq 0) { copilot --banner } 
    elseif ($args[0] -eq '-y') { copilot --banner ($args[1..($args.Count - 1)]) --allow-all-tools } 
    else { copilot --banner @args }
}

function kubectl { minikube kubectl -- $args }

# New-Password
function New-Password {
    [CmdletBinding()] [OutputType([String])]
    param (
        [Parameter(ValueFromPipeline)][ValidateRange(8, 255)][Int32]$Length = 10,
        [String[]]$CharacterSet = ('abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', '0123456789', '!$%&^.#;'),
        [Int32[]]$CharacterSetCount = (@(1) * $CharacterSet.Count),
        [switch]$ConvertToSecureString
    )
    begin {
        try {
            $bytes = [Byte[]]::new(4); $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create(); $rng.GetBytes($bytes)
            $rnd = [Random]::new([System.BitConverter]::ToInt32($bytes, 0))
            if ($CharacterSet.Count -ne $CharacterSetCount.Count) { throw "CharacterSet count mismatch" }
            $allCharacterSets = [String]::Concat($CharacterSet)
        } catch { Record-ProfileError "New-Password 初始化失敗" $_ }
    }
    process {
        try {
            $requiredCharLength = 0; foreach ($i in $CharacterSetCount) { $requiredCharLength += $i }
            if ($requiredCharLength -gt $Length) { throw "Length too short" }
            $password = [Char[]]::new($Length); $index = 0
            for ($i = 0; $i -lt $CharacterSet.Count; $i++) { for ($j = 0; $j -lt $CharacterSetCount[$i]; $j++) { $password[$index++] = $CharacterSet[$i][$rnd.Next($CharacterSet[$i].Length)] } }
            for ($i = $index; $i -lt $Length; $i++) { $password[$index++] = $allCharacterSets[$rnd.Next($allCharacterSets.Length)] }
            for ($i = $Length; $i -gt 0; $i--) { $n = $i - 1; $m = $rnd.Next($i); $j = $password[$m]; $password[$m] = $password[$n]; $password[$n] = $j }
            $password = [String]::new($password)
            if ($ConvertToSecureString.IsPresent) { ConvertTo-SecureString -String $password -AsPlainText -Force } else { $password }
        } catch { Record-ProfileError "New-Password 執行失敗" $_; Write-Error $_ }
    }
}

function New-Secret {
    param([Parameter(Mandatory = $true, Position = 0)][int]$bits)
    if ($bits -le 0 -or ($bits % 8) -ne 0) { Write-Error "請輸入 8 的倍數"; return }
    try {
        $bytes = New-Object "Byte[]" ($bits / 8)
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes); $rng.Dispose()
        $base64Secret = [Convert]::ToBase64String($bytes)
        $base64Secret; $base64Secret | Set-Clipboard
        Write-Host "Secret 已複製到剪貼簿！" -ForegroundColor Cyan
    } catch { Record-ProfileError "New-Secret 失敗" $_ }
}

function Split-Copilot {
    try {
        if (-not (Get-Command wt -ErrorAction SilentlyContinue)) { throw "需安裝 Windows Terminal" }
        if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) { throw "需安裝 Copilot CLI" }
        wt -w 0 split-pane -d "$PWD" pwsh -NoLogo -NoExit -Command "copilot"
    } catch { Write-Error $_; Record-ProfileError "Split-Copilot 失敗" $_ }
}
Set-Alias -Name spc -Value Split-Copilot

# =============================================================================
# 2. 參數自動補全 (失敗會被記錄，但不會中斷)
# =============================================================================

try {
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        winget complete --word="$($wordToComplete.Replace('"', '""'))" --commandline "$($commandAst.ToString().Replace('"', '""'))" --position $cursorPosition | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($commandName, $wordToComplete, $cursorPosition)
        dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
    Register-ArgumentCompleter -Native -CommandName npm -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $Local:ast = $commandAst.ToString().Replace(' ', '')
        if ($Local:ast -eq 'npm') { ('run install start'.Split(' ')) | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { New-Object -Type System.Management.Automation.CompletionResult -ArgumentList $_ } }
        if ($Local:ast -eq 'npmrun' -and (Test-Path .\package.json)) {
             $scripts = (Get-Content .\package.json | ConvertFrom-Json).scripts
             if ($scripts) { $scripts | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object { New-Object -Type System.Management.Automation.CompletionResult -ArgumentList $_.Name } }
        }
    }
} catch {
    Record-ProfileError "自動補全註冊失敗" $_
}


# =============================================================================
# 3. 互動式環境設定 & PSReadLine
# =============================================================================
$IsRealTerminal = $false
try {
    # 我們把判斷邏輯包在 try 裡面
    # 因為如果沒有 Console Handle，光是讀取 WindowWidth 就會崩潰
    if ($Host.UI.SupportsVirtualTerminal -and 
        ([Console]::WindowWidth -gt 0) -and 
        (-not [Console]::IsOutputRedirected)) {
        $IsRealTerminal = $true
    }
}
catch {
    # 如果讀取寬度失敗，代表這是一個無頭(Headless)環境，保持 False
    $IsRealTerminal = $false
}
if ($IsRealTerminal) {
    try {
        # --- PSReadLine 設定 ---
        Import-Module PSReadLine -ErrorAction SilentlyContinue
        Set-PSReadLineOption -EditMode Windows
        
        if ([Environment]::UserInteractive -and -not [Console]::IsOutputRedirected) {
             Set-PSReadLineOption -PredictionSource History
             Set-PSReadLineOption -PredictionViewStyle ListView
        }

        # Key Handlers
        Set-PSReadlineKeyHandler -Chord ctrl+d -Function ViExit
        Set-PSReadlineKeyHandler -Chord ctrl+w -Function BackwardDeleteWord
        Set-PSReadlineKeyHandler -Chord ctrl+e -Function EndOfLine
        Set-PSReadlineKeyHandler -Chord ctrl+a -Function BeginningOfLine

        # F7
        Set-PSReadLineKeyHandler -Key F7 -BriefDescription History -ScriptBlock {
            $pattern = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$pattern, [ref]$null)
            if ($pattern) { $pattern = [regex]::Escape($pattern) }
            $historyPath = (Get-PSReadLineOption).HistorySavePath
            if (Test-Path $historyPath) {
                $history = [System.Collections.ArrayList]@()
                Get-Content $historyPath -Encoding UTF8 | ForEach-Object { $history.Add($_) }
                $history.Reverse()
                $command = $history | Out-GridView -Title History -PassThru
                if ($command) { [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine(); [Microsoft.PowerShell.PSConsoleReadLine]::Insert($command) }
            }
        }
        
        # F1
        Set-PSReadLineKeyHandler -Key F1 -BriefDescription CommandHelp -ScriptBlock {
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

        # 簡化版的 Smart Handlers (功能不變)
        Set-PSReadLineKeyHandler -Key '"', "'" -ScriptBlock {
            param($key, $arg); $quote = $key.KeyChar; $sStart = $null; $sLen = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$sStart, [ref]$sLen)
            if ($sStart -ne -1) { 
                $line = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$null)
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace($sStart, $sLen, "$quote$($line.SubString($sStart, $sLen))$quote"); [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($sStart + $sLen + 2)
            } else { [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote) }
        }
        Set-PSReadLineKeyHandler -Key '(', '{', '[' -ScriptBlock {
            param($key, $arg); $c = switch ($key.KeyChar) { '(' {')'} '{' {'}'} '[' {']'} }; [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$c"); 
            $cur = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$null, [ref]$cur); [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cur - 1)
        }
        Set-PSReadLineKeyHandler -Key ')', ']', '}' -ScriptBlock {
            param($key, $arg); $l = $null; $c = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$l, [ref]$c);
            if ($c -lt $l.Length -and $l[$c] -eq $key.KeyChar) { [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($c + 1) } else { [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)") }
        }
        Set-PSReadLineKeyHandler -Key Backspace -ScriptBlock {
            param($key, $arg); $l = $null; $c = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$l, [ref]$c)
            if ($c -gt 0 -and $c -lt $l.Length) {
                $m = switch ($l[$c]) { '"' {'"'} "'" {"'"} ')' {'('} ']' {'['} '}' {'{'} default {$null} }
                if ($m -ne $null -and $l[$c - 1] -eq $m) { [Microsoft.PowerShell.PSConsoleReadLine]::Delete($c - 1, 2) } else { [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg) }
            } else { [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg) }
        }

    } catch {
        Record-ProfileError "PSReadLine 設定失敗" $_
    }

    # --- 視覺美化 (獨立 Catch) ---
    try {
        if (Get-Module -ListAvailable Terminal-Icons) { Import-Module Terminal-Icons }
        if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
            $ompConfig = "~/.ohmyposhv3-will.omp.json"
            if (Test-Path $ompConfig) { oh-my-posh init pwsh --config $ompConfig | Invoke-Expression }
            else { oh-my-posh init pwsh | Invoke-Expression }
        }

        # 安全的 Clear-Host
        if ([Console]::WindowWidth -gt 0) { [System.Console]::Clear() }
    } catch {
        # 捕捉視覺錯誤
        Record-ProfileError "視覺特效載入失敗 (Oh-My-Posh/Clear-Host)" $_
    }
}
