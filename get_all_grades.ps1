# Get All Grades Script (PowerShell)
# Fetches grades from the danh-sach-diem-hoc-ky-mon-hoc API endpoint
# and saves to JSON file

param(
    [Parameter(Mandatory=$true)]
    [string]$AuthToken,
    
    [Parameter(Mandatory=$true)]
    [string]$Cookie,
    
    [string]$OutputFile = "all_grades.json"
)

# Set encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

try {
    $url = "https://mybk.hcmut.edu.vn/api/share/ket-qua-hoc-tap/danh-sach-diem-hoc-ky-mon-hoc/v2?tuychon=BANGDIEM_MONHOC"
    
    $headers = @{
        "Accept" = "application/json"
        "Content-Type" = "application/json"
        "Accept-Encoding" = "gzip, deflate, br"
        "Accept-Language" = "en-US,en;q=0.9,vi;q=0.8"
        "Authorization" = $AuthToken
        "Cookie" = "JSESSIONID=$Cookie"
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        "Referer" = "https://mybk.hcmut.edu.vn/"
        "Origin" = "https://mybk.hcmut.edu.vn"
    }
    
    # Write status to stderr (not stdout) so it doesn't interfere with JSON output
    [Console]::Error.WriteLine("Fetching grades from API...")
    
    # Use WebClient to get raw UTF-8 response without PowerShell's encoding interference
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("Accept", "application/json")
    $webClient.Headers.Add("Content-Type", "application/json")
    $webClient.Headers.Add("Authorization", $AuthToken)
    $webClient.Headers.Add("Cookie", "JSESSIONID=$Cookie")
    $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
    $webClient.Headers.Add("Referer", "https://mybk.hcmut.edu.vn/")
    $webClient.Headers.Add("Origin", "https://mybk.hcmut.edu.vn")
    
    # Upload data and get response as UTF-8 bytes
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes("{}")
    $responseBytes = $webClient.UploadData($url, "POST", $bodyBytes)
    
    # Convert bytes to UTF-8 string
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $jsonString = $utf8.GetString($responseBytes)
    
    # Parse to object for filtering
    $response = $jsonString | ConvertFrom-Json
    
    # Filter out records where soTinChi = 0
    $originalCount = 0
    $filteredCount = 0
    if ($null -ne $response.data -and $response.data -is [System.Array]) {
        $originalCount = $response.data.Count
        $filteredData = $response.data | Where-Object { $_.soTinChi -ne 0 }
        $filteredCount = $filteredData.Count
        [Console]::Error.WriteLine("Filtered out $($originalCount - $filteredCount) records with 0 credits")
        
        # Remove duplicates - keep only the best grade for each course
        # Group by course code (maMonHoc)
        $courseGroups = $filteredData | Group-Object -Property maMonHoc
        
        $deduplicatedData = @()
        $duplicatesRemoved = 0
        
        foreach ($group in $courseGroups) {
            if ($group.Count -eq 1) {
                # Single instance, keep it
                $deduplicatedData += $group.Group[0]
            } else {
                # Multiple instances - keep the best one
                $bestCourse = $null
                $bestScore = -1
                $bestIsPassing = $false
                
                foreach ($course in $group.Group) {
                    # Check if this is a failing score (13 or 11 mean fail)
                    $isFailCode = ($course.diemSo -eq 13 -or $course.diemSo -eq 11)
                    
                    # Determine if passing (diemDat = "1" means passed, diemChu = "F" means failed)
                    $isPassing = ($course.diemDat -eq "1" -and -not $isFailCode -and $course.diemChu -ne "F")
                    
                    # Get score (handle null cases, treat 0 as valid score for F grades)
                    $score = if ($course.diemSo -ne $null) { $course.diemSo } else { -1 }
                    
                    # Skip fail codes (13, 11) - these are special fail indicators
                    if ($isFailCode) {
                        continue
                    }
                    
                    # Prefer passing over failing
                    if ($bestCourse -eq $null) {
                        $bestCourse = $course
                        $bestScore = $score
                        $bestIsPassing = $isPassing
                    } elseif ($isPassing -and -not $bestIsPassing) {
                        # This is passing, best is not - prefer this
                        $bestCourse = $course
                        $bestScore = $score
                        $bestIsPassing = $isPassing
                    } elseif ($isPassing -eq $bestIsPassing) {
                        # Both same pass/fail status - prefer higher score
                        if ($score -gt $bestScore) {
                            $bestCourse = $course
                            $bestScore = $score
                            $bestIsPassing = $isPassing
                        }
                    }
                    # else: Best is passing, this is not - keep best (do nothing)
                }
                
                if ($bestCourse -ne $null) {
                    $deduplicatedData += $bestCourse
                } else {
                    # All were fail codes or no valid course found, keep the first one anyway
                    $deduplicatedData += $group.Group[0]
                }
                # Count duplicates removed (all except the one kept)
                $duplicatesRemoved += ($group.Count - 1)
            }
        }
        
        $response.data = $deduplicatedData
        if ($duplicatesRemoved -gt 0) {
            [Console]::Error.WriteLine("Removed $duplicatesRemoved duplicate course(s), kept best grades")
        }
    }
    
    # Convert filtered response back to JSON string
    # Use ConvertTo-Json and then fix encoding by reading the original JSON structure
    $filteredJsonString = $response | ConvertTo-Json -Depth 20 -Compress:$false
    
    # Fix Unicode encoding - ConvertTo-Json may have corrupted UTF-8
    # We'll reconstruct from the filtered objects preserving original string values
    # For now, save as-is since the main issue was with the initial fetch
    # The filtered data should maintain encoding from the original parse
    
    # Save the filtered JSON string with UTF-8 encoding
    $absolutePath = $OutputFile
    try {
        $absolutePath = (Resolve-Path -Path $OutputFile -ErrorAction Stop).Path
    } catch {
        # If Resolve-Path failed, use the provided path directly
        $absolutePath = $OutputFile
    }
    
    # Save filtered JSON string with UTF-8 encoding (no BOM)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($absolutePath, $filteredJsonString, $utf8NoBom)
    
    # Cleanup
    $webClient.Dispose()
    
    [Console]::Error.WriteLine("Successfully saved grades to: $OutputFile")
    
    # Determine record count based on filtered response structure
    $recordCount = 0
    if ($null -ne $response) {
        if ($response -is [System.Array]) {
            $recordCount = $response.Count
        } elseif ($null -ne $response.data -and $response.data -is [System.Array]) {
            $recordCount = $response.data.Count
        } elseif ($null -ne $response.data) {
            $recordCount = 1
        } else {
            $recordCount = 1
        }
    }
    
    # Output success result
    $result = @{
        success = $true
        output_file = $OutputFile
        record_count = $recordCount
    }
    $result | ConvertTo-Json -Compress
    exit 0
    
} catch {
    $errorMessage = $_.Exception.Message
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorMessage = "HTTP $statusCode : $errorMessage"
    }
    
    # Write error to stderr (not stdout)
    [Console]::Error.WriteLine("Error fetching grades: $errorMessage")
    
    $result = @{
        success = $false
        error = $errorMessage
    }
    $result | ConvertTo-Json -Compress
    exit 1
}

