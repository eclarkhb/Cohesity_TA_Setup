#
# TA Lab Environment Setup Script for VMWare Demos
# Eric Clark
# Last Update 7/23/2020
#
# Tested with 6.4.1b Cloud Demo - Azure
# Instructions: 
#.  Once Lab is ready, add Azure Cloud Archive Source 
#.  Then execute this script 
#
# This script does the following:
# - set up cohesity-01 & cohesity-02 as replication targets
# - Create a local SMB Share & add it as a source with some files
# - Create an SMB View, Blacklist mp3 files
# - Mount the View to Z:\ & create some editable files to show Previous Versions capability
#

# Make sure we have the latest Cohesity Module
Update-Module -Name “Cohesity.PowerShell”

# Setup Cohesity Credentials
$username = "admin"
$password = "admin"
$secstr = New-Object -TypeName System.Security.SecureString
$password.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $username, $secstr

### Configure Remote Clusters for Replication & Remote Management

# Connect to cohesity-02
Connect-CohesityCluster -Server 172.16.3.102 -Credential ($cred)

# Create replication from cohesity02 -> cohesity-01
Register-CohesityRemoteCluster -RemoteClusterIps 172.16.3.101 -RemoteClusterCredential ($cred) -EnableReplication -EnableRemoteAccess -StorageDomainPairs @{LocalStorageDomainId=5;LocalStorageDomainName="DefaultStorageDomain";RemoteStorageDomainId=5;RemoteStorageDomainName="DefaultStorageDomain"}
# Done with cohesity-02

# Connect to cohesity-01
Connect-CohesityCluster -Server 172.16.3.101 -Credential ($cred)

# Create replication from cohesity02 -> cohesity-02
Register-CohesityRemoteCluster -RemoteClusterIps 172.16.3.102 -RemoteClusterCredential ($cred) -EnableReplication -EnableRemoteAccess -StorageDomainPairs @{LocalStorageDomainId=5;LocalStorageDomainName="DefaultStorageDomain";RemoteStorageDomainId=5;RemoteStorageDomainName="DefaultStorageDomain"}

# Set up local smb share 
Mkdir c:\smb_share
Net share smb_share=c:\smb_share /grant:everyone,FULL
CD C:\smb_share
For ($I=1;$I -le 100;$i++) {fsutil file createnew “file$i.tmp” 1000}

# Register smb source
$smbusername = "TALABS\Administrator"
$smbpassword = "TechAccel1!"
$smbsecstr = New-Object -TypeName System.Security.SecureString
$smbpassword.ToCharArray() | ForEach-Object {$smbsecstr.AppendChar($_)}
$smbcred = new-object -typename System.Management.Automation.PSCredential -argumentlist $smbusername, $smbsecstr

Register-CohesityProtectionSourceSMB -Credential $smbcred -MountPath "\\adc.talabs.local\smb_share"

# Create Cohesity SMB View
New-CohesityView -Name 'CohesityView' -StorageDomainName 'DefaultStorageDomain' -AccessProtocol KSMBOnly -BrowsableShares -CaseInsensitiveNames -QosPolicy 'TestAndDev High'
$view = Get-CohesityView -ViewNames CohesityView

# Set SMB Permissions
$permission = [Cohesity.Model.SmbPermission]::new()
$permission.Sid = 'S-1-1-0'
$permission.Type = [Cohesity.Model.SmbPermission+TypeEnum]::KAllow
$permission.Mode = [Cohesity.Model.SmbPermission+ModeEnum]::KFolderSubFoldersAndFiles
$permission.Access = [Cohesity.Model.SmbPermission+AccessEnum]::KFullControl

# Add permissions for the view
$view.SmbPermissionsInfo.Permissions = $permission
$view.SharePermissions = $permission
$view.SmbPermissionsInfo.OwnerSid = 'S-1-5-32-544'

# Blacklist MP3 files
$fileext = [Cohesity.model.FileExtensionFilter]::new()
$fileext.Mode = [Cohesity.Model.FileExtensionFilter+ModeEnum]::KBlacklist
$fileext.FileExtensionsList = {mp3}
$fileext.IsEnabled = $true
$view.FileExtensionFilter = $fileext

# Update the view
$view | Set-CohesityView

# Mount CohesityView locally
net use Z: \\cohesity-01.talabs.local\CohesityView /PERSISTENT:YES

# Create some editable files on CohesityView (to show Previous Versions)
CD Z:\
Echo this is the first file created in Cohesity view > viewtestfile1.txt
Echo this is the second file created in Cohesity view > viewtestfile2.txt
Echo this is the third file created in Cohesity view > viewtestfile3.txt
Echo this is the fourth file created in Cohesity view > viewtestfile4.txt
Echo this is the fifth file created in Cohesity view > viewtestfile5.txt

# Create a fake mp3 file
COPY viewtestfile5.txt C:\Users\Administrator\Desktop\badfile.mp3
