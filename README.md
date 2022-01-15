There are two options to run this version of the script
1. Run script directly on the server where the db is
2. Run script remotely using PowerShell command below:
Specify directory where you store your script on your local machine.
Invoke-Command -FilePath "C:\Scripts\ftp_restore_sql_db.ps1" -ComputerName "computer1"

What the script does:
1.	Checks local directory to see if directory exists (c:\bak)
     a.	if it does not exist it creates directory
     b.	It will download db backup file into this directory
2.	Establishes connection with the ftp server
     a.	Checks ftp server directory for the specified db backup file
     b.	If found Download db backup file into the local directory (c:\bak)
3.	Unzips db backup file
4.	Check sql server db list
     a.	If db is found
     i.	Kill process
    ii.	Set to read only
   iii.	Start db restore
5.	If db restored successfully 
     a.	Send success email
     b.	Else send failed email
6.	Remove db zip and db bak files from the temp directory