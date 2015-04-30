# This script is responsible for installing a web site on an EC2 server
#
# When a new EC2 server is created, the .zip file that contains the release package is expanded into a temp directory.
# Any .zip files in the temp directory are themselves expanded.
# Then all Deploy.ps1 files in the temp directory (or its sub directories) are executed as follows:
# 
# Deploy.ps1 -version <version> -dbServer <database server name> -dbUsername <user name to access database> -dbUserPassword <password to access database>

Param(
  [Parameter(Mandatory=$False, HelpMessage="Version name of this deployment. Typically the version number generated by for example TeamCity")]
  [string]$version,

  [Parameter(Mandatory=$False, HelpMessage="Name of the database server")]
  [string]$dbServer,

  [Parameter(Mandatory=$False, HelpMessage="User name to be used when accessing the database")]
  [string]$dbUsername,

  [Parameter(Mandatory=$False, HelpMessage="Password to be used when accessing the database")]
  [string]$dbPassword
)

# The implementation of this script will work on a standard Windows Server 2012 installation.
# It installs IIS and then installs the web site on the Default Web Site.
# It does these string replacements in the web.config file, to make it work with the databases etc.
# that have been created:
#
# string in web.config      replaced by parameter
# --------------------		---------------------
# {{Version}}				$version
# {{DbServer}}				$dbServer
# {{DbUsername}}			$dbUsername
# {{DbPassword}}			$dbPassword

# To make this all work, this file must be part of the Visual Studio project. 
# It must have property "Copy to Output Directory" set to "Do not copy", otherwise it will be copied
# to the bin directory and so will be executed twice.
# Also, it must sit in the root directory of the web site. That is, in the same directory as the web.config

Function wait-until-website-has-state([string]$siteName, [string]$state)
{
	do { 
		Start-Sleep -m 50; 
		$webSiteState = (cmd /c %systemroot%\system32\inetsrv\appcmd list site $siteName /text:state) | Out-String
	} while ($webSiteState.Trim() -ne $state)
}

Function get-website-physicalpath([string]$siteName)
{
	$webSitePhysicalPath = (cmd /c %systemroot%\system32\inetsrv\APPCMD list vdirs "$siteName/" /text:physicalPath) | Out-String
	Return [System.Environment]::ExpandEnvironmentVariables($webSitePhysicalPath).Trim()
}

# Find the directory that this script is running in
$scriptpath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptpath

# -------------------
# Install IIS and IIS manager
Import-Module ServerManager
add-windowsfeature web-webserver -includeallsubfeature -logpath $env:temp\webserver_addrole.log
add-windowsfeature web-mgmt-tools -includeallsubfeature -logpath $env:temp\mgmttools_addrole.log

# Reinstall .Net 4.0
# See http://stackoverflow.com/questions/13162545/handler-extensionlessurlhandler-integrated-4-0-has-a-bad-module-managedpipeli
cmd /c %systemroot%\Microsoft.NET\Framework\v4.0.30319\aspnet_regiis.exe -i

# Stop the Default Web Site
cmd /c %systemroot%\system32\inetsrv\appcmd stop site /site.name:"Default Web Site"

# Replace placeholders in the web.config file. Both this Deploy.ps1 file and web.config are assumed to
# sit in the root directory of the web site.
# Note that you must set the encoding to UTF8. If you do not do that, Out-File uses Unicode. As a result, IIS will not be able to
# read the web.config and show a 500.19 - Internal Server Error page

$webConfigPath = "$scriptDir\web.config"
(Get-Content $webConfigPath) | Foreach-Object {$_ `
	-replace '{{Version}}', $version `
	-replace '{{DbServer}}', $dbServer `
	-replace '{{DbUsername}}', $dbUsername `
	-replace '{{DbPassword}}', $dbPassword `
} | Out-File $webConfigPath -encoding UTF8

# Wait until the web site has stopped
wait-until-website-has-state "Default Web Site" "Stopped"

# Remove all its files
$physicalPath = get-website-physicalpath("Default Web Site")
Get-ChildItem $physicalPath -Recurse | Remove-Item -force -Recurse

# Deploy the files to the root directory of the Default Web Site
copy-item "$scriptDir\*" $physicalPath -force -recurse

# Start the web site again
cmd /c %systemroot%\system32\inetsrv\appcmd start site /site.name:"Default Web Site"




