$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$settingsFile = Join-Path $projectRoot '.env.sensor'
$pythonw = Join-Path $projectRoot '.venv-sensor\Scripts\pythonw.exe'
$simulator = Join-Path $PSScriptRoot 'sensor_simulator.py'
$taskName = 'CampusFlow Sensor'
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

if (-not (Test-Path -LiteralPath $settingsFile -PathType Leaf)) {
    throw "Missing $settingsFile. Copy .env.sensor.example to .env.sensor and fill in the Supabase and sensor values first."
}
if (-not (Test-Path -LiteralPath $pythonw -PathType Leaf)) {
    throw "Missing $pythonw. Create .venv-sensor and install tools/requirements-sensor.txt first."
}
if (-not (Test-Path -LiteralPath $simulator -PathType Leaf)) {
    throw "Missing simulator script: $simulator"
}

$action = New-ScheduledTaskAction `
    -Execute $pythonw `
    -Argument "`"$simulator`" --headless" `
    -WorkingDirectory $projectRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$principal = New-ScheduledTaskPrincipal `
    -UserId $currentUser `
    -LogonType Interactive `
    -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -RestartCount 5 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Runs CampusFlow webcam crowd counting after the current Windows user signs in.' `
    -Force | Out-Null

Start-ScheduledTask -TaskName $taskName
Write-Host "Registered and started '$taskName' for $currentUser."
Write-Host "Check the status in: $PSScriptRoot\sensor_simulator.log"
Write-Host 'The scanner runs hidden and continues only while this Windows user is signed in and the laptop is awake.'

