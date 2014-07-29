Function Get-TargetResource {
    param (
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$gitIps,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$gitRsa,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$path
    )
    @{
        gitIps = $gitIps
        gitRsa = $gitRsa
        path = $path
    }
}

Function Test-TargetResource {
    param (
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$gitIps,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$gitRsa,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$path
    )
    if(!(Test-Path -Path $($path, "known_hosts" -join '\'))) {
        return $false
    }
    else {
        $lines = (Get-Content -Path $($path, "known_hosts" -join '\')).Split("`n")
        foreach($gitIp in $gitIPs) {
            if($lines -notcontains ($gitIP, "ssh-rsa", $gitRsa -join " ")) {
                return $false
            }
        }
        return $true
    }
}

Function Set-TargetResource {
    param (
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$gitIps,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$gitRsa,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$path
    )
    if(!(Test-Path -Path $($path, "known_hosts" -join '\'))) {
        if(!(Test-Path -Path $path)) {
            New-Item -Path $path -ItemType directory
        }
            foreach($gitIp in $gitIps) {
                Add-Content -Path $($path, "known_hosts" -join '\') -Value $($gitIP, "ssh-rsa", $gitRsa -join " ")
            }
    }
    else {
        Remove-Item -Path $($path, "known_hosts" -join '\') -Force
        foreach($gitIp in $gitIps) {
            Add-Content -Path $($path, "known_hosts" -join '\') -Value $($gitIP, "ssh-rsa", $gitRsa -join " ")
        }
    }

}

Export-ModuleMember -Function *-TargetResource