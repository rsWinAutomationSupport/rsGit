Function New-ResourceZip {
   param
   (
      $modulePath,
      $outputDir
   )
   #Read the module name & version
   $module = Import-Module $modulePath -PassThru
   $moduleName = $module.Name
   $version = $module.Version.ToString()
   Remove-Module $moduleName
   
   $zipFilename = ("{0}_{1}.zip" -f $moduleName, $version)
   $outputPath = Join-Path $outputDir $zipFilename
   if ( -not (Test-Path $outputPath) ) 
   { 
      # Code to create an 'acceptable' structured ZIP file for DSC
      # Courtesy of: @Neptune443 (http://blog.cosmoskey.com/powershell/desired-state-configuration-in-pull-mode-over-smb/)
      [byte[]]$data = New-Object byte[] 22
      $data[0] = 80
      $data[1] = 75
      $data[2] = 5
      $data[3] = 6
      [System.IO.File]::WriteAllBytes($outputPath, $data)
      $acl = Get-Acl -Path $outputPath
      
      $shellObj = New-Object -ComObject "Shell.Application"
      $zipFileObj = $shellObj.NameSpace($outputPath)
      if ($zipFileObj -ne $null)
      {
         $target = get-item $modulePath
         # CopyHere might be async and we might need to wait for the Zip file to have been created full before we continue
         # Added flags to minimize any UI & prompts etc.
         $zipFileObj.CopyHere($target.FullName, 0x14)
         do 
         {
            $zipCount = $zipFileObj.Items().count
            Start-sleep -Milliseconds 50
         }
         While ($zipFileObj.Items().count -lt 1)
         [Runtime.InteropServices.Marshal]::ReleaseComObject($zipFileObj) | Out-Null
         Set-Acl -Path $outputPath -AclObject $acl
      }
      else
      {
         Throw "Failed to create the zip file"
      }
   }
   else
   {
      $outputPath = $null
   }
   
   return $outputPath
}

function Get-TargetResource
{
   [OutputType([Hashtable])]
   param (
      [ValidateSet('Present','Absent')]
      [string]
      $Ensure = 'Present',
      [parameter(Mandatory = $true)]
      [string]
      $Source,
      [parameter(Mandatory = $true)]
      [string]
      $Destination,
      [parameter(Mandatory = $true)]
      [string]
      $Branch,
      [parameter(Mandatory = $true)]
      [string]
      $Name,
      [string]
      $DestinationZip,
      [bool]
      $Logging
   )

   try
   {
      $myLogSource = $PSCmdlet.MyInvocation.MyCommand.ModuleName
      New-Eventlog -LogName "DevOps" -Source $myLogSource -ErrorAction SilentlyContinue
   }
   catch {}

   @{
        Name = $Name
        Destination = $Destination
        DestinationZip = $DestinationZip
        Source = $Source
        Ensure = $Ensure
        Branch = $Branch
    }  
}

function Set-TargetResource
{
   param (
      [ValidateSet('Present','Absent')]
      [string]
      $Ensure = 'Present',
      [parameter(Mandatory = $true)]
      [ValidateNotNullOrEmpty()]
      [string]
      $Source,
      [parameter(Mandatory = $true)]
      [ValidateNotNullOrEmpty()]
      [string]
      $Destination,
      [parameter(Mandatory = $true)]
      [string]
      $Branch,
      [parameter(Mandatory = $true)]
      [string]
      $Name,
      [string]
      $DestinationZip,
      [bool]
      $Logging
   )
   try
   {
      $myLogSource = $PSCmdlet.MyInvocation.MyCommand.ModuleName
      New-Eventlog -LogName "DevOps" -Source $myLogSource -ErrorAction SilentlyContinue
   }
   catch {}

   if ($Ensure -eq "Present")
   {
      if ((Get-Service "Browser").status -eq "Stopped" ) 
      {
         
         Get-Job | ? State -match "Completed" | Remove-Job
         $startmode = (Get-WmiObject -Query "Select StartMode From Win32_Service Where Name='browser'").startmode
         if ( $startmode -eq 'disabled' ){ Set-Service -Name Browser -StartupType Manual }
         if($Logging -eq $true) { Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("Starting Browser Service") }
         Start-Service Browser
         if ( (Get-Job "Stop_Browser" -ErrorAction SilentlyContinue).count -eq 0 )
         {
            if($Logging -eq $true) { Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("Creating PSJob to Stop Browser Service") }
            Start-Job -Name "Stop_Browser" -ScriptBlock { Start-Sleep -Seconds 60; Stop-Service Browser; }
         }
      }
      if(($Source.split("/.")[0]) -eq "https:") { $i = 5 } else { $i = 2 }
      if((test-path -Path (Join-Path $Destination -ChildPath ($Source.split("/."))[$i]) -PathType Container) -eq $false) {
         if((Test-Path -Path $Destination) -eq $false) { 
            New-Item $Destination -ItemType Directory -Force 
         }
         chdir $Destination
         if($Logging -eq $true) { Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("$Source : git clone --branch $branch $Source") }
         Start -Wait -NoNewWindow "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "clone --branch $Branch $Source"
      }
      
      else 
      {
         chdir (Join-Path $Destination -ChildPath ($Source.split("/."))[$i])
         if($Logging -eq $true) { Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("$Source : git checkout $branch;git reset --hard; git clean -f -d; git pull") }
         start -Wait 'C:\Program Files (x86)\Git\cmd\git.exe' -ArgumentList "checkout $Branch; reset --hard; clean -f -d; fetch origin $Branch; merge remotes/origin/$Branch"
      }
      if ( -not ([String]::IsNullOrEmpty($DestinationZip)) )
      {
         if($Logging -eq $true) { Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("Starting Resource Zip") }
         $resourceZipPath = New-ResourceZip -modulePath $(Join-Path $Destination -ChildPath ($Source.split("/."))[$i]) -outputDir $DestinationZip 
         if ( $resourceZipPath -ne $null )
         {
            if($Logging -eq $true) { Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("Starting Checksum") }
            Remove-Item -Path ($resourceZipPath + ".checksum") -Force -ErrorAction SilentlyContinue
            New-Item -Path ($resourceZipPath + ".checksum") -ItemType file
            $hash = (Get-FileHash -Path $resourceZipPath).Hash
            [System.IO.File]::AppendAllText(($resourceZipPath + '.checksum'), $hash)
         }
      }
   }
   if ($Ensure -eq "Absent")
   {
      if(($Source.split("/.")[0]) -eq "https:") { $i = 5 } else { $i = 2 }
      if($Logging -eq $true) { Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("Removing git") }
      remove-item -Path (Join-Path $Destination -ChildPath ($Source.split("/."))[$i]) -Recurse -Force
   }
}

function Test-TargetResource
{
    [OutputType([boolean])]
    param (
        [ValidateSet('Present','Absent')]
        [string]
        $Ensure = 'Present',
        [parameter(Mandatory = $true)]
        [string]
        $Source,
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Destination,
        [parameter(Mandatory = $true)]
        [string]
        $Branch,
        [parameter(Mandatory = $true)]
        [string]
        $Name,
        [string]
        $DestinationZip,
        [bool]
        $Logging
    )

    $RepoPath = $Destination + $Name

    try
    {
        $myLogSource = $PSCmdlet.MyInvocation.MyCommand.ModuleName
        New-Eventlog -LogName "DevOps" -Source $myLogSource -ErrorAction SilentlyContinue
    }
    catch {}

    Write-Verbose "Start Test-TargetResource path: $RepoPath"
    
    if (-not (IsGitRepoUpToDate -RepoPath $RepoPath -Source $Source))
    {
        return $false
    }

    return $true
}

function IsGitRepoUpToDate
{
    param(
    	[Parameter(Position=0,Mandatory = $true)][string]$RepoPath,
        [Parameter(Position=1,Mandatory = $true)][string]$Source
    ) 
    
    if (VerifyGitRepo -RepoPath $RepoPath -Source $Source)
    {
        Set-Location $RepoPath
        $update = ExecGit "fetch origin"
        
        if ($update.Length -ne 0)
        {
            Write-Verbose "Origin has been updated:`n$update"
        }
        
        $local = ExecGit "rev-parse HEAD"
        $remote = ExecGit "rev-parse origin/master"
        
        Write-Verbose "Comparing comits:`n - Local commit:  $local - Remote commit: $remote"
        
        if ($local -eq $remote)
        {
            Write-Verbose "Latest local commit matches remote. Checking for uncommited local changes..."
            
            $statusOutput = ExecGit "status"
            if (-not ($statusOutput.Contains("nothing to commit")))
            {
                Write-Verbose "Local repo contains uncommited changes! `n$statusOutput"
                return $false
            }
            else
            {
                return $true
            }
        }
        else
        {
            Write-Verbose "Local repository does not match remote!"
            return $false
        }
    }
    else
    {
        return $false
    }
}

function VerifyGitRepo
{
    # Confirm that local repository settings are as per current DSC configuration
    #
    param(
		[Parameter(Position=0,Mandatory = $true)][string]$RepoPath,
        [Parameter(Position=1,Mandatory = $true)][string]$Source
	) 

    Write-Verbose "Checking local repository path..."
	if(Test-Path "$RepoPath")
    {
        Set-Location $RepoPath
	    $output = ExecGit "status"
        $outputRemote = ExecGit "remote -v"       
    }
    else
    {
        Write-Verbose "Invalid repository path specified: $RepoPath"
        Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Error -EventId 1000 -Message ("Invalid repository path specified: $RepoPath")
        return $false
    }

    if(-not ($outputRemote.Contains("origin	$Source (fetch)")))
    {
        Write-Verbose "Source repository settings do not match:`nLocal setting: $outputRemote `nDSC Setting: $Source"
        return $false
    }
	
    if ($output.Contains("fatal"))
	{
		Write-Verbose " `n$output"
        Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Error -EventId 1000 -Message ("$RepoPath `n $output")
		return $false
	}

	return $true
}

function ExecGit
{
	param(
		[Parameter(Mandatory = $true)][string]$args
	)

    # Conifugraiton and DSC resource-wide variables
    . ($PSScriptRoot + "\RS_rsGit_settings.ps1")
    $gitCmd = $global:gitExe
    $location = Get-Location

    try
    {
        #Check if location specified for git executable is valid
	    if (CheckCommand $gitCmd)
	    {
	    	Write-Verbose "Executing: git $args"

	        # Capture git output
	        $psi = New-object System.Diagnostics.ProcessStartInfo 
	        $psi.CreateNoWindow = $true 
	        $psi.UseShellExecute = $false 
	        $psi.RedirectStandardOutput = $true 
	        $psi.RedirectStandardError = $true 
	        $psi.FileName = $gitCmd
            $psi.WorkingDirectory = $location.ToString()
	        $psi.Arguments = $args
	        $process = New-Object System.Diagnostics.Process 
	        $process.StartInfo = $psi
	        $process.Start() | Out-Null
	        $process.WaitForExit()
	        $output = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()

	        return $output
	    }
	    else
	    {
            Write-Verbose "Git executable not found at $((get-command $gitCmd).path) `n"
            Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Error -EventId 1000 -Message ("Git executable not found at $((get-command $gitCmd).path)")
            Throw "Git executable not found at $((get-command $gitCmd).path)"
	    }
    }
    catch
    {
        Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Error -EventId 1000 -Message ("Git client execution failed with the following error:`n $($Error[0].Exception)")
        return "fatal: Git executable not found"
    }
}

function CheckCommand
{
	Param ($command)

	$oldPreference = $ErrorActionPreference
	$ErrorActionPreference = 'stop'

	try 
	{
		if(Get-Command $command)
		{
			return $true
		}
	}
	Catch 
	{
		return $false
	}
	Finally {
		$ErrorActionPreference=$oldPreference
	}
} 

Export-ModuleMember -Function *-TargetResource