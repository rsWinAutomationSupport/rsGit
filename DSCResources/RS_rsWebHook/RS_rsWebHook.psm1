Function Get-TargetResource {
   param (
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Name,
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Repo,
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][uint32]$Port,
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Ensure,
      [bool]$Logging
   )
   $myLogSource = $PSCmdlet.MyInvocation.MyCommand.ModuleName
   if(!([System.Diagnostics.EventLog]::SourceExists($myLogSource))) {
      New-Eventlog -LogName "DevOps" -Source $myLogSource
   }
   . "C:\cloud-automation\secrets.ps1"
   try {
      $currentHooks = Invoke-RestMethod -Uri $("https://api.github.com/repos", $($d.gCA), $Repo, "hooks" -join '/') -Headers @{"Authorization" = "token $($d.gAPI)"} -ContentType application/json -Method Get
   }
   catch {
      if($Logging) {
         Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Error -EventId 1002 -Message "Failed to retrieve github webhooks `n $($_.Exception.Message)"
      }
   }
   if($($currentHooks.count) -eq 1) {
      $returnHash = @{}
      if($currentHooks.name) { $returnHash.Name = $currentHooks.name } else { $returnHash.Name = "Not Defined"}
      if($($currentHooks.config).url) { $returnHash.Repo = $($currentHooks.config).url } else { $returnHash.Repo = "Not Defined"}
      if($Ensure -eq "Present") { $returnHash.Ensure = "Present"}
      if($Ensure -eq "Absent") { $returnHash.Ensure = "Absent"}
      if($((($repoHooks.config.url).Split("/")).split(":")[4]).trim()) { $returnHash.Port = $((($repoHooks.config.url).Split("/")).split(":")[4]).trim() }
      $returnHash.Logging = $Logging
      return $returnHash
   }
   else {
      @{
   Name = $Name
   Repo = $Repo
   Port = $Port
   Ensure = $Ensure
   Logging = $Logging
   }
   }
   
}

Function Test-TargetResource {
   param (
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Name,
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Repo,
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][uint32]$Port,
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Ensure,
      [bool]$Logging
   )
   $myLogSource = $PSCmdlet.MyInvocation.MyCommand.ModuleName
   if(!([System.Diagnostics.EventLog]::SourceExists($myLogSource))) {
      New-Eventlog -LogName "DevOps" -Source $myLogSource
   }
   . "C:\cloud-automation\secrets.ps1"
   try {
      $currentHooks = Invoke-RestMethod -Uri $("https://api.github.com/repos", $($d.gCA), $Repo, "hooks" -join '/') -Headers @{"Authorization" = "token $($d.gAPI)"} -ContentType application/json -Method Get
   }
   catch {
      if($Logging) {
         Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Error -EventId 1002 -Message "Failed to retrieve github webhooks `n $($_.Exception.Message)"
      }
   }
   if($currentHooks.name -ne $Name) {
      return $false
   }
   if($($currentHooks.config).url -ne $repo) {
      return $false
   }
   if($((($repoHooks.config.url).Split("/")).split(":")[4]).trim() -ne $Port) {
      return $false
   }
   if($($currentHooks.count) -ge 1) {
      return $false
   }
   return $true
}

Function Set-TargetResource {
   param (
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Name,
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Repo,
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][uint32]$Port,
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Ensure,
      [bool]$Logging
   )
   $myLogSource = $PSCmdlet.MyInvocation.MyCommand.ModuleName
   if(!([System.Diagnostics.EventLog]::SourceExists($myLogSource))) {
      New-Eventlog -LogName "DevOps" -Source $myLogSource
   }
   . "C:\cloud-automation\secrets.ps1"
   . "$($d.wD, $d.mR, "PullServerInfo.ps1" -join '\')"
   try {
      $currentHooks = Invoke-RestMethod -Uri $("https://api.github.com/repos", $($d.gCA), $Repo, "hooks" -join '/') -Headers @{"Authorization" = "token $($d.gAPI)"} -ContentType application/json -Method Get
   }
   catch {
      if($Logging) {
         Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Error -EventId 1002 -Message "Failed to retrieve github webhooks `n $($_.Exception.Message)"
      }
   }
   foreach($currentHook in $currentHooks) {
      try {
         Invoke-RestMethod -Uri $("https://api.github.com/repos", $($d.gCA), $Repo, "hooks", $($currentHook.id) -join '/') -Headers @{"Authorization" = "token $($d.gAPI)"} -ContentType application/json -Method Delete
      }
      catch {
         if($Logging) {
            Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Error -EventId 1002 -Message "Failed to DELETE github webhook(s) `n $($_.Exception.Message)"
         }
      }
   }
   $((($("http://", $($pullserverInfo.pullserverPublicIp) -join ''), $Port -join ':'), "/Deployment/SmokeTest/_self?source=" -join ''), $($d.mR) -join '')
   $body = @{"name" = "web"; "active" = "true"; "events" = @("push"); "config" = @{"url" = $((($("http://", $($pullserverInfo.pullserverPublicIp) -join ''), $Port -join ':'), "/Deployment/SmokeTest/_self?source=" -join ''), $($d.mR) -join ''); "content_type" = "json"} } | ConvertTo-Json -Depth 3
   try {
      Invoke-RestMethod -Uri $("https://api.github.com/repos", $($d.gCA), $($d.mR), "hooks" -join '/') -Body $body -Headers @{"Authorization" = "token $($d.gAPI)"} -ContentType application/json -Method Post
   }
   catch {
      Write-EventLog -LogName DevOps -Source $myLogSource -EntryType Error -EventId 1002 -Message "Failed to create github Webhook `n $($_.Exception.Message)"
   }
}
Export-ModuleMember -Function *-TargetResource