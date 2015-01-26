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
    
    $RepoPath = (SetRepoPath -Source $Source -Destination $Destination)
    Write-Verbose "Setting Repopath to $RepoPath"

    if (Test-Path $RepoPath)
    {
        if (IsValidRepo -RepoPath $RepoPath)
        {
            Set-Location $RepoPath
            $ensureResult = "Present"
            # Retreive current branch and clean-up output
            $currentBranch = (ExecGit "rev-parse --abbrev-ref HEAD").split()[0]
            Write-Verbose "Branch: $currentBranch"

            # Retrieve current repo origin fetch settings
            # Split output by line; find one that is listed as (fetch); split by space and list just origin URI
            $SourceResult = (((ExecGit -args "remote -v").Split("`n") | Where-Object { $_.contains("(fetch)") }) -split "\s+")[1]

            if (-not ([String]::IsNullOrEmpty($DestinationZip)))
            {
                if (Test-Path $DestinationZip)
                {
                    # Just checking if the file is here - not really doing things properly though
                    $currentDestZip = $DestinationZip
                }
                else
                {
                    $currentDestZip = $null
                }
            }
            else
            {
                $currentDestZip = $null
            }
        }
        else
        {
            $ensureResult = "Absent"
            $currentBranch = $null
            $Destination = $null
            $SourceResult = $null
            if ($DestinationZip)
            {
                $currentDestZip = $null
            }
        }
    }
    else
    {
        $ensureResult = "Absent"
        $currentBranch = $null
        $Destination = $null
        $SourceResult = $null
        if ($DestinationZip)
        {
            $DestinationZip = $null
        }
    }
    
    @{
        Name = $Name
        Destination = $Destination
        DestinationZip = $currentDestZip
        Source = $SourceResult
        Ensure = $ensureResult
        Branch = $currentBranch
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

    $RepoPath = (SetRepoPath -Source $Source -Destination $Destination)
    
    if ($Ensure -eq "Present")
    {
        # Disabling Browser service - need to check if this is needed
        <#
        if ((Get-Service "Browser").status -eq "Stopped" ) 
        {
            Get-Job | ? State -match "Completed" | Remove-Job
            $startmode = (Get-WmiObject -Query "Select StartMode From Win32_Service Where Name='browser'").startmode

            if ( $startmode -eq 'disabled' )
            {
                Set-Service -Name Browser -StartupType Manual 
            }

            Write-Verbose "Starting Browser Service"
            if($Logging -eq $true) 
            {
                Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("Starting Browser Service")
            }
            Start-Service Browser
 
            if ( (Get-Job "Stop_Browser" -ErrorAction SilentlyContinue).count -eq 0 )
            {
                Write-Verbose "Creating PSJob to Stop Browser Service"
                if($Logging -eq $true) 
                {
                    Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("Creating PSJob to Stop Browser Service")
                }
                Start-Job -Name "Stop_Browser" -ScriptBlock 
                {
                    Start-Sleep -Seconds 60
                    Stop-Service Browser
                }
            }
        }
        #>
        
        $GetResult = (Get-TargetResource -Ensure $Ensure -Source $Source -Destination $Destination -Branch $Branch -Name $Name)

        if (($GetResult.Ensure -ne "Present") -or ($GetResult.Source -ne $Source) -or (-not $GetResult.Destination))
        {
            
            if (-not (Test-Path $Destination))
            {
                New-Item $Destination -ItemType Directory -Force
            }
            Set-Location $Destination
            
            if (Test-Path $RepoPath)
            {
                Remove-Item -Path $RepoPath -Recurse -Force
            }
            
            if($Logging) 
            {
                Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("$Source : git clone --branch $branch $Source") 
            }
            $GitOutput = (ExecGit "clone --branch $branch $Source")
            Write-Verbose " `n$GitOutput"
        }
        else
        {
            Set-Location $RepoPath

            # Verify that we are using the correct branch and force-set the correct one - will destroy any uncommited changes
            if ($GetResult.Branch -ne $Branch)
            {
                $GitCheckout = (ExecGit "checkout --force $Branch")
                    if($Logging) 
                {
                    Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("$Source : git checkout --force $Branch `n$GitCheckout") 
                }
                Write-Verbose " `n git checkout --force $Branch `n$GitCheckout"
            }
            
            # Check if origin contains changes which have not been merged locally
            $Fetch = ExecGit "fetch origin"
            if ($Fetch.Length -ne 0)
            {
                if($Logging) 
                {
                    Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Warning -EventId 1000 -Message ("origin/$Branch has pending updates:`n$Fetch") 
                }
                Write-Verbose "origin/$Branch has pending updates:`n$Fetch"
                $RequireUpdate = $true
            }
            else
            {
                $localCommit = ExecGit "rev-parse HEAD"
                $originCommit = ExecGit "rev-parse origin/$Branch"
                if ($localCommit -ne $originCommit)
                {
                    if($Logging) 
                    {
                        Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Warning -EventId 1000 -Message (" `norigin/$Branch and local are not in sync:`nLocal Commit: $localCommit`nOrigin Commit: $originCommit") 
                    }
                    Write-Verbose " `norigin/$Branch and local are not in sync:`nLocal Commit: $localCommit`nOrigin Commit: $originCommit"
                    $RequireUpdate = $true
                }
                $RequireUpdate = $false
            }
            if ($RequireUpdate)
            {
                # Reset local repo to match remote for tracked files
                $GitReset = ExecGit "reset --hard origin/$branch"
                if($Logging) 
                {
                    Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("git reset --hard origin/$Branch :`n$GitReset") 
                }
                Write-Verbose "git reset --hard origin/$Branch :`n$GitReset"
            }
         
            # Check local repo status for local uncommited changes and delete them
            $RepoStatus = ExecGit "status"
            if (-not ($RepoStatus.Contains("working directory clean")))
            {
                if($Logging) 
                {
                    Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("Local repo contains uncommited changes! `n$RepoStatus `n Running git clean -xdf") 
                }
                
                Write-Verbose "Local repo contains uncommited changes! `n$RepoStatus"
                
                # Reset local repo to match remote for tracked files
                ExecGit "reset --hard origin/$branch"
                # Remove any untracked files (-f [force], directories (-d) and any ignored files (-x)
                ExecGit "clean -xdf"
            }
            
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
        Write-Verbose "Removing $RepoPath"
        if($Logging -eq $true) 
        {
            Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("Removing $RepoPath")
        }
        
        Remove-Item -Path $RepoPath -Recurse -Force
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

    try
    {
        $myLogSource = $PSCmdlet.MyInvocation.MyCommand.ModuleName
        New-Eventlog -LogName "DevOps" -Source $myLogSource -ErrorAction SilentlyContinue
    }
    catch {}

    $RepoPath = (SetRepoPath -Source $Source -Destination $Destination)
    
    Write-Verbose "Calling Get: `n -Ensure $Ensure`n -Source $Source`n -Destination $Destination`n -Branch $Branch `n -Name $Name"

    $GetResult = (Get-TargetResource -Ensure $Ensure -Source $Source -Destination $Destination -Branch $Branch -Name $Name)
    #Get-TargetResource -Ensure "Present" -Name "website" -Source "https://github.com/leshkinski/website.git" -Destination "C:\WebSites\" -Branch "master"

    if ($Ensure -eq "Present")
    {
        if (Test-Path $RepoPath)
        {
            Set-Location $RepoPath
            if (($GetResult.Destination -eq $Destination) -and ($GetResult.Source -eq $Source) -and ($GetResult.Branch -eq $Branch))
            {
            
                # Check if origin contains changes which have not been merged locally
                $Fetch = ExecGit "fetch origin"
                if ($Fetch.Length -ne 0)
                {
                    Write-Verbose "origin/$Branch has pending updates:`n$Fetch"
                    return $false
                }
                
                # Ensure that local and remote commits match after a fetch operation has been mad
                $localCommit = ExecGit "rev-parse HEAD"
                $originCommit = ExecGit "rev-parse origin/$Branch"
                if (-not ($localCommit -eq $originCommit))
                {
                    Write-Verbose "Latest local commit does not match origin/$Branch"
                    return $false
                }

                # Final check for local repo status for local uncommited changes
                $RepoStatus = ExecGit "status"
                if (-not ($RepoStatus.Contains("working directory clean")))
                {
                    Write-Verbose "Local repo contains uncommited changes! `n$RepoStatus"
                    return $false
                }
                else
                {
                    # If all tests above pass, our repo test is true
                    return $true
                }
            }
            else
            {
                Write-Verbose "Repository settings are not consistent. `n $($GetResult | Out-String)"
                return $false
            }
        }
        else
        {
            Write-Verbose "$RepoPath is not found."
            return $false
        }
    }
    else
    {
        if (Test-Path $RepoPath)
        {
            Write-Verbose "$RepoPath still exists."
            return $false
        }
        else
        {
            return $true
        }
    }

}

function ExecGit
{
	param(
		[Parameter(Mandatory = $true)][string]$args
	)

    # Conifugraiton and DSC resource-wide variables
    #. ($MyInvocation.PSScriptRoot + "\RS_rsGit_settings.ps1")
    #$gitCmd = $global:gitExe
    $gitCmd = "C:\Program Files (x86)\Git\cmd\git.exe"
    $location = Get-Location

    try
    {
        #Check if location specified for git executable is valid
	    if (CheckCommand $gitCmd)
	    {
	    	#Write-Verbose "Executing: git $args in $($location.path)"

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
            Write-Verbose "Git executable not found at $gitCmd `n"
            Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Error -EventId 1000 -Message ("Git executable not found at $gitCmd")
            Throw "Git executable not found at $gitCmd"
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

function SetRepoPath
{
    param (
        [Parameter(Position=0,Mandatory = $true)][string]$Source,
        [Parameter(Position=1,Mandatory = $true)][string]$Destination
    )

    if(($Source.split("/.")[0]) -eq "https:")
    {
        $i = 5
    }
    else
    {
        $i = 2
    }

    $RepoPath = Join-Path $Destination -ChildPath ($Source.split("/."))[$i]
    
    return $RepoPath
}

function IsValidRepo
{
    param(
		[Parameter(Position=0,Mandatory = $true)][string]$RepoPath
	)

    if (Test-Path $RepoPath)
    {
        Set-Location $RepoPath
        $output = (ExecGit -args "status")
        if ($output -notcontains "Not a git repository")
        {
            return $true
        }
        else
        {
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


Export-ModuleMember -Function *-TargetResource