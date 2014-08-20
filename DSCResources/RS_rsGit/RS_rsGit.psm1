Function New-ResourceZip {
   param
   (
      $modulePath,
      $outputDir
   )
   Add-Type -AssemblyName System.IO.Compression.FileSystem | out-null
   $module = Import-Module $modulePath -PassThru
   $moduleName = $module.Name
   $version = $module.Version.ToString()
   $zipFilename = ("{0}_{1}.zip" -f $moduleName, $version)
   $outputPath = Join-Path $outputDir $zipFilename
   if ( -not (Test-Path $outputPath) ) 
   { 
      if(test-path $outputPath){
         Remove-Item $outputPath -Force
      }
      [System.IO.Compression.ZipFile]::CreateFromDirectory($module.ModuleBase,$outputPath)
      Remove-Module $moduleName
   }
   else
   {
      $outputPath = $null
   }
   return $outputPath
   
}

<#Function New-ResourceZip {
   param
   (
      $modulePath,
      $outputDir
   )
   # Read the module name & version
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
}#>

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
   if ($Ensure -eq "Present")
   {
      if ((Get-Service "Browser").status -eq "Stopped" ) 
      {
         
         Get-Job | ? State -match "Completed" | Remove-Job
         $startmode = (Get-WmiObject -Query "Select StartMode From Win32_Service Where Name='browser'").startmode
         if ( $startmode -eq 'disabled' ){ Set-Service -Name Browser -StartupType Manual }
         Write-Verbose "Starting Browser Service"
         Start-Service Browser
         if ( (Get-Job "Stop_Browser" -ErrorAction SilentlyContinue).count -eq 0 )
         {
            Write-Verbose "Creating PSJob to Stop Browser Service"
            Start-Job -Name "Stop_Browser" -ScriptBlock { Start-Sleep -Seconds 60; Stop-Service Browser; }
         }
      }
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
         Write-Verbose "git checkout $branch;git reset --hard; git clean -f -d; git pull"
         Start -Wait "C:\Program Files (x86)\Git\bin\sh.exe" -ArgumentList "--login -i -c ""git checkout $branch;git reset --hard; git clean -f -d;git pull;"""
      }
      if ( -not ([String]::IsNullOrEmpty($DestinationZip)) )
      {
         Write-Verbose "Starting Resource Zip"
         $resourceZipPath = New-ResourceZip -modulePath $(Join-Path $Destination -ChildPath ($Source.split("/."))[$i]) -outputDir $DestinationZip
         if ( $resourceZipPath -ne $null )
         {
            Write-Verbose "Starting Checksum"
            Remove-Item -Path ($resourceZipPath + ".checksum") -Force -ErrorAction SilentlyContinue
            #Start-Sleep 4
            New-Item -Path ($resourceZipPath + ".checksum") -ItemType file
            $hash = (Get-FileHash -Path $resourceZipPath).Hash
            [System.IO.File]::AppendAllText(($resourceZipPath + '.checksum'), $hash)
         }
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
      $Name,
      [string]
      $DestinationZip
   )
   return $false
}
Export-ModuleMember -Function *-TargetResource