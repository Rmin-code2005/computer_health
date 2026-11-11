#requires -Version 5.1
<#
.SYNOPSIS
 Read-only Windows system health audit with HTML, TXT and JSON reports.
.EXAMPLE
 powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Windows-Full-HealthCheck.ps1
.EXAMPLE
 powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Windows-Full-HealthCheck.ps1 -DeepScan
#>
[CmdletBinding()]
param([switch]$DeepScan,[string]$OutputDirectory = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'WindowsHealthReports'))
$ErrorActionPreference='Continue'
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$base=Join-Path $OutputDirectory "Health-$stamp"
$items=New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Section,[string]$Name,[string]$Status,[object]$Details) {
 $items.Add([pscustomobject]@{Section=$Section;Name=$Name;Status=$Status;Details=([string]$Details)})
 Write-Host "[$Status] $Section / $Name"
}
function Run-Check([string]$Section,[string]$Name,[scriptblock]$Script) {
 try { & $Script } catch { Add-Check $Section $Name 'Unavailable' $_.Exception.Message }
}
function Format-Data($value) { if($null -eq $value){return 'No data'}; return (($value | Format-List * | Out-String -Width 220).Trim()) }
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Add-Check 'General' 'Administrator' $(if($admin){'OK'}else{'Warning'}) $(if($admin){'Elevated'}else{'Run as Administrator for complete results'})
Run-Check 'Windows' 'OS and uptime' {
 $os=Get-CimInstance Win32_OperatingSystem
 $boot=$os.LastBootUpTime
 Add-Check 'Windows' 'OS and uptime' 'Info' "OS: $($os.Caption); Version: $($os.Version); Build: $($os.BuildNumber); Last boot: $boot; Uptime: $([math]::Round(((Get-Date)-$boot).TotalHours,1)) hours"
}
Run-Check 'Windows' 'Activation' {
 $lic=Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" | Where-Object { $_.Name -match 'Windows' } | Select-Object -First 1
 if($lic){Add-Check 'Windows' 'Activation' $(if($lic.LicenseStatus -eq 1){'OK'}else{'Warning'}) "License status code: $($lic.LicenseStatus); $($lic.Name)"}else{Add-Check 'Windows' 'Activation' 'Unavailable' 'Windows license information not exposed'}
}
Run-Check 'Hardware' 'CPU' {
 $cpu=Get-CimInstance Win32_Processor
 Add-Check 'Hardware' 'CPU' 'Info' (($cpu | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,LoadPercentage,MaxClockSpeed | Format-List | Out-String).Trim())
}
Run-Check 'Hardware' 'CPU temperature' {
 $t=Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
 $values=@($t | ForEach-Object { [math]::Round(($_.CurrentTemperature / 10)-273.15,1) })
 Add-Check 'Hardware' 'CPU temperature' 'Info' "ACPI thermal zones (not necessarily CPU die): $($values -join ', ') C"
}
Run-Check 'Hardware' 'RAM' {
 $os=Get-CimInstance Win32_OperatingSystem
 $total=[math]::Round($os.TotalVisibleMemorySize/1MB,2);$free=[math]::Round($os.FreePhysicalMemory/1MB,2)
 $pct=if($total){[math]::Round(100*($total-$free)/$total,1)}else{0}
 Add-Check 'Hardware' 'RAM' $(if($pct -ge 90){'Warning'}else{'OK'}) "Total: $total GB; Free: $free GB; Used: $pct percent"
 $modules=Get-CimInstance Win32_PhysicalMemory | Select-Object Manufacturer,PartNumber,Capacity,Speed
 Add-Check 'Hardware' 'Memory modules' 'Info' (($modules | Format-Table -AutoSize | Out-String).Trim())
}
Run-Check 'Hardware' 'GPU' {
 $gpu=Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,DriverDate,Status,AdapterRAM
 Add-Check 'Hardware' 'GPU' 'Info' (($gpu | Format-List | Out-String).Trim())
}
Run-Check 'Storage' 'Physical disks' {
 $disks=Get-PhysicalDisk -ErrorAction Stop
 foreach($d in $disks){
  Add-Check 'Storage' "Disk $($d.FriendlyName)" $(if($d.HealthStatus -eq 'Healthy'){'OK'}else{'Warning'}) "Health: $($d.HealthStatus); Operational: $($d.OperationalStatus); Type: $($d.MediaType); Bus: $($d.BusType); Size GB: $([math]::Round($d.Size/1GB,1)); Serial: $($d.SerialNumber)"
  try {$r=$d | Get-StorageReliabilityCounter -ErrorAction Stop;Add-Check 'Storage' "Reliability $($d.FriendlyName)" 'Info' (Format-Data $r)}catch{Add-Check 'Storage' "Reliability $($d.FriendlyName)" 'Unavailable' $_.Exception.Message}
 }
}
Run-Check 'Storage' 'Logical disks' {
 foreach($d in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')){
  $pct=if($d.Size){[math]::Round(100*$d.FreeSpace/$d.Size,1)}else{0}
  Add-Check 'Storage' "Volume $($d.DeviceID)" $(if($pct -lt 10){'Warning'}else{'OK'}) "Label: $($d.VolumeName); FS: $($d.FileSystem); Size GB: $([math]::Round($d.Size/1GB,1)); Free GB: $([math]::Round($d.FreeSpace/1GB,1)); Free: $pct percent"
 }
}
Run-Check 'Storage' 'Disk drive status' {
 Add-Check 'Storage' 'Disk drive status' 'Info' ((Get-CimInstance Win32_DiskDrive | Select-Object Model,Status,FirmwareRevision,InterfaceType,Size | Format-List | Out-String).Trim())
}
Run-Check 'Battery' 'Battery status' {
 $b=Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
 if($b){Add-Check 'Battery' 'Battery status' 'Info' (Format-Data ($b | Select-Object Name,BatteryStatus,EstimatedChargeRemaining,EstimatedRunTime))}else{Add-Check 'Battery' 'Battery status' 'Unavailable' 'No battery reported'}
}
Run-Check 'Battery' 'Battery capacity report' {
 $path="$base-battery.html"
 & powercfg.exe /batteryreport /output $path 2>&1 | Out-Null
 if(Test-Path $path){Add-Check 'Battery' 'Battery capacity report' 'Info' "Detailed battery wear report: $path"}else{Add-Check 'Battery' 'Battery capacity report' 'Unavailable' 'Battery report could not be generated'}
}
Run-Check 'Drivers' 'Problem devices' {
 $bad=@(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 })
 Add-Check 'Drivers' 'Problem devices' $(if($bad.Count){'Warning'}else{'OK'}) $(if($bad.Count){($bad | Select-Object Name,ConfigManagerErrorCode,PNPDeviceID | Format-List | Out-String).Trim()}else{'No PnP devices with reported error codes'})
}
Run-Check 'Security' 'Firewall' {
 $fw=Get-NetFirewallProfile | Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction
 Add-Check 'Security' 'Firewall' $(if(@($fw | Where-Object {-not $_.Enabled}).Count){'Warning'}else{'OK'}) (($fw | Format-Table -AutoSize | Out-String).Trim())
}
Run-Check 'Security' 'Defender' {
 $d=Get-MpComputerStatus -ErrorAction Stop
 Add-Check 'Security' 'Defender' $(if($d.AntivirusEnabled -and $d.RealTimeProtectionEnabled){'OK'}else{'Warning'}) "Antivirus enabled: $($d.AntivirusEnabled); Real-time protection: $($d.RealTimeProtectionEnabled); Signatures updated: $($d.AntivirusSignatureLastUpdated); Quick scan age days: $($d.QuickScanAge)"
}
Run-Check 'Security' 'BitLocker' {
 $v=Get-BitLockerVolume -ErrorAction Stop | Select-Object MountPoint,VolumeStatus,ProtectionStatus,EncryptionPercentage
 Add-Check 'Security' 'BitLocker' 'Info' (($v | Format-Table -AutoSize | Out-String).Trim())
}
Run-Check 'Security' 'Secure Boot' {
 $sb=Confirm-SecureBootUEFI -ErrorAction Stop
 Add-Check 'Security' 'Secure Boot' $(if($sb){'OK'}else{'Warning'}) "Enabled: $sb"
}
Run-Check 'Network' 'Adapters and DNS' {
 $n=Get-NetIPConfiguration | Select-Object InterfaceAlias,IPv4Address,IPv4DefaultGateway,DNSServer
 Add-Check 'Network' 'Adapters and DNS' 'Info' (($n | Format-List | Out-String).Trim())
}
Run-Check 'Network' 'Internet HTTPS' {
 $r=Invoke-WebRequest -Uri 'https://www.microsoft.com' -UseBasicParsing -TimeoutSec 12 -ErrorAction Stop
 Add-Check 'Network' 'Internet HTTPS' $(if($r.StatusCode -ge 200 -and $r.StatusCode -lt 400){'OK'}else{'Warning'}) "HTTP $($r.StatusCode)"
}
Run-Check 'Windows Update' 'Update service' {
 $s=Get-Service wuauserv
 Add-Check 'Windows Update' 'Update service' 'Info' "Status: $($s.Status); Start type: $($s.StartType) (stopped may be normal when idle)"
}
Run-Check 'Windows Update' 'Pending updates' {
 $session=New-Object -ComObject Microsoft.Update.Session
 $searcher=$session.CreateUpdateSearcher()
 $searcher.Online=$true
 $result=$searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
 $updates=@($result.Updates | ForEach-Object {$_.Title})
 Add-Check 'Windows Update' 'Pending updates' $(if($updates.Count){'Warning'}else{'OK'}) "Count: $($updates.Count); $($updates -join ' | ')"
}
Run-Check 'Windows Update' 'Recent installed hotfixes' {
 $h=Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 15 HotFixID,Description,InstalledOn
 Add-Check 'Windows Update' 'Recent installed hotfixes' 'Info' (($h | Format-Table -AutoSize | Out-String).Trim())
}
Run-Check 'Windows Update' 'Reboot pending' {
 $paths=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
 $pending=@($paths | Where-Object {Test-Path $_})
 $rename=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
 if($rename){$pending+= 'PendingFileRenameOperations'}
 Add-Check 'Windows Update' 'Reboot pending' $(if($pending.Count){'Warning'}else{'OK'}) $(if($pending.Count){$pending -join '; '}else{'No common reboot-pending flags detected'})
}
Run-Check 'System' 'Recent critical and error events' {
 $ev=@(Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 40 -ErrorAction Stop)
 Add-Check 'System' 'Recent critical and error events' $(if($ev.Count){'Warning'}else{'OK'}) $(if($ev.Count){($ev | Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message | Format-List | Out-String -Width 220).Trim()}else{'No critical/error events in the last 7 days'})
}
Run-Check 'System' 'Component store health (read only)' {
 $out=& dism.exe /Online /Cleanup-Image /CheckHealth 2>&1
 Add-Check 'System' 'Component store health (read only)' $(if($LASTEXITCODE -eq 0){'Info'}else{'Warning'}) (($out | Out-String).Trim())
}
if($DeepScan){
 Run-Check 'System' 'DISM ScanHealth (deep)' {
  $out=& dism.exe /Online /Cleanup-Image /ScanHealth 2>&1
  Add-Check 'System' 'DISM ScanHealth (deep)' $(if($LASTEXITCODE -eq 0){'Info'}else{'Warning'}) (($out | Out-String).Trim())
 }
 Run-Check 'System' 'SFC verify only (deep)' {
  $out=& sfc.exe /verifyonly 2>&1
  Add-Check 'System' 'SFC verify only (deep)' $(if($LASTEXITCODE -eq 0){'Info'}else{'Warning'}) (($out | Out-String).Trim())
 }
 Run-Check 'Storage' 'CHKDSK scan (deep)' {
  $systemDrive=$env:SystemDrive
  $out=& chkdsk.exe $systemDrive /scan 2>&1
  Add-Check 'Storage' 'CHKDSK scan (deep)' $(if($LASTEXITCODE -eq 0){'Info'}else{'Warning'}) (($out | Out-String).Trim())
 }
}
$summary=[ordered]@{Generated=(Get-Date).ToString('o');Computer=$env:COMPUTERNAME;Administrator=$admin;DeepScan=[bool]$DeepScan;Checks=@($items)}
$summary | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath "$base.json" -Encoding UTF8
$txt=@("WINDOWS FULL HEALTH REPORT","Generated: $(Get-Date)","Computer: $env:COMPUTERNAME",'')
foreach($i in $items){$txt+= "[$($i.Status)] $($i.Section) / $($i.Name)`r`n$($i.Details)`r`n"}
$txt | Set-Content -LiteralPath "$base.txt" -Encoding UTF8
function Escape-Html([string]$s){return [System.Net.WebUtility]::HtmlEncode($s)}
$rows=foreach($i in $items){
 $color=switch($i.Status){'OK'{'#167347'}'Warning'{'#b45309'}'Unavailable'{'#a12626'}default{'#355c91'}}
 "<tr><td>$(Escape-Html $i.Section)</td><td>$(Escape-Html $i.Name)</td><td style='color:$color;font-weight:bold'>$(Escape-Html $i.Status)</td><td><pre>$(Escape-Html $i.Details)</pre></td></tr>"
}
$html=@"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Windows Health Report</title><style>body{font-family:Segoe UI,Arial,sans-serif;margin:30px;background:#f5f7fb;color:#182338}h1{margin-bottom:5px}p{color:#526076}table{width:100%;border-collapse:collapse;background:white}th,td{padding:12px;text-align:left;border-bottom:1px solid #e5e7eb;vertical-align:top}th{background:#e9eef6}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-family:Consolas,monospace;font-size:12px;margin:0}tr:hover{background:#f8fafc}</style></head><body><h1>Windows Full Health Report</h1><p>Computer: $(Escape-Html $env:COMPUTERNAME) | Generated: $(Get-Date) | Deep scan: $DeepScan</p><p>Read-only checks. Warning is not necessarily a hardware failure. Update availability depends on Windows Update configuration and connectivity.</p><table><thead><tr><th>Section</th><th>Check</th><th>Status</th><th>Details</th></tr></thead><tbody>$($rows -join "`n")</tbody></table></body></html>
"@
$html | Set-Content -LiteralPath "$base.html" -Encoding UTF8
Write-Host "`nReports generated:" -ForegroundColor Green
Write-Host "$base.html`n$base.txt`n$base.json"
Write-Host 'For a more thorough read-only scan, rerun with -DeepScan.'
