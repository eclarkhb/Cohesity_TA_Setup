#
# TA Lab Environment Setup Script for VMWare Demos
# Eric Clark
# Last Update 10/2/2020
#
# Tested with 6.5.1b Cloud Demo - Azure
# Instructions: 
#.  Once Lab is ready, add Azure Cloud Archive Source 
#.  Then execute this script 
#
# This script does the following:
# - set up cohesity-01 & cohesity-02 as replication targets
# - Create a local SMB Share & add it as a source with some files
# - Create an SMB View, Blacklist mp3 files
# - Mount the View to Z:\ & create some editable files to show Previous Versions capability
# - Modify Gold Policy to backup every 20 minutes
# - Modify Bronze Policy to backup once an hour
# - Create a 25 Minute NAS Policy
# - Add Replication to Gold, Bronze & 25Min NAS Policies
# - Add Cloud Archive to Gold & 25Min NAS Policies
# - Create Ptoection Group for CohesityView

# Make sure we have the latest Cohesity Module
echo "Updating Cohesity Powershell Module"
Update-Module -Name “Cohesity.PowerShell”

# Setup Cohesity Credentials
$username = "admin"
# For 6.5.1 Lab:
$password = "TechAccel1!"
$secstr = New-Object -TypeName System.Security.SecureString
$password.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $username, $secstr

### Configure Remote Clusters for Replication & Remote Management

Echo "Configuring Replication & Remote Management"
# Connect to cohesity-02
Connect-CohesityCluster -Server 172.16.3.102 -Credential ($cred)
$StorageDomain = get-CohesityStorageDomain

# Create replication from cohesity02 -> cohesity-01
Register-CohesityRemoteCluster -RemoteClusterIps 172.16.3.101 -RemoteClusterCredential ($cred) -EnableReplication -EnableRemoteAccess -StorageDomainPairs @{LocalStorageDomainId=$storagedomain.id;LocalStorageDomainName="DefaultStorageDomain";RemoteStorageDomainId=$storagedomain.id;RemoteStorageDomainName="DefaultStorageDomain"}
# Save Cohesity-02 Configuration
$cohesity02 = get-CohesityClusterConfiguration

#Add Data Security User
New-CohesityUser -Name CISO -Roles COHESITY_DATA_SECURITY -EmailAddress "test@cohesity.com" -Password "TechAccel1!"

# Done with cohesity-02

# Connect to cohesity-01
Connect-CohesityCluster -Server 172.16.3.101 -Credential ($cred)

# Create replication from cohesity02 -> cohesity-02
Register-CohesityRemoteCluster -RemoteClusterIps 172.16.3.102 -RemoteClusterCredential ($cred) -EnableReplication -EnableRemoteAccess -StorageDomainPairs @{LocalStorageDomainId=$storagedomain.id;LocalStorageDomainName="DefaultStorageDomain";RemoteStorageDomainId=$storagedomain.id;RemoteStorageDomainName="DefaultStorageDomain"}

#Add Data Security User
New-CohesityUser -Name CISO -Roles COHESITY_DATA_SECURITY -EmailAddress "test@cohesity.com" -Password "TechAccel1!"

# Set up local smb share 

echo "Setting up local SMB Share c:\smb_share & creating files"
Mkdir c:\smb_share 
Net share smb_share=c:\smb_share /grant:everyone,FULL 
CD C:\smb_share 
For ($I=1;$I -le 100;$i++) {fsutil file createnew “file$i.tmp” 1000} 

# Register smb source
echo "Registering SMB Source"
$smbusername = "TALABS\Administrator"
$smbpassword = "TechAccel1!"
$smbsecstr = New-Object -TypeName System.Security.SecureString
$smbpassword.ToCharArray() | ForEach-Object {$smbsecstr.AppendChar($_)}
$smbcred = new-object -typename System.Management.Automation.PSCredential -argumentlist $smbusername, $smbsecstr

Register-CohesityProtectionSourceSMB -Credential $smbcred -MountPath "\\adc.talabs.local\smb_share" 

# Create Cohesity SMB View
echo "Creating CohesityView"
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
echo "Mounting the View to Z: & Creating some files"
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

# Set up Policies
echo "Setting Gold, Bronze & 25Min NAS Policies"
new-CohesityProtectionPolicy -PolicyName "25Min NAS" -BackupInHours 1 -RetainInDays 1 -Confirm:$false 

$gold = get-CohesityProtectionPolicy -Names Gold
$bronze = get-CohesityProtectionPolicy -Names Bronze
$naspolicy = get-CohesityProtectionPolicy -Names "25Min NAS"

# Set Retention 
$gold.IncrementalSchedulingPolicy.ContinuousSchedule.BackupIntervalMins = 20
$gold.DaysToKeep = 1
$bronze.IncrementalSchedulingPolicy.Periodicity = [Cohesity.Model.SchedulingPolicy+PeriodicityEnum]::KContinuous
$bronze.IncrementalSchedulingPolicy.DailySchedule = $null
$bronze.IncrementalSchedulingPolicy.ContinuousSchedule = [Cohesity.Model.ContinuousSchedule]::new()
$bronze.IncrementalSchedulingPolicy.ContinuousSchedule.BackupIntervalMins = 60
$bronze.DaysToKeep = 1
$naspolicy.IncrementalSchedulingPolicy.ContinuousSchedule.BackupIntervalMins = 25

$extretention = @([Cohesity.Model.ExtendedRetentionPolicy]::new(),[Cohesity.Model.ExtendedRetentionPolicy]::new())
$extretention[0].Periodicity = [Cohesity.Model.ExtendedRetentionPolicy+PeriodicityEnum]::KDay
$extretention[0].DaysToKeep = 30
$extretention[0].Multiplier = 1
$extretention[1].Periodicity = [Cohesity.Model.ExtendedRetentionPolicy+PeriodicityEnum]::KMonth
$extretention[1].DaysToKeep = 1096
$extretention[1].Multiplier = 1

$gold.ExtendedRetentionPolicies = $extretention
$naspolicy.ExtendedRetentionPolicies = $extretention

# Add Replication
$snappolicy = [Cohesity.Model.SnapshotReplicationCopyPolicy]::new()
$snappolicy.Periodicity = [Cohesity.Model.ExtendedRetentionPolicy+PeriodicityEnum]::KEvery
$snappolicy.CopyPartial = $true
$snappolicy.DaysToKeep = 30
$snappolicy.Multiplier = 1
$target = [Cohesity.Model.ReplicationTargetSettings]::new()
$target.ClusterID = $cohesity02.id
$target.ClusterName = "cohesity-02"
$snappolicy.Target = $target

$gold.SnapshotReplicationCopyPolicies = $snappolicy
$bronze.SnapshotReplicationCopyPolicies = $snappolicy
$naspolicy.SnapshotReplicationCopyPolicies = $snappolicy

#Add Cloud Archive
$vaultname = "Azure-Hot-Archive"
$vault = get-CohesityVault -VaultName $VaultName

# Only Add archival to the policies if the Vault was created before running this script

If ($vault -ne $null) {
  echo "External Target Found, Adding Cloud Archive to Policies"
  $archpolicy = [Cohesity.Model.SnapshotArchivalCopyPolicy]::new()
  $archpolicy.Periodicity = [Cohesity.Model.ExtendedRetentionPolicy+PeriodicityEnum]::KEvery
  $archpolicy.CopyPartial = $true
  $archpolicy.DaysToKeep = 90
  $archpolicy.Multiplier = 1
  $archtarget = [Cohesity.Model.ArchivalExternalTarget]::new()
  $archtarget.VaultType = [Cohesity.Model.ArchivalExternalTarget+VaultTypeEnum]::KCloud
  $archtarget.VaultId = $Vault.id 
  $archtarget.VaultName = $vaultname 
  $archpolicy.Target = $archtarget
  $gold.SnapshotArchivalCopyPolicies = $archpolicy
  $naspolicy.SnapshotArchivalCopyPolicies = $archpolicy
} Else {
  echo "External Target Not Found"
}

# Set DataLock Policy
$gold.WormRetentionType = [Cohesity.Model.ProtectionPolicy+WormRetentionTypeEnum]::KCompliance

$CISOcred = new-object -typename System.Management.Automation.PSCredential -argumentlist "CISO", $secstr
Connect-CohesityCluster -Server 172.16.3.101 -Credential ($CISOcred)

# Set Policies
$gold | set-CohesityProtectionPolicy
$bronze | set-CohesityProtectionPolicy
$naspolicy | set-CohesityProtectionPolicy

# Reconect as Admin user
Connect-CohesityCluster -Server 172.16.3.101 -Credential ($cred)

# Create Protection Groups

# Create CohesityView Protection Group
echo "Creating Protection Group for CohesityView"
$indexing = [cohesity.model.indexingpolicy]::new()
$indexing.DisableIndexing = $false
$indexing.allowPrefixes = "/"
$ViewJob = New-CohesityProtectionJob -Name "CohesityView" -PolicyId $naspolicy.Id -StorageDomainId $storagedomain.id -ViewName $view.Name
$ViewJob.IndexingPolicy = $indexing
$ViewJob | set-CohesityProtectionJob

# Create Protection Group for BizApp VMs 
echo "Creating Protection Group for BizApp"
$BizApp = get-CohesityProtectionSourceObject -Environments kVMWare -IncludeVMFolders | Where-Object { $_.Name -eq "BizApp" } | Where-Object { $_.VmWareProtectionSource.type -eq 'kFolder' }
$BizAppJob = New-CohesityProtectionJob -Name BizApp -PolicyId $gold.id -StorageDomainId $storagedomain.id -Environment kVMWare -SourceIds $BizApp.id -ParentSourceID $BizApp.ParentId
$BizAppJob.IndexingPolicy = $indexing
$BizAppJob | set-CohesityProtectionJob
