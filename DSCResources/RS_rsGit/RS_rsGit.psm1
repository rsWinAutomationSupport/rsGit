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
         Set-Location $Destination
         if($Logging -eq $true) { Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("$Source : git clone --branch $branch $Source") }
         Start -Wait -NoNewWindow "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "clone --branch $Branch $Source"
      }
      
      else 
      {
         Set-Location (Join-Path $Destination -ChildPath ($Source.split("/."))[$i])
         if($Logging -eq $true) { Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("$Source : git checkout $branch;git reset --hard; git clean -f -d; git pull") }
         start -Wait 'C:\Program Files (x86)\Git\cmd\git.exe' -ArgumentList "checkout $Branch; reset --hard; clean -f -d; fetch origin $Branch; merge remotes/origin/$Branch"
      }
      if ( -not ([String]::IsNullOrEmpty($DestinationZip)) )
      {
         if($Logging -eq $true) { Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("Starting Resource Zip") }
         
         ### new
        $module = Import-Module $(Join-Path $Destination -ChildPath ($Source.split("/."))[$i]) -PassThru
        $moduleName = $module.Name
        $version = $module.Version.ToString()
        #Remove-Module $moduleName -Force
   
        $zipFilename = ("{0}_{1}.zip" -f $moduleName, $version)
        $outputPath = Join-Path $DestinationZip $zipFilename      
         ###
         
         #$resourceZipPath = New-ResourceZip -modulePath $(Join-Path $Destination -ChildPath ($Source.split("/."))[$i]) -outputDir $DestinationZip 
        if($Logging -eq $true) { Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Information -EventId 1000 -Message ("Starting Checksum") }
        $module = Import-Module $(Join-Path $Destination -ChildPath ($Source.split("/."))[5]) -PassThru
        $moduleName = $module.Name
        $version = $module.Version.ToString()
        Remove-Module $moduleName
        $zipFilename = ("{0}_{1}.zip" -f $moduleName, $version)
        $outputPath = Join-Path $DestinationZip $zipFilename 
        if(!(Test-Path -Path $outputPath) ) {
          Compress-Archive -Path $(Join-Path $Destination -ChildPath $name) -DestinationPath $outputPath -Force
        }
        else {
          Compress-Archive -Path $(Join-Path $Destination -ChildPath $name) -DestinationPath $outputPath -Update
        }
        Set-Content -Path $($outputPath, 'checksum' -join '') -Value ((Get-FileHash $outputPath).Hash)
         
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
   return $false
}
Export-ModuleMember -Function *-TargetResource