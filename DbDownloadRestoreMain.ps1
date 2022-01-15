Write-Host 'Script started'
Write-Host '******'

# create local path for backups
$path = "C:\bak"
Write-Host 'Check if db backup folder path exists '
Write-Host '******'
If(!(test-path $path))
{
      New-Item -ItemType Directory -Force -Path $path
      Write-Host 'Path created'
      Write-Host '******'
}
else
{
    Write-Host 'Path exists'
    Write-Host '******'
}

# for the unzip...
Add-Type -AssemblyName System.IO.Compression.FileSystem
function unzip 
{
    param([string]$zipfile,[string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

# metadata for email params
$SMTP = "smtp.office365.com"
$From = ""
$To = ""
$SubjectSuccess = "DB backup success"
$SubjectFailed = "DB backup failed"
$Body = "Yay"
$Email = New-Object Net.Mail.SmtpClient($SMTP, 587)
$Email.EnableSsl = $true
$Email.Credentials = New-Object System.Net.NetworkCredential("email", "password");

# ftp server information
$ftp = ""
$user = "FTP_Remote"
$pass = ""
$folder = ""
$target = "C:\bak\"

# register get ftp directory function
function Get-FtpDir ($url, $credentials) {
	$request = [Net.WebRequest]::Create($url)
	$request.Method = [System.Net.WebRequestMethods+FTP]::ListDirectory

	if ($credentials) { $request.Credentials = $credentials }
	
	$response = $request.GetResponse()
	$reader = New-Object IO.StreamReader $response.GetResponseStream() 
	
	while(-not $reader.EndOfStream) {
		$reader.ReadLine()
	}
	
	$reader.Close()
	$response.Close()
}

# set crednetials
$credentials = new-object System.Net.NetworkCredential($user, $pass)

# set folder path
$folderPath= $ftp + "/" + $folder + "/"

$files = Get-FTPDir -url $folderPath -credentials $credentials

$webclient = New-Object System.Net.WebClient 
$webclient.Credentials = $credentials 

# set db restore outcome success/failed for email response
$result = $null
###
Write-Host 'Checking for db backup file'
Write-Host '******'

# look for the specified file in ftp directory if == download.
foreach ($file in $files)
{
   if($file -eq "PAUL_TESTING_FTP_COPY_RESTORE.zip")
   {
	    $source = $folderPath + $file  
	    $destination = $target + $file 
	    $webclient.DownloadFile($source, $destination)
    
        Write-Host "DB backup # $file # Downloaded successfully"
        Write-Host '******'
   }
}

# unzzip bk file
# Expand-Archive -Path 'C:\bak\PAUL_TESTING_FTP_COPY_RESTORE.zip' -DestinationPath 'C:\bak\'
Write-Host 'Unzip db backup file'
Write-Host '******'
unzip "C:\bak\PAUL_TESTING_FTP_COPY_RESTORE.zip" "C:\bak"



# db restore 
[ScriptBlock] $global:RestoreDBSMO = {
    param([string] $newDBName, [string] $backupFilePath, [bool] $isNetworkPath = $true)
    try
    {   
        Write-Host 'DB RESTORE STARTED'
        Write-Host '******'
        # Load assemblies
        [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") | Out-Null
        [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoExtended") | Out-Null
        [Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null
        [Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum") | Out-Null
 
        # Create sql server object
        $server = New-Object ('Microsoft.SqlServer.Management.Smo.Server')
 
        #Copy database locally if backup file is on a network share
        if($isNetworkPath)
        {
            $fileName = [IO.Path]::GetFileName($backupFilePath)
            $localPath = Join-Path -Path $server.DefaultFile -ChildPath $fileName
            Copy-Item $backupFilePath $localPath
            $backupFilePath = $localPath
        }
 
        # Create restore object and specify its settings
        $smoRestore = new-object("Microsoft.SqlServer.Management.Smo.Restore")
        $smoRestore.Database = $newDBName
        $smoRestore.NoRecovery = $false;
        $smoRestore.ReplaceDatabase = $true;
        $smoRestore.Action = "Database"
 
        # Create location to restore from
        $backupDevice = New-Object("Microsoft.SqlServer.Management.Smo.BackupDeviceItem") ($backupFilePath, "File")
        $smoRestore.Devices.Add($backupDevice)
 
        # Give empty string a name
        $empty = ""
 
        # Specify new data file (mdf)
        $smoRestoreDataFile = New-Object("Microsoft.SqlServer.Management.Smo.RelocateFile") 
        $defaultData = $server.DefaultFile
        if (($defaultData -eq $null) -or ($defaultData -eq $empty))
        {
            $defaultData = $server.MasterDBPath
        }
        $smoRestoreDataFile.PhysicalFileName = Join-Path -Path $defaultData -ChildPath ($newDBName + "_Data.mdf")
 
        # Specify new log file (ldf)
        $smoRestoreLogFile = New-Object("Microsoft.SqlServer.Management.Smo.RelocateFile")
        $defaultLog = $server.DefaultLog
        if (($defaultLog -eq $null) -or ($defaultLog -eq $empty))
        {
            $defaultLog = $server.MasterDBLogPath
        }
        $smoRestoreLogFile.PhysicalFileName = Join-Path -Path $defaultLog -ChildPath ($newDBName + "_Log.ldf")
 
        # Get the file list from backup file
        $dbFileList = $smoRestore.ReadFileList($server)
 
        # The logical file names should be the logical filename stored in the backup media
        $smoRestoreDataFile.LogicalFileName = $dbFileList.Select("Type = 'D'")[0].LogicalName
        $smoRestoreLogFile.LogicalFileName = $dbFileList.Select("Type = 'L'")[0].LogicalName
 
        # Add the new data and log files to relocate to
        $smoRestore.RelocateFiles.Add($smoRestoreDataFile)
        $smoRestore.RelocateFiles.Add($smoRestoreLogFile)
 
        # Restore the database
        $smoRestore.SqlRestore($server)
 
        $success = "Database restore completed successfully"
        $success
        Write-Host '******'
        $result = "success"
        
    }
    catch [Exception]
    {
       $failed = "Database restore failed:`n`n " + $_.Exception
       $failed
       Write-Host '******'
       $result = 'failed'
    }
}

# load SQL Server SMO assemblies
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo') | out-null

# make connection to sql server/instance
$sqlServer = New-Object ('Microsoft.SqlServer.Management.Smo.Server') "MEDIA-W12s12dev"

# grab all user DBs
$dbs = $sqlServer.databases

Write-Host 'Checking sql server db list'
Write-Host '******'

# foreach loop to loop through all user dbs attached in SQL
foreach ($db in $dbs)
{
# If statement to search for only user dbs with SPContent as part of its name, and exclude the CA database.  Here you would substitute SPContent for the naming convention of your DBs.
    if ($db.Name -eq 'PAUL_TESTING_FTP_COPY_RESTORE')
    {
        Write-Host "DB: $db is found!"
        Write-Host '******'
        $dbname = $db.Name
        $DBObject = $sqlServer.Databases[$dbname]
        #Kill all the DBs processes to allow for database alter
        Write-Host "Killing $dbname Proccess"
        Write-Host '******'
        $sqlServer.KillAllProcesses($dbname)
        #Set db object to ReadOnly set flag as $false; if you want to revert back set flag to $true (read/write)
        Write-Host "Setting $dbname to Read-Only"
        Write-Host '******'
        $DBObject.DatabaseOptions.ReadOnly = $false
        #Alter DB Object
        #$DBObject.Alter()
        #{
        #}
        Write-Host 'Waiting for db restore to start....'
        Write-Host '******'
        # The database to restore and the bak file to restore from
       .$RestoreDBSMO 'PAUL_TESTING_FTP_COPY_RESTORE' "C:\bak\PAUL_TESTING_FTP_COPY_RESTORE.bak" $false
    }
}

# nn db restore success/failure send email
if($result -eq 'success')
{
    $Email.Send($From, $To, $SubjectSuccess, "DB RESTORED SUCCESS")
    Write-Host 'Email has been sent'
    Write-Host '******'
}
elseif($result -eq  'failed')
{
    $Email.Send($From, $To, $SubjectFailed, "DB RESTORED FAILED")
    Write-Host 'Email has been sent'
    Write-Host '******'
}
else
{
    Write-Host 'Sending email failed'
    Write-Host '******'
}

# clean up the files after the restore is completed....POOP
Write-Host 'Removing files'
Write-Host '******'
Remove-Item  "C:\bak\PAUL_TESTING_FTP_COPY_RESTORE.bak" -Force -Confirm:$false
Remove-Item  "C:\bak\PAUL_TESTING_FTP_COPY_RESTORE.zip" -Force -Confirm:$false
Write-Host 'Files Removed'
Write-Host '******'

#Restore orphaned users.
#$cn2 = new-object system.data.SqlClient.SQLConnection("Data Source=media-w12s12dev;Integrated Security=SSPI;Initial Catalog=PAUL_TESTING_FTP_COPY_RESTORE");
#$cmd = new-object system.data.sqlclient.sqlcommand("EXEC sp_change_users_login 'Auto_Fix', [MSResearchUser]", $cn2);
#$cn2.Open();
#if ($cmd.ExecuteNonQuery() -ne -1)
#{
    #echo "Failed";
#}
#$cn2.Close();
Read-Host -Prompt "Press enter to exit"