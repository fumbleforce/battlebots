# Print native Godot crashes the Windows event log recorded in the last hour
# (CI failure diagnostics, #10). Never fails the job itself.
Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=(Get-Date).AddHours(-1)} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'Godot|battlebots' } |
    Select-Object TimeCreated, Message | Format-List
