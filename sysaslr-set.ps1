# Runs on the lab VM host. -On: force Mandatory ASLR and Bottom-up ASLR system-wide; -Off: back to defaults. Reboots.
param([switch]$On, [switch]$Off)
if ($On) { Set-ProcessMitigation -System -Enable ForceRelocateImages, BottomUp; 'set: ForceRelocateImages + BottomUp ON' }
if ($Off) { Set-ProcessMitigation -System -Disable ForceRelocateImages, BottomUp; 'set: ForceRelocateImages + BottomUp OFF (defaults)' }
$m = (Get-ProcessMitigation -System).ASLR
"registry says: ForceRelocateImages=$($m.ForceRelocateImages) BottomUp=$($m.BottomUp)"
'rebooting'
Restart-Computer -Force
