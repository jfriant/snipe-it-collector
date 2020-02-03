$ScriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$config = Get-Content -Path "$ScriptDirectory\config.json" -Raw | ConvertFrom-Json

$standard_headers = @{
    'Accept' = "application/json"
    'Content-Type' = "application/json"
    'Authorization' = "Bearer " + $config.apikey
}

function get-model {
    Param(
        [Parameter(Mandatory=$true)]
        [String[]]
        $model_number,
        [Parameter(Mandatory=$true)]
        [String[]]
        $memory_amount,
        [Parameter(Mandatory=$true)]
        [String[]]
        $cpu_type
    )
    
    $uri = $config.baseUrl + "/api/v1/models"
    
    $response = Invoke-RestMethod -Uri $uri -Headers $standard_headers

    try {
        $model_number_re = ".*" + $model_number.replace(" ", ".") + ".*"
    } catch {
        $model_number_re = ".*[" + $model_number + "].*"
    }
    
    $result = $response.rows | Where-Object {$_.name -match $model_number_re -and $_.name -match ".*$memory_amount.*" -and $_.name -match ".*$cpu_type.*"}
    
    if ( $result -is [array]) {
        $result = $result[0]
    }
    return $result
}

function get-hardware {

    Param($search_term)
    
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
        $assetTag = (Get-WmiObject win32_bios).SerialNumber
    } catch {
        $assetTag = "NONE"
    }
    
    $computerName = $env:COMPUTERNAME
    try {
        $cs = (Get-WmiObject -class Win32_ComputerSystem).TotalPhysicalMemory
        $memoryAmount = [math]::Ceiling($cs / 1024 / 1024 / 1024)
    } catch {
        $memoryAmount = 0
    }

    try {
        $modelno = (Get-WmiObject -class Win32_ComputerSystem).Model
        if ($modelno -is [array]) {
            $modelno = $modelno[0]
        }
    } catch {
        $modelno = "NONE"
    }

    try {
        $cpu = (Get-WmiObject Win32_Processor).Name
        if ($cpu -is [array]) {
            $cpu = $cpu[0]
        }
        if ($cpu -like "*i5*"){
            $cpuType = "i5"
        }
        elseif ($cpu -like "*i7*"){
            $cpuType = "i7"
        }
        elseif ($cpu -like "*m7*"){
            $cpuType = "m7"
        }
        elseif ($cpu -like "*Xeon*"){
            $cpuType = "Xeon"
        }
    } catch {
        $cpuType = "NONE"
    }
    
    $hash = @{
        'AssetTag'        = $assetTag
        'ComputerName'    = $computerName
        'MemoryAmount'    = $memoryAmount
        'ModelNumber'     = $modelno
        'CpuType'         = $cpuType
    }
    $computer_info = New-Object PSObject -Property $hash
    return $computer_info
}

function new-asset {
    Param(
        [Parameter(Mandatory=$true)]
        [PSObject]
        $computer_info,
        [Parameter(Mandatory=$true)]
        [PSObject]
        $model_info
    )

    $uri = $config.baseUrl + "/api/v1/hardware"

    $payload = @{
        "asset_tag" = $computer_info.AssetTag
        "status_id" = "2"
        "model_id"  = $model_info.id
        "name"      = $computer_info.ComputerName
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

if (([string]::IsNullOrEmpty($result))) {

    $this_model = get-model $my_computer.ModelNumber $my_computer.CpuType $my_computer.MemoryAmount

    Write-Host "[INFO] Model ID:" $this_model.id
    Write-Host "[INFO] Model ID:" $this_model.name

    if (([string]::IsNullOrEmpty($this_model))) {
        $msg = "[WARNING] No Asset Model found for: " + $my_computer.ModelNumber + " [" + $my_computer_CpuType + "] [" + $my_computer.MemoryAmount + "]"
        write-host $msg
    } else {
        Write-Host "[INFO] Add new asset"

        $result = new-asset $my_computer $this_model
        write-host "[INFO] new-asset result:" $result
    }
} else {
    Write-Host "Asset already exists:" $result
}
