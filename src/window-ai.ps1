<#
    The window's AI-hulp tab (phase 6, step 4): the problem in the client's
    own words, and Claude picks which checks to run -- the ? of the text
    menu. The whole conversation (Invoke-HcAiConversation, src\ai.ps1) runs
    in the worker, checks included; the tab shows which check the AI is
    running while it works, then its answer. The fixes it names open in
    Problemen, through the same Ja/Nee, check again and undo as always.
#>

function New-HcAiState {
    @{ Stage = 'new'; Question = ''; Progress = @(); State = $null; Error = $null; Box = $null }
}

function Start-HcAi {
    $w = $script:HcWin
    $a = $w.Ai
    if ($a.Stage -ne 'new') { return }
    if (-not $w.Environment.Online) { $a.Stage = 'offline' }
    elseif (Test-HcUnlocked) { $a.Stage = 'ask' }
    else { $a.Stage = 'code' }
}

# The worker runs the conversation with this session's token.
function Start-HcAiQuestion {
    $w = $script:HcWin
    $a = $w.Ai
    $text = "$($a.Box.Text)".Trim()
    if (-not $text -or (Test-HcBusy)) { return }
    if (-not (Test-HcUnlocked)) { $a.Stage = 'code'; Update-HcOther; return }
    $a.Question = $text
    $a.Progress = @()
    $a.State = $null
    $a.Error = $null
    $a.Stage = 'running'
    Add-HcJob @{ Kind = 'ai'; Text = $text; Body = @{ Token = $script:HcToken; Expires = $script:HcTokenExpires }
                 Seen = 0; Live = 'Update-HcAiProgress'; Done = 'Complete-HcAi' }
    Update-HcOther
    Update-HcSide
}

# While the AI works: what it wrote so far ("De AI controleert: B1 ...").
function Update-HcAiProgress {
    param([hashtable]$Job)
    $lines = @($Job.PS.Streams.Information | ForEach-Object { "$($_.MessageData)".Trim() } | Where-Object { $_ })
    if ($lines.Count -eq $Job.Seen) { return }
    $Job.Seen = $lines.Count
    $script:HcWin.Ai.Progress = @($lines | Where-Object { $_ -ne (T 'ai.thinking') })
    if ($script:HcWin.Tab -eq 'ai') { Update-HcOther }
}

function Complete-HcAi {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $a = $w.Ai
    $state = @($Output | Where-Object { $_ -and $_.PSObject.Properties['Answer'] -and $_.PSObject.Properties['Reports'] }) | Select-Object -Last 1
    $a.Progress = @($Info | Where-Object { $_ -ne (T 'ai.thinking') })
    if ($ErrorText -or -not $state) {
        $a.Stage = 'answer'
        $a.Error = T 'win.error' $(if ($ErrorText) { $ErrorText } else { '-' })
    } else {
        $a.State = $state
        $a.Stage = 'answer'
        if ($state.Error) {
            if ($state.Error -eq 'locked_out') { $script:HcToken = $null }
            $a.Error = Get-HcRelayMessage $state.Error
        } elseif ($state.Refused) { $a.Error = T 'win.ai.refused' }
        # The checks the AI ran count as opened this visit, as in the text menu.
        foreach ($code in @($state.Reports.Keys)) {
            $w.Reports[$code] = $state.Reports[$code]
            if ($state.Inputs.ContainsKey($code)) { $w.Inputs[$code] = $state.Inputs[$code] }
        }
        $pick = if ($state.Answer) { [string]$state.Answer.problem_code } else { '' }
        if ($state.Reports.ContainsKey($pick)) { Save-HcVisit $pick $state.Reports[$pick] }
    }
    Update-HcOther
    Update-HcSide
}

# "Show the fixes": the report of the problem the AI points to, in
# Problemen, with only the fixes it chose (all of them after a re-check).
function Open-HcAiFixes {
    $w = $script:HcWin
    $s = $w.Ai.State
    $code = [string]$s.Answer.problem_code
    $report = $s.Reports[$code]
    if (-not $report) { return }
    Select-HcActions $report @($s.Answer.fix_ids | ForEach-Object { [string]$_ })
    $w.Tab = 'problems'
    $w.Code = $code
    $w.Report = $report
    $w.FromAll = $false
    Clear-HcMessages
    $w.View = 'report'
    $script:HcCurrentCode = $code
    Update-HcTabs
    Update-HcGroups
    Update-HcResult
}

# A chat bubble: the client's words on the right, the AI's on the left.
function New-HcBubble {
    param([object[]]$Children, [switch]$Mine)
    $stack = New-Object Windows.Controls.StackPanel
    foreach ($c in $Children) { if ($c) { [void]$stack.Children.Add($c) } }
    $b = New-Object Windows.Controls.Border
    $b.CornerRadius = New-Object Windows.CornerRadius(14)
    $b.BorderThickness = New-HcThickness @(1, 1, 1, 1)
    $b.Padding = New-HcThickness @(16, 12, 16, 8)
    $b.Margin = New-HcThickness @($(if ($Mine) { 120 } else { 0 }), 0, $(if ($Mine) { 0 } else { 80 }), 12)
    $b.HorizontalAlignment = if ($Mine) { 'Right' } else { 'Left' }
    $b.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $(if ($Mine) { 'HiSoft' } else { 'Panel' }))
    $b.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Line')
    $b.Child = $stack
    $b
}

function Update-HcAiPanel {
    param($Panel)
    $w = $script:HcWin
    $a = $w.Ai
    $add = { param($element) [void]$Panel.Children.Add($element) }
    Start-HcAi

    switch ($a.Stage) {
        'offline' { & $add (New-HcText (T 'ai.offline') 15 'Soft'); return }
        'code'    { & $add (New-HcCodeBox 'ai' (T 'win.ai.codeIntro')); return }
    }
    & $add (New-HcText (T 'ai.privacy') 14 'Soft' -Margin @(0, 0, 0, 14))

    if ($a.Stage -eq 'ask') {
        & $add (New-HcText (T 'ai.title') 15 'Text' -Bold)
        $box = New-HcTextBox $a.Question
        $box.AcceptsReturn = $false
        $box.TextWrapping = 'Wrap'
        $box.MinHeight = 70
        $box.VerticalContentAlignment = 'Top'
        $box.Tag = @{ Do = 'aiAsk' }
        $box.Add_TextChanged({ $script:HcWin.Ai.Question = $this.Text })
        $box.Add_KeyDown({ if ($_.Key -eq 'Return') { Invoke-HcClick $this } })
        $box.Margin = New-HcThickness @(0, 4, 0, 8)
        $box.Add_Loaded({ [void]$this.Focus() })
        $a.Box = $box
        & $add $box
        $ask = New-HcButton (T 'win.ai.ask') @{ Do = 'aiAsk' } 'HcPrimary'
        $ask.HorizontalAlignment = 'Left'
        & $add $ask
        # Examples, as a client would say it: one click fills the box.
        & $add (New-HcText (T 'win.ai.examples') 13 'Soft' -Bold -Margin @(0, 14, 0, 6))
        $chips = New-Object Windows.Controls.WrapPanel
        foreach ($e in @((T 'win.ai.example') -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            [void]$chips.Children.Add((New-HcChip $e @{ Do = 'aiExample'; Text = $e }))
        }
        & $add $chips
        return
    }

    & $add (New-HcBubble @(New-HcText $a.Question 15 'Text' -Margin @(0, 0, 0, 4)) -Mine)
    $lines = @()
    foreach ($p in @($a.Progress)) { $lines += New-HcLine 'ok' $p 'Soft' }
    if ($a.Stage -eq 'running') {
        $lines += New-HcText (T 'ai.thinking') 14.5 'Soft' -Margin @(0, 4, 0, 4)
        $bar = New-Object Windows.Controls.ProgressBar
        $bar.IsIndeterminate = $true
        $bar.Height = 6
        $bar.Width = 260
        $bar.HorizontalAlignment = 'Left'
        $bar.Margin = New-HcThickness @(0, 0, 0, 6)
        $bar.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Hi')
        $lines += $bar
        & $add (New-HcBubble $lines)
        return
    }

    # The answer.
    $s = $a.State
    if ($a.Error) {
        $lines += New-HcText $a.Error 15 'Warn' -Bold
    } elseif ($s -and $s.Answer) {
        $answer = $s.Answer
        $lines += New-HcText ([string]$answer.summary) 15.5 'Text' -Margin @(0, 4, 0, 6)
        $lines += New-HcText (T ('ai.confidence.' + $answer.confidence)) 13 'Soft'
        $steps = @($answer.steps | Where-Object { $_ })
        if ($steps.Count) {
            $lines += New-HcText (T 'ai.steps').TrimEnd(':') 14 'Text' -Bold -Margin @(0, 8, 0, 4)
            for ($i = 0; $i -lt $steps.Count; $i++) { $lines += New-HcText ("$($i + 1).  " + [string]$steps[$i]) 14.5 'Text' -Margin @(0, 0, 0, 4) }
        }
        $code = [string]$answer.problem_code
        if ($s.Reports.ContainsKey($code)) {
            $count = @($answer.fix_ids | Where-Object { $_ }).Count
            $label = if ($count) { T 'win.ai.openFixes' $code (T "problem.$code") } else { T 'win.ai.openCheck' $code (T "problem.$code") }
            $open = New-HcButton $label @{ Do = 'aiFixes' } 'HcPrimary'
            $open.Margin = New-HcThickness @(0, 8, 0, 8)
            $open.HorizontalAlignment = 'Left'
            $lines += $open
        }
    } elseif ($s -and $s.Text) {
        $lines += New-HcText ([string]$s.Text) 15 'Text'
    } else {
        $lines += New-HcText (T 'win.ai.noAnswer') 15 'Warn'
    }
    & $add (New-HcBubble $lines)
    $again = New-HcButton (T 'win.ai.again') @{ Do = 'aiAgain' }
    $again.HorizontalAlignment = 'Left'
    & $add $again
}

function Invoke-HcAiClick {
    param([hashtable]$Tag)
    $w = $script:HcWin
    switch ($Tag.Do) {
        'aiAsk'     { Start-HcAiQuestion }
        'aiExample' { $w.Ai.Box.Text = $Tag.Text; $w.Ai.Box.CaretIndex = $Tag.Text.Length; [void]$w.Ai.Box.Focus() }
        'aiFixes'   { Open-HcAiFixes }
        'aiAgain'   { $w.Ai.Stage = 'ask'; $w.Ai.Question = ''; Update-HcOther }
        default     { return $false }
    }
    $true
}
