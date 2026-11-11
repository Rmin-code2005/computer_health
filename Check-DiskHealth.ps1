
# Disk Health Diagnostic Script
# Windows PowerShell

$OutputFile = "$env:USERPROFILE\Desktop\DiskHealthReport.txt"

"========== DISK HEALTH REPORT ==========" |
    Out-File $OutputFile

"`n[1] PHYSICAL DISK INFORMATION" |
    Out-File $OutputFile -Append

Get-PhysicalDisk | Format-List `
    FriendlyName,
    SerialNumber,
    MediaType,
    BusType,
    HealthStatus,
    OperationalStatus,
    Size |
    Out-String |
    Out-File $OutputFile -Append

"`n[2] SMART / RELIABILITY COUNTERS" |
    Out-File $OutputFile -Append

foreach ($disk in Get-PhysicalDisk) {
    "`n--- $($disk.FriendlyName) ---" |
        Out-File $OutputFile -Append

    try {
        $disk | Get-StorageReliabilityCounter |
            Format-List * |
            Out-String |
            Out-File $OutputFile -Append
    }
    catch {
        "Reliability counters unavailable: $_" |
            Out-File $OutputFile -Append
    }
}

"`n[3] LOGICAL DISK INFORMATION" |
    Out-File $OutputFile -Append

Get-CimInstance Win32_LogicalDisk |
    Select-Object DeviceID, VolumeName, FileSystem,
        Size, FreeSpace |
    Format-Table -AutoSize |
    Out-String |
    Out-File $OutputFile -Append

"`n[4] DISK STATUS (WMI)" |
    Out-File $OutputFile -Append

Get-CimInstance Win32_DiskDrive |
    Select-Object Model, Status, Size,
        FirmwareRevision, InterfaceType |
    Format-List |
    Out-String |
    Out-File $OutputFile -Append

"`n========== REPORT FINISHED ==========" |
    Out-File $OutputFile -Append

Write-Host "Report saved to: $OutputFile" -ForegroundColor Green
