# ====================================================================
# Windows Debloater and System Cleaner - UNIFIED GUI
# ====================================================================

#Requires -RunAsAdministrator

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Fix for High DPI monitors so mouse coordinates align correctly
Add-Type @"
using System.Runtime.InteropServices;
public class DPI {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
try { [DPI]::SetProcessDPIAware() | Out-Null } catch {}

 $script:LogPath = "$env:TEMP\WindowsDebloat_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
 $script:PendingRebootDeletes = [System.Collections.Generic.List[string]]::new()
 $script:PendingRebootSize = 0.0
 $script:PendingRebootCount = 0
 $script:Stats = @{
    RegistryKeysSet  = 0; ServicesDisabled = 0; ServicesSkipped = 0
    AppsRemoved      = 0; AppsFailed       = 0; AppsNotFound    = 0
}
 $script:FailedApps = [System.Collections.Generic.List[string]]::new()
 $script:ResultsBox = $null
 $script:PendingOp = $false

# ===================================================================
# TASK TOOLTIPS
# ===================================================================
 

# ===================================================================
# LOGGING & DISPLAY FUNCTIONS
# ===================================================================
function Write-Log { param([string]$Message, [string]$Level = "Info"); Add-Content -Path $script:LogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message" -ErrorAction SilentlyContinue }
function Write-ToResults { param([string]$Message); if ($null -ne $script:ResultsBox) { $script:ResultsBox.AppendText("$Message`r`n"); $script:ResultsBox.SelectionStart = $script:ResultsBox.TextLength; $script:ResultsBox.ScrollToCaret(); [System.Windows.Forms.Application]::DoEvents() } }
function Write-ColoredHeader { param([string]$Message); if ($null -ne $script:ResultsBox) { $startPos = $script:ResultsBox.TextLength; $script:ResultsBox.AppendText("$Message`r`n"); $script:ResultsBox.Select($startPos, $Message.Length); $script:ResultsBox.SelectionColor = [System.Drawing.Color]::Cyan; $script:ResultsBox.SelectionLength = 0; $script:ResultsBox.SelectionStart = $script:ResultsBox.TextLength; $script:ResultsBox.ScrollToCaret(); [System.Windows.Forms.Application]::DoEvents() } }
function Write-ColoredSummary { param([string]$Message); if ($null -ne $script:ResultsBox) { $startPos = $script:ResultsBox.TextLength; $script:ResultsBox.AppendText("$Message`r`n"); $script:ResultsBox.Select($startPos, $Message.Length); $script:ResultsBox.SelectionColor = [System.Drawing.Color]::Yellow; $script:ResultsBox.SelectionLength = 0; $script:ResultsBox.SelectionStart = $script:ResultsBox.TextLength; $script:ResultsBox.ScrollToCaret(); [System.Windows.Forms.Application]::DoEvents() } }
function Write-ColoredScheduled { param([string]$Message); if ($null -ne $script:ResultsBox) { $startPos = $script:ResultsBox.TextLength; $script:ResultsBox.AppendText("$Message`r`n"); $script:ResultsBox.Select($startPos, $Message.Length); $script:ResultsBox.SelectionColor = [System.Drawing.Color]::Orange; $script:ResultsBox.SelectionLength = 0; $script:ResultsBox.SelectionStart = $script:ResultsBox.TextLength; $script:ResultsBox.ScrollToCaret(); [System.Windows.Forms.Application]::DoEvents() } }
function Write-ColoredNotInstalled { param([string]$Message); if ($null -ne $script:ResultsBox) { $startPos = $script:ResultsBox.TextLength; $script:ResultsBox.AppendText("$Message`r`n"); $script:ResultsBox.Select($startPos, $Message.Length); $script:ResultsBox.SelectionColor = [System.Drawing.Color]::Silver; $script:ResultsBox.SelectionLength = 0; $script:ResultsBox.SelectionStart = $script:ResultsBox.TextLength; $script:ResultsBox.ScrollToCaret(); [System.Windows.Forms.Application]::DoEvents() } }
function Write-ColoredSubCategory { param([string]$Message); Write-ColoredSummary -Message $Message }

function Show-CustomDialog {
    param([string]$Message, [string]$Title, [string]$Type = "YesNo")
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = $Title; $dialog.Size = New-Object System.Drawing.Size(500, 280); $dialog.StartPosition = "CenterScreen"
    $dialog.BackColor = [System.Drawing.Color]::Black; $dialog.ForeColor = [System.Drawing.Color]::White
    $dialog.FormBorderStyle = "FixedDialog"; $dialog.MaximizeBox = $false; $dialog.MinimizeBox = $false
    
    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(20, 20); $label.Size = New-Object System.Drawing.Size(450, 150)
    $label.Text = $Message; $label.ForeColor = [System.Drawing.Color]::White; $label.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $dialog.Controls.Add($label)
    
    if ($Type -eq "YesNo") {
        $yesBtn = New-Object System.Windows.Forms.Button; $yesBtn.Location = New-Object System.Drawing.Point(140, 190); $yesBtn.Size = New-Object System.Drawing.Size(100, 40); $yesBtn.Text = "Yes"
        $yesBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215); $yesBtn.ForeColor = [System.Drawing.Color]::White; $yesBtn.FlatStyle = "Flat"; $yesBtn.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold); $yesBtn.DialogResult = [System.Windows.Forms.DialogResult]::Yes
        $dialog.Controls.Add($yesBtn)
        $noBtn = New-Object System.Windows.Forms.Button; $noBtn.Location = New-Object System.Drawing.Point(260, 190); $noBtn.Size = New-Object System.Drawing.Size(100, 40); $noBtn.Text = "No"
        $noBtn.BackColor = [System.Drawing.Color]::FromArgb(220, 20, 60); $noBtn.ForeColor = [System.Drawing.Color]::White; $noBtn.FlatStyle = "Flat"; $noBtn.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold); $noBtn.DialogResult = [System.Windows.Forms.DialogResult]::No
        $dialog.Controls.Add($noBtn)
    } else {
        $okBtn = New-Object System.Windows.Forms.Button; $okBtn.Location = New-Object System.Drawing.Point(200, 190); $okBtn.Size = New-Object System.Drawing.Size(100, 40); $okBtn.Text = "OK"
        $okBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215); $okBtn.ForeColor = [System.Drawing.Color]::White; $okBtn.FlatStyle = "Flat"; $okBtn.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold); $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Controls.Add($okBtn)
    }
    return $dialog.ShowDialog()
}

# ===================================================================
# TASK SELECTION WINDOW
# ===================================================================
function Show-TaskSelectionWindow {
    param (
        [hashtable]$Tasks,
        [string]$WindowTitle = "Select Cleanup Tasks",
        [string]$ApplyButtonText = "Apply Selected Tasks",
        [System.Drawing.Color]$ApplyButtonColor = [System.Drawing.Color]::FromArgb(0, 120, 215),
        [bool]$HideProfiles = $false
    )

    $taskForm = New-Object System.Windows.Forms.Form
    $taskForm.Text = $WindowTitle; $taskForm.Size = New-Object System.Drawing.Size(500, 750); $taskForm.StartPosition = "CenterParent"
    $taskForm.FormBorderStyle = "FixedDialog"; $taskForm.MaximizeBox = $false; $taskForm.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30); $taskForm.ForeColor = [System.Drawing.Color]::White

    $script:SuppressCheckEvent = $false

    $treeView = New-Object System.Windows.Forms.TreeView
    $treeView.Location = New-Object System.Drawing.Point(15, 50); $treeView.Size = New-Object System.Drawing.Size(455, 580)
    $treeView.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20); $treeView.ForeColor = [System.Drawing.Color]::White
    $treeView.CheckBoxes = $true; $treeView.Font = New-Object System.Drawing.Font("Segoe UI", 10)

    $applyButton = New-Object System.Windows.Forms.Button
    $applyButton.Location = New-Object System.Drawing.Point(15, 685); $applyButton.Size = New-Object System.Drawing.Size(335, 35)
    $applyButton.BackColor = $ApplyButtonColor; $applyButton.ForeColor = [System.Drawing.Color]::White; $applyButton.FlatStyle = "Flat"
    $applyButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

    $updateApplyText = {
        $count = 0
        foreach ($node in $treeView.Nodes) { foreach ($child in $node.Nodes) { if ($child.Checked) { $count++ } } }
        $applyButton.Text = "$ApplyButtonText ($count)"
    }

    $treeView.Add_AfterCheck({
        param($sender, $e)
        if ($script:SuppressCheckEvent) { return }
        $script:SuppressCheckEvent = $true
        if ($e.Node.Nodes.Count -gt 0) {
            foreach ($childNode in $e.Node.Nodes) { $childNode.Checked = $e.Node.Checked }
        } else {
            $parentNode = $e.Node.Parent
            if ($null -ne $parentNode) {
                $anyChecked = $false; foreach ($child in $parentNode.Nodes) { if ($child.Checked) { $anyChecked = $true; break } }
                $parentNode.Checked = $anyChecked
            }
        }
        & $updateApplyText
        $script:SuppressCheckEvent = $false
    })

    $script:SuppressCheckEvent = $true
    foreach ($category in $Tasks.Keys) {
        $parentNode = $treeView.Nodes.Add($category); $parentNode.Checked = $true
        foreach ($subTask in $Tasks[$category].Keys) {
            $childNode = $parentNode.Nodes.Add($subTask); $childNode.Name = $subTask; $childNode.Checked = $true
            $statusText = ""
            if ($script:TaskChecks.ContainsKey($subTask)) {
                try {
                    $isApplied = & $script:TaskChecks[$subTask]
                    if ($HideProfiles) {
                        if ($isApplied) { $statusText = " [Active - Will Undo]"; $childNode.ForeColor = [System.Drawing.Color]::LightSkyBlue } else { $statusText = " [Inactive]"; $childNode.ForeColor = [System.Drawing.Color]::DarkGray }
                    } else {
                        if ($isApplied) { $statusText = " [Already Active]"; $childNode.ForeColor = [System.Drawing.Color]::LightSkyBlue } else { $statusText = " [Inactive]" }
                    }
                } catch {}
            }
            if ($script:TempTaskChecks.ContainsKey($subTask)) {
                try {
                    $isAvailable = & $script:TempTaskChecks[$subTask]
                    if (-not $isAvailable) {
                        $statusText = " [Not Installed]"
                        $childNode.ForeColor = [System.Drawing.Color]::Silver
                        $childNode.NodeFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
                        $childNode.Checked = $false
                    }
                } catch {}
            }
            $childNode.Text = "$subTask $statusText"
        }
        $anyChildChecked = $false; foreach ($c in $parentNode.Nodes) { if ($c.Checked) { $anyChildChecked = $true; break } }
        $parentNode.Checked = $anyChildChecked
        $parentNode.Expand()
    }
    $script:SuppressCheckEvent = $false
    & $updateApplyText

    $profileLabel = New-Object System.Windows.Forms.Label; $profileLabel.Text = "Profiles:"; $profileLabel.Location = New-Object System.Drawing.Point(15, 15); $profileLabel.Size = New-Object System.Drawing.Size(55, 20); $profileLabel.ForeColor = [System.Drawing.Color]::White

    $safeProfileBtn = New-Object System.Windows.Forms.Button; $safeProfileBtn.Text = "Safe"; $safeProfileBtn.Location = New-Object System.Drawing.Point(75, 10); $safeProfileBtn.Size = New-Object System.Drawing.Size(85, 30); $safeProfileBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215); $safeProfileBtn.ForeColor = [System.Drawing.Color]::White; $safeProfileBtn.FlatStyle = "Flat"
    $safeProfileBtn.Add_Click({
        $script:SuppressCheckEvent = $true
        $safeItems = @("Disable Telemetry Services", "Set Telemetry Level to 0", "Disable Windows AI & Recall", "Remove Cortana", "Disable Advertising ID", "Disable Cloud Consumer Features", "Remove OneDrive", "Remove Xbox Suite", "Remove Bing & MSN Apps", "Remove Media & Zune Apps", "Remove Social & Streaming Apps", "Remove Productivity Apps", "Remove New Outlook", "Remove System Bloatware", "Remove Games (king.com etc)", "Clean Taskbar (Hide Icons)", "Disable Lock Screen Ads & Tips", "Disable Xbox Services", "Disable Misc System Services", "Disable AI Fabric Service (26H2)", "Disable Web & Store Search (26H2)")
        foreach ($node in $treeView.Nodes) { 
            $anyChecked = $false
            foreach ($child in $node.Nodes) { if ($safeItems -contains $child.Name) { $child.Checked = $true; $anyChecked = $true } else { $child.Checked = $false } }
            $node.Checked = $anyChecked
        }
        $script:SuppressCheckEvent = $false; & $updateApplyText
    })

    $ltscProfileBtn = New-Object System.Windows.Forms.Button; $ltscProfileBtn.Text = "LTSC"; $ltscProfileBtn.Location = New-Object System.Drawing.Point(170, 10); $ltscProfileBtn.Size = New-Object System.Drawing.Size(85, 30); $ltscProfileBtn.BackColor = [System.Drawing.Color]::FromArgb(108, 117, 125); $ltscProfileBtn.ForeColor = [System.Drawing.Color]::White; $ltscProfileBtn.FlatStyle = "Flat"
    $ltscProfileBtn.Add_Click({
        $script:SuppressCheckEvent = $true
        $ltscItems = @("Disable Telemetry Services", "Set Telemetry Level to 0", "Disable Feedback & Notifications", "Limit Diagnostic Log Collection", "Disable Windows AI & Recall", "Remove Recall Packages", "Disable Click to Do & AI Agents", "Disable Windows Copilot (System)", "Disable Copilot in Edge", "Disable AI in Notepad", "Remove Cortana", "Disable Activity History", "Disable Advertising ID", "Disable Cloud Consumer Features", "Disable Location Tracking", "Disable Error Reporting", "Disable Web Search in Start Menu", "Disable Wi-Fi Sense", "Disable Content Delivery (Suggested Apps)", "Disable Windows Tips & Soft Landing", "Disable Input Personalization (Ink/Text)", "Remove OneDrive", "Remove Xbox Suite", "Remove Bing & MSN Apps", "Remove Media & Zune Apps", "Remove Social & Streaming Apps", "Remove Productivity Apps", "Remove New Outlook", "Remove System Bloatware", "Remove Games (king.com etc)", "Clean Taskbar (Hide Icons)", "Enable Classic Context Menu (Win11)", "Disable Lock Screen Ads & Tips", "Show Hidden Files & Extensions", "Disable Start Menu Tracking", "Disable Xbox Services", "Disable Hyper-V Services", "Disable Misc System Services", "Enforce Group Policy (Refresh)", "Disable AI Fabric Service (26H2)", "Disable Semantic Search Indexing (26H2)", "Disable Mu AI Agent (26H2)", "Disable Web & Store Search (26H2)", "Disable Copilot in File Explorer (26H2)", "Disable Ask Copilot Search (26H2)")
        foreach ($node in $treeView.Nodes) { 
            $anyChecked = $false
            foreach ($child in $node.Nodes) { if ($ltscItems -contains $child.Name) { $child.Checked = $true; $anyChecked = $true } else { $child.Checked = $false } }
            $node.Checked = $anyChecked
        }
        $script:SuppressCheckEvent = $false; & $updateApplyText
    })

    $aggressiveProfileBtn = New-Object System.Windows.Forms.Button; $aggressiveProfileBtn.Text = "Aggressive (All)"; $aggressiveProfileBtn.Location = New-Object System.Drawing.Point(265, 10); $aggressiveProfileBtn.Size = New-Object System.Drawing.Size(120, 30); $aggressiveProfileBtn.BackColor = [System.Drawing.Color]::FromArgb(220, 20, 60); $aggressiveProfileBtn.ForeColor = [System.Drawing.Color]::White; $aggressiveProfileBtn.FlatStyle = "Flat"
    $aggressiveProfileBtn.Add_Click({
        $script:SuppressCheckEvent = $true
        foreach ($node in $treeView.Nodes) { $node.Checked = $true; foreach ($child in $node.Nodes) { $child.Checked = $true } }
        $script:SuppressCheckEvent = $false; & $updateApplyText
    })

    $selectAllBtn = New-Object System.Windows.Forms.Button; $selectAllBtn.Text = "Select All"; $selectAllBtn.Location = New-Object System.Drawing.Point(15, 640); $selectAllBtn.Size = New-Object System.Drawing.Size(105, 35); $selectAllBtn.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60); $selectAllBtn.ForeColor = [System.Drawing.Color]::White; $selectAllBtn.FlatStyle = "Flat"
    $selectAllBtn.Add_Click({ $script:SuppressCheckEvent = $true; foreach ($node in $treeView.Nodes) { $node.Checked = $true; foreach ($child in $node.Nodes) { $child.Checked = $true } }; $script:SuppressCheckEvent = $false; & $updateApplyText })

    $uncheckAllBtn = New-Object System.Windows.Forms.Button; $uncheckAllBtn.Text = "Uncheck All"; $uncheckAllBtn.Location = New-Object System.Drawing.Point(130, 640); $uncheckAllBtn.Size = New-Object System.Drawing.Size(105, 35); $uncheckAllBtn.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60); $uncheckAllBtn.ForeColor = [System.Drawing.Color]::White; $uncheckAllBtn.FlatStyle = "Flat"
    $uncheckAllBtn.Add_Click({ $script:SuppressCheckEvent = $true; foreach ($node in $treeView.Nodes) { $node.Checked = $false; foreach ($child in $node.Nodes) { $child.Checked = $false } }; $script:SuppressCheckEvent = $false; & $updateApplyText })

    $expandAllBtn = New-Object System.Windows.Forms.Button; $expandAllBtn.Text = "Expand All"; $expandAllBtn.Location = New-Object System.Drawing.Point(245, 640); $expandAllBtn.Size = New-Object System.Drawing.Size(105, 35); $expandAllBtn.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60); $expandAllBtn.ForeColor = [System.Drawing.Color]::White; $expandAllBtn.FlatStyle = "Flat"
    $expandAllBtn.Add_Click({ $treeView.ExpandAll() })

    $collapseAllBtn = New-Object System.Windows.Forms.Button; $collapseAllBtn.Text = "Collapse All"; $collapseAllBtn.Location = New-Object System.Drawing.Point(360, 640); $collapseAllBtn.Size = New-Object System.Drawing.Size(110, 35); $collapseAllBtn.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60); $collapseAllBtn.ForeColor = [System.Drawing.Color]::White; $collapseAllBtn.FlatStyle = "Flat"
    $collapseAllBtn.Add_Click({ $treeView.CollapseAll() })

    $applyButton.Add_Click({
        $selectedTasks = [System.Collections.ArrayList]::new()
        foreach ($parentNode in $treeView.Nodes) { foreach ($childNode in $parentNode.Nodes) { if ($childNode.Checked) { $selectedTasks.Add($childNode.Name) | Out-Null } } }
        $taskForm.Tag = [string[]]$selectedTasks.ToArray(); $taskForm.DialogResult = [System.Windows.Forms.DialogResult]::OK; $taskForm.Close()
    })

    $cancelButton = New-Object System.Windows.Forms.Button; $cancelButton.Text = "Cancel"; $cancelButton.Location = New-Object System.Drawing.Point(360, 685); $cancelButton.Size = New-Object System.Drawing.Size(110, 35); $cancelButton.BackColor = [System.Drawing.Color]::FromArgb(220, 20, 60); $cancelButton.ForeColor = [System.Drawing.Color]::White; $cancelButton.FlatStyle = "Flat"; $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $taskForm.Controls.Add($treeView); $taskForm.Controls.Add($selectAllBtn); $taskForm.Controls.Add($uncheckAllBtn); $taskForm.Controls.Add($expandAllBtn); $taskForm.Controls.Add($collapseAllBtn); $taskForm.Controls.Add($applyButton); $taskForm.Controls.Add($cancelButton)
    if (-not $HideProfiles) { $taskForm.Controls.Add($profileLabel); $taskForm.Controls.Add($safeProfileBtn); $taskForm.Controls.Add($ltscProfileBtn); $taskForm.Controls.Add($aggressiveProfileBtn) }

    if ($taskForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $taskForm.Tag } else { return $null }
}

# ===================================================================
# CORE ACTION FUNCTIONS
# ===================================================================
function Set-RegistryKeySafe {
    param($Path, $Name, $Value, $Type = "DWord", [Alias('Desc')]$Description)   
    try {
        $pathExists = Test-Path $Path       
        if (-not $pathExists) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null; Write-ToResults "  [+] Created registry path: $Path" }       
        $oldValue = $null
        if ($pathExists) { try { $oldValue = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name } catch { } }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop      
        $displayMsg = if ($null -ne $oldValue) { "(was: $oldValue)" } else { "" }
        Write-ToResults "  [OK] $Description : $Name = $Value $displayMsg"       
        $script:Stats.RegistryKeysSet++; [System.Windows.Forms.Application]::DoEvents(); return $true
    } catch {
        Write-ToResults "  [X] Failed: $Description - $($_.Exception.Message)"; [System.Windows.Forms.Application]::DoEvents(); return $false
    }
}

function Disable-ServiceSafe {
    param($ServiceName, $Description)
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue        
        if (-not $service) { return $false }       
        $originalStatus = $service.Status; $originalStartType = $service.StartType       
        if ($originalStartType -eq "Disabled" -and $originalStatus -eq "Stopped") { $script:Stats.ServicesSkipped++; return $true }       
        if ($originalStatus -ne "Stopped") { Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500 }
        Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction Stop
        Write-ToResults "  [OK] $Description : $originalStatus/$originalStartType -> Stopped/Disabled"       
        $script:Stats.ServicesDisabled++; [System.Windows.Forms.Application]::DoEvents(); return $true
    } catch {
        Write-ToResults "  [X] Failed to disable $Description : $($_.Exception.Message)"; [System.Windows.Forms.Application]::DoEvents(); return $false
    }
}

function Remove-AppXSafe {
    param($Pattern, $Description, $PrefetchedPackages = $null)   
    try {
        if ($null -eq $PrefetchedPackages) { $packages = Get-AppxPackage -Name $Pattern -AllUsers -ErrorAction SilentlyContinue } else { $packages = $PrefetchedPackages }
        $packageCount = ($packages | Measure-Object).Count       
        if ($packageCount -eq 0) { $script:Stats.AppsNotFound++; return 0 }       
        Write-ToResults "  [*] $Description : Found $packageCount package(s)"        
        $removed = 0; $failed = 0       
        foreach ($package in $packages) {
            $packageName = $package.Name; $packageVersion = $package.Version; $packageFullName = $package.PackageFullName           
            try {
                Remove-AppxPackage -Package $packageFullName -AllUsers -ErrorAction Stop
                Write-ToResults "    [OK] Removed: $packageName v$packageVersion (all users)"; $removed++
            } catch {
                try {
                    Remove-AppxPackage -Package $packageFullName -ErrorAction Stop
                    Write-ToResults "    [OK] Removed: $packageName v$packageVersion (current user)"; $removed++
                } catch {
                    Write-ToResults "  [X] FAILED TO REMOVE: $packageName v$packageVersion"; $failed++; $script:Stats.AppsFailed++; $script:FailedApps.Add("$packageName (v$packageVersion)"); [System.Windows.Forms.Application]::DoEvents()
                }
            }
        }       
        try {
            $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $Pattern }
            if (($provisioned | Measure-Object).Count -gt 0) { foreach ($pkg in $provisioned) { try { Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null } catch {} } }
        } catch { }       
        if ($removed -gt 0 -or $failed -gt 0) { $script:Stats.AppsRemoved += $removed; [System.Windows.Forms.Application]::DoEvents() }       
        return $removed
    } catch {
        Write-ToResults "  [X] Error removing $Description : $($_.Exception.Message)"; return 0
    }
}

# ===================================================================
# GRANULAR SUB-TASK DEFINITIONS
# ===================================================================
 $script:TaskDefinitions = [ordered]@{
    "1. Privacy & Telemetry" = [ordered]@{
        "Disable Telemetry Services" = { Disable-ServiceSafe -ServiceName "DiagTrack" -Description "Connected User Experiences and Telemetry"; Disable-ServiceSafe -ServiceName "dmwappushservice" -Description "WAP Push" }
        "Set Telemetry Level to 0" = { Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Description "Telemetry Level" }
        "Disable Feedback & Notifications" = { Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Value 1 -Description "Feedback Notifications" }
        "Limit Diagnostic Log Collection" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Set-RegistryKeySafe -Path $p -Name "LimitDiagnosticLogCollection" -Value 1 -Description "Limit Diag Log"; Set-RegistryKeySafe -Path $p -Name "DisableOneSettingsDownloads" -Value 1 -Description "OneSettings"; Set-RegistryKeySafe -Path $p -Name "DisableTelemetryOptInChangeNotification" -Value 1 -Description "Opt-in Notifications" }
        "Disable Windows AI & Recall" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Set-RegistryKeySafe -Path $p -Name "DisableAIDataAnalysis" -Value 1 -Desc "AI Data Analysis"; Set-RegistryKeySafe -Path $p -Name "AllowRecallEnablement" -Value 0 -Desc "Recall Enablement"; Set-RegistryKeySafe -Path $p -Name "AllowWindowsAI" -Value 0 -Desc "Windows AI"; Set-RegistryKeySafe -Path $p -Name "TurnOffSavingSnapshots" -Value 1 -Desc "AI Snapshots"; Set-RegistryKeySafe -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1 -Desc "AI Data Analysis (User)" }
        "Remove Recall Packages" = { Remove-AppXSafe -Pattern "*Windows.Recall*" -Description "Recall App"; Remove-AppXSafe -Pattern "*Microsoft.Windows.Ai.Recall*" -Description "AI Recall"; Disable-ServiceSafe -ServiceName "RecallService" -Description "Recall Service" }
        "Disable Click to Do & AI Agents" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Set-RegistryKeySafe -Path $p -Name "DisableClickToDo" -Value 1 -Desc "Click to Do"; Set-RegistryKeySafe -Path $p -Name "DisableSettingsAgent" -Value 1 -Desc "Settings AI Agent"; Set-RegistryKeySafe -Path $p -Name "RemoveMicrosoftCopilotApp" -Value 1 -Desc "Remove Copilot App" }
        "Disable Windows Copilot (System)" = { Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Description "Windows Copilot"; Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CopilotKey" -Name "SetCopilotHardwareKey" -Value " " -Type String -Description "Copilot Hardware Key" }
        "Disable Copilot in Edge" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Set-RegistryKeySafe -Path $p -Name "CopilotPageContext" -Value 0 -Desc "Copilot Page Context"; Set-RegistryKeySafe -Path $p -Name "HubsSidebarEnabled" -Value 0 -Desc "Edge Sidebar"; Set-RegistryKeySafe -Path $p -Name "CopilotCDPPageContext" -Value 0 -Desc "Copilot CDP Context"; Set-RegistryKeySafe -Path $p -Name "EdgeEntraCopilotPageContext" -Value 0 -Desc "Entra Copilot"; Set-RegistryKeySafe -Path $p -Name "EdgeHistoryAISearchEnabled" -Value 0 -Desc "AI History Search"; Set-RegistryKeySafe -Path $p -Name "ComposeInlineEnabled" -Value 0 -Desc "Compose Inline"; Set-RegistryKeySafe -Path $p -Name "GenAILocalFoundationalModelSettings" -Value 1 -Desc "AI Local Model"; Set-RegistryKeySafe -Path $p -Name "BuiltInAIAPIsEnabled" -Value 0 -Desc "Built-in AI APIs"; Set-RegistryKeySafe -Path $p -Name "AIGenThemesEnabled" -Value 0 -Desc "AI Themes"; Set-RegistryKeySafe -Path $p -Name "AllowBrowsingWithCopilot" -Value 0 -Desc "Browse with Copilot"; Set-RegistryKeySafe -Path $p -Name "CopilotNewTabPageEnabled" -Value 0 -Desc "Copilot New Tab"; Set-RegistryKeySafe -Path $p -Name "CopilotAddressBarSuggestionsEnabled" -Value 0 -Desc "Copilot Address Bar" }
        "Disable AI in Notepad" = { Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\WindowsNotepad" -Name "DisableAIFeatures" -Value 1 -Description "Notepad AI Features" }
        "Remove Cortana" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Set-RegistryKeySafe -Path $p -Name "AllowCortana" -Value 0 -Description "Cortana"; Set-RegistryKeySafe -Path $p -Name "AllowCortanaAboveLock" -Value 0 -Description "Cortana Above Lock"; Remove-AppXSafe -Pattern "*Microsoft.549981C3F5F10*" -Description "Cortana App" }
        "Disable Activity History" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Set-RegistryKeySafe -Path $p -Name "EnableActivityFeed" -Value 0 -Desc "Activity Feed"; Set-RegistryKeySafe -Path $p -Name "PublishUserActivities" -Value 0 -Desc "Publish User Activities"; Set-RegistryKeySafe -Path $p -Name "UploadUserActivities" -Value 0 -Desc "Upload User Activities" }
        "Disable Advertising ID" = { Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -Value 1 -Desc "Ad ID Policy"; Set-RegistryKeySafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -Desc "Ad ID User" }
        "Disable Cloud Consumer Features" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Set-RegistryKeySafe -Path $p -Name "DisableWindowsConsumerFeatures" -Value 1 -Desc "Consumer Features"; Set-RegistryKeySafe -Path $p -Name "DisableCloudOptimizedContent" -Value 1 -Desc "Cloud Optimised Content"; Set-RegistryKeySafe -Path $p -Name "DisableSoftLanding" -Value 1 -Desc "Soft Landing" }
        "Disable Location Tracking" = { Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -Value 1 -Description "Location Services" }
        "Disable Error Reporting" = { Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 1 -Description "Error Reporting"; Disable-ServiceSafe -ServiceName "WerSvc" -Description "Error Reporting Service" }
        "Disable Web Search in Start Menu" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Set-RegistryKeySafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0 -Desc "Bing Search"; Set-RegistryKeySafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Value 0 -Desc "Cortana Consent"; Set-RegistryKeySafe -Path $p -Name "DisableWebSearch" -Value 1 -Desc "Web Search"; Set-RegistryKeySafe -Path $p -Name "ConnectedSearchUseWeb" -Value 0 -Desc "Connected Search" }
        "Disable Wi-Fi Sense" = { Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" -Name "AutoConnectAllowedOEM" -Value 0 -Description "Wi-Fi Sense" }
        "Disable Content Delivery (Suggested Apps)" = { $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Set-RegistryKeySafe -Path $p -Name "ContentDeliveryAllowed" -Value 0 -Desc "Content Delivery"; Set-RegistryKeySafe -Path $p -Name "OemPreInstalledAppsEnabled" -Value 0 -Desc "OEM Pre-installed"; Set-RegistryKeySafe -Path $p -Name "PreInstalledAppsEnabled" -Value 0 -Desc "Pre-installed"; Set-RegistryKeySafe -Path $p -Name "PreInstalledAppsEverEnabled" -Value 0 -Desc "Pre-installed (ever)"; Set-RegistryKeySafe -Path $p -Name "SilentInstalledAppsEnabled" -Value 0 -Desc "Silent App Installs"; Set-RegistryKeySafe -Path $p -Name "SubscribedContent-338388Enabled" -Value 0 -Desc "Suggested Apps in Start"; Set-RegistryKeySafe -Path $p -Name "SubscribedContent-353698Enabled" -Value 0 -Desc "Timeline Suggestions" }
        "Disable Windows Tips & Soft Landing" = { $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Set-RegistryKeySafe -Path $p -Name "SubscribedContent-338389Enabled" -Value 0 -Desc "Windows Tips"; Set-RegistryKeySafe -Path $p -Name "SoftLandingEnabled" -Value 0 -Desc "Soft Landing" }
        "Disable Input Personalization (Ink/Text)" = { $p="HKCU:\Software\Microsoft\InputPersonalization"; Set-RegistryKeySafe -Path $p -Name "RestrictImplicitInkCollection" -Value 1 -Desc "Ink Collection"; Set-RegistryKeySafe -Path $p -Name "RestrictImplicitTextCollection" -Value 1 -Desc "Text Collection"; Set-RegistryKeySafe -Path "HKCU:\Software\Microsoft\Personalization\Settings" -Name "AcceptedPrivacyPolicy" -Value 0 -Desc "Personalisation Privacy Policy" }
        "Disable AI Fabric Service (26H2)" = { Disable-ServiceSafe -ServiceName "WSAIFabricSvc" -Description "Windows AI Fabric Service (NPU)"; Disable-ServiceSafe -ServiceName "WsaService" -Description "Windows Subsystem AI" }
        "Disable Semantic Search Indexing (26H2)" = { Disable-ServiceSafe -ServiceName "AISearchService" -Description "AI Semantic Search"; Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableSemanticSearch" -Value 1 -Desc "Semantic Search Indexing"; Set-RegistryKeySafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsDeviceSearchEnabled" -Value 0 -Desc "Device AI Search" }
        "Disable Mu AI Agent (26H2)" = { Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableMuAgent" -Value 1 -Desc "Mu Settings Agent"; Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableSettingsAgent" -Value 1 -Desc "Settings AI Agent"; Remove-AppXSafe -Pattern "*Microsoft.Windows.Ai.Copilot*" -Description "Copilot AI App" }
        "Disable Web & Store Search (26H2)" = { $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Set-RegistryKeySafe -Path $p -Name "BingSearchEnabled" -Value 0 -Desc "Bing Search"; Set-RegistryKeySafe -Path $p -Name "CortanaConsent" -Value 0 -Desc "Cortana Consent"; Set-RegistryKeySafe -Path $p -Name "EnableWebSuggestions" -Value 0 -Desc "Web Suggestions"; Set-RegistryKeySafe -Path $p -Name "EnableMSACloudSearch" -Value 0 -Desc "MSA Cloud Search"; $p2="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Set-RegistryKeySafe -Path $p2 -Name "DisableWebSearch" -Value 1 -Desc "Web Search"; Set-RegistryKeySafe -Path $p2 -Name "ConnectedSearchUseWeb" -Value 0 -Desc "Connected Search"; Set-RegistryKeySafe -Path $p2 -Name "AllowSearchToUseLocation" -Value 0 -Desc "Search Location"; Set-RegistryKeySafe -Path $p2 -Name "AllowCloudSearch" -Value 0 -Desc "Cloud Search"; Set-RegistryKeySafe -Path $p2 -Name "AllowCortana" -Value 0 -Desc "Cortana Search" }
        "Disable Copilot in File Explorer (26H2)" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Set-RegistryKeySafe -Path $p -Name "DisableCopilotInExplorer" -Value 1 -Desc "Copilot in Explorer"; $p2="HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Set-RegistryKeySafe -Path $p2 -Name "HubsSidebarEnabled" -Value 0 -Desc "Edge Sidebar"; Set-RegistryKeySafe -Path $p2 -Name "CopilotPageContext" -Value 0 -Desc "Copilot Page Context" }
        "Disable Ask Copilot Search (26H2)" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Set-RegistryKeySafe -Path $p -Name "DisableCopilotSearch" -Value 1 -Desc "Ask Copilot Search"; $p2="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Set-RegistryKeySafe -Path $p2 -Name "DisableWebSearch" -Value 1 -Desc "Web Search"; Set-RegistryKeySafe -Path $p2 -Name "ConnectedSearchUseWeb" -Value 0 -Desc "Connected Search"; Set-RegistryKeySafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0 -Desc "Bing Search" }
    }
    "2. Bloatware Removal" = [ordered]@{
        "Remove OneDrive" = { Write-ColoredHeader "=== ONEDRIVE REMOVAL ==="; Get-Process -Name "OneDrive" -EA SilentlyContinue | Stop-Process -Force; Start-Sleep -Seconds 2; $setups = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"); foreach ($setup in $setups) { if (Test-Path $setup) { try { Start-Process -FilePath $setup -ArgumentList "/uninstall" -NoNewWindow -Wait -EA Stop; Write-ToResults "  [OK] OneDrive uninstall initiated" } catch { Write-ToResults "  [i] OneDrive uninstall failed (may already be removed)" } } }; Start-Sleep -Seconds 2; $folders = @("$env:USERPROFILE\OneDrive", "$env:LOCALAPPDATA\Microsoft\OneDrive", "$env:PROGRAMDATA\Microsoft OneDrive"); foreach ($folder in $folders) { if (Test-Path $folder) { Remove-Item -Path $folder -Recurse -Force -EA SilentlyContinue; Write-ToResults "  [OK] Removed folder: $folder" } }; Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Value 1 -Description "OneDrive Sync"; Remove-AppXSafe -Pattern "*OneDrive*" -Description "OneDrive" }
        "Remove Xbox Suite" = { $all = Get-AppxPackage -AllUsers -EA SilentlyContinue; $apps = @("*Microsoft.Xbox*", "*Microsoft.GamingApp*", "*Microsoft.XboxGameOverlay*", "*Microsoft.XboxGamingOverlay*"); foreach ($app in $apps) { $m = $all | Where-Object { $_.Name -like $app }; Remove-AppXSafe -Pattern $app -Description ($app -replace '\*', '') -PrefetchedPackages $m } }
        "Remove Bing & MSN Apps" = { $all = Get-AppxPackage -AllUsers -EA SilentlyContinue; $apps = @("*Microsoft.BingWeather*", "*Microsoft.BingNews*", "*Microsoft.BingSports*", "*Microsoft.BingFinance*", "*Microsoft.BingSearch*"); foreach ($app in $apps) { $m = $all | Where-Object { $_.Name -like $app }; Remove-AppXSafe -Pattern $app -Description ($app -replace '\*', '') -PrefetchedPackages $m } }
        "Remove Media & Zune Apps" = { $all = Get-AppxPackage -AllUsers -EA SilentlyContinue; $apps = @("*Microsoft.ZuneMusic*", "*Microsoft.ZuneVideo*"); foreach ($app in $apps) { $m = $all | Where-Object { $_.Name -like $app }; Remove-AppXSafe -Pattern $app -Description ($app -replace '\*', '') -PrefetchedPackages $m } }
        "Remove Social & Streaming Apps" = { $all = Get-AppxPackage -AllUsers -EA SilentlyContinue; $apps = @("*Microsoft.SkypeApp*", "*Facebook*", "*Twitter*", "*Disney*", "*Netflix*", "*Clipchamp.Clipchamp*"); foreach ($app in $apps) { $m = $all | Where-Object { $_.Name -like $app }; Remove-AppXSafe -Pattern $app -Description ($app -replace '\*', '') -PrefetchedPackages $m } }
        "Remove Productivity Apps" = { $all = Get-AppxPackage -AllUsers -EA SilentlyContinue; $apps = @("*Microsoft.MicrosoftOfficeHub*", "*Microsoft.MicrosoftSolitaireCollection*", "*Microsoft.Todos*", "*Microsoft.PowerAutomateDesktop*", "*MicrosoftTeams*", "*Microsoft.WindowsCommunicationsApps*", "*microsoft.windowscommunicationsapps*", "*Microsoft.YourPhone*", "*Microsoft.Phone*"); foreach ($app in $apps) { $m = $all | Where-Object { $_.Name -like $app }; Remove-AppXSafe -Pattern $app -Description ($app -replace '\*', '') -PrefetchedPackages $m } }
        "Remove New Outlook" = { $all = Get-AppxPackage -AllUsers -EA SilentlyContinue; $apps = @("*Microsoft.OutlookForWindows*"); foreach ($app in $apps) { $m = $all | Where-Object { $_.Name -like $app }; Remove-AppXSafe -Pattern $app -Description "New Outlook" -PrefetchedPackages $m } }
        "Remove System Bloatware" = { $all = Get-AppxPackage -AllUsers -EA SilentlyContinue; $apps = @("*Microsoft.GetHelp*", "*Microsoft.Getstarted*", "*Microsoft.People*", "*Microsoft.WindowsFeedbackHub*", "*Microsoft.3DBuilder*", "*Microsoft.Messaging*", "*Microsoft.Print3D*", "*Microsoft.WindowsMaps*", "*Microsoft.Wallet*", "*Microsoft.MixedReality.Portal*", "*Microsoft.3DViewer*", "*Microsoft.MSPaint*", "*Microsoft.ScreenSketch*", "*Microsoft.WindowsAlarms*", "*Microsoft.WindowsSoundRecorder*"); foreach ($app in $apps) { $m = $all | Where-Object { $_.Name -like $app }; Remove-AppXSafe -Pattern $app -Description ($app -replace '\*', '') -PrefetchedPackages $m } }
        "Remove Games (king.com etc)" = { $all = Get-AppxPackage -AllUsers -EA SilentlyContinue; $apps = @("*king.com*"); foreach ($app in $apps) { $m = $all | Where-Object { $_.Name -like $app }; Remove-AppXSafe -Pattern $app -Description ($app -replace '\*', '') -PrefetchedPackages $m } }
    }
    "3. UI & System Tweaks" = [ordered]@{
        "Clean Taskbar (Hide Icons)" = { $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Set-RegistryKeySafe -Path $p -Name "ShowTaskViewButton" -Value 0 -Desc "Task View"; Set-RegistryKeySafe -Path $p -Name "TaskbarDa" -Value 0 -Desc "Widgets"; Set-RegistryKeySafe -Path $p -Name "ShowCopilotButton" -Value 0 -Desc "Copilot Button"; Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat" -Name "ChatIcon" -Value 3 -Desc "Teams Chat Icon"; Set-RegistryKeySafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "HideSCAMeetNow" -Value 1 -Desc "Meet Now" }
        "Enable Classic Context Menu (Win11)" = { Set-RegistryKeySafe -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "(default)" -Value "" -Type String -Description "Classic Context Menu" }
        "Disable Lock Screen Ads & Tips" = { $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Set-RegistryKeySafe -Path $p -Name "RotatingLockScreenEnabled" -Value 0 -Desc "Lock Screen Ads"; Set-RegistryKeySafe -Path $p -Name "SystemPaneSuggestionsEnabled" -Value 0 -Desc "Suggestions"; Set-RegistryKeySafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -Desc "Tailored Experiences"; Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0 -Desc "News and Interests" }
        "Show Hidden Files & Extensions" = { $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Set-RegistryKeySafe -Path $p -Name "HideFileExt" -Value 0 -Desc "Show File Extensions"; Set-RegistryKeySafe -Path $p -Name "Hidden" -Value 1 -Desc "Show Hidden Files" }
        "Disable Start Menu Tracking" = { $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Set-RegistryKeySafe -Path $p -Name "Start_TrackProgs" -Value 0 -Desc "Track App Launches"; Set-RegistryKeySafe -Path $p -Name "Start_TrackDocs" -Value 0 -Desc "Track Recent Docs"; $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"; Set-RegistryKeySafe -Path $p -Name "ShowFrequent" -Value 0 -Desc "Frequent Folders"; Set-RegistryKeySafe -Path $p -Name "ShowRecent" -Value 0 -Desc "Recent Files"; $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Set-RegistryKeySafe -Path $p -Name "HideRecentlyAddedApps" -Value 1 -Desc "Recently Added Apps"; Set-RegistryKeySafe -Path $p -Name "NoPinningStoreToTaskbar" -Value 1 -Desc "Store Icon on Taskbar" }
        "Disable Xbox Services" = { Disable-ServiceSafe -ServiceName "XblAuthManager" -Description "Xbox Auth"; Disable-ServiceSafe -ServiceName "XblGameSave" -Description "Xbox Save"; Disable-ServiceSafe -ServiceName "XboxGipSvc" -Description "Xbox Accessory"; Disable-ServiceSafe -ServiceName "XboxNetApiSvc" -Description "Xbox Network" }
        "Disable Hyper-V Services" = { Disable-ServiceSafe -ServiceName "HvHost" -Description "Hyper-V"; Disable-ServiceSafe -ServiceName "vmickvpexchange" -Description "Hyper-V Data" }
        "Disable Misc System Services" = { Disable-ServiceSafe -ServiceName "Fax" -Description "Fax"; Disable-ServiceSafe -ServiceName "RetailDemo" -Description "Retail Demo"; Disable-ServiceSafe -ServiceName "MapsBroker" -Description "Maps Broker"; Disable-ServiceSafe -ServiceName "lfsvc" -Description "Geolocation"; Disable-ServiceSafe -ServiceName "SharedAccess" -Description "ICS"; Disable-ServiceSafe -ServiceName "icssvc" -Description "Mobile Hotspot"; Disable-ServiceSafe -ServiceName "wisvc" -Description "Insider Service"; Disable-ServiceSafe -ServiceName "diagnosticshub.standardcollector.service" -Description "Diagnostics Hub"; Disable-ServiceSafe -ServiceName "DusmSvc" -Description "Data Usage"; Disable-ServiceSafe -ServiceName "PcaSvc" -Description "Program Compat Asst" }
        "Prompt: Disable Biometric Service" = { $biometric = Show-CustomDialog -Message "Disable Biometric service (fingerprint reader, face recognition)?" -Title "Biometric Service" -Type "YesNo"; if ($biometric -eq [System.Windows.Forms.DialogResult]::Yes) { Disable-ServiceSafe -ServiceName "WbioSrvc" -Description "Biometric" } else { Write-ToResults "  [i] Biometric service preserved" } }
        "Prompt: Disable Remote Desktop" = { $rdp = Show-CustomDialog -Message "Disable Remote Desktop services?`n`nThis will prevent RDP connections to this machine." -Title "Remote Desktop" -Type "YesNo"; if ($rdp -eq [System.Windows.Forms.DialogResult]::Yes) { Disable-ServiceSafe -ServiceName "TermService" -Description "Remote Desktop"; Disable-ServiceSafe -ServiceName "UmRdpService" -Description "RDP User Mode" } else { Write-ToResults "  [i] Remote Desktop preserved" } }
        "Prompt: Disable Touch Keyboard" = { $touchKbd = Show-CustomDialog -Message "Disable Touch Keyboard & Handwriting service?`n`nOnly disable if you use a physical keyboard exclusively." -Title "Touch Keyboard" -Type "YesNo"; if ($touchKbd -eq [System.Windows.Forms.DialogResult]::Yes) { Disable-ServiceSafe -ServiceName "TabletInputService" -Description "Touch Keyboard & Handwriting" } else { Write-ToResults "  [i] Touch Keyboard preserved" } }
        "Enforce Group Policy (Refresh)" = { Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows" -Name "CEIPEnable" -Value 0 -Description "CEIP"; try { Start-Process "gpupdate.exe" -ArgumentList "/force" -Wait -WindowStyle Hidden -EA SilentlyContinue; Write-ToResults "  [OK] GPUpdate complete" } catch { Write-ToResults "  [i] GPUpdate skipped" } }
    }
}

# ===================================================================
# TASK VALIDATION CHECKS
# ===================================================================
 $script:TaskChecks = @{
    "Disable Telemetry Services" = { (Get-Service -Name DiagTrack -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Restore Telemetry Services" = { (Get-Service -Name DiagTrack -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Set Telemetry Level to 0" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -EA SilentlyContinue).AllowTelemetry -eq 0 }
    "Restore Telemetry Level to Default" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -EA SilentlyContinue).AllowTelemetry -eq 0 }
    "Disable Feedback & Notifications" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -EA SilentlyContinue).DoNotShowFeedbackNotifications -eq 1 }
    "Restore Feedback & Notifications" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -EA SilentlyContinue).DoNotShowFeedbackNotifications -eq 1 }
    "Limit Diagnostic Log Collection" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "LimitDiagnosticLogCollection" -EA SilentlyContinue).LimitDiagnosticLogCollection -eq 1 }
    "Restore Diagnostic Log Collection" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "LimitDiagnosticLogCollection" -EA SilentlyContinue).LimitDiagnosticLogCollection -eq 1 }
    "Disable Windows AI & Recall" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -EA SilentlyContinue).DisableAIDataAnalysis -eq 1 }
    "Restore Windows AI & Recall Policies" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -EA SilentlyContinue).DisableAIDataAnalysis -eq 1 }
    "Remove Recall Packages" = { $null -eq (Get-AppxPackage -Name "*Windows.Recall*" -EA SilentlyContinue) }
    "Restore Recall Packages (Requires Store Reinstall)" = { $null -eq (Get-AppxPackage -Name "*Windows.Recall*" -EA SilentlyContinue) }
    "Disable Click to Do & AI Agents" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableClickToDo" -EA SilentlyContinue).DisableClickToDo -eq 1 }
    "Restore Click to Do & AI Agents" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableClickToDo" -EA SilentlyContinue).DisableClickToDo -eq 1 }
    "Disable Windows Copilot (System)" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -EA SilentlyContinue).TurnOffWindowsCopilot -eq 1 }
    "Restore Windows Copilot (System)" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -EA SilentlyContinue).TurnOffWindowsCopilot -eq 1 }
    "Disable Copilot in Edge" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "CopilotPageContext" -EA SilentlyContinue).CopilotPageContext -eq 0 }
    "Restore Copilot in Edge" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "CopilotPageContext" -EA SilentlyContinue).CopilotPageContext -eq 0 }
    "Disable AI in Notepad" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\WindowsNotepad" -Name "DisableAIFeatures" -EA SilentlyContinue).DisableAIFeatures -eq 1 }
    "Restore AI in Notepad" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\WindowsNotepad" -Name "DisableAIFeatures" -EA SilentlyContinue).DisableAIFeatures -eq 1 }
    "Remove Cortana" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -EA SilentlyContinue).AllowCortana -eq 0 }
    "Restore Cortana Policies" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -EA SilentlyContinue).AllowCortana -eq 0 }
    "Disable Activity History" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -EA SilentlyContinue).EnableActivityFeed -eq 0 }
    "Restore Activity History" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -EA SilentlyContinue).EnableActivityFeed -eq 0 }
    "Disable Advertising ID" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -EA SilentlyContinue).DisabledByGroupPolicy -eq 1 }
    "Restore Advertising ID" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -EA SilentlyContinue).DisabledByGroupPolicy -eq 1 }
    "Disable Cloud Consumer Features" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -EA SilentlyContinue).DisableWindowsConsumerFeatures -eq 1 }
    "Restore Cloud Consumer Features" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -EA SilentlyContinue).DisableWindowsConsumerFeatures -eq 1 }
    "Disable Location Tracking" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -EA SilentlyContinue).DisableLocation -eq 1 }
    "Restore Location Tracking" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -EA SilentlyContinue).DisableLocation -eq 1 }
    "Disable Error Reporting" = { (Get-Service -Name WerSvc -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Restore Error Reporting" = { (Get-Service -Name WerSvc -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Disable Web Search in Start Menu" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -EA SilentlyContinue).DisableWebSearch -eq 1 }
    "Restore Web Search in Start Menu" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -EA SilentlyContinue).DisableWebSearch -eq 1 }
    "Disable Wi-Fi Sense" = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" -Name "AutoConnectAllowedOEM" -EA SilentlyContinue).AutoConnectAllowedOEM -eq 0 }
    "Restore Wi-Fi Sense" = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" -Name "AutoConnectAllowedOEM" -EA SilentlyContinue).AutoConnectAllowedOEM -eq 0 }
    "Disable Content Delivery (Suggested Apps)" = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "ContentDeliveryAllowed" -EA SilentlyContinue).ContentDeliveryAllowed -eq 0 }
    "Restore Content Delivery (Suggested Apps)" = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "ContentDeliveryAllowed" -EA SilentlyContinue).ContentDeliveryAllowed -eq 0 }
    "Disable Windows Tips & Soft Landing" = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SoftLandingEnabled" -EA SilentlyContinue).SoftLandingEnabled -eq 0 }
    "Restore Windows Tips & Soft Landing" = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SoftLandingEnabled" -EA SilentlyContinue).SoftLandingEnabled -eq 0 }
    "Disable Input Personalization (Ink/Text)" = { (Get-ItemProperty "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -EA SilentlyContinue).RestrictImplicitInkCollection -eq 1 }
    "Restore Input Personalization (Ink/Text)" = { (Get-ItemProperty "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -EA SilentlyContinue).RestrictImplicitInkCollection -eq 1 }
    "Remove OneDrive" = { $null -eq (Get-Process -Name "OneDrive" -EA SilentlyContinue) -and (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -EA SilentlyContinue).DisableFileSyncNGSC -eq 1 }
    "Restore OneDrive Sync Policy" = { $null -eq (Get-Process -Name "OneDrive" -EA SilentlyContinue) -and (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -EA SilentlyContinue).DisableFileSyncNGSC -eq 1 }
    "Remove Xbox Suite" = { $null -eq (Get-AppxPackage -Name "*Microsoft.Xbox*" -EA SilentlyContinue) }
    "Restore Xbox Suite (Requires Store Reinstall)" = { $null -eq (Get-AppxPackage -Name "*Microsoft.Xbox*" -EA SilentlyContinue) }
    "Remove Bing & MSN Apps" = { $null -eq (Get-AppxPackage -Name "*Microsoft.BingWeather*" -EA SilentlyContinue) }
    "Restore Bing & MSN Apps (Requires Store Reinstall)" = { $null -eq (Get-AppxPackage -Name "*Microsoft.BingWeather*" -EA SilentlyContinue) }
    "Remove Media & Zune Apps" = { $null -eq (Get-AppxPackage -Name "*Microsoft.ZuneMusic*" -EA SilentlyContinue) }
    "Restore Media & Zune Apps (Requires Store Reinstall)" = { $null -eq (Get-AppxPackage -Name "*Microsoft.ZuneMusic*" -EA SilentlyContinue) }
    "Remove Social & Streaming Apps" = { $null -eq (Get-AppxPackage -Name "*Microsoft.SkypeApp*" -EA SilentlyContinue) }
    "Restore Social & Streaming Apps (Requires Store Reinstall)" = { $null -eq (Get-AppxPackage -Name "*Microsoft.SkypeApp*" -EA SilentlyContinue) }
    "Remove Productivity Apps" = { $null -eq (Get-AppxPackage -Name "*Microsoft.MicrosoftOfficeHub*" -EA SilentlyContinue) }
    "Restore Productivity Apps (Requires Store Reinstall)" = { $null -eq (Get-AppxPackage -Name "*Microsoft.MicrosoftOfficeHub*" -EA SilentlyContinue) }
    "Remove New Outlook" = { $null -eq (Get-AppxPackage -Name "*Microsoft.OutlookForWindows*" -EA SilentlyContinue) }
    "Restore New Outlook (Requires Store Reinstall)" = { $null -eq (Get-AppxPackage -Name "*Microsoft.OutlookForWindows*" -EA SilentlyContinue) }
    "Remove System Bloatware" = { $null -eq (Get-AppxPackage -Name "*Microsoft.GetHelp*" -EA SilentlyContinue) }
    "Restore System Bloatware (Requires Store Reinstall)" = { $null -eq (Get-AppxPackage -Name "*Microsoft.GetHelp*" -EA SilentlyContinue) }
    "Remove Games (king.com etc)" = { $null -eq (Get-AppxPackage -Name "*king.com*" -EA SilentlyContinue) }
    "Restore Games (Requires Store Reinstall)" = { $null -eq (Get-AppxPackage -Name "*king.com*" -EA SilentlyContinue) }
    "Clean Taskbar (Hide Icons)" = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -EA SilentlyContinue).ShowTaskViewButton -eq 0 }
    "Restore Taskbar Icons" = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -EA SilentlyContinue).ShowTaskViewButton -eq 0 }
    "Enable Classic Context Menu (Win11)" = { (Get-ItemProperty "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "(default)" -EA SilentlyContinue).'(default)' -eq "" }
    "Restore Default Context Menu (Win11)" = { (Get-ItemProperty "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "(default)" -EA SilentlyContinue).'(default)' -eq "" }
    "Disable Lock Screen Ads & Tips" = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenEnabled" -EA SilentlyContinue).RotatingLockScreenEnabled -eq 0 }
    "Restore Lock Screen Ads & Tips" = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenEnabled" -EA SilentlyContinue).RotatingLockScreenEnabled -eq 0 }
    "Show Hidden Files & Extensions" = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -EA SilentlyContinue).HideFileExt -eq 0 }
    "Restore Hidden Files & Extensions" = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -EA SilentlyContinue).HideFileExt -eq 0 }
    "Disable Start Menu Tracking" = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -EA SilentlyContinue).Start_TrackProgs -eq 0 }
    "Restore Start Menu Tracking" = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -EA SilentlyContinue).Start_TrackProgs -eq 0 }
    "Disable Xbox Services" = { (Get-Service -Name XblAuthManager -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Restore Xbox Services" = { (Get-Service -Name XblAuthManager -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Disable Hyper-V Services" = { (Get-Service -Name HvHost -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Restore Hyper-V Services" = { (Get-Service -Name HvHost -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Disable Misc System Services" = { (Get-Service -Name Fax -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Restore Misc System Services" = { (Get-Service -Name Fax -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Prompt: Disable Biometric Service" = { (Get-Service -Name WbioSrvc -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Restore Biometric Service" = { (Get-Service -Name WbioSrvc -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Prompt: Disable Remote Desktop" = { (Get-Service -Name TermService -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Restore Remote Desktop Services" = { (Get-Service -Name TermService -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Prompt: Disable Touch Keyboard" = { (Get-Service -Name TabletInputService -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Restore Touch Keyboard Service" = { (Get-Service -Name TabletInputService -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Enforce Group Policy (Refresh)" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows" -Name "CEIPEnable" -EA SilentlyContinue).CEIPEnable -eq 0 }
    "Restore Group Policy (CEIP)" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows" -Name "CEIPEnable" -EA SilentlyContinue).CEIPEnable -eq 0 }
    "Disable AI Fabric Service (26H2)" = { (Get-Service -Name WSAIFabricSvc -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Restore AI Fabric Service (26H2)" = { (Get-Service -Name WSAIFabricSvc -EA SilentlyContinue).StartType -eq 'Disabled' }
    "Disable Semantic Search Indexing (26H2)" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableSemanticSearch" -EA SilentlyContinue).DisableSemanticSearch -eq 1 }
    "Restore Semantic Search Indexing (26H2)" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableSemanticSearch" -EA SilentlyContinue).DisableSemanticSearch -eq 1 }
    "Disable Mu AI Agent (26H2)" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableMuAgent" -EA SilentlyContinue).DisableMuAgent -eq 1 }
    "Restore Mu AI Agent (26H2)" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableMuAgent" -EA SilentlyContinue).DisableMuAgent -eq 1 }
    "Disable Web & Store Search (26H2)" = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -EA SilentlyContinue).BingSearchEnabled -eq 0 }
    "Restore Web & Store Search (26H2)" = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -EA SilentlyContinue).BingSearchEnabled -eq 0 }
    "Disable Copilot in File Explorer (26H2)" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableCopilotInExplorer" -EA SilentlyContinue).DisableCopilotInExplorer -eq 1 }
    "Restore Copilot in File Explorer (26H2)" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableCopilotInExplorer" -EA SilentlyContinue).DisableCopilotInExplorer -eq 1 }
    "Disable Ask Copilot Search (26H2)" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableCopilotSearch" -EA SilentlyContinue).DisableCopilotSearch -eq 1 }
    "Restore Ask Copilot Search (26H2)" = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableCopilotSearch" -EA SilentlyContinue).DisableCopilotSearch -eq 1 }
}

# ===================================================================
# REVERT SUB-TASK DEFINITIONS (1-to-1 Exact Inverse)
# ===================================================================
 $script:RevertTaskDefinitions = [ordered]@{
    "1. Revert Privacy & Telemetry" = [ordered]@{
        "Restore Telemetry Services" = { try { Set-Service -Name "DiagTrack" -StartupType Automatic -EA SilentlyContinue } catch {}; try { Set-Service -Name "dmwappushservice" -StartupType Automatic -EA SilentlyContinue } catch {}; Write-ToResults "  [OK] Restored DiagTrack & dmwappushservice to Automatic" }
        "Restore Telemetry Level to Default" = { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Telemetry Level" }
        "Restore Feedback & Notifications" = { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Feedback Notifications" }
        "Restore Diagnostic Log Collection" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; $n=@("LimitDiagnosticLogCollection", "DisableOneSettingsDownloads", "DisableTelemetryOptInChangeNotification"); foreach ($x in $n) { Remove-ItemProperty -Path $p -Name $x -Force -EA SilentlyContinue }; Write-ToResults "  [OK] Restored Diagnostic Log Collection" }
        "Restore Windows AI & Recall Policies" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; $n=@("DisableAIDataAnalysis", "AllowRecallEnablement", "AllowWindowsAI", "TurnOffSavingSnapshots"); foreach ($x in $n) { Remove-ItemProperty -Path $p -Name $x -Force -EA SilentlyContinue }; Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored AI & Recall Policies" }
        "Restore Recall Packages (Requires Store Reinstall)" = { try { Set-Service -Name "RecallService" -StartupType Manual -EA SilentlyContinue } catch {}; Write-ToResults "  [i] Recall service restored. Reinstall Recall from Store." }
        "Restore Click to Do & AI Agents" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; $n=@("DisableClickToDo", "DisableSettingsAgent", "RemoveMicrosoftCopilotApp"); foreach ($x in $n) { Remove-ItemProperty -Path $p -Name $x -Force -EA SilentlyContinue }; Write-ToResults "  [OK] Restored Click to Do & AI Agents" }
        "Restore Windows Copilot (System)" = { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Force -EA SilentlyContinue; Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CopilotKey" -Name "SetCopilotHardwareKey" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Windows Copilot" }
        "Restore Copilot in Edge" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Edge"; $n=@("CopilotPageContext","HubsSidebarEnabled","CopilotCDPPageContext","EdgeEntraCopilotPageContext","EdgeHistoryAISearchEnabled","ComposeInlineEnabled","GenAILocalFoundationalModelSettings","BuiltInAIAPIsEnabled","AIGenThemesEnabled","AllowBrowsingWithCopilot","CopilotNewTabPageEnabled","CopilotAddressBarSuggestionsEnabled"); foreach ($x in $n) { Remove-ItemProperty -Path $p -Name $x -Force -EA SilentlyContinue }; Write-ToResults "  [OK] Restored Copilot in Edge" }
        "Restore AI in Notepad" = { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\WindowsNotepad" -Name "DisableAIFeatures" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored AI in Notepad" }
        "Restore Cortana Policies" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Remove-ItemProperty -Path $p -Name "AllowCortana" -Force -EA SilentlyContinue; Remove-ItemProperty -Path $p -Name "AllowCortanaAboveLock" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Cortana Policies (App requires Store reinstall)" }
        "Restore Activity History" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; $n=@("EnableActivityFeed", "PublishUserActivities", "UploadUserActivities"); foreach ($x in $n) { Remove-ItemProperty -Path $p -Name $x -Force -EA SilentlyContinue }; Write-ToResults "  [OK] Restored Activity History" }
        "Restore Advertising ID" = { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -Force -EA SilentlyContinue; Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Advertising ID" }
        "Restore Cloud Consumer Features" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; $n=@("DisableWindowsConsumerFeatures", "DisableCloudOptimizedContent", "DisableSoftLanding"); foreach ($x in $n) { Remove-ItemProperty -Path $p -Name $x -Force -EA SilentlyContinue }; Write-ToResults "  [OK] Restored Cloud Consumer Features" }
        "Restore Location Tracking" = { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Location Tracking" }
        "Restore Error Reporting" = { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Force -EA SilentlyContinue; try { Set-Service -Name "WerSvc" -StartupType Manual -EA SilentlyContinue } catch {}; Write-ToResults "  [OK] Restored Error Reporting" }
        "Restore Web Search in Start Menu" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; $n=@("DisableWebSearch", "ConnectedSearchUseWeb"); foreach ($x in $n) { Remove-ItemProperty -Path $p -Name $x -Force -EA SilentlyContinue }; $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Remove-ItemProperty -Path $p -Name "BingSearchEnabled" -Force -EA SilentlyContinue; Remove-ItemProperty -Path $p -Name "CortanaConsent" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Web Search in Start Menu" }
        "Restore Wi-Fi Sense" = { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" -Name "AutoConnectAllowedOEM" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Wi-Fi Sense" }
        "Restore Content Delivery (Suggested Apps)" = { $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; $n=@("ContentDeliveryAllowed","OemPreInstalledAppsEnabled","PreInstalledAppsEnabled","PreInstalledAppsEverEnabled","SilentInstalledAppsEnabled","SubscribedContent-338388Enabled","SubscribedContent-353698Enabled"); foreach ($x in $n) { Remove-ItemProperty -Path $p -Name $x -Force -EA SilentlyContinue }; Write-ToResults "  [OK] Restored Content Delivery" }
        "Restore Windows Tips & Soft Landing" = { $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Remove-ItemProperty -Path $p -Name "SubscribedContent-338389Enabled" -Force -EA SilentlyContinue; Remove-ItemProperty -Path $p -Name "SoftLandingEnabled" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Windows Tips" }
        "Restore Input Personalization (Ink/Text)" = { $p="HKCU:\Software\Microsoft\InputPersonalization"; Remove-ItemProperty -Path $p -Name "RestrictImplicitInkCollection" -Force -EA SilentlyContinue; Remove-ItemProperty -Path $p -Name "RestrictImplicitTextCollection" -Force -EA SilentlyContinue; Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Personalization\Settings" -Name "AcceptedPrivacyPolicy" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Input Personalization" }
        "Restore AI Fabric Service (26H2)" = { try { Set-Service -Name "WSAIFabricSvc" -StartupType Manual -EA SilentlyContinue } catch {}; try { Set-Service -Name "WsaService" -StartupType Manual -EA SilentlyContinue } catch {}; Write-ToResults "  [OK] Restored AI Fabric Service" }
        "Restore Semantic Search Indexing (26H2)" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; $n=@("DisableSemanticSearch"); foreach ($x in $n) { Remove-ItemProperty -Path $p -Name $x -Force -EA SilentlyContinue }; Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsDeviceSearchEnabled" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Semantic Search Indexing" }
        "Restore Mu AI Agent (26H2)" = { $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; $n=@("DisableMuAgent", "DisableSettingsAgent"); foreach ($x in $n) { Remove-ItemProperty -Path $p -Name $x -Force -EA SilentlyContinue }; Write-ToResults "  [OK] Restored Mu AI Agent" }
        "Restore Web & Store Search (26H2)" = { $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; $n=@("BingSearchEnabled", "CortanaConsent", "EnableWebSuggestions", "EnableMSACloudSearch"); foreach ($x in $n) { Remove-ItemProperty -Path $p -Name $x -Force -EA SilentlyContinue }; $p2="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; $n2=@("DisableWebSearch", "ConnectedSearchUseWeb", "AllowSearchToUseLocation", "AllowCloudSearch", "AllowCortana"); foreach ($x in $n2) { Remove-ItemProperty -Path $p2 -Name $x -Force -EA SilentlyContinue }; Write-ToResults "  [OK] Restored Web & Store Search" }
        "Restore Copilot in File Explorer (26H2)" = { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableCopilotInExplorer" -Force -EA SilentlyContinue; $p="HKLM:\SOFTWARE\Policies\Microsoft\Edge"; $n=@("HubsSidebarEnabled", "CopilotPageContext"); foreach ($x in $n) { Remove-ItemProperty -Path $p -Name $x -Force -EA SilentlyContinue }; Write-ToResults "  [OK] Restored Copilot in File Explorer" }
        "Restore Ask Copilot Search (26H2)" = { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableCopilotSearch" -Force -EA SilentlyContinue; $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; $n=@("DisableWebSearch", "ConnectedSearchUseWeb"); foreach ($x in $n) { Remove-ItemProperty -Path $p -Name $x -Force -EA SilentlyContinue }; Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Ask Copilot Search" }
    }
    "2. Revert Bloatware Removal" = [ordered]@{
        "Restore OneDrive Sync Policy" = { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored OneDrive Sync Policy (App requires reinstall)" }
        "Restore Xbox Suite (Requires Store Reinstall)" = { Write-ToResults "  [i] You must reinstall Xbox apps from the Microsoft Store." }
        "Restore Bing & MSN Apps (Requires Store Reinstall)" = { Write-ToResults "  [i] You must reinstall Bing/MSN apps from the Microsoft Store." }
        "Restore Media & Zune Apps (Requires Store Reinstall)" = { Write-ToResults "  [i] You must reinstall Media/Zune apps from the Microsoft Store." }
        "Restore Social & Streaming Apps (Requires Store Reinstall)" = { Write-ToResults "  [i] You must reinstall Social/Streaming apps from the Microsoft Store." }
        "Restore Productivity Apps (Requires Store Reinstall)" = { Write-ToResults "  [i] You must reinstall Productivity apps from the Microsoft Store." }
        "Restore New Outlook (Requires Store Reinstall)" = { Write-ToResults "  [i] You must reinstall New Outlook from the Microsoft Store." }
        "Restore System Bloatware (Requires Store Reinstall)" = { Write-ToResults "  [i] You must reinstall System apps from the Microsoft Store." }
        "Restore Games (Requires Store Reinstall)" = { Write-ToResults "  [i] You must reinstall Games from the Microsoft Store." }
    }
    "3. Revert UI & System Tweaks" = [ordered]@{
        "Restore Taskbar Icons" = { $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; $n=@("ShowTaskViewButton", "TaskbarDa", "ShowCopilotButton"); foreach ($x in $n) { Remove-ItemProperty -Path $p -Name $x -Force -EA SilentlyContinue }; Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat" -Name "ChatIcon" -Force -EA SilentlyContinue; Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "HideSCAMeetNow" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Taskbar Icons" }
        "Restore Default Context Menu (Win11)" = { Remove-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Default Context Menu" }
        "Restore Lock Screen Ads & Tips" = { $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Remove-ItemProperty -Path $p -Name "RotatingLockScreenEnabled" -Force -EA SilentlyContinue; Remove-ItemProperty -Path $p -Name "SystemPaneSuggestionsEnabled" -Force -EA SilentlyContinue; Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Force -EA SilentlyContinue; Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Lock Screen Ads & Tips" }
        "Restore Hidden Files & Extensions" = { $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Remove-ItemProperty -Path $p -Name "HideFileExt" -Force -EA SilentlyContinue; Remove-ItemProperty -Path $p -Name "Hidden" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Hidden Files settings" }
        "Restore Start Menu Tracking" = { $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Remove-ItemProperty -Path $p -Name "Start_TrackProgs" -Force -EA SilentlyContinue; Remove-ItemProperty -Path $p -Name "Start_TrackDocs" -Force -EA SilentlyContinue; $p="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"; Remove-ItemProperty -Path $p -Name "ShowFrequent" -Force -EA SilentlyContinue; Remove-ItemProperty -Path $p -Name "ShowRecent" -Force -EA SilentlyContinue; $p="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Remove-ItemProperty -Path $p -Name "HideRecentlyAddedApps" -Force -EA SilentlyContinue; Remove-ItemProperty -Path $p -Name "NoPinningStoreToTaskbar" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored Start Menu Tracking" }
        "Restore Xbox Services" = { try { Set-Service -Name "XblAuthManager" -StartupType Manual -EA SilentlyContinue } catch {}; try { Set-Service -Name "XblGameSave" -StartupType Manual -EA SilentlyContinue } catch {}; try { Set-Service -Name "XboxGipSvc" -StartupType Manual -EA SilentlyContinue } catch {}; try { Set-Service -Name "XboxNetApiSvc" -StartupType Manual -EA SilentlyContinue } catch {}; Write-ToResults "  [OK] Restored Xbox Services" }
        "Restore Hyper-V Services" = { try { Set-Service -Name "HvHost" -StartupType Manual -EA SilentlyContinue } catch {}; try { Set-Service -Name "vmickvpexchange" -StartupType Manual -EA SilentlyContinue } catch {}; Write-ToResults "  [OK] Restored Hyper-V Services" }
        "Restore Misc System Services" = { try { Set-Service -Name "Fax" -StartupType Manual -EA SilentlyContinue } catch {}; try { Set-Service -Name "RetailDemo" -StartupType Manual -EA SilentlyContinue } catch {}; try { Set-Service -Name "MapsBroker" -StartupType Automatic -EA SilentlyContinue } catch {}; try { Set-Service -Name "lfsvc" -StartupType Manual -EA SilentlyContinue } catch {}; try { Set-Service -Name "SharedAccess" -StartupType Manual -EA SilentlyContinue } catch {}; try { Set-Service -Name "icssvc" -StartupType Manual -EA SilentlyContinue } catch {}; try { Set-Service -Name "wisvc" -StartupType Manual -EA SilentlyContinue } catch {}; try { Set-Service -Name "diagnosticshub.standardcollector.service" -StartupType Manual -EA SilentlyContinue } catch {}; try { Set-Service -Name "DusmSvc" -StartupType Automatic -EA SilentlyContinue } catch {}; try { Set-Service -Name "PcaSvc" -StartupType Automatic -EA SilentlyContinue } catch {}; Write-ToResults "  [OK] Restored Misc System Services" }
        "Restore Biometric Service" = { try { Set-Service -Name "WbioSrvc" -StartupType Manual -EA SilentlyContinue } catch {}; Write-ToResults "  [OK] Restored Biometric Service" }
        "Restore Remote Desktop Services" = { try { Set-Service -Name "TermService" -StartupType Manual -EA SilentlyContinue } catch {}; try { Set-Service -Name "UmRdpService" -StartupType Manual -EA SilentlyContinue } catch {}; Write-ToResults "  [OK] Restored Remote Desktop Services" }
        "Restore Touch Keyboard Service" = { try { Set-Service -Name "TabletInputService" -StartupType Manual -EA SilentlyContinue } catch {}; Write-ToResults "  [OK] Restored Touch Keyboard Service" }
        "Restore Group Policy (CEIP)" = { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows" -Name "CEIPEnable" -Force -EA SilentlyContinue; Write-ToResults "  [OK] Restored CEIP Group Policy" }
    }
}

# ===================================================================
# MISC QUICK FIX FUNCTIONS
# ===================================================================
function Start-SystemBackup {
    param($StatusLabel)
    Write-ColoredHeader "========== CREATING RESTORE POINT =========="
    $StatusLabel.Text = "Creating System Restore point..."; $StatusLabel.Refresh()
    Write-ToResults "  [*] This may take up to 60 seconds..."; [System.Windows.Forms.Application]::DoEvents()
    try {
        try { Set-Service -Name "swprv" -StartupType Manual -EA SilentlyContinue } catch {}
        try { Start-Service -Name "swprv" -EA SilentlyContinue } catch {}
        try { Set-Service -Name "VSS" -StartupType Manual -EA SilentlyContinue } catch {}
        try { Start-Service -Name "VSS" -EA SilentlyContinue } catch {}

        $srEnabled = $false
        try { $sr = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "RPSessionInterval" -EA SilentlyContinue; if ($null -ne $sr) { $srEnabled = $true } } catch {}

        if (-not $srEnabled) { Write-ToResults "  [i] System Restore was disabled. Enabling for C:\..."; Enable-ComputerRestore -Drive "C:\" -EA SilentlyContinue }

        Checkpoint-Computer -Description "Before Debloat Tool" -RestorePointType "MODIFY_SETTINGS" -EA Stop
        Write-ToResults "  [OK] Restore point created: Before Debloat Tool"
        $StatusLabel.Text = "Restore point created"; $StatusLabel.ForeColor = [System.Drawing.Color]::Green
    } catch {
        Write-ToResults "  [X] Failed to create restore point: $($_.Exception.Message)"
        $StatusLabel.Text = "Restore point failed"; $StatusLabel.ForeColor = [System.Drawing.Color]::Orange
    }
}

# ===================================================================
# TEMP CLEAN HELPER - Shared cleanup logic for selectable temp tasks
# ===================================================================
function Invoke-TempCleanLocation {
    param([string]$Label, [string]$Path, [string]$Filter = "*", [bool]$Recurse = $true)
    try { $exists = Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue } catch { $exists = $false }
    if (-not $exists) {
        $appNotInstalled = $false
        if ($Label -match "Chrome") { $appNotInstalled = -not (Test-Path "$env:LOCALAPPDATA\Google\Chrome" -EA SilentlyContinue) -and -not (Test-Path "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" -EA SilentlyContinue) -and -not (Test-Path "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe" -EA SilentlyContinue) }
        elseif ($Label -match "Firefox") { $appNotInstalled = -not (Test-Path "$env:LOCALAPPDATA\Mozilla\Firefox" -EA SilentlyContinue) -and -not (Test-Path "$env:ProgramFiles\Mozilla Firefox\firefox.exe" -EA SilentlyContinue) }
        elseif ($Label -match "Teams") { $appNotInstalled = -not (Test-Path "$env:APPDATA\Microsoft\Teams" -EA SilentlyContinue) -and -not (Test-Path "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe" -EA SilentlyContinue) -and -not (Test-Path "$env:LOCALAPPDATA\Microsoft\Teams" -EA SilentlyContinue) }
        elseif ($Label -match "Slack") { $appNotInstalled = -not (Test-Path "$env:APPDATA\Slack" -EA SilentlyContinue) }
        elseif ($Label -match "AMD") { $appNotInstalled = -not (Test-Path "$env:LOCALAPPDATA\AMD" -EA SilentlyContinue) -and -not (Test-Path "$env:ProgramFiles\AMD" -EA SilentlyContinue) }
        elseif ($Label -match "NVIDIA") { $appNotInstalled = -not (Test-Path "$env:LOCALAPPDATA\NVIDIA" -EA SilentlyContinue) -and -not (Test-Path "$env:LOCALAPPDATA\NVIDIA Corporation" -EA SilentlyContinue) -and -not (Test-Path "$env:ProgramData\NVIDIA Corporation" -EA SilentlyContinue) }
        elseif ($Label -match "Intel") { $appNotInstalled = -not (Test-Path "$env:LOCALAPPDATA\Intel" -EA SilentlyContinue) }
        elseif ($Label -match "Edge") { $appNotInstalled = $false }
        if ($appNotInstalled) {
            Write-ColoredNotInstalled "  [i] $Label : Not Installed (app not found, skipped)"
        } else {
            Write-ToResults "  [i] $Label : Not Found (path not found, skipped)"
        }
        return
    }
    $getArgs = @{ Path = $Path; ErrorAction = "SilentlyContinue" }
    if ($Filter -ne "*") { $getArgs.Filter = $Filter }
    if ($Recurse) { $getArgs.Recurse = $true }
    $before = @(Get-ChildItem @getArgs); $beforeSize = ($before | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum -EA SilentlyContinue).Sum; $beforeFiles = ($before | Where-Object { -not $_.PSIsContainer }).Count; $beforeDirs  = ($before | Where-Object {  $_.PSIsContainer }).Count
    if ($null -eq $beforeSize) { $beforeSize = 0 }; if ($beforeFiles -eq 0 -and $beforeDirs -eq 0) { Write-ToResults "  [i] $Label : Empty (already clean)"; return }
    $toDelete = @(Get-ChildItem @getArgs | Where-Object { $_.FullName -ne $script:LogPath })
    $toDelete | Remove-Item -Recurse -Force -EA SilentlyContinue
    $stillLocked = @($toDelete | Where-Object { Test-Path -LiteralPath $_.FullName -EA SilentlyContinue })
    foreach ($locked in $stillLocked) {
        $lockedSize = 0
        try { if (-not $locked.PSIsContainer) { $lockedSize = $locked.Length } } catch {}
        if ($null -eq $lockedSize) { $lockedSize = 0 }
        $lockedMB = [math]::Round($lockedSize / 1MB, 2)
        Write-ColoredScheduled ("  [Scheduled] " + $locked.Name + " in use - queued for delete on next reboot")
        $script:PendingRebootDeletes.Add($locked.FullName) | Out-Null
        $script:PendingRebootCount++
        $script:PendingRebootSize += $lockedMB
        try {
            $queueFile = "C:\DebloatBackups\PendingDeletes.txt"
            if (-not (Test-Path "C:\DebloatBackups")) { New-Item -ItemType Directory -Path "C:\DebloatBackups" -Force | Out-Null }
            Add-Content -LiteralPath $queueFile -Value $locked.FullName -Force -EA SilentlyContinue
        } catch {}
    }
    $after = @(Get-ChildItem @getArgs); $afterSize = ($after | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum -EA SilentlyContinue).Sum
    if ($null -eq $afterSize) { $afterSize = 0 }
    $freed = [math]::Round(($beforeSize - $afterSize) / 1MB, 2); $filesClean = $beforeFiles - ($after | Where-Object { -not $_.PSIsContainer }).Count
    $script:TempFreed += $freed; $script:TempFiles += $filesClean; $script:TempFolders += $beforeDirs
    $sizeStr = if ($freed -ge 1024) { "$([math]::Round($freed/1024,2)) GB" } else { "$freed MB" }
    Write-ToResults "  [OK] $Label"
    Write-ToResults "       Files removed : $filesClean   Folders : $beforeDirs   Freed : $sizeStr"
    if ($filesClean -gt 0 -or $beforeDirs -gt 0) { $script:TempClearedLocations.Add("$Label ($filesClean files, $sizeStr)") }
}

# ===================================================================
# TEMP CLEAN SUB-TASK DEFINITIONS (for selectable Clean Temp menu)
# Mirrors Full System Clean pattern - shown in TreeView via Show-TaskSelectionWindow
# ===================================================================
 $script:TempTaskDefinitions = [ordered]@{
    "1. System Temp & Logs" = [ordered]@{
        "Error Reports" = { Invoke-TempCleanLocation -Label "Windows Error Reports" -Path "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"; Invoke-TempCleanLocation -Label "WER Queue" -Path "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" }
        "System Log Files" = { Invoke-TempCleanLocation -Label "System Log Files (Windows\Logs)" -Path "$env:SystemRoot\Logs"; Invoke-TempCleanLocation -Label "System Log Files (System32\LogFiles)" -Path "$env:SystemRoot\System32\LogFiles" }
        "User Temp Files" = { Invoke-TempCleanLocation -Label "User Temp (%TEMP%)" -Path "$env:TEMP" }
        "Windows Temp Files" = { Invoke-TempCleanLocation -Label "Windows Temp" -Path "$env:SystemRoot\Temp" }
        "Windows.old Files" = { Invoke-TempCleanLocation -Label "Windows.old" -Path "$env:SystemDrive\Windows.old"; Invoke-TempCleanLocation -Label "Windows.old (~BT)" -Path "$env:SystemDrive\`$Windows.~BT"; Invoke-TempCleanLocation -Label "Windows.old (~WS)" -Path "$env:SystemDrive\`$Windows.~WS" }
        "Orphaned App Data" = { Invoke-TempCleanLocation -Label "Orphaned App Data (CrashDumps)" -Path "$env:LOCALAPPDATA\CrashDumps"; Invoke-TempCleanLocation -Label "Orphaned App Data (WER Temp)" -Path "$env:LOCALAPPDATA\Microsoft\Windows\WER\Temp"; Invoke-TempCleanLocation -Label "AutomaticDestinations" -Path "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations" -Filter "*.automaticDestinations-ms" -Recurse $false; Invoke-TempCleanLocation -Label "CustomDestinations" -Path "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations" -Filter "*.customDestinations-ms" -Recurse $false }
        "Prefetch Files" = { Invoke-TempCleanLocation -Label "Prefetch (.pf files)" -Path "$env:SystemRoot\Prefetch" -Filter "*.pf" -Recurse $false }
        "Thumbnail Cache" = { Invoke-TempCleanLocation -Label "Thumbnail Cache" -Path "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter "thumbcache_*.db" -Recurse $false }
        "CBS Log Files" = { Invoke-TempCleanLocation -Label "CBS Logs" -Path "$env:SystemRoot\Logs\CBS" -Filter "*.log" -Recurse $false }
        "Memory Dumps (*.dmp)" = { Invoke-TempCleanLocation -Label "Memory Dump Files" -Path "$env:SystemRoot" -Filter "*.dmp" -Recurse $false }
        "Recent Files List" = { Invoke-TempCleanLocation -Label "Recent Files List" -Path "$env:APPDATA\Microsoft\Windows\Recent" -Recurse $false }
    }
    "2. Windows Update & Security" = [ordered]@{
        "Windows Update Cleanup" = { Invoke-TempCleanLocation -Label "Windows Update Download" -Path "$env:SystemRoot\SoftwareDistribution\Download"; Invoke-TempCleanLocation -Label "Windows Update DataStore Logs" -Path "$env:SystemRoot\SoftwareDistribution\DataStore\Logs"; Invoke-TempCleanLocation -Label "Windows Update DeliveryOpt" -Path "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization" }
        "Windows Defender History" = { Invoke-TempCleanLocation -Label "Windows Defender History" -Path "$env:ProgramData\Microsoft\Windows Defender\Scans\History"; Invoke-TempCleanLocation -Label "Windows Defender Scans Temp" -Path "$env:ProgramData\Microsoft\Windows Defender\Scans\mpcache" }
        "Delivery Optimization" = { Invoke-TempCleanLocation -Label "Delivery Optimization (NetworkService)" -Path "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"; Invoke-TempCleanLocation -Label "Delivery Optimization (ProgramData)" -Path "$env:ProgramData\Microsoft\Windows\DeliveryOptimization\Cache"; Invoke-TempCleanLocation -Label "Delivery Optimization (System)" -Path "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization" }
    }
    "3. Browser Caches" = [ordered]@{
        "Chrome Cache" = { Invoke-TempCleanLocation -Label "Chrome Cache" -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"; Invoke-TempCleanLocation -Label "Chrome Code Cache" -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"; Invoke-TempCleanLocation -Label "Chrome GPU Cache" -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache" }
        "Firefox Cache" = { $ffProfiles = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"; if (Test-Path $ffProfiles) { Get-ChildItem $ffProfiles -Directory -EA SilentlyContinue | ForEach-Object { Invoke-TempCleanLocation -Label "Firefox Cache ($($_.Name))" -Path "$($_.FullName)\cache2" } } else { Write-ToResults "  [i] Firefox Cache : no profiles found" } }
        "Edge Cache" = { Invoke-TempCleanLocation -Label "Edge Cache" -Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"; Invoke-TempCleanLocation -Label "Edge Code Cache" -Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache"; Invoke-TempCleanLocation -Label "Edge GPU Cache" -Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache"; Invoke-TempCleanLocation -Label "IE / Edge Legacy Cache" -Path "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"; Invoke-TempCleanLocation -Label "Edge WebCache" -Path "$env:LOCALAPPDATA\Microsoft\Windows\WebCache" }
    }
    "4. Shader Caches" = [ordered]@{
        "DirectX Shader Cache" = { Invoke-TempCleanLocation -Label "DirectX Shader Cache (D3DSCache)" -Path "$env:LOCALAPPDATA\D3DSCache"; Invoke-TempCleanLocation -Label "DirectX Shader Cache (Microsoft Direct3D)" -Path "$env:LOCALAPPDATA\Microsoft\Direct3D\ShaderCache"; Invoke-TempCleanLocation -Label "DirectX Shader Cache (LocalLow)" -Path "$env:USERPROFILE\AppData\LocalLow\Microsoft\Direct3D\ShaderCache" }
        "AMD Shader Cache" = { Invoke-TempCleanLocation -Label "AMD DxCache" -Path "$env:LOCALAPPDATA\AMD\DxCache"; Invoke-TempCleanLocation -Label "AMD GLCache" -Path "$env:LOCALAPPDATA\AMD\GLCache"; Invoke-TempCleanLocation -Label "AMD VkCache" -Path "$env:LOCALAPPDATA\AMD\VkCache" }
        "NVIDIA Shader Cache" = { Invoke-TempCleanLocation -Label "NVIDIA GLCache" -Path "$env:LOCALAPPDATA\NVIDIA\GLCache"; Invoke-TempCleanLocation -Label "NVIDIA DXCache" -Path "$env:LOCALAPPDATA\NVIDIA\DXCache"; Invoke-TempCleanLocation -Label "NVIDIA NV_Cache" -Path "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache"; Invoke-TempCleanLocation -Label "NVIDIA NV_Cache (ProgramData)" -Path "$env:ProgramData\NVIDIA Corporation\NV_Cache" }
        "Intel Shader Cache" = { Invoke-TempCleanLocation -Label "Intel ShaderCache" -Path "$env:LOCALAPPDATA\Intel\ShaderCache"; Invoke-TempCleanLocation -Label "Intel IGCCache" -Path "$env:LOCALAPPDATA\Intel\IGCCache" }
    }
    "5. App Caches" = [ordered]@{
        "Microsoft Teams Cache" = { Invoke-TempCleanLocation -Label "Teams Cache (Roaming)" -Path "$env:APPDATA\Microsoft\Teams\Cache"; Invoke-TempCleanLocation -Label "Teams GPUCache" -Path "$env:APPDATA\Microsoft\Teams\GPUCache"; Invoke-TempCleanLocation -Label "Teams Code Cache" -Path "$env:APPDATA\Microsoft\Teams\Code Cache"; Invoke-TempCleanLocation -Label "Teams New (MSTeams)" -Path "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"; Invoke-TempCleanLocation -Label "Teams Classic Blob" -Path "$env:APPDATA\Microsoft\Teams\Blob_storage" }
        "Slack Cache" = { Invoke-TempCleanLocation -Label "Slack Cache" -Path "$env:APPDATA\Slack\Cache"; Invoke-TempCleanLocation -Label "Slack GPUCache" -Path "$env:APPDATA\Slack\GPUCache"; Invoke-TempCleanLocation -Label "Slack Code Cache" -Path "$env:APPDATA\Slack\Code Cache"; Invoke-TempCleanLocation -Label "Slack Service Worker Cache" -Path "$env:APPDATA\Slack\Service Worker\CacheStorage" }
    }
    "6. Shortcuts & Network" = [ordered]@{
        "Broken Desktop Shortcuts" = {
            $before = 0; $removed = 0
            $paths = @("$env:USERPROFILE\Desktop", "$env:PUBLIC\Desktop")
            $shell = $null; try { $shell = New-Object -ComObject WScript.Shell } catch {}
            foreach ($p in $paths) {
                if (-not (Test-Path $p)) { continue }
                $links = Get-ChildItem -Path $p -Filter "*.lnk" -ErrorAction SilentlyContinue
                foreach ($lnk in $links) {
                    $before++
                    $target = $null
                    try { if ($null -ne $shell) { $shortcut = $shell.CreateShortcut($lnk.FullName); $target = $shortcut.TargetPath } } catch {}
                    if (-not [string]::IsNullOrWhiteSpace($target)) {
                        $exists = Test-Path $target
                        if (-not $exists) {
                            try { Remove-Item -LiteralPath $lnk.FullName -Force -ErrorAction SilentlyContinue; $removed++; Write-ToResults "  [OK] Removed broken desktop shortcut: $($lnk.Name) -> $target" } catch {}
                        }
                    }
                }
            }
            $script:TempFiles += $removed
            if ($removed -gt 0) { $script:TempClearedLocations.Add("Broken Desktop Shortcuts ($removed removed)") } else { Write-ToResults "  [i] Broken Desktop Shortcuts : none found" }
        }
        "Broken Start Menu Shortcuts" = {
            $before = 0; $removed = 0
            $paths = @("$env:APPDATA\Microsoft\Windows\Start Menu", "$env:ProgramData\Microsoft\Windows\Start Menu")
            $shell = $null; try { $shell = New-Object -ComObject WScript.Shell } catch {}
            foreach ($p in $paths) {
                if (-not (Test-Path $p)) { continue }
                $links = Get-ChildItem -Path $p -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue
                foreach ($lnk in $links) {
                    $before++
                    $target = $null
                    try { if ($null -ne $shell) { $shortcut = $shell.CreateShortcut($lnk.FullName); $target = $shortcut.TargetPath } } catch {}
                    if (-not [string]::IsNullOrWhiteSpace($target)) {
                        $exists = Test-Path $target
                        if (-not $exists) {
                            try { Remove-Item -LiteralPath $lnk.FullName -Force -ErrorAction SilentlyContinue; $removed++; Write-ToResults "  [OK] Removed broken start menu shortcut: $($lnk.Name) -> $target" } catch {}
                        }
                    }
                }
            }
            $script:TempFiles += $removed
            if ($removed -gt 0) { $script:TempClearedLocations.Add("Broken Start Menu Shortcuts ($removed removed)") } else { Write-ToResults "  [i] Broken Start Menu Shortcuts : none found" }
        }
        "DNS Cache" = { try { Clear-DnsClientCache -ErrorAction SilentlyContinue; Start-Process ipconfig.exe -ArgumentList "/flushdns" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null; Write-ToResults "  [OK] DNS Cache flushed"; $script:TempClearedLocations.Add("DNS Cache (flushed)") } catch { Write-ToResults "  [X] Failed to flush DNS: $($_.Exception.Message)" } }
        "Network Cache" = { try { Start-Process arp.exe -ArgumentList "-d *" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null; Start-Process nbtstat.exe -ArgumentList "-R" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null; Start-Process nbtstat.exe -ArgumentList "-RR" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null; try { netsh interface ip delete arpcache | Out-Null } catch {}; Write-ToResults "  [OK] Network Cache cleared (ARP/NetBIOS)"; $script:TempClearedLocations.Add("Network Cache (ARP/NetBIOS cleared)") } catch { Write-ToResults "  [X] Failed to clear Network Cache: $($_.Exception.Message)" } }
    }
    "7. Recycle Bin" = [ordered]@{
        "Recycle Bin" = { try { $shell = New-Object -ComObject Shell.Application; $rb = $shell.Namespace(0xA); $rbSize = ($rb.Items() | ForEach-Object { $_.Size } | Measure-Object -Sum).Sum; if ($null -eq $rbSize) { $rbSize = 0 }; Clear-RecycleBin -Force -EA SilentlyContinue; $rbMB = [math]::Round($rbSize / 1MB, 2); $script:TempFreed += $rbMB; $sizeStr = if ($rbMB -ge 1024) { "$([math]::Round($rbMB/1024,2)) GB" } else { "$rbMB MB" }; Write-ToResults "  [OK] Recycle Bin emptied : $sizeStr"; if ($rbMB -gt 0) { $script:TempClearedLocations.Add("Recycle Bin ($sizeStr)") } } catch { try { Clear-RecycleBin -Force -EA SilentlyContinue; Write-ToResults "  [OK] Recycle Bin emptied" } catch { Write-ToResults "  [X] Failed to empty Recycle Bin: $($_.Exception.Message)" } } }
    }
}

# ===================================================================
# TEMP TASK AVAILABILITY CHECKS - grey out Not Installed apps in Clean Temp UI
# ===================================================================
 $script:TempTaskChecks = @{
    "Chrome Cache" = { 
        foreach ($p in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) { if (Test-Path $p -EA SilentlyContinue) { return $true } }
        try { foreach ($rp in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")) { if (Get-ItemProperty $rp -EA SilentlyContinue | Where-Object { $_.DisplayName -like "*Chrome*" }) { return $true } } } catch {}
        return $false
    }
    "Firefox Cache" = { 
        foreach ($p in @("$env:ProgramFiles\Mozilla Firefox\firefox.exe","${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe","$env:LOCALAPPDATA\Mozilla Firefox\firefox.exe")) { if (Test-Path $p -EA SilentlyContinue) { return $true } }
        try { foreach ($rp in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")) { if (Get-ItemProperty $rp -EA SilentlyContinue | Where-Object { $_.DisplayName -like "*Firefox*" }) { return $true } } } catch {}
        return $false
    }
    "AMD Shader Cache" = { 
        foreach ($p in @("$env:ProgramFiles\AMD\CNext\CNext\RadeonSoftware.exe","$env:LOCALAPPDATA\AMD\DxCache","$env:ProgramFiles\AMD")) { if (Test-Path $p -EA SilentlyContinue) { return $true } }
        try { if (Get-Service -Name "AMD External Events Utility" -EA SilentlyContinue) { return $true } } catch {}
        return $false
    }
    "NVIDIA Shader Cache" = { 
        foreach ($p in @("$env:ProgramFiles\NVIDIA Corporation","${env:ProgramFiles(x86)}\NVIDIA Corporation","$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache","$env:ProgramData\NVIDIA Corporation\NV_Cache")) { if (Test-Path $p -EA SilentlyContinue) { return $true } }
        try { if (Get-Service -Name "NVDisplay.ContainerLocalSystem" -EA SilentlyContinue) { return $true } } catch {}
        return $false
    }
    "Intel Shader Cache" = { 
        foreach ($p in @("$env:ProgramFiles\Intel","${env:ProgramFiles(x86)}\Intel","$env:LOCALAPPDATA\Intel\ShaderCache")) { if (Test-Path $p -EA SilentlyContinue) { return $true } }
        try { if (Get-Service -Name "igfxCUIService*" -EA SilentlyContinue) { return $true } } catch {}
        # Fallback: check Intel GPU via CIM
        try { if (Get-CimInstance Win32_VideoController -EA SilentlyContinue | Where-Object { $_.Name -like "*Intel*" }) { return $true } } catch {}
        return $false
    }
    "Microsoft Teams Cache" = { 
        foreach ($p in @("$env:APPDATA\Microsoft\Teams","$env:LOCALAPPDATA\Microsoft\Teams","$env:ProgramFiles\Microsoft\Teams","$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe")) { if (Test-Path $p -EA SilentlyContinue) { return $true } }
        try { if (Get-AppxPackage -Name "*MSTeams*" -EA SilentlyContinue) { return $true } } catch {}
        try { foreach ($rp in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*")) { if (Get-ItemProperty $rp -EA SilentlyContinue | Where-Object { $_.DisplayName -like "*Teams*" }) { return $true } } } catch {}
        return $false
    }
    "Slack Cache" = { 
        foreach ($p in @("$env:APPDATA\Slack","$env:LOCALAPPDATA\slack","$env:ProgramFiles\Slack","${env:ProgramFiles(x86)}\Slack")) { if (Test-Path $p -EA SilentlyContinue) { return $true } }
        try { foreach ($rp in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*")) { if (Get-ItemProperty $rp -EA SilentlyContinue | Where-Object { $_.DisplayName -like "*Slack*" }) { return $true } } } catch {}
        return $false
    }
}

# Safe Temp profile - low-risk selection
 $script:TempSafeTasks = @("User Temp Files","Windows Temp Files","Prefetch Files","Thumbnail Cache","Chrome Cache","Firefox Cache","Edge Cache","Recycle Bin","Error Reports","CBS Log Files","Recent Files List","DNS Cache","Network Cache","Broken Desktop Shortcuts","Broken Start Menu Shortcuts","DirectX Shader Cache")

function Get-TempTaskPreview {
    param([string]$TaskName)
    try {
        $paths = @()
        switch ($TaskName) {
            "Error Reports" { $paths = @("$env:ProgramData\Microsoft\Windows\WER\ReportArchive","$env:ProgramData\Microsoft\Windows\WER\ReportQueue") }
            "System Log Files" { $paths = @("$env:SystemRoot\Logs","$env:SystemRoot\System32\LogFiles") }
            "User Temp Files" { $paths = @("$env:TEMP") }
            "Windows Temp Files" { $paths = @("$env:SystemRoot\Temp") }
            "Windows.old Files" { $paths = @("$env:SystemDrive\Windows.old","$env:SystemDrive\`$Windows.~BT","$env:SystemDrive\`$Windows.~WS") }
            "Orphaned App Data" { $paths = @("$env:LOCALAPPDATA\CrashDumps","$env:LOCALAPPDATA\Microsoft\Windows\WER\Temp","$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations","$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations") }
            "Prefetch Files" { $paths = @("$env:SystemRoot\Prefetch") }
            "Thumbnail Cache" { $paths = @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer") }
            "CBS Log Files" { $paths = @("$env:SystemRoot\Logs\CBS") }
            "Memory Dumps (*.dmp)" { $paths = @("$env:SystemRoot") }
            "Recent Files List" { $paths = @("$env:APPDATA\Microsoft\Windows\Recent") }
            "Windows Update Cleanup" { $paths = @("$env:SystemRoot\SoftwareDistribution\Download","$env:SystemRoot\SoftwareDistribution\DataStore\Logs") }
            "Windows Defender History" { $paths = @("$env:ProgramData\Microsoft\Windows Defender\Scans\History") }
            "Delivery Optimization" { $paths = @("$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache","$env:ProgramData\Microsoft\Windows\DeliveryOptimization\Cache") }
            "Chrome Cache" { $paths = @("$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache","$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache","$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache") }
            "Firefox Cache" { $paths = @("$env:LOCALAPPDATA\Mozilla\Firefox\Profiles") }
            "Edge Cache" { $paths = @("$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache","$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache","$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache","$env:LOCALAPPDATA\Microsoft\Windows\INetCache","$env:LOCALAPPDATA\Microsoft\Windows\WebCache") }
            "DirectX Shader Cache" { $paths = @("$env:LOCALAPPDATA\D3DSCache","$env:LOCALAPPDATA\Microsoft\Direct3D\ShaderCache") }
            "AMD Shader Cache" { $paths = @("$env:LOCALAPPDATA\AMD\DxCache","$env:LOCALAPPDATA\AMD\GLCache","$env:LOCALAPPDATA\AMD\VkCache") }
            "NVIDIA Shader Cache" { $paths = @("$env:LOCALAPPDATA\NVIDIA\GLCache","$env:LOCALAPPDATA\NVIDIA\DXCache","$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache") }
            "Intel Shader Cache" { $paths = @("$env:LOCALAPPDATA\Intel\ShaderCache","$env:LOCALAPPDATA\Intel\IGCCache") }
            "Microsoft Teams Cache" { $paths = @("$env:APPDATA\Microsoft\Teams\Cache","$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe") }
            "Slack Cache" { $paths = @("$env:APPDATA\Slack\Cache") }
            "Broken Desktop Shortcuts" { $paths = @("$env:USERPROFILE\Desktop","$env:PUBLIC\Desktop") }
            "Broken Start Menu Shortcuts" { $paths = @("$env:APPDATA\Microsoft\Windows\Start Menu","$env:ProgramData\Microsoft\Windows\Start Menu") }
            "DNS Cache" { return " [Special]" }
            "Network Cache" { return " [Special]" }
            "Recycle Bin" { return " [Special]" }
            default { $paths = @() }
        }
        $total = 0; $found = $false
        foreach ($p in $paths) {
            if (Test-Path $p -EA SilentlyContinue) {
                $found = $true
                try { $items = Get-ChildItem -LiteralPath $p -Recurse -Force -EA SilentlyContinue | Where-Object { -not $_.PSIsContainer }; $size = ($items | Measure-Object -Property Length -Sum -EA SilentlyContinue).Sum; if ($null -ne $size) { $total += $size } } catch {}
            }
        }
        if (-not $found) { return " [Not Found]" }
        if ($total -eq 0) { return " [Empty]" }
        $mb = [math]::Round($total / 1MB, 2)
        if ($mb -ge 1024) { $gb = [math]::Round($mb / 1024, 2); return " [$gb GB]" } else { return " [$mb MB]" }
    } catch { return "" }
}

function Start-TempFilesCleanup {
    param($StatusLabel)
    Write-ColoredHeader "========== TEMP FILES CLEANUP STARTED =========="
    $StatusLabel.Text = "Cleaning temporary files..."; $StatusLabel.Refresh()
    $script:TempFreed = 0.0; $script:TempFiles = 0; $script:TempFolders = 0; $script:TempClearedLocations = [System.Collections.Generic.List[string]]::new()

    function Clean-Location {
        param([string]$Label, [string]$Path, [string]$Filter = "*", [bool]$Recurse = $true)
        if (-not (Test-Path $Path)) { return }
        $getArgs = @{ Path = $Path; ErrorAction = "SilentlyContinue" }
        if ($Filter -ne "*") { $getArgs.Filter = $Filter }
        if ($Recurse) { $getArgs.Recurse = $true }
        $before = @(Get-ChildItem @getArgs); $beforeSize = ($before | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum -EA SilentlyContinue).Sum; $beforeFiles = ($before | Where-Object { -not $_.PSIsContainer }).Count; $beforeDirs  = ($before | Where-Object {  $_.PSIsContainer }).Count
        if ($null -eq $beforeSize) { $beforeSize = 0 }; if ($beforeFiles -eq 0 -and $beforeDirs -eq 0) { return }

        Get-ChildItem @getArgs | Where-Object { $_.FullName -ne $script:LogPath } | Remove-Item -Recurse -Force -EA SilentlyContinue

        $after = @(Get-ChildItem @getArgs); $afterSize = ($after | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum -EA SilentlyContinue).Sum
        if ($null -eq $afterSize) { $afterSize = 0 }
        $freed = [math]::Round(($beforeSize - $afterSize) / 1MB, 2); $filesClean = $beforeFiles - ($after | Where-Object { -not $_.PSIsContainer }).Count
        $script:TempFreed += $freed; $script:TempFiles += $filesClean; $script:TempFolders += $beforeDirs

        $sizeStr = if ($freed -ge 1024) { "$([math]::Round($freed/1024,2)) GB" } else { "$freed MB" }
        Write-ToResults "  [OK] $Label"; Write-ToResults "       Files removed : $filesClean   Folders : $beforeDirs   Freed : $sizeStr"
        if ($filesClean -gt 0 -or $beforeDirs -gt 0) { $script:TempClearedLocations.Add("$Label ($filesClean files, $sizeStr)") }
    }

    Write-ColoredSubCategory "--- System Temp Folders ---"
    Clean-Location "Windows Temp" "$env:SystemRoot\Temp"; Clean-Location "Prefetch (.pf files)" "$env:SystemRoot\Prefetch" -Filter "*.pf" -Recurse $false; Clean-Location "Windows Error Reports" "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"; Clean-Location "WER Queue" "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"; Clean-Location "CBS Logs" "$env:SystemRoot\Logs\CBS" -Filter "*.log" -Recurse $false; Clean-Location "Memory Dump Files" "$env:SystemRoot" -Filter "*.dmp" -Recurse $false

    Write-ColoredSubCategory "--- User Temp Folders ---"
    Clean-Location "User Temp (%TEMP%)" "$env:TEMP"; Clean-Location "IE / Edge Cache" "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"; Clean-Location "Edge WebCache" "$env:LOCALAPPDATA\Microsoft\Windows\WebCache"; Clean-Location "Thumbnail Cache" "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter "thumbcache_*.db" -Recurse $false; Clean-Location "Recent Files List" "$env:APPDATA\Microsoft\Windows\Recent" -Recurse $false

    Write-ColoredSubCategory "--- Browser Caches ---"
    Clean-Location "Chrome Cache" "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"; Clean-Location "Chrome GPU Cache" "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache"; Clean-Location "Edge Cache" "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"; Clean-Location "Edge GPU Cache" "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache"
    $ffProfiles = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $ffProfiles) { Get-ChildItem $ffProfiles -Directory -EA SilentlyContinue | ForEach-Object { Clean-Location "Firefox Cache ($($_.Name))" "$($_.FullName)\cache2" } }

    Write-ColoredSubCategory "--- Recycle Bin ---"
    try { $shell = New-Object -ComObject Shell.Application; $rb = $shell.Namespace(0xA); $rbSize = ($rb.Items() | ForEach-Object { $_.Size } | Measure-Object -Sum).Sum; if ($null -eq $rbSize) { $rbSize = 0 }; Clear-RecycleBin -Force -EA SilentlyContinue; $rbMB = [math]::Round($rbSize / 1MB, 2); $script:TempFreed += $rbMB; Write-ToResults "  [OK] Recycle Bin emptied : $rbMB MB" } catch { Clear-RecycleBin -Force -EA SilentlyContinue }

    $totalFreedGB = [math]::Round($script:TempFreed / 1024, 2); $sizeDisplay = if ($script:TempFreed -ge 1024) { "$totalFreedGB GB" } else { "$([math]::Round($script:TempFreed,2)) MB" }

    if ($script:TempClearedLocations.Count -gt 0) { Write-ColoredSubCategory "  Locations cleaned:"; foreach ($loc in $script:TempClearedLocations) { Write-ToResults "    [OK] $loc" } }
    Write-ColoredHeader "=========================================="; Write-ColoredSummary "  CLEANUP SUMMARY"; Write-ColoredHeader "=========================================="
    Write-ColoredSummary "  Files removed   : $($script:TempFiles)"; Write-ColoredSummary "  Folders cleared  : $($script:TempFolders)"; Write-ColoredSummary "  Total freed      : $sizeDisplay"
    Write-ColoredHeader "========== TEMP FILES CLEANUP COMPLETE =========="
    $StatusLabel.Text = "Temp cleanup complete - Freed $sizeDisplay"; $StatusLabel.ForeColor = [System.Drawing.Color]::Green
}

 $script:TelemetryDomains = @("vortex.data.microsoft.com", "vortex-win.data.microsoft.com", "telecommand.telemetry.microsoft.com", "telecommand.telemetry.microsoft.com.nsatc.net", "oca.telemetry.microsoft.com", "oca.telemetry.microsoft.com.nsatc.net", "sqm.telemetry.microsoft.com", "sqm.telemetry.microsoft.com.nsatc.net", "watson.telemetry.microsoft.com", "watson.telemetry.microsoft.com.nsatc.net", "redir.metaservices.microsoft.com", "choice.microsoft.com", "choice.microsoft.com.nsatc.net", "df.telemetry.microsoft.com", "reports.wes.df.telemetry.microsoft.com", "wes.df.telemetry.microsoft.com", "services.wes.df.telemetry.microsoft.com", "sqm.df.telemetry.microsoft.com", "telemetry.microsoft.com", "watson.microsoft.com", "watson.ppe.telemetry.microsoft.com", "telemetry.appex.bing.net", "telemetry.urs.microsoft.com", "settings-sandbox.data.microsoft.com", "settings-win.data.microsoft.com", "client.wns.windows.com", "wns.notify.windows.com", "auth.gfx.ms", "login.live.com", "login.msa.nexus.microsoft.com", "mscrl.microsoft.com", "sls.update.microsoft.com", "fe3cr.delivery.mp.microsoft.com", "fe3.delivery.dsp.mp.microsoft.com.nsatc.net", "au.download.windowsupdate.com", "download.windowsupdate.com", "ctldl.windowsupdate.com", "ntp.msn.com", "c.microsoft.com")

function Start-TelemetryBlocking {
    param($StatusLabel, [bool]$Enable)
    $action = if ($Enable) { "BLOCK" } else { "UNBLOCK" }
    Write-ColoredHeader "========== TELEMETRY $action STARTED =========="
    $StatusLabel.Text = if ($Enable) { "Blocking telemetry domains..." } else { "Unblocking telemetry domains..." }; $StatusLabel.Refresh()
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    try {
        if (-not (Test-Path $hostsPath)) { New-Item -Path $hostsPath -ItemType File -Force | Out-Null }
        & attrib.exe -r $hostsPath 2>$null; Copy-Item -Path $hostsPath -Destination "$hostsPath.bak" -Force -EA SilentlyContinue
        if ($Enable) {
            $hostsContent = @(Get-Content $hostsPath -EA Stop); $newLines = @(); $existingEntries = @{}
            foreach ($line in $hostsContent) { $newLines += $line; $trimmed = $line.Trim(); foreach ($domain in $script:TelemetryDomains) { $escaped = [regex]::Escape($domain); if ($trimmed -match "^0\.0\.0\.0\s+$escaped$" -or $trimmed -match "^127\.0\.0\.1\s+$escaped$") { $existingEntries[$domain] = $true; break } } }
            $newEntries = @()
            foreach ($domain in $script:TelemetryDomains) { if (-not $existingEntries.ContainsKey($domain)) { $newEntries += "0.0.0.0 $domain"; Write-ToResults "  [OK] Blocked: $domain" } }
            if ($newEntries.Count -gt 0) { $newLines += ""; $newLines += $newEntries; Set-Content -Path $hostsPath -Value $newLines -Force -Encoding ASCII -EA Stop }
            Write-ColoredHeader "=========================================="; Write-ColoredSummary "  TELEMETRY BLOCKING SUMMARY"; Write-ColoredSummary "  Total domains evaluated: $($script:TelemetryDomains.Count)"; Write-ColoredSummary "  Newly blocked           : $($newEntries.Count)"; Write-ColoredSummary "  Already blocked         : $($existingEntries.Count)"; Write-ColoredHeader "=========================================="
        } else {
            $hostsContent = @(Get-Content $hostsPath -EA Stop); $newContent = @(); $blockedCount = 0
            foreach ($line in $hostsContent) { $trimmed = $line.Trim(); $isTelemetryEntry = $false; foreach ($domain in $script:TelemetryDomains) { $escaped = [regex]::Escape($domain); if ($trimmed -match "^0\.0\.0\.0\s+$escaped$" -or $trimmed -match "^127\.0\.0\.1\s+$escaped$") { $isTelemetryEntry = $true; $blockedCount++; Write-ToResults "  [OK] Unblocked: $domain"; break } }; if (-not $isTelemetryEntry) { $newContent += $line } }
            if ($blockedCount -gt 0) { Set-Content -Path $hostsPath -Value $newContent -Force -Encoding ASCII -EA Stop }
            Write-ColoredHeader "=========================================="; Write-ColoredSummary "  TELEMETRY UNBLOCKING SUMMARY"; Write-ColoredSummary "  Domains unblocked: $blockedCount"; Write-ColoredHeader "=========================================="
        }
        Start-Process ipconfig.exe -ArgumentList "/flushdns" -Wait -WindowStyle Hidden -EA SilentlyContinue
        Write-ColoredHeader "========== TELEMETRY $action COMPLETE =========="
        $StatusLabel.Text = if ($Enable) { "$($newEntries.Count + $existingEntries.Count) domains blocked" } else { "$blockedCount domains unblocked" }; $StatusLabel.ForeColor = [System.Drawing.Color]::Green
    } catch { Write-ToResults "  [X] Error: $($_.Exception.Message)"; $StatusLabel.Text = "Failed to modify hosts file"; $StatusLabel.ForeColor = [System.Drawing.Color]::Red }
}

function Start-StartupDelay {
    param($StatusLabel)
    $path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize"; $value = Get-ItemProperty -Path $path -Name "StartupDelayInMSec" -EA SilentlyContinue
    if ($null -ne $value -and $null -ne $value.StartupDelayInMSec -and $value.StartupDelayInMSec -gt 0) { Set-ItemProperty -Path $path -Name "StartupDelayInMSec" -Value 0 -Force; Write-ToResults "  [OK] Startup delay DISABLED"; $StatusLabel.Text = "Startup delay disabled" }
    else { if (-not (Test-Path $path)) { $null = New-Item -Path $path -Force }; Set-ItemProperty -Path $path -Name "StartupDelayInMSec" -Value 4000 -Force; Write-ToResults "  [OK] Startup delay ENABLED (4-second stagger)"; $StatusLabel.Text = "Startup delay enabled (4s)" }
    $StatusLabel.ForeColor = [System.Drawing.Color]::Green
}

# ===================================================================
# GUI CREATION & EVENT HANDLERS
# ===================================================================
 $form = New-Object System.Windows.Forms.Form
 $form.Text = "Windows Debloater and System Cleaner"; $form.Size = New-Object System.Drawing.Size(1010, 800); $form.StartPosition = "CenterScreen"; $form.MinimumSize = New-Object System.Drawing.Size(1010, 800); $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30); $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi; $form.StartPosition = "CenterScreen"
 $normalFont = New-Object System.Drawing.Font("Segoe UI", 10); $boldFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold); $titleFont = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
 $titleLabel = New-Object System.Windows.Forms.Label; $titleLabel.Location = New-Object System.Drawing.Point(10, 35); $titleLabel.Size = New-Object System.Drawing.Size(980, 40); $titleLabel.Text = "WINDOWS DEBLOATER AND SYSTEM CLEANER Tool"; $titleLabel.Font = $titleFont; $titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 200, 255); $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter; $titleLabel.Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right); $form.Controls.Add($titleLabel)
 $statusLabel = New-Object System.Windows.Forms.Label; $statusLabel.Location = New-Object System.Drawing.Point(10, 85); $statusLabel.Size = New-Object System.Drawing.Size(980, 30); $statusLabel.Text = "Ready"; $statusLabel.Font = $normalFont; $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 200); $statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter; $statusLabel.Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right); $form.Controls.Add($statusLabel)
 $actionBox = New-Object System.Windows.Forms.GroupBox; $actionBox.Location = New-Object System.Drawing.Point(10, 125); $actionBox.Size = New-Object System.Drawing.Size(980, 178); $actionBox.Text = "Quick Actions"; $actionBox.Font = $boldFont; $actionBox.ForeColor = [System.Drawing.Color]::White; $actionBox.Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right); $form.Controls.Add($actionBox)
 $actionLayout = New-Object System.Windows.Forms.TableLayoutPanel; $actionLayout.Dock = [System.Windows.Forms.DockStyle]::Fill; $actionLayout.ColumnCount = 5; $actionLayout.RowCount = 2
for ($i = 0; $i -lt 5; $i++) { $null = $actionLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 20))) }
 $actionLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50))) | Out-Null; $actionLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50))) | Out-Null; $actionBox.Controls.Add($actionLayout)

function New-ActionButton { param($Text, $Color); $btn = New-Object System.Windows.Forms.Button; $btn.Dock = [System.Windows.Forms.DockStyle]::Fill; $btn.Margin = New-Object System.Windows.Forms.Padding(2, 2, 2, 2); $btn.Text = $Text; $btn.Font = $boldFont; $btn.BackColor = $Color; $btn.ForeColor = [System.Drawing.Color]::White; $btn.FlatStyle = "Flat"; $btn.FlatAppearance.BorderSize = 0; return $btn }
 $statusBtn = New-ActionButton "STATUS" ([System.Drawing.Color]::FromArgb(0, 120, 215)); $fullCleanupBtn = New-ActionButton "FULL CLEANUP" ([System.Drawing.Color]::FromArgb(34, 139, 34)); $blockDomainsBtn = New-ActionButton "BLOCK" ([System.Drawing.Color]::FromArgb(220, 20, 60)); $unblockDomainsBtn = New-ActionButton "UNBLOCK" ([System.Drawing.Color]::FromArgb(34, 139, 34)); $gpoBtn = New-ActionButton "REFRESH GP" ([System.Drawing.Color]::FromArgb(0, 120, 215))
 $cleanTempBtn = New-ActionButton "CLEAN TEMP" ([System.Drawing.Color]::FromArgb(70, 130, 180)); $backupBtn = New-ActionButton "RESTORE POINT" ([System.Drawing.Color]::FromArgb(255, 165, 0)); $scanBtn = New-ActionButton "SYSTEM HEALTH" ([System.Drawing.Color]::FromArgb(0, 120, 215)); $revertAIBtn = New-ActionButton "REVERT AI" ([System.Drawing.Color]::FromArgb(255, 140, 0)); $startupDelayBtn = New-ActionButton "STARTUP DELAY" ([System.Drawing.Color]::FromArgb(218, 165, 32))
 $actionLayout.Controls.Add($statusBtn, 0, 0); $actionLayout.Controls.Add($fullCleanupBtn, 1, 0); $actionLayout.Controls.Add($blockDomainsBtn, 2, 0); $actionLayout.Controls.Add($unblockDomainsBtn, 3, 0); $actionLayout.Controls.Add($gpoBtn, 4, 0)
 $actionLayout.Controls.Add($cleanTempBtn, 0, 1); $actionLayout.Controls.Add($backupBtn, 1, 1); $actionLayout.Controls.Add($scanBtn, 2, 1); $actionLayout.Controls.Add($revertAIBtn, 3, 1); $actionLayout.Controls.Add($startupDelayBtn, 4, 1)

 $tabControl = New-Object System.Windows.Forms.TabControl; $tabControl.Location = New-Object System.Drawing.Point(10, 345); $tabControl.Size = New-Object System.Drawing.Size(980, 365); $tabControl.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30); $tabControl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $tabControl.Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right); $form.Controls.Add($tabControl)
 $tabResults = New-Object System.Windows.Forms.TabPage; $tabResults.Text = "  Results Log  "; $tabResults.BackColor = [System.Drawing.Color]::Black; $tabControl.TabPages.Add($tabResults)
 $resultsBox = New-Object System.Windows.Forms.RichTextBox; $resultsBox.Dock = [System.Windows.Forms.DockStyle]::Fill; $resultsBox.Font = New-Object System.Drawing.Font("Consolas", 9); $resultsBox.BackColor = [System.Drawing.Color]::Black; $resultsBox.ForeColor = [System.Drawing.Color]::FromArgb(0, 255, 100); $resultsBox.ReadOnly = $true; $tabResults.Controls.Add($resultsBox); $script:ResultsBox = $resultsBox
 $progressBar = New-Object System.Windows.Forms.ProgressBar; $progressBar.Location = New-Object System.Drawing.Point(10, 720); $progressBar.Size = New-Object System.Drawing.Size(800, 8); $progressBar.Style = "Continuous"; $progressBar.Anchor = ([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right); $form.Controls.Add($progressBar)
 $authorLabel = New-Object System.Windows.Forms.Label; $authorLabel.Location = New-Object System.Drawing.Point(840, 730); $authorLabel.Size = New-Object System.Drawing.Size(150, 20); $authorLabel.Text = "Peter Lobo"; $authorLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic); $authorLabel.ForeColor = [System.Drawing.Color]::LightGray; $authorLabel.BackColor = [System.Drawing.Color]::Transparent; $authorLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight; $authorLabel.Anchor = ([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right); $form.Controls.Add($authorLabel)

# ===================================================================
# BUTTON EVENT HANDLERS
# ===================================================================
 $fullCleanupBtn.Add_Click({
    if ($script:PendingOp) { return }
    $selectedTasks = $null
    try { $selectedTasks = Show-TaskSelectionWindow -Tasks $script:TaskDefinitions -WindowTitle "Select Cleanup Tasks" -ApplyButtonText "Apply Selected Tasks" -ApplyButtonColor ([System.Drawing.Color]::FromArgb(0, 120, 215)) -HideProfiles $false } catch { Write-ToResults "ERROR opening Task Window: $($_.Exception.Message)"; return }
    if ($null -eq $selectedTasks -or $selectedTasks.Count -eq 0) { Write-ToResults "Full Cleanup cancelled or no tasks selected."; return }
    
    $rpResult = Show-CustomDialog -Message "You selected $($selectedTasks.Count) task(s).`n`nDo you want to create a System Restore Point before starting?" -Title "Create Restore Point?" -Type "YesNo"
    $script:PendingOp = $true
    try {
        $resultsBox.Clear(); $progressBar.Value = 0
        if ($rpResult -eq [System.Windows.Forms.DialogResult]::Yes) { Start-SystemBackup -StatusLabel $statusLabel }

        $backupDir = "C:\DebloatBackups\Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"; New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Write-ToResults "  [*] Backing up registry to $backupDir..."
        & reg export "HKLM\SOFTWARE\Policies" "$backupDir\HKLM_Policies.reg" /y 2>$null | Out-Null
        & reg export "HKCU\Software\Policies" "$backupDir\HKCU_Policies.reg" /y 2>$null | Out-Null
        & reg export "HKCU\Software\Microsoft\Windows\CurrentVersion" "$backupDir\HKCU_CurrentVersion.reg" /y 2>$null | Out-Null
        & reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion" "$backupDir\HKLM_CurrentVersion.reg" /y 2>$null | Out-Null
        Write-ToResults "  [OK] Registry backed up successfully."
        
        $script:Stats.RegistryKeysSet = 0; $script:Stats.ServicesDisabled = 0; $script:Stats.ServicesSkipped = 0; $script:Stats.AppsRemoved = 0; $script:Stats.AppsFailed = 0; $script:Stats.AppsNotFound = 0; $script:FailedApps.Clear()
        $taskCount = $selectedTasks.Count; $progressStep = [math]::Round(100 / $taskCount); $currentProgress = 0; $executedTasks = [System.Collections.ArrayList]::new(); $skippedTasks = [System.Collections.ArrayList]::new(); $alreadyActiveCount = 0; $newlyAppliedCount = 0
        $preCheckResults = @{}

        foreach ($category in $script:TaskDefinitions.Keys) {
            foreach ($subTaskName in $script:TaskDefinitions[$category].Keys) {
                if ($selectedTasks -contains $subTaskName) {
                    $wasActive = $false; $hadCheck = $false
                    if ($script:TaskChecks.ContainsKey($subTaskName)) {
                        try { $wasActive = [bool](& $script:TaskChecks[$subTaskName]); $hadCheck = $true; $preCheckResults[$subTaskName] = $wasActive } catch {}
                    }
                    $prevText = if ($hadCheck) { if ($wasActive) { " [Already Active]" } else { " [Inactive -> will apply]" } } else { "" }
                    Write-ColoredHeader "--- [CATEGORY: $category] ---"; Write-ColoredSubCategory ">>> Executing: $subTaskName$prevText"
                    if ($hadCheck) {
                        if ($wasActive) { Write-ToResults "      Previous state: Already Active (no change needed)" } else { Write-ToResults "      Previous state: Inactive" }
                    }
                    try { & $script:TaskDefinitions[$category][$subTaskName] } catch { Write-ToResults "  [X] ERROR executing ${subTaskName}: $($_.Exception.Message)" }
                    # Post-check
                    if ($hadCheck) {
                        try { $nowActive = [bool](& $script:TaskChecks[$subTaskName]); if ($nowActive -and -not $wasActive) { $newlyAppliedCount++ } elseif ($wasActive) { $alreadyActiveCount++ } } catch {}
                    }
                    $executedTasks.Add($subTaskName) | Out-Null; $currentProgress += $progressStep; if ($currentProgress -gt 100) { $currentProgress = 100 }; $progressBar.Value = $currentProgress; [System.Windows.Forms.Application]::DoEvents()
                } else { $skippedTasks.Add($subTaskName) | Out-Null }
            }
        }
        $progressBar.Value = 100
        Write-ColoredHeader "`r`n========== PRE-CLEANUP STATE =========="
        Write-ColoredSummary "  Already Active before run : $alreadyActiveCount"
        Write-ColoredSummary "  Inactive before run       : $newlyAppliedCount"
        Write-ColoredSummary "  No check available        : $($executedTasks.Count - $alreadyActiveCount - $newlyAppliedCount)"
        Write-ColoredHeader "=========================================="
        Write-ColoredSummary "`r`nTASKS EXECUTED ($($executedTasks.Count)):"; foreach ($t in $executedTasks) {
            $was = $preCheckResults[$t]
            $suffix = if ($null -eq $was) { "" } elseif ($was) { " [was Already Active]" } else { " [was Inactive]" }
            Write-ColoredSummary "  [+] $t$suffix"
        }
        if ($skippedTasks.Count -gt 0) { Write-ColoredSummary "`r`nTASKS SKIPPED ($($skippedTasks.Count)):"; foreach ($t in $skippedTasks) { Write-ColoredSummary "  [-] $t" } }
        Write-ColoredSummary "`r`n  ** RESTART YOUR COMPUTER NOW! **"
        $statusLabel.Text = "Selected cleanup complete - RESTART REQUIRED"; $statusLabel.ForeColor = [System.Drawing.Color]::Green
    } catch { Write-ToResults "FATAL ERROR during cleanup loop: $($_.Exception.Message)" } finally { $script:PendingOp = $false }
})

 $revertAIBtn.Add_Click({
    if ($script:PendingOp) { return }
    $selectedReverts = $null
    try { $selectedReverts = Show-TaskSelectionWindow -Tasks $script:RevertTaskDefinitions -WindowTitle "Select Revert Tasks" -ApplyButtonText "Revert Selected" -ApplyButtonColor ([System.Drawing.Color]::FromArgb(255, 140, 0)) -HideProfiles $true } catch { Write-ToResults "ERROR opening Revert Window: $($_.Exception.Message)"; return }
    if ($null -eq $selectedReverts -or $selectedReverts.Count -eq 0) { Write-ToResults "Revert cancelled or no tasks selected."; return }
    $script:PendingOp = $true
    try {
        $resultsBox.Clear(); $progressBar.Value = 0; Write-ColoredHeader "=== REVERT SELECTED CHANGES ==="
        $taskCount = $selectedReverts.Count; $progressStep = [math]::Round(100 / $taskCount); $currentProgress = 0; $executedTasks = [System.Collections.ArrayList]::new()
        foreach ($category in $script:RevertTaskDefinitions.Keys) {
            foreach ($subTaskName in $script:RevertTaskDefinitions[$category].Keys) {
                if ($selectedReverts -contains $subTaskName) {
                    Write-ColoredSubCategory ">>> Reverting: $subTaskName"
                    try { & $script:RevertTaskDefinitions[$category][$subTaskName]; $executedTasks.Add($subTaskName) | Out-Null } catch { Write-ToResults "  [X] ERROR reverting ${subTaskName}: $($_.Exception.Message)" }
                    $currentProgress += $progressStep; if ($currentProgress -gt 100) { $currentProgress = 100 }; $progressBar.Value = $currentProgress; [System.Windows.Forms.Application]::DoEvents()
                }
            }
        }
        $progressBar.Value = 100
        Write-ColoredSummary "`r`nTASKS REVERTED ($($executedTasks.Count)):"; foreach ($t in $executedTasks) { Write-ColoredSummary "  [+] $t" }
        Write-ColoredSummary "`r`n  Complete! Restart your PC for all changes to take effect."
        Write-ColoredHeader "========== REVERT COMPLETE =========="
        $statusLabel.Text = "Revert complete - restart recommended"; $statusLabel.ForeColor = [System.Drawing.Color]::Orange
    } catch { Write-ToResults "FATAL ERROR during revert loop: $($_.Exception.Message)" } finally { $script:PendingOp = $false }
})

 $startupDelayBtn.Add_Click({ if ($script:PendingOp) { return }; $script:PendingOp = $true; try { $resultsBox.Clear(); Start-StartupDelay -StatusLabel $statusLabel } finally { $script:PendingOp = $false } })
 $cleanTempBtn.Add_Click({
    if ($script:PendingOp) { return }
    $selectedTempTasks = $null
    try { $selectedTempTasks = Show-TaskSelectionWindow -Tasks $script:TempTaskDefinitions -WindowTitle "Select Temp Files to Clean" -ApplyButtonText "Clean Selected" -ApplyButtonColor ([System.Drawing.Color]::FromArgb(70, 130, 180)) -HideProfiles $true } catch { Write-ToResults "ERROR opening Temp Selection Window: $($_.Exception.Message)"; return }
    if ($null -eq $selectedTempTasks -or $selectedTempTasks.Count -eq 0) { Write-ToResults "Temp cleanup cancelled or no tasks selected."; return }
    $script:PendingOp = $true
    try {
        $resultsBox.Clear(); $progressBar.Value = 0
        Write-ColoredHeader "========== TEMP FILES CLEANUP STARTED =========="
        $statusLabel.Text = "Cleaning selected temp files..."; $statusLabel.Refresh()
        $script:TempFreed = 0.0; $script:TempFiles = 0; $script:TempFolders = 0; $script:TempClearedLocations = [System.Collections.Generic.List[string]]::new(); $script:PendingRebootDeletes.Clear(); $script:PendingRebootSize = 0.0; $script:PendingRebootCount = 0
        $taskCount = $selectedTempTasks.Count; $progressStep = [math]::Round(100 / $taskCount); $currentProgress = 0; $executedTasks = [System.Collections.ArrayList]::new()
        foreach ($category in $script:TempTaskDefinitions.Keys) {
            $needsHeader = $false
            foreach ($subTaskName in $script:TempTaskDefinitions[$category].Keys) {
                if ($selectedTempTasks -contains $subTaskName) {
                    if (-not $needsHeader) { Write-ColoredSubCategory "--- $category ---"; $needsHeader = $true }
                    Write-ColoredSubCategory ">>> Cleaning: $subTaskName"
                    try { & $script:TempTaskDefinitions[$category][$subTaskName] } catch { Write-ToResults "  [X] ERROR cleaning ${subTaskName}: $($_.Exception.Message)" }
                    $executedTasks.Add($subTaskName) | Out-Null; $currentProgress += $progressStep; if ($currentProgress -gt 100) { $currentProgress = 100 }; $progressBar.Value = $currentProgress; [System.Windows.Forms.Application]::DoEvents()
                }
            }
        }
        $progressBar.Value = 100
        $totalFreedGB = [math]::Round($script:TempFreed / 1024, 2); $sizeDisplay = if ($script:TempFreed -ge 1024) { "$totalFreedGB GB" } else { "$([math]::Round($script:TempFreed,2)) MB" }
        if ($script:TempClearedLocations.Count -gt 0) { Write-ColoredSubCategory "  Locations cleaned:"; foreach ($loc in $script:TempClearedLocations) { Write-ToResults "    [OK] $loc" } }
        $pendingDisplay = ""
        if ($script:PendingRebootCount -gt 0) {
            $pendingGB = [math]::Round($script:PendingRebootSize / 1024, 2)
            if ($script:PendingRebootSize -ge 1024) { $pendingDisplay = "$pendingGB GB" } else { $pendingDisplay = [string][math]::Round($script:PendingRebootSize,2) + " MB" }
            Write-ColoredScheduled ("  Queued for reboot : " + $script:PendingRebootCount + " files (" + $pendingDisplay + ") - in use - will delete on next start")
            Write-ColoredScheduled "  Files queued for delete on next reboot:"
            foreach ($p in $script:PendingRebootDeletes) { Write-ColoredScheduled ("    [Scheduled] " + $p) }
            Write-ColoredScheduled "  ** RESTART REQUIRED to complete - queued files shown above **"
        }
        Write-ColoredHeader "=========================================="; Write-ColoredSummary "  CLEANUP SUMMARY"; Write-ColoredHeader "=========================================="
        Write-ColoredSummary "  Tasks executed  : $($executedTasks.Count)"; Write-ColoredSummary "  Files removed   : $($script:TempFiles)"; Write-ColoredSummary "  Folders cleared  : $($script:TempFolders)"; Write-ColoredSummary "  Total freed      : $sizeDisplay"
        if ($script:PendingRebootCount -gt 0) {
            Write-ColoredScheduled ("  Queued for reboot : " + $script:PendingRebootCount + " files (" + $pendingDisplay + ")")
            $statusLabel.Text = "Temp cleanup - Freed " + $sizeDisplay + " + " + $script:PendingRebootCount + " queued for reboot (" + $pendingDisplay + ")"
            $statusLabel.ForeColor = [System.Drawing.Color]::Orange
        } else {
            $statusLabel.Text = "Temp cleanup complete - Freed " + $sizeDisplay
            $statusLabel.ForeColor = [System.Drawing.Color]::Green
        }
        Write-ColoredHeader "========== TEMP FILES CLEANUP COMPLETE =========="
    } catch { Write-ToResults "FATAL ERROR during temp cleanup: $($_.Exception.Message)" } finally { $script:PendingOp = $false }
})
 $backupBtn.Add_Click({ if ($script:PendingOp) { return }; $script:PendingOp = $true; try { $resultsBox.Clear(); Start-SystemBackup -StatusLabel $statusLabel } finally { $script:PendingOp = $false } })
 $gpoBtn.Add_Click({ if ($script:PendingOp) { return }; $script:PendingOp = $true; try { $resultsBox.Clear(); Set-RegistryKeySafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows" -Name "CEIPEnable" -Value 0 -Description "CEIP"; Start-Process "gpupdate.exe" -ArgumentList "/force" -Wait -WindowStyle Hidden; Write-ToResults "  [OK] GPUpdate complete" } finally { $script:PendingOp = $false } })

 $blockDomainsBtn.Add_Click({ if ($script:PendingOp) { return }; if ((Show-CustomDialog -Message "Block 39 Microsoft telemetry domains at the network level?" -Title "Block Telemetry Domains" -Type "YesNo") -eq [System.Windows.Forms.DialogResult]::Yes) { $script:PendingOp = $true; try { $resultsBox.Clear(); Start-TelemetryBlocking -StatusLabel $statusLabel -Enable $true } finally { $script:PendingOp = $false } } })
 $unblockDomainsBtn.Add_Click({ if ($script:PendingOp) { return }; if ((Show-CustomDialog -Message "Remove telemetry domain blocks from the hosts file?" -Title "Unblock Telemetry Domains" -Type "YesNo") -eq [System.Windows.Forms.DialogResult]::Yes) { $script:PendingOp = $true; try { $resultsBox.Clear(); Start-TelemetryBlocking -StatusLabel $statusLabel -Enable $false } finally { $script:PendingOp = $false } } })

 $scanBtn.Add_Click({
    if ($script:PendingOp) { return }; $script:PendingOp = $true
    try {
        $resultsBox.Clear(); $progressBar.Value = 0; $statusLabel.Text = "System health..."; Write-ColoredHeader "========== SYSTEM HEALTH =========="
        $osReg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -EA SilentlyContinue; $bios = Get-ItemProperty "HKLM:\HARDWARE\DESCRIPTION\System\BIOS" -EA SilentlyContinue; $cpu = Get-ItemProperty "HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0" -EA SilentlyContinue; $disks = Get-PSDrive -PSProvider FileSystem -EA SilentlyContinue | Where-Object { $_.Root -match '^[A-Z]:\\$' }
        $cpuName = if ($cpu) { $cpu.ProcessorNameString.Trim() } else { "N/A" }; $biosVen = if ($bios) { $bios.BIOSVendor } else { "N/A" }; $sysMfg = if ($bios) { $bios.SystemManufacturer } else { "N/A" }; $sysModel = if ($bios) { $bios.SystemProductName } else { "N/A" }; $osName = if ($osReg) { $osReg.ProductName } else { "Windows" }; $osBuild = if ($osReg) { $osReg.CurrentBuild } else { "?" }
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -Property TotalPhysicalMemory -EA SilentlyContinue; $os = Get-CimInstance -ClassName Win32_OperatingSystem -Property FreePhysicalMemory, LastBootUpTime -EA SilentlyContinue
        $ramTotal = if ($cs) { [math]::Round($cs.TotalPhysicalMemory/1GB,1) } else { "?" }; $ramFree = if ($os) { [math]::Round($os.FreePhysicalMemory/1MB,1) } else { "?" }; $boot = if ($os) { $os.LastBootUpTime } else { $null }; $uptime = if ($boot) { (Get-Date) - $boot } else { $null }; $uptimeStr = if ($uptime) { "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes } else { "N/A" }
        $resultsBox.SelectionColor = [System.Drawing.Color]::FromArgb(100, 200, 255)
        $resultsBox.AppendText("`r`n  Windows   : $osName (Build $osBuild)`r`n  System    : $sysMfg $sysModel`r`n  BIOS      : $biosVen`r`n  Processor : $cpuName`r`n  RAM       : ${ramTotal}GB total ($ramFree GB free)`r`n  Uptime    : $uptimeStr`r`n`r`n")
        foreach ($d in $disks) { $free = [math]::Round($d.Free / 1GB, 1); $total = [math]::Round(($d.Used + $d.Free) / 1GB, 1); $resultsBox.AppendText("  $($d.Name):  ${free}GB free / ${total}GB`r`n") }
        $resultsBox.AppendText("`r`n"); Write-ColoredHeader "========== SYSTEM HEALTH COMPLETE =========="
        $statusLabel.Text = "System health checked"; $statusLabel.ForeColor = [System.Drawing.Color]::Cyan
    } finally { $script:PendingOp = $false }
})

 $statusBtn.Add_Click({
    if ($script:PendingOp) { return }; $script:PendingOp = $true
    try {
        $resultsBox.Clear(); $statusLabel.Text = "Checking system status..."; Write-ColoredHeader "========== SYSTEM STATUS =========="
        $checks = @()
        $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -EA SilentlyContinue).AllowTelemetry; $checks += [PSCustomObject]@{Feature="Telemetry Disabled"; Passed=($v -eq 0)}
        $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -EA SilentlyContinue).DisableAIDataAnalysis; $checks += [PSCustomObject]@{Feature="AI Analysis Disabled"; Passed=($v -eq 1)}
        $v = (Get-Service -Name DiagTrack -EA SilentlyContinue).StartType; $checks += [PSCustomObject]@{Feature="Telemetry Service Disabled"; Passed=($v -eq 'Disabled')}
        $okCount = ($checks | Where-Object { $_.Passed }).Count; $total = $checks.Count; $pct = [math]::Round($okCount/$total*100)
        foreach ($c in $checks) { if ($c.Passed) { $resultsBox.SelectionColor = [System.Drawing.Color]::FromArgb(100, 220, 100); $resultsBox.AppendText("  [OK] $($c.Feature)`r`n") } else { $resultsBox.SelectionColor = [System.Drawing.Color]::FromArgb(255, 80, 80); $resultsBox.AppendText("  [X] $($c.Feature)`r`n") } }
        Write-ColoredSummary "`r`n  Overall Score: ${pct}% ($okCount/$total checks passed)"
        $statusLabel.Text = "Status: ${pct}%"
        if ($pct -ge 90) { $statusLabel.ForeColor = [System.Drawing.Color]::Green } elseif ($pct -ge 50) { $statusLabel.ForeColor = [System.Drawing.Color]::Orange } else { $statusLabel.ForeColor = [System.Drawing.Color]::Red }
    } finally { $script:PendingOp = $false }
})

# ===================================================================
# WELCOME AND SHOW
# ===================================================================
Write-ColoredHeader "========================================"
Write-ColoredHeader "  WINDOWS DEBLOATER AND SYSTEM CLEANER  "
Write-ColoredHeader "========================================"
Write-ToResults "1. Click 'STATUS' for a full system health check."
Write-ToResults "2. Click 'FULL CLEANUP' to select and run tasks."
Write-ToResults "3. Restart your PC when done."

[void]$form.ShowDialog()
