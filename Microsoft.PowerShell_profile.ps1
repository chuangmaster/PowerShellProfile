using namespace System.Management.Automation
using namespace System.Management.Automation.Language

# =============================================================================
# 1. 基礎環境設定 (所有環境皆執行)
#    包含：編碼、執行原則、通用函數
# =============================================================================

# --- Force UTF-8 console ---
# 移到最外層確保所有輸出的編碼正確
$OutputEncoding = [Console]::InputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# 設定執行原則 (防止腳本無法執行)
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue

# --- 通用工具函數 (無論是否有 UI 支援都應該要能用) ---

# 快速開啟 hosts
function hosts { start-process notepad c:\windows\system32\drivers\etc\hosts -Verb RunAs }

# 快速開啟工作目錄
function cdw { Set-Location D:\Repository }

# VS Code Insiders
function codi { code-insiders $args }

# GitHub Copilot CLI
function c { 
    if ($args.Count -eq 0) {
        copilot --banner
    } elseif ($args[0] -eq '-y') { # 允許所有工具（包含實驗性工具）
        $remainingArgs = $args[1..($args.Count - 1)]
        copilot --banner @remainingArgs --allow-all-tools
    } else {
        copilot --banner @args
    }
}

# miniKube 縮短的指令
function kubectl { minikube kubectl -- $args }

# 產生亂數密碼 (保留你原本強大的邏輯)
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

        [String[]]$CharacterSet = ('abcdefghijklmnopqrstuvwxyz',
            'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
            '0123456789',
            '!$%&^.#;'),

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

        if ($CharacterSet.Count -ne $CharacterSetCount.Count) {
            throw "The number of items in -CharacterSet needs to match the number of items in -CharacterSetCount"
        }

        $allCharacterSets = [String]::Concat($CharacterSet)
    }

    process {
        try {
            $requiredCharLength = 0
            foreach ($i in $CharacterSetCount) {
                $requiredCharLength += $i
            }

            if ($requiredCharLength -gt $Length) {
                throw "The sum of characters specified by CharacterSetCount is higher than the desired password length"
            }

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

            # Fisher-Yates shuffle
            for ($i = $Length; $i -gt 0; $i--) {
                $n = $i - 1
                $m = $rnd.Next($i)
                $j = $password[$m]
                $password[$m] = $password[$n]
                $password[$n] = $j
            }

            $password = [String]::new($password)
            if ($ConvertToSecureString.IsPresent) {
                ConvertTo-SecureString -String $password -AsPlainText -Force
            }
            else {
                $password
            }
        }
        catch {
            Write-Error -ErrorRecord $_
        }
    }
}

# =============================================================================
# 2. 參數自動補全 (Argument Completers)
#    通常在互動模式下有用，但放在外層較為保險
# =============================================================================

try {
    # winget parameter completion
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $Local:word = $wordToComplete.Replace('"', '""')
        $Local:ast = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }

    # dotnet CLI completion
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($commandName, $wordToComplete, $cursorPosition)
        dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }

    # npm CLI completion
    Register-ArgumentCompleter -Native -CommandName npm -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $Local:ast = $commandAst.ToString().Replace(' ', '')
        if ($Local:ast -eq 'npm') {
            $command = 'run install start'
            $array = $command.Split(' ')
            $array | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                New-Object -Type System.Management.Automation.CompletionResult -ArgumentList $_
            }
        }
        if ($Local:ast -eq 'npmrun') {
            if (Test-Path .\package.json) {
                $scripts = (Get-Content .\package.json | ConvertFrom-Json).scripts
                if ($scripts) {
                    $scripts | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object {
                        New-Object -Type System.Management.Automation.CompletionResult -ArgumentList $_.Name
                    }
                }
            }
        }
    }
}
catch {
    # 忽略補全註冊錯誤
}

# =============================================================================
# 3. 互動式環境設定 & PSReadLine
#    (僅在支援 Virtual Terminal 的環境執行，避免舊環境報錯)
# =============================================================================

if ($Host.UI.SupportsVirtualTerminal) {
    try {
        # 移除 Host Name 檢查，確保 VS Code 等現代終端機也能載入
        Import-Module PSReadLine -ErrorAction SilentlyContinue

        # 基本設定
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -PredictionViewStyle ListView
        Set-PSReadLineOption -EditMode Windows

        # --- 快捷鍵綁定 ---
        Set-PSReadlineKeyHandler -Chord ctrl+d -Function ViExit
        Set-PSReadlineKeyHandler -Chord ctrl+w -Function BackwardDeleteWord
        Set-PSReadlineKeyHandler -Chord ctrl+e -Function EndOfLine
        Set-PSReadlineKeyHandler -Chord ctrl+a -Function BeginningOfLine

        # F7: History Grid View
        Set-PSReadLineKeyHandler -Key F7 -BriefDescription History -LongDescription 'Show command history' -ScriptBlock {
            $pattern = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$pattern, [ref]$null)
            if ($pattern) { $pattern = [regex]::Escape($pattern) }

            $historyPath = (Get-PSReadLineOption).HistorySavePath
            if (Test-Path $historyPath) {
                $history = [System.Collections.ArrayList]@(
                    $last = ''
                    $lines = ''
                    foreach ($line in [System.IO.File]::ReadLines($historyPath)) {
                        if ($line.EndsWith('`')) {
                            $line = $line.Substring(0, $line.Length - 1)
                            $lines = if ($lines) { "$lines`n$line" } else { $line }
                            continue
                        }
                        if ($lines) { $line = "$lines`n$line"; $lines = '' }
                        if (($line -cne $last) -and (!$pattern -or ($line -match $pattern))) {
                            $last = $line
                            $line
                        }
                    }
                )
                $history.Reverse()
                $command = $history | Out-GridView -Title History -PassThru
                if ($command) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert(($command -join "`n"))
                }
            }
        }

        # F1: Help
        Set-PSReadLineKeyHandler -Key F1 -BriefDescription CommandHelp -LongDescription "Open help" -ScriptBlock {
            param($key, $arg)
            $ast = $null; $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$null, [ref]$null, [ref]$cursor)
            $commandAst = $ast.FindAll( {
                    $node = $args[0]
                    $node -is [CommandAst] -and $node.Extent.StartOffset -le $cursor -and $node.Extent.EndOffset -ge $cursor
                }, $true) | Select-Object -Last 1

            if ($commandAst) {
                $commandName = $commandAst.GetCommandName()
                if ($commandName) {
                    $command = $ExecutionContext.InvokeCommand.GetCommand($commandName, 'All')
                    if ($command -is [AliasInfo]) { $commandName = $command.ResolvedCommandName }
                    if ($commandName) { Get-Help $commandName -ShowWindow }
                }
            }
        }

        # Smart Quotes (' or ")
        Set-PSReadLineKeyHandler -Key '"', "'" -BriefDescription SmartInsertQuote -LongDescription "Insert paired quotes" -ScriptBlock {
            param($key, $arg)
            $quote = $key.KeyChar
            $selectionStart = $null; $selectionLength = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
            $line = $null; $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

            if ($selectionStart -ne -1) {
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $quote + $line.SubString($selectionStart, $selectionLength) + $quote)
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
                return
            }

            $ast = $null; $tokens = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$null, [ref]$null)

            function FindToken {
                param($tokens, $cursor)
                foreach ($token in $tokens) {
                    if ($cursor -lt $token.Extent.StartOffset) { continue }
                    if ($cursor -lt $token.Extent.EndOffset) {
                        $result = $token
                        $token = $token -as [StringExpandableToken]
                        if ($token) {
                            $nested = FindToken $token.NestedTokens $cursor
                            if ($nested) { $result = $nested }
                        }
                        return $result
                    }
                }
                return $null
            }
            $token = FindToken $tokens $cursor

            if ($token -is [StringToken] -and $token.Kind -ne [TokenKind]::Generic) {
                if ($token.Extent.StartOffset -eq $cursor) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote ")
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                    return
                }
                if ($token.Extent.EndOffset -eq ($cursor + 1) -and $line[$cursor] -eq $quote) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                    return
                }
            }

            if ($null -eq $token -or $token.Kind -in ([TokenKind]::RParen, [TokenKind]::RCurly, [TokenKind]::RBracket)) {
                if ($line[0..$cursor].Where{ $_ -eq $quote }.Count % 2 -eq 1) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
                } else {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote")
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                }
                return
            }

            if ($token.Extent.StartOffset -eq $cursor) {
                if ($token.Kind -in ([TokenKind]::Generic, [TokenKind]::Identifier, [TokenKind]::Variable) -or $token.TokenFlags.hasFlag([TokenFlags]::Keyword)) {
                    $end = $token.Extent.EndOffset
                    $len = $end - $cursor
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace($cursor, $len, $quote + $line.SubString($cursor, $len) + $quote)
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($end + 2)
                    return
                }
            }
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
        }

        # Smart Braces (, {, [
        Set-PSReadLineKeyHandler -Key '(', '{', '[' -BriefDescription InsertPairedBraces -LongDescription "Insert matching braces" -ScriptBlock {
            param($key, $arg)
            $closeChar = switch ($key.KeyChar) { '(' { ')'; break } '{' { '}'; break } '[' { ']'; break } }
            $selectionStart = $null; $selectionLength = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
            $line = $null; $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

            if ($selectionStart -ne -1) {
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $key.KeyChar + $line.SubString($selectionStart, $selectionLength) + $closeChar)
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
            } else {
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$closeChar")
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            }
        }

        # Smart Close Braces ), }, ]
        Set-PSReadLineKeyHandler -Key ')', ']', '}' -BriefDescription SmartCloseBraces -LongDescription "Insert closing brace or skip" -ScriptBlock {
            param($key, $arg)
            $line = $null; $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            if ($line[$cursor] -eq $key.KeyChar) {
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            } else {
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)")
            }
        }

        # Smart Backspace
        Set-PSReadLineKeyHandler -Key Backspace -BriefDescription SmartBackspace -LongDescription "Delete previous char or matching pair" -ScriptBlock {
            param($key, $arg)
            $line = $null; $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            if ($cursor -gt 0) {
                $toMatch = $null
                if ($cursor -lt $line.Length) {
                    switch ($line[$cursor]) {
                        '"' { $toMatch = '"'; break } "'" { $toMatch = "'"; break }
                        ')' { $toMatch = '('; break } ']' { $toMatch = '['; break } '}' { $toMatch = '{'; break }
                    }
                }
                if ($toMatch -ne $null -and $line[$cursor - 1] -eq $toMatch) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor - 1, 2)
                } else {
                    [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg)
                }
            }
        }

        # --- 外觀美化與 Prompt ---

        # 載入 Terminal-Icons (如果有的話)
        if (Get-Module -ListAvailable Terminal-Icons) {
            Import-Module Terminal-Icons
        }

        # 載入 Oh-My-Posh (如果有的話)
        if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
            # 確保使用指定的 config，如果檔案不存在則使用預設
            $ompConfig = "~/.ohmyposhv3-will.omp.json"
            if (Test-Path $ompConfig) {
                oh-my-posh init pwsh --config $ompConfig | Invoke-Expression
            } else {
                oh-my-posh init pwsh | Invoke-Expression
            }
        }

        # 清除雜訊
        Clear-Host
    }
    catch {
        Write-Warning "Profile 載入時發生部分錯誤 (PSReadLine/Visuals): $_"
    }
}
