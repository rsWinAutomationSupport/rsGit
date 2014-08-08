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
        $Name
    )
    @{
        Name = $Name
        Destination = $Destination
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
        $Name
    )
    try 
    {
        Set-Service -StartupType Manual -Name Browser
        Start-Service Browser
    }
    catch 
    {
        Write-EventLog -LogName DevOps -Source RS_rsGit -EntryType Error -EventId 1002 -Message "Failed to Start Browser `n $_.Exception.Message"
    }
    if ($Ensure -eq "Present")
    {
        if(($Source.split("/.")[0]) -eq "https:") { $i = 5 } else { $i = 2 }
            if((test-path -Path (Join-Path $Destination -ChildPath ($Source.split("/."))[$i]) -PathType Container) -eq $false) {
                if((Test-Path -Path $Destination) -eq $false) { 
                    New-Item $Destination -ItemType Directory -Force 
                }
                chdir $Destination
                Write-Verbose "git clone --branch $branch $Source"
                Start -Wait "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "clone --branch $Branch $Source"
            }
        
        else 
        {
            chdir (Join-Path $Destination -ChildPath ($Source.split("/."))[$i])
            Write-Verbose "git checkout $branch"
            Start -Wait "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "checkout $Branch"
            
            Write-Verbose "git reset --hard"
            Start -Wait "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "reset --hard"

            Write-Verbose "git clean -f -d"
            Start -Wait "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "clean -f -d"

            Write-Verbose "git pull"
            Start -Wait "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "pull"
        }
    }
    if ($Ensure -eq "Absent")
    {
        if(($Source.split("/.")[0]) -eq "https:") { $i = 5 } else { $i = 2 }
        Write-Verbose "Removing git"
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
        $Name
    )
    return $false
}
Export-ModuleMember -Function *-TargetResource