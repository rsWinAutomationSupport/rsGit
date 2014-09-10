Function Get-TargetResource {
   param (
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$installedPath,
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$hostedPath
   )
   @{
        installedPath = $installedPath
        hostedPath = $hostedPath
    }
}

Function Test-TargetResource {
   param (
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$installedPath,
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$hostedPath
   )
   
   . "C:\cloud-automation\secrets.ps1"
   $keys = Invoke-RestMethod -Uri "https://api.github.com/user/keys" -Headers @{"Authorization" = "token $($d.gAPI)"} -ContentType application/json -Method GET
   $pullKeys = $keys | ? title -eq $($d.DDI + "_" + $env:COMPUTERNAME)
   $numberOfKeys = (($pullKeys).id).count
   if($numberOfKeys -ne 1) {
      return $false
   }
   if(!(Test-Path -Path (Join-Path $installedPath -ChildPath "id_rsa"))) {
      return $false
   }
   if(!(Test-Path -Path (Join-Path $installedPath -ChildPath "id_rsa.pub"))) {
      return $false
   }
   if(!(Test-Path (Join-Path $hostedPath -ChildPath "id_rsa.txt"))) {
      return $false
   }
   if(!(Test-Path (Join-Path $hostedPath -ChildPath "id_rsa.pub"))) {
      return $false
   }
   if(($pullKeys.key -eq ((Get-Content (Join-Path $installedPath -ChildPath "id_rsa.pub")).Split("==")[0] + "==")) -and ((Get-Content -Path (Join-Path $installedPath -ChildPath "id_rsa.pub")) -eq (Get-Content -Path (Join-Path $hostedPath -ChildPath "id_rsa.pub")))) {
      return $true
   }
   else {
      return $false
   }
   return $true
   
}

Function Set-TargetResource {
   param (
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$installedPath,
      [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$hostedPath
   )
   . "C:\cloud-automation\secrets.ps1"
   $keys = Invoke-RestMethod -Uri "https://api.github.com/user/keys" -Headers @{"Authorization" = "token $($d.gAPI)"} -ContentType application/json -Method GET
   $pullKeys = $keys | ? title -eq $($d.DDI + "_" + $env:COMPUTERNAME)
   $numberOfKeys = (($pullKeys).id).count
   Remove-Item (Join-Path $installedPath -ChildPath "id_rsa*") -Force
   Remove-Item (Join-Path $hostedPath -ChildPath "id_rsa*") -Force
   foreach($pullKey in $pullKeys) {
      Invoke-RestMethod -Uri $("https://api.github.com/user/keys/" + $pullKey.id) -Headers @{"Authorization" = "token $($d.gAPI)"} -ContentType application/json -Method DELETE
   }
   ssh-keygen.exe -t rsa -f $($installedPath, 'id_rsa' -join '\') -N """"
   Write-Verbose "$(Get-Date)Uploading Key to GitHub"
   $sshKey = Get-Content -Path (Join-Path $installedPath -ChildPath "id_rsa.pub")
   $json = @{"title" = "$($d.DDI + "_" + $env:COMPUTERNAME)"; "key" = "$sshKey"} | ConvertTo-Json
   Invoke-RestMethod -Uri "https://api.github.com/user/keys" -Headers @{"Authorization" = "token $($d.gAPI)"} -ContentType application/json -Body $json -Method Post
   Copy-Item -Path (Join-Path $installedPath -ChildPath "id_rsa") -Destination (Join-Path $hostedPath -ChildPath "id_rsa.txt") -Force
   Copy-Item -Path (Join-Path $installedPath -ChildPath "id_rsa.pub") -Destination (Join-Path $hostedPath -ChildPath "id_rsa.pub") -Force     
}
Export-ModuleMember -Function *-TargetResource