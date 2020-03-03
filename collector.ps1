##
## Collector Script for Snipe-IT
##

<#
.SYNOPSIS
Collects information from the local machine to create a new asset in a Snipe-IT database

.DESCRIPTION
The script uses some WMI calls to find out the make, CPU type, etc., and then contacts the Snipe-IT database to find a matching model.  If that is found, then it attempts to create a new asset.  It avoids duplicates by searching for the Asset tag before creating a new record.

.PARAMETER DryRun
Use this flag to just print what would be updated, but do nothing to the database.

.EXAMPLE
collector.ps1 -DryRun

.INPUTS
None

.OUTPUTS
None
#>
Param
(
    [Parameter(Mandatory=$false)] [switch] $DryRun = $false
)

$ScriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$config = Get-Content -Path "$ScriptDirectory\config.json" -Raw | ConvertFrom-Json

$standard_headers = @{
    'Accept' = "application/json"
    'Content-Type' = "application/json"
    'Authorization' = "Bearer " + $config.apikey
}

function get-model {
    Param
    (
        [Parameter(Mandatory=$true)] [String[]] $model_number,
        [Parameter(Mandatory=$true)] [String[]] $cpu_type,
        [Parameter(Mandatory=$true)] [String[]] $memory_amount
    )
    
    $uri = $config.baseUrl + "/api/v1/models"
    
    $response = Invoke-RestMethod -Uri $uri -Headers $standard_headers

    try {
        $model_re = ".*" + $model_number.replace(" ", ".") + ".*"
    } catch {
        $model_re = ".*[" + $model_number + "].*"
    }

    # TODO: do I need to do any replaces on these?
    $mem_re = ".*$memory_amount.*"
    $cpu_re = ".*$cpu_type.*"
    
    $result = $response.rows | Where-Object {$_.name -match $model_re -and $_.name -match $mem_re -and $_.name -match $cpu_re}
    
    if ( $result -is [array]) {
        $result = $result[0]
    }
    return $result
}

function get-hardware {
    Param
    (
        [Parameter(Mandatory=$true)] [String[]] $search_term
    )
    
    if ($search_term) {
        $search_arg = "&search=" + $search_term
    } else {
        $search_arg = ""
    }

    $uri = $config.baseUrl + "/api/v1/hardware?limit=1&offset=0&sort=created_at&order=desc" + $search_arg

    $response = Invoke-RestMethod -Uri $uri -Headers $standard_headers

    return $response.rows
}

function get-computerinfo {
    try {
        $assetTag = (Get-CimInstance win32_bios).SerialNumber
    } catch {
        $assetTag = "ERROR"
    }
    
    $computerName = $env:COMPUTERNAME
    try {
        $cs = (Get-CimInstance -class Win32_ComputerSystem).TotalPhysicalMemory
        $memoryAmount = [math]::Ceiling($cs / 1024 / 1024 / 1024)
    } catch {
        $memoryAmount = 0
    }

    try {
        $modelno = (Get-CimInstance -class Win32_ComputerSystem).Model
        if ($modelno -is [array]) {
            $modelno = $modelno[0]
        }
    } catch {
        $modelno = "ERROR"
    }

    try {
        # Parse the CPU name, for example:
        #   Intel(R) Core(TM) i7-4770 CPU @ 3.40GHz
        #   Intel(R) Xeon(R) CPU E5-2640 0 @ 2.50GHz
        #   AMD Athlon(tm) II X2 245 Processor
        #
        # For more info see: https://www.intel.com/content/www/us/en/processors/processor-numbers.html
        #
        $CPU_REGEX = @(
            "Intel\(.*\) Core\(.*\) ([im]\d)-\d.*",
            "Intel\(.*\) Xeon\(.*\) CPU (E\d)-\d.*",
            ".*(Pentium|Atom|Celeron).*",
            "AMD Athlon\(.*\) II X\d (\d+)"
        )
        $cpu = (Get-CimInstance Win32_Processor).Name
        if ($cpu -is [array]) {
            $cpu = $cpu[0]
        }
        $cpuType = ""
        foreach ($filter in $CPU_REGEX) {
            if ($cpu -Match $filter)
            {
                $cpuType = $matches[1]
                break
            }
        }
        # elseif ($cpu -like "*Duo")
        # {
        #     $cpuType = "Core-2-Duo"
        # }
    } catch {
        $cpuType = "ERROR"
    }
    
    $hash = @{
        'AssetTag'        = $assetTag
        'ComputerName'    = $computerName
        'MemoryAmount'    = $memoryAmount
        'ModelNumber'     = $modelno
        'CpuType'         = $cpuType
        'UserName'        = $env:USERNAME
    }
    $computer_info = New-Object PSObject -Property $hash
    return $computer_info
}

function new-asset {
    Param
    (
        [Parameter(Mandatory=$true)] [PSObject] $computer_info,
        [Parameter(Mandatory=$true)] [PSObject] $model_info
    )

    $uri = $config.baseUrl + "/api/v1/hardware"

    $payload = @{
        "asset_tag" = $computer_info.AssetTag
        "status_id" = "2"
        "model_id"  = $model_info.id
        "name"      = $computer_info.ComputerName
        "notes"     = "Current username is " + $computer_info.UserName
    }
    $json = $payload | ConvertTo-Json
    $response = Invoke-RestMethod -Method 'Post' -Uri $uri -Headers $standard_headers -Body $json -ContentType 'application/json'
    return $response
}

#
# Main routine to grab the computer information, check if the asset ID has been registered, and if not, create a new record.
#
$my_computer = get-computerinfo

Write-Host "[INFO] Asset Tag:" $my_computer.AssetTag
Write-Host "[INFO] Computer Name:" $my_computer.ComputerName
Write-Host "[INFO] Model Name:" $my_computer.ModelNumber

$result = get-hardware $my_computer.AssetTag

if (([string]::IsNullOrEmpty($result)) -or $dryrun -eq $true) {

    $this_model = get-model $my_computer.ModelNumber $my_computer.CpuType $my_computer.MemoryAmount

    if (([string]::IsNullOrEmpty($this_model))) {
        $msg = "[WARNING] No Asset Model found for: " + $my_computer.ModelNumber + " [" + $my_computer.CpuType + "] [" + $my_computer.MemoryAmount + "]"
        write-host $msg
    } else {
        if ($dryrun -eq $false) {
            Write-Host "[INFO] Adding a new asset for" $this_model.id

            $result = new-asset $my_computer $this_model
            write-host "[INFO] new-asset result:" $result
        } else {
            write-host "[DEBUG]" $my_computer
            $msg = "Would create a new asset [" + $my_computer.AssetTag + "] for model [" + $this_model.name + "]"
            Write-Host "[DEBUG]" $msg
        }
    }
} else {
    # TODO: should this script update an existing asset?
    Write-Host "[INFO] Asset already exists:" $result
}
