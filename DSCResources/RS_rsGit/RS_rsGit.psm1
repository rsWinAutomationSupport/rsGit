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
        $DestinationZip
    )
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
        $DestinationZip
    )
    try 
    {
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
                if ( -not ([String]::IsNullOrEmpty($DestinationZip)) )
                {
                    Write-Verbose "archive --format zip -o ""$DestinationZip"" $branch"
                    Start -Wait "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "archive --format zip -o ""$DestinationZip"" $branch"
                    New-Item -Path ($DestinationZip + ".checksum") -ItemType file
                    $hash = (Get-FileHash -Path $DestinationZip).Hash
                    [System.IO.File]::AppendAllText(($DestinationZip + '.checksum'), $hash)
                }
            }
        
        else 
        {
            chdir (Join-Path $Destination -ChildPath ($Source.split("/."))[$i])
            Write-Verbose "git checkout $branch;git reset --hard; git clean -f -d; git pull"
            Start -Wait "C:\Program Files (x86)\Git\bin\sh.exe" -ArgumentList "--login -i -c ""git checkout $branch;git reset --hard; git clean -f -d;git pull;"""
            if ( -not ([String]::IsNullOrEmpty($DestinationZip)) )
            {
                Write-Verbose "archive --format zip -o ""$DestinationZip"" $branch"
                Start -Wait "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "archive --format zip -o ""$DestinationZip"" $branch"
                New-Item -Path ($DestinationZip + ".checksum") -ItemType file
                $hash = (Get-FileHash -Path $DestinationZip).Hash
                [System.IO.File]::AppendAllText(($DestinationZip + '.checksum'), $hash)
            }
        }
    }
    if ($Ensure -eq "Absent")
    {
        if(($Source.split("/.")[0]) -eq "https:") { $i = 5 } else { $i = 2 }
        Write-Verbose "Removing git"
        remove-item -Path (Join-Path $Destination -ChildPath ($Source.split("/."))[$i]) -Recurse -Force
    }
    try 
    {
        Stop-Service Browser
    }
    catch 
    {
        Write-EventLog -LogName DevOps -Source RS_rsGit -EntryType Error -EventId 1002 -Message "Failed to Stop Browser `n $_.Exception.Message"
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
        $DestinationZip
    )
    return $false
}
Export-ModuleMember -Function *-TargetResource