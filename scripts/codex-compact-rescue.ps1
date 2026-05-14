param(
  [int]$PollSeconds = 5,
  [int]$CompactWaitSeconds = 600,
  [int]$AfterStopDelaySeconds = 1,
  [int]$RoundCooldownSeconds = 60,
  [string]$ResumeText = "",
  [ValidateSet("", "5.4-Mini", "5.5")]
  [string]$SwitchModelOnly = "",
  [switch]$Once,
  [switch]$NoFinalResume,
  [switch]$FinalResume,
  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$nativeMouseSource = @'
using System;
using System.Runtime.InteropServices;
public static class NativeMouse {
  [DllImport("user32.dll")]
  public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
}
'@
Add-Type -TypeDefinition $nativeMouseSource -ErrorAction SilentlyContinue

function Write-Log {
  param([string]$Message)
  $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "[$stamp] $Message"
}

function U {
  param([int[]]$CodePoints)
  return -join ($CodePoints | ForEach-Object { [char]$_ })
}

$TextContinue = U @(0x7e7c, 0x7e8c)
$TextCompactMarker = U @(0x4e0a, 0x4e0b, 0x6587, 0x5df2, 0x81ea, 0x52d5, 0x7cbe, 0x7c21)
$TextCompactingA = U @(0x6b63, 0x5728, 0x81ea, 0x52d5, 0x58d3, 0x7e2e, 0x4e0a, 0x4e0b, 0x6587)
$TextCompactingB = U @(0x4e0a, 0x4e0b, 0x6587, 0x6b63, 0x5728, 0x81ea, 0x52d5, 0x7cbe, 0x7c21)
$TextCompactingC = U @(0x6b63, 0x5728, 0x81ea, 0x52d5, 0x7cbe, 0x7c21, 0x4e0a, 0x4e0b, 0x6587)
$TextStop = U @(0x505c, 0x6b62)
$TextPause = U @(0x66ab, 0x505c)
$TextContinueTask = U @(0x7e7c, 0x7e8c, 0x5b8c, 0x6210, 0x4efb, 0x52d9)
$TextComposerPlaceholder = U @(0x8981, 0x6c42, 0x5f8c, 0x7e8c, 0x8ddf, 0x9032, 0x8b8a, 0x66f4)
$TextOtherModels = U @(0x5176, 0x4ed6, 0x6a21, 0x578b)
$TextXHigh = U @(0x8d85, 0x9ad8)

if (-not $ResumeText) {
  $ResumeText = $TextContinue
}

if (-not $FinalResume) {
  $NoFinalResume = $true
}

$HandledTriggerKeys = @{}
$HandledTriggerTtlSeconds = 900
$HandledStatusTtlSeconds = 86400

function Get-RootElement {
  return [System.Windows.Automation.AutomationElement]::RootElement
}

function Get-CodexWindow {
  $root = Get-RootElement
  $windows = $root.FindAll(
    [System.Windows.Automation.TreeScope]::Children,
    [System.Windows.Automation.Condition]::TrueCondition
  )

  foreach ($window in $windows) {
    if ($window.Current.Name -eq "Codex") {
      return $window
    }
  }

  throw "Cannot find the Codex window. Open the Codex desktop app first."
}

function Get-Descendants {
  param(
    [System.Windows.Automation.AutomationElement]$Element
  )

  return $Element.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition
  )
}

function Get-AllUiNodes {
  $root = Get-RootElement
  return $root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition
  )
}

function Find-Node {
  param(
    [object]$Nodes,
    [string]$NameRegex,
    [string]$ControlTypeRegex = ".*",
    [switch]$VisibleOnly,
    [switch]$EnabledOnly
  )

  foreach ($node in $Nodes) {
    $name = $node.Current.Name
    $type = $node.Current.ControlType.ProgrammaticName
    $bounds = $node.Current.BoundingRectangle

    if (-not $name) { continue }
    if ($name -notmatch $NameRegex) { continue }
    if ($type -notmatch $ControlTypeRegex) { continue }
    if ($EnabledOnly -and -not $node.Current.IsEnabled) { continue }
    if ($VisibleOnly -and ($bounds.IsEmpty -or $bounds.Width -le 0 -or $bounds.Height -le 0 -or $bounds.Y -lt -20)) { continue }

    return $node
  }

  return $null
}

function Find-VisibleMenuItemExact {
  param(
    [object]$Nodes,
    [string]$Name
  )

  $matches = @()
  foreach ($node in $Nodes) {
    $bounds = $node.Current.BoundingRectangle
    if (
      $node.Current.ControlType.ProgrammaticName -eq "ControlType.MenuItem" -and
      $node.Current.Name -eq $Name -and
      $node.Current.IsEnabled -and
      -not $bounds.IsEmpty -and
      $bounds.Width -gt 0 -and
      $bounds.Height -gt 0 -and
      $bounds.Y -gt -20
    ) {
      $matches += $node
    }
  }

  return $matches | Sort-Object { $_.Current.BoundingRectangle.X } -Descending | Select-Object -First 1
}

function Click-Node {
  param(
    [System.Windows.Automation.AutomationElement]$Node,
    [string]$Label
  )

  if (-not $Node) {
    throw "Cannot find clickable item: $Label"
  }

  $bounds = $Node.Current.BoundingRectangle
  Write-Log "Click: $Label [$($Node.Current.Name)] @ $($bounds.ToString())"

  if ($WhatIf) {
    return
  }

  $pattern = $null
  if ($Node.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
    $pattern.Invoke()
    Start-Sleep -Milliseconds 250
    return
  }

  if ($bounds.IsEmpty -or $bounds.Width -le 0 -or $bounds.Height -le 0) {
    throw "Item is not visible and cannot be clicked: $Label"
  }

  [System.Windows.Forms.Cursor]::Position = [System.Drawing.Point]::new(
    [int]($bounds.X + ($bounds.Width / 2)),
    [int]($bounds.Y + ($bounds.Height / 2))
  )
  Start-Sleep -Milliseconds 80
  [NativeMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [NativeMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 250
}

function Hover-Node {
  param(
    [System.Windows.Automation.AutomationElement]$Node,
    [string]$Label
  )

  if (-not $Node) {
    throw "Cannot find hover item: $Label"
  }

  $bounds = $Node.Current.BoundingRectangle
  Write-Log "Hover: $Label [$($Node.Current.Name)] @ $($bounds.ToString())"

  if ($WhatIf) {
    return
  }

  if ($bounds.IsEmpty -or $bounds.Width -le 0 -or $bounds.Height -le 0) {
    throw "Item is not visible and cannot be hovered: $Label"
  }

  Move-SmoothToPoint ($bounds.X + ($bounds.Width / 2)) ($bounds.Y + ($bounds.Height / 2))
  Start-Sleep -Milliseconds 900
}

function Move-SmoothToPoint {
  param(
    [double]$X,
    [double]$Y,
    [int]$Steps = 18,
    [int]$StepDelayMilliseconds = 18
  )

  $start = [System.Windows.Forms.Cursor]::Position
  for ($index = 1; $index -le $Steps; $index++) {
    $nextX = $start.X + (($X - $start.X) * $index / $Steps)
    $nextY = $start.Y + (($Y - $start.Y) * $index / $Steps)
    [System.Windows.Forms.Cursor]::Position = [System.Drawing.Point]::new([int]$nextX, [int]$nextY)
    Start-Sleep -Milliseconds $StepDelayMilliseconds
  }
}

function Hover-NodeAtFraction {
  param(
    [System.Windows.Automation.AutomationElement]$Node,
    [double]$XFraction,
    [string]$Label
  )

  if (-not $Node) {
    throw "Cannot find hover item: $Label"
  }

  $bounds = $Node.Current.BoundingRectangle
  Write-Log "Hover: $Label [$($Node.Current.Name)] @ $($bounds.ToString()) fraction=$XFraction"

  if ($WhatIf) {
    return
  }

  if ($bounds.IsEmpty -or $bounds.Width -le 0 -or $bounds.Height -le 0) {
    throw "Item is not visible and cannot be hovered: $Label"
  }

  Move-SmoothToPoint ($bounds.X + ($bounds.Width * $XFraction)) ($bounds.Y + ($bounds.Height / 2))
  Start-Sleep -Milliseconds 750
}

function Hover-BoundsAtFraction {
  param(
    [System.Windows.Rect]$Bounds,
    [double]$XFraction,
    [string]$Name,
    [string]$Label
  )

  Write-Log "Hover: $Label [$Name] @ $($Bounds.ToString()) fraction=$XFraction"

  if ($WhatIf) {
    return
  }

  if ($Bounds.IsEmpty -or $Bounds.Width -le 0 -or $Bounds.Height -le 0) {
    throw "Item is not visible and cannot be hovered: $Label"
  }

  Move-SmoothToPoint ($Bounds.X + ($Bounds.Width * $XFraction)) ($Bounds.Y + ($Bounds.Height / 2))
  Start-Sleep -Milliseconds 750
}

function Click-BoundsAtFraction {
  param(
    [System.Windows.Rect]$Bounds,
    [double]$XFraction,
    [string]$Name,
    [string]$Label
  )

  Write-Log "Click: $Label [$Name] @ $($Bounds.ToString()) fraction=$XFraction"

  if ($WhatIf) {
    return
  }

  if ($Bounds.IsEmpty -or $Bounds.Width -le 0 -or $Bounds.Height -le 0) {
    throw "Item is not visible and cannot be clicked: $Label"
  }

  [System.Windows.Forms.Cursor]::Position = [System.Drawing.Point]::new(
    [int]($Bounds.X + ($Bounds.Width * $XFraction)),
    [int]($Bounds.Y + ($Bounds.Height / 2))
  )
  Start-Sleep -Milliseconds 80
  [NativeMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [NativeMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 650
}

function Click-Point {
  param(
    [double]$X,
    [double]$Y,
    [string]$Label
  )

  Write-Log "Click point: $Label @ $([int]$X),$([int]$Y)"

  if ($WhatIf) {
    return
  }

  [System.Windows.Forms.Cursor]::Position = [System.Drawing.Point]::new([int]$X, [int]$Y)
  Start-Sleep -Milliseconds 80
  [NativeMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [NativeMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 650
}

function Send-KeySequence {
  param([string[]]$Keys)

  foreach ($key in $Keys) {
    Write-Log "Key: $key"
    if (-not $WhatIf) {
      [System.Windows.Forms.SendKeys]::SendWait($key)
    }
    Start-Sleep -Milliseconds 250
  }
}

function Close-OpenMenu {
  if (-not $WhatIf) {
    [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
    Start-Sleep -Milliseconds 250
  }
}

function Set-CodexModelWithAnchoredClicks {
  param(
    [ValidateSet("5.4-Mini", "5.5")]
    [string]$Model
  )

  $button = Get-ModelButton
  $bounds = $button.Current.BoundingRectangle
  $anchorX = $bounds.X + $bounds.Width
  $anchorY = $bounds.Y

  Click-Point ($bounds.X + ($bounds.Width / 2)) ($bounds.Y + ($bounds.Height / 2)) "model menu anchor"
  Start-Sleep -Milliseconds 500

  if ($Model -eq "5.4-Mini") {
    Click-Point $anchorX ($anchorY - 48) "model family row"
    Start-Sleep -Milliseconds 500
    Click-Point ($anchorX - 205) ($anchorY + 36) "other models row"
    Start-Sleep -Milliseconds 500
    Click-Point $anchorX ($anchorY - 30) "GPT-5.4-Mini anchored"
  } else {
    Click-Point $anchorX ($anchorY - 62) "GPT-5.5 anchored"
  }

  Start-Sleep -Seconds 1
  [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
  Start-Sleep -Milliseconds 200

  $current = Get-CurrentModelName
  if ($Model -eq "5.4-Mini" -and $current -match "^5\.4-Mini") {
    Write-Log "Anchored model switch confirmed: $current"
    return $true
  }
  if ($Model -eq "5.5" -and $current -match "^5\.5") {
    Write-Log "Anchored model switch confirmed: $current"
    return $true
  }

  Write-Log "Anchored model switch did not confirm. Current model button: $current"
  return $false
}

function Find-TargetMenuItemAfterHover {
  param(
    [string]$TargetName,
    [int]$Attempts = 5
  )

  for ($index = 0; $index -lt $Attempts; $index++) {
    $allNodes = Get-AllUiNodes
    $target = Find-VisibleMenuItemExact $allNodes $TargetName
    if ($target) {
      return $target
    }
    Start-Sleep -Milliseconds 300
  }

  return $null
}

function Open-SubmenuAndFindTarget {
  param(
    [System.Windows.Automation.AutomationElement]$SubmenuItem,
    [string]$Label,
    [string]$TargetName
  )

  if (-not $SubmenuItem) {
    return $null
  }

  $bounds = $SubmenuItem.Current.BoundingRectangle
  $name = $SubmenuItem.Current.Name

  foreach ($fraction in @(0.5, 0.95, 0.05, 0.95)) {
    Hover-BoundsAtFraction $bounds $fraction $name $Label
    Click-BoundsAtFraction $bounds $fraction $name $Label
    $target = Find-TargetMenuItemAfterHover $TargetName 2
    if ($target) {
      return $target
    }
  }

  return $null
}

function Get-VisibleMenuItemNames {
  $items = @()
  foreach ($node in (Get-AllUiNodes)) {
    $bounds = $node.Current.BoundingRectangle
    if (
      $node.Current.ControlType.ProgrammaticName -eq "ControlType.MenuItem" -and
      $node.Current.Name -and
      -not $bounds.IsEmpty -and
      $bounds.Width -gt 0 -and
      $bounds.Height -gt 0 -and
      $bounds.Y -gt -20
    ) {
      $items += "$($node.Current.Name)@$($bounds.ToString())"
    }
  }
  return ($items -join "; ")
}

function Send-Text {
  param([string]$Text)

  Write-Log "Send text: $Text"
  if ($WhatIf) {
    return
  }

  [System.Windows.Forms.Clipboard]::SetText($Text)
  Start-Sleep -Milliseconds 100
  [System.Windows.Forms.SendKeys]::SendWait("^v")
  Start-Sleep -Milliseconds 100
  [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
}

function Get-ModelButton {
  $window = Get-CodexWindow
  $nodes = Get-Descendants $window
  $button = Find-Node $nodes "^(5\.5|5\.4|GPT)" "ControlType\.Button" -VisibleOnly -EnabledOnly

  if (-not $button) {
    throw "Cannot find the model dropdown button."
  }

  return $button
}

function Get-CurrentModelName {
  try {
    return (Get-ModelButton).Current.Name
  } catch {
    return ""
  }
}

function Open-ModelMenu {
  param([switch]$SkipVerify)

  $button = Get-ModelButton
  $bounds = $button.Current.BoundingRectangle
  $name = $button.Current.Name
  Click-Node $button "model menu"
  Start-Sleep -Milliseconds 500

  if ($SkipVerify) {
    return
  }

  $items = Get-AllUiNodes
  $modelItem = Find-Node $items "^GPT-5\.(4|5)$" "ControlType\.MenuItem" -VisibleOnly -EnabledOnly
  if ($modelItem) {
    return
  }

  Click-BoundsAtFraction $bounds 0.85 $name "model menu retry"
  Start-Sleep -Milliseconds 500

  $items = Get-AllUiNodes
  $modelItem = Find-Node $items "^GPT-5\.(4|5)$" "ControlType\.MenuItem" -VisibleOnly -EnabledOnly
  if ($modelItem) {
    return
  }

  Click-BoundsAtFraction $bounds 0.95 $name "model menu retry 2"
  Start-Sleep -Milliseconds 500
}

function Set-CodexModelWithKeyboard {
  param(
    [ValidateSet("5.4-Mini", "5.5")]
    [string]$Model
  )

  Close-OpenMenu

  $currentBefore = Get-CurrentModelName
  Open-ModelMenu -SkipVerify

  $toModelFamily = @("{DOWN}")
  if ($currentBefore -notmatch [regex]::Escape($TextXHigh)) {
    $toModelFamily = @("{DOWN}", "{DOWN}")
  }

  if ($Model -eq "5.4-Mini") {
    Send-KeySequence ($toModelFamily + @("{RIGHT}", "{DOWN}", "{DOWN}", "{RIGHT}", "{ENTER}"))
    Start-Sleep -Seconds 1

    $current = Get-CurrentModelName
    if ($current -match "^5\.4-Mini") {
      Write-Log "Keyboard model switch confirmed: $current"
      return $true
    }

    Close-OpenMenu
    Write-Log "Keyboard model switch did not confirm. Current model button: $current"
    return $false
  }

  foreach ($sequenceSpec in @(
    "{RIGHT}|{ENTER}",
    "{RIGHT}|{HOME}|{ENTER}",
    "{RIGHT}|{UP}|{ENTER}",
    "{RIGHT}|{DOWN}|{ENTER}"
  )) {
    Close-OpenMenu
    $currentBefore = Get-CurrentModelName
    Open-ModelMenu -SkipVerify

    $toModelFamily = @("{DOWN}")
    if ($currentBefore -notmatch [regex]::Escape($TextXHigh)) {
      $toModelFamily = @("{DOWN}", "{DOWN}")
    }

    $modelSubmenuSequence = $sequenceSpec -split "\|"
    Send-KeySequence ($toModelFamily + $modelSubmenuSequence)
    Start-Sleep -Seconds 1

    $current = Get-CurrentModelName
    if ($current -match "^5\.5") {
      Write-Log "Keyboard model switch confirmed: $current"
      return $true
    }

    Write-Log "Keyboard sequence did not confirm. Current model button: $current"
  }

  Close-OpenMenu
  Write-Log "Keyboard model switch did not confirm. Current model button: $current"
  return $false
}

function Set-CodexModelWithMouse {
  param(
    [ValidateSet("5.4-Mini", "5.5")]
    [string]$Model
  )

  $targetName = "GPT-$Model"
  Open-ModelMenu

  $allNodes = Get-AllUiNodes
  $currentModelItem = $null
  foreach ($modelMenuName in @("GPT-5.5", "GPT-5.4-Mini", "GPT-5.4")) {
    $currentModelItem = Find-VisibleMenuItemExact $allNodes $modelMenuName
    if ($currentModelItem) {
      break
    }
  }

  $currentModelBounds = $null
  if ($currentModelItem) {
    $currentModelBounds = $currentModelItem.Current.BoundingRectangle
    $currentModelName = $currentModelItem.Current.Name
  }

  $target = Find-TargetMenuItemAfterHover $targetName 2
  if (-not $target -and $currentModelBounds) {
    foreach ($fraction in @(0.95, 0.98, 0.85)) {
      Hover-BoundsAtFraction $currentModelBounds $fraction $currentModelName "open model submenu arrow"
      $target = Find-TargetMenuItemAfterHover $targetName 2
      if ($target) {
        break
      }

      if (-not $WhatIf) {
        [System.Windows.Forms.SendKeys]::SendWait("{RIGHT}")
        Start-Sleep -Milliseconds 350
      }
      $target = Find-TargetMenuItemAfterHover $targetName 2
      if ($target) {
        break
      }

      Click-BoundsAtFraction $currentModelBounds $fraction $currentModelName "open model submenu arrow"
      $target = Find-TargetMenuItemAfterHover $targetName 2
      if ($target) {
        break
      }
    }
  }

  if (-not $target -and $Model -eq "5.4-Mini") {
    $allNodes = Get-AllUiNodes
    $otherModels = Find-VisibleMenuItemExact $allNodes $TextOtherModels
    if ($otherModels) {
      $otherBounds = $otherModels.Current.BoundingRectangle
      $otherName = $otherModels.Current.Name
      Hover-BoundsAtFraction $otherBounds 0.95 $otherName "other models"
      $target = Find-TargetMenuItemAfterHover $targetName

      if (-not $target -and $currentModelBounds) {
        $fallbackX = $currentModelBounds.X + ($currentModelBounds.Width / 2)
        $fallbackY = $otherBounds.Y - 51
        Click-Point $fallbackX $fallbackY "$targetName fallback"
        Start-Sleep -Seconds 1
        return
      }
    }
  }

  if (-not $target) {
    $visibleMenuItems = Get-VisibleMenuItemNames
    [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
    Start-Sleep -Milliseconds 200
    throw "Cannot find target model menu item: $targetName. Visible menu items: $visibleMenuItems"
  }

  Click-Node $target $targetName
  Start-Sleep -Seconds 1

  [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
  Start-Sleep -Milliseconds 200

  $current = Get-CurrentModelName
  if ($Model -eq "5.4-Mini" -and $current -match "^5\.4-Mini") {
    Write-Log "Mouse model switch confirmed: $current"
    return $true
  }
  if ($Model -eq "5.5" -and $current -match "^5\.5") {
    Write-Log "Mouse model switch confirmed: $current"
    return $true
  }

  Write-Log "Mouse model switch did not confirm. Current model button: $current"
  return $false
}

function Set-CodexModel {
  param(
    [ValidateSet("5.4-Mini", "5.5")]
    [string]$Model
  )

  $targetName = "GPT-$Model"
  Write-Log "Switch model to $targetName"
  if ($WhatIf) {
    return
  }

  $current = Get-CurrentModelName
  if ($Model -eq "5.4-Mini" -and $current -match "^5\.4-Mini") {
    Write-Log "Already on target model: $current"
    return
  }
  if ($Model -eq "5.5" -and $current -match "^5\.5") {
    Write-Log "Already on target model: $current"
    return
  }

  if ($Model -eq "5.5") {
    for ($attempt = 1; $attempt -le 4; $attempt++) {
      Write-Log "Switch model to $targetName attempt $attempt."

      if (Set-CodexModelWithKeyboard $Model) {
        return
      }

      try {
        if (Set-CodexModelWithMouse $Model) {
          return
        }
      } catch {
        Write-Log "Mouse model switch attempt $attempt failed: $($_.Exception.Message)"
        Close-OpenMenu
      }

      Close-OpenMenu
      Start-Sleep -Seconds 1
    }

    Close-OpenMenu
    throw "Model switch to $targetName was not confirmed. Speed/reasoning fallback was skipped."
  }

  if (Set-CodexModelWithKeyboard $Model) {
    return
  }

  if (Set-CodexModelWithAnchoredClicks $Model) {
    return
  }

  [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
  throw "Model switch to $targetName was not confirmed."
}

function Get-CompactTriggers {
  $window = Get-CodexWindow
  $nodes = Get-Descendants $window
  $matches = @()

  foreach ($node in $nodes) {
    if ($node.Current.ControlType.ProgrammaticName -ne "ControlType.Text") { continue }

    $bounds = $node.Current.BoundingRectangle
    if ($bounds.IsEmpty -or $bounds.Width -le 0 -or $bounds.Height -le 0 -or $bounds.Y -lt -20) { continue }

    $name = $node.Current.Name
    if (-not $name) { continue }

    if ($name -match "Error running remote compact task:.*backend-api/codex/responses/compact|stream disconnected before completion") {
      $matches += $node
      continue
    }

    $trimmed = $name.Trim()
    $isShortStatus = $trimmed.Length -le 48
    if (-not $isShortStatus) { continue }

    if (
      $trimmed -eq $TextCompactingA -or
      $trimmed -eq $TextCompactingB -or
      $trimmed -eq $TextCompactingC -or
      $trimmed -match "^(compacting.*context|context.*compacting|auto.*compact)$"
    ) {
      $matches += $node
      continue
    }
  }

  return $matches
}

function Get-CompactTrigger {
  $triggers = @(Get-CompactTriggers)
  if ($triggers.Count -gt 0) {
    return $triggers[0]
  }

  return $null
}

function Get-CompactTriggerKey {
  param([System.Windows.Automation.AutomationElement]$Trigger)

  if (-not $Trigger) {
    return "missing-trigger"
  }

  $name = [string]$Trigger.Current.Name
  $trimmed = $name.Trim()
  if ($trimmed -match "Error running remote compact task:.*backend-api/codex/responses/compact|stream disconnected before completion") {
    return "error|$trimmed"
  }

  $bounds = $Trigger.Current.BoundingRectangle
  $roundedY = [math]::Round($bounds.Y / 10) * 10
  try {
    $runtimeId = $Trigger.GetRuntimeId()
    if ($runtimeId -and $runtimeId.Count -gt 0) {
      return "status|$trimmed|rid=$($runtimeId -join '.')"
    }
  } catch {
  }

  return "status|$trimmed|y=$roundedY"
}

function Test-HandledTrigger {
  param([System.Windows.Automation.AutomationElement]$Trigger)

  $now = Get-Date
  $visibleStatusKeys = @{}
  foreach ($visibleTrigger in @(Get-CompactTriggers)) {
    $visibleKey = Get-CompactTriggerKey $visibleTrigger
    if ($visibleKey -like "status|*") {
      $visibleStatusKeys[$visibleKey] = $true
    }
  }

  foreach ($key in @($HandledTriggerKeys.Keys)) {
    if ($key -like "status|*") {
      if (-not $visibleStatusKeys.ContainsKey($key) -or $HandledTriggerKeys[$key] -lt $now) {
        $HandledTriggerKeys.Remove($key)
      }
    } elseif ($HandledTriggerKeys[$key] -lt $now) {
      $HandledTriggerKeys.Remove($key)
    }
  }

  $key = Get-CompactTriggerKey $Trigger
  return $HandledTriggerKeys.ContainsKey($key)
}

function Add-HandledTriggerKey {
  param([string]$Key)

  if ($Key -like "status|*") {
    $HandledTriggerKeys[$Key] = (Get-Date).AddSeconds($HandledStatusTtlSeconds)
    Write-Log "Marked visible compact status as handled until it disappears: $Key"
    return
  }

  if ($Key -notlike "error|*") {
    return
  }

  $HandledTriggerKeys[$Key] = (Get-Date).AddSeconds($HandledTriggerTtlSeconds)
  Write-Log "Marked compact error trigger as handled: $Key"
}

function Add-HandledTrigger {
  param([System.Windows.Automation.AutomationElement]$Trigger)

  Add-HandledTriggerKey (Get-CompactTriggerKey $Trigger)
}

function Add-VisibleStatusTriggers {
  $count = 0
  foreach ($visibleTrigger in @(Get-CompactTriggers)) {
    $key = Get-CompactTriggerKey $visibleTrigger
    if ($key -like "status|*") {
      $HandledTriggerKeys[$key] = (Get-Date).AddSeconds($HandledStatusTtlSeconds)
      $count += 1
    }
  }

  if ($count -gt 0) {
    Write-Log "Marked $count visible compact status trigger(s) as handled until they disappear."
  }
}

function Wait-For-CompactMarker {
  param([int]$TimeoutSeconds)

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $window = Get-CodexWindow
    $nodes = Get-Descendants $window
    $markerRegex = ([regex]::Escape($TextCompactMarker) + "|context.*compact")
    $marker = Find-Node $nodes $markerRegex "ControlType\.Text" -VisibleOnly
    if ($marker) {
      Write-Log "Compact marker detected."
      return $true
    }
    Start-Sleep -Seconds 2
  }

  Write-Log "Compact marker was not detected before timeout."
  return $false
}

function Get-NodeIdentity {
  param([System.Windows.Automation.AutomationElement]$Node)

  $name = $Node.Current.Name
  $bounds = $Node.Current.BoundingRectangle

  try {
    $runtimeId = $Node.GetRuntimeId()
    if ($runtimeId -and $runtimeId.Length -gt 0) {
      return "rid:" + ($runtimeId -join ".")
    }
  } catch {
  }

  return "bounds:$name|$([math]::Round($bounds.X)),$([math]::Round($bounds.Y)),$([math]::Round($bounds.Width)),$([math]::Round($bounds.Height))"
}

function Get-CompactMarkerSnapshot {
  $window = Get-CodexWindow
  $nodes = Get-Descendants $window
  $markerRegex = ([regex]::Escape($TextCompactMarker) + "|context.*compact")
  $count = 0
  $maxY = -99999
  $keys = @{}

  foreach ($node in $nodes) {
    $name = $node.Current.Name
    $bounds = $node.Current.BoundingRectangle
    if (-not $name) { continue }
    if ($node.Current.ControlType.ProgrammaticName -ne "ControlType.Text") { continue }
    if ($name -notmatch $markerRegex) { continue }
    if ($bounds.IsEmpty -or $bounds.Width -le 0 -or $bounds.Height -le 0 -or $bounds.Y -lt -20) { continue }

    $count += 1
    $keys[(Get-NodeIdentity $node)] = $true
    if ($bounds.Y -gt $maxY) {
      $maxY = $bounds.Y
    }
  }

  return [pscustomobject]@{ Count = $count; MaxY = $maxY; Keys = $keys }
}

function Test-ActiveCompactingVisible {
  $window = Get-CodexWindow
  $nodes = Get-Descendants $window

  foreach ($node in $nodes) {
    if ($node.Current.ControlType.ProgrammaticName -ne "ControlType.Text") { continue }

    $bounds = $node.Current.BoundingRectangle
    if ($bounds.IsEmpty -or $bounds.Width -le 0 -or $bounds.Height -le 0 -or $bounds.Y -lt -20) { continue }

    $name = $node.Current.Name
    if (-not $name) { continue }

    $trimmed = $name.Trim()
    if ($trimmed.Length -gt 48) { continue }

    if (
      $trimmed -eq $TextCompactingA -or
      $trimmed -eq $TextCompactingB -or
      $trimmed -eq $TextCompactingC -or
      $trimmed -match "^(compacting.*context|context.*compacting|auto.*compact)$"
    ) {
      return $true
    }
  }

  return $false
}

function Get-StopButton {
  $window = Get-CodexWindow
  $nodes = Get-Descendants $window
  $stopRegex = ("^" + [regex]::Escape($TextStop) + "$|^" + [regex]::Escape($TextPause) + "$|^Stop$|^Pause$")
  return Find-Node $nodes $stopRegex "ControlType\.Button" -VisibleOnly -EnabledOnly
}

function Test-StopVisible {
  return [bool](Get-StopButton)
}

function Wait-For-NewCompactMarker {
  param(
    [int]$TimeoutSeconds,
    [int]$BaselineCount,
    [double]$BaselineMaxY,
    [hashtable]$BaselineKeys
  )

  if (-not $BaselineKeys) {
    $BaselineKeys = @{}
  }

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $snapshot = Get-CompactMarkerSnapshot
    $hasNewMarker = $false
    foreach ($key in $snapshot.Keys.Keys) {
      if (-not $BaselineKeys.ContainsKey($key)) {
        $hasNewMarker = $true
        break
      }
    }

    if ($hasNewMarker -or $snapshot.Count -gt $BaselineCount -or $snapshot.MaxY -gt ($BaselineMaxY + 12)) {
      Write-Log "New compact marker detected. Count=$($snapshot.Count) BaselineCount=$BaselineCount MaxY=$($snapshot.MaxY) BaselineMaxY=$BaselineMaxY"
      return $true
    }

    Start-Sleep -Seconds 2
  }

  Write-Log "New compact marker was not detected before timeout."
  return $false
}

function Stop-If-Running {
  $stopButton = Get-StopButton

  if ($stopButton) {
    Click-Node $stopButton "stop/pause"
    Start-Sleep -Seconds $AfterStopDelaySeconds
    return $true
  }

  Write-Log "Stop button not visible; continuing."
  return $false
}

function Click-Continue-Or-Send {
  param([string]$Text)

  $window = Get-CodexWindow
  $nodes = Get-Descendants $window
  $continueRegex = (
    "^" + [regex]::Escape($TextContinueTask) + "$|^" +
    [regex]::Escape($TextContinue) + "$|^Continue"
  )
  $continueButton = Find-Node $nodes $continueRegex "ControlType\.Button|ControlType\.Text" -VisibleOnly -EnabledOnly

  if ($continueButton -and $continueButton.Current.ControlType.ProgrammaticName -eq "ControlType.Button") {
    Click-Node $continueButton "continue"
    return
  }

  $editorRegex = ("ProseMirror|" + [regex]::Escape($TextComposerPlaceholder) + "|Message")
  $editor = Find-Node $nodes $editorRegex "ControlType\.Group|ControlType\.Edit|ControlType\.Text" -VisibleOnly
  if ($editor) {
    Click-Node $editor "composer"
  }

  Send-Text $Text
}

function Invoke-Recovery {
  param([string]$TriggerName = "")

  if ($TriggerName) {
    Write-Log "Compact trigger detected: $TriggerName"
  }
  Write-Log "Starting recovery flow."
  Stop-If-Running | Out-Null
  Set-CodexModel "5.4-Mini"
  $markerBaseline = Get-CompactMarkerSnapshot
  Write-Log "Waiting for compact to finish after 5.4-Mini. BaselineCount=$($markerBaseline.Count) BaselineMaxY=$($markerBaseline.MaxY)"
  Click-Continue-Or-Send $ResumeText
  Wait-For-NewCompactMarker $CompactWaitSeconds $markerBaseline.Count $markerBaseline.MaxY $markerBaseline.Keys | Out-Null
  Stop-If-Running | Out-Null
  Set-CodexModel "5.5"

  if (-not $NoFinalResume) {
    Click-Continue-Or-Send $ResumeText
  }

  Write-Log "Recovery flow finished."
}

Write-Log "Codex compact rescue watcher started. PollSeconds=$PollSeconds RoundCooldownSeconds=$RoundCooldownSeconds Once=$Once FinalResume=$FinalResume WhatIf=$WhatIf"

if ($SwitchModelOnly) {
  Set-CodexModel $SwitchModelOnly
  Write-Log "SwitchModelOnly finished."
  return
}

do {
  try {
    $currentModelName = Get-CurrentModelName
    $currentMarkerSnapshot = Get-CompactMarkerSnapshot
    if ($currentModelName -match "^5\.4-Mini" -and $currentMarkerSnapshot.Count -gt 0) {
      Write-Log "Compact marker already visible while model is $currentModelName; switching back to GPT-5.5."
      Stop-If-Running | Out-Null
      Set-CodexModel "5.5"
      if (-not $NoFinalResume) {
        Click-Continue-Or-Send $ResumeText
      }
      Write-Log "Recovery round complete; waiting $RoundCooldownSeconds seconds before watching for a new round."
      Start-Sleep -Seconds $RoundCooldownSeconds
      continue
    }

    if ($currentModelName -match "^5\.4-Mini") {
      Write-Log "Already on GPT-5.4-Mini; waiting for compact marker instead of switching again."
      Start-Sleep -Seconds $PollSeconds
      continue
    }

    $compactTrigger = Get-CompactTrigger
    if ($compactTrigger) {
      if (Test-HandledTrigger $compactTrigger) {
        Write-Log "Ignoring already-handled compact trigger: $($compactTrigger.Current.Name)"
        Start-Sleep -Seconds $PollSeconds
        continue
      }

      $compactTriggerKey = Get-CompactTriggerKey $compactTrigger
      $compactTriggerName = $compactTrigger.Current.Name
      Invoke-Recovery $compactTriggerName
      Add-HandledTriggerKey $compactTriggerKey
      Add-VisibleStatusTriggers
      if ($Once) {
        break
      }

      Write-Log "Recovery round complete; waiting $RoundCooldownSeconds seconds before watching for a new round."
      Start-Sleep -Seconds $RoundCooldownSeconds
    } else {
      Write-Log "No compact trigger visible."
      Start-Sleep -Seconds $PollSeconds
    }
  } catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    if ($Once) {
      throw
    }
    Start-Sleep -Seconds $PollSeconds
  }
} while (-not $Once)

Write-Log "Watcher stopped."
