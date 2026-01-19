# Get All Grades Script for HCMIU (PowerShell)
# Fetches grades from the xemdiemthi page and saves to JSON file

param(
    [Parameter(Mandatory=$true)]
    [string]$Cookie,
    
    [string]$OutputFile = "all_grades.json"
)

# Set encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

function Parse-GradesHTML {
    param([string]$html)
    
    $grades = @()
    $currentMaHocKy = ""
    
    try {
        # Find the table with class "view-table" that contains the grades
        $tableMatch = [regex]::Match($html, '<table[^>]*class="view-table"[^>]*>(.*?)</table>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        if (-not $tableMatch.Success) {
            return $grades
        }
        
        $tableContent = $tableMatch.Groups[1].Value
        
        # Extract all rows
        $rowMatches = [regex]::Matches($tableContent, '<tr[^>]*class="([^"]*)"[^>]*>(.*?)</tr>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        $headerFound = $false
        $colIndices = @{
            STT = -1
            MaMon = -1
            TenMon = -1
            TC = -1
            PhanTramQT = -1
            PhanTramKT = -1
            PhanTramThi = -1
            BaiTap = -1
            KiemTra = -1
            ThiL1 = -1
            TK1_10 = -1
            TK_10 = -1
            TK1_CH = -1
            TK_CH = -1
        }
        
        foreach ($rowMatch in $rowMatches) {
            $rowClass = $rowMatch.Groups[1].Value
            $rowContent = $rowMatch.Groups[2].Value
            
            # Check if this is a semester header row (title-hk-diem)
            if ($rowClass -match 'title-hk-diem') {
                # Extract semester info from span: "Học kỳ X - Năm học YYYY-YYYY"
                $spanMatch = [regex]::Match($rowContent, '<span[^>]*class="Label"[^>]*>(.*?)</span>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                if ($spanMatch.Success) {
                    $semText = $spanMatch.Groups[1].Value
                    # Clean HTML entities and tags
                    $semText = $semText -replace '<[^>]+>', '' -replace '&nbsp;', ' ' -replace '\s+', ' '
                    $semText = $semText.Trim()
                    
                    # Pattern: Extract semester number and year from "Học kỳ 1 - Năm học 2023-2024"
                    # Look for: digit(s) followed by dash, then 4 digits - 4 digits
                    # This pattern works: (\d+) for semester, then (\d{4})-(\d{4}) for years
                    $semMatch = [regex]::Match($semText, '(\d+).*?(\d{4})-(\d{4})')
                    if ($semMatch.Success) {
                        $semester = $semMatch.Groups[1].Value
                        $yearStart = [int]$semMatch.Groups[2].Value
                        # Format: YYYYS (e.g., 20231 for semester 1 of 2023-2024)
                        $currentMaHocKy = "$yearStart$semester"
                    }
                }
                continue
            }
            
            # Skip summary rows (row-diemTK)
            if ($rowClass -match 'row-diemTK') {
                continue
            }
            
            # Extract cells - look for <td> with <span class="Label">
            $cellMatches = [regex]::Matches($rowContent, '<td[^>]*>(.*?)</td>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            
            if ($cellMatches.Count -eq 0) { continue }
            
            # Clean cell text - extract text from <span class="Label">
            $cells = @()
            foreach ($cell in $cellMatches) {
                $cellContent = $cell.Groups[1].Value
                # Extract text from span with class Label
                $spanMatch = [regex]::Match($cellContent, '<span[^>]*class="Label"[^>]*>(.*?)</span>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                if ($spanMatch.Success) {
                    $cellText = $spanMatch.Groups[1].Value
                } else {
                    $cellText = $cellContent
                }
                # Clean up
                $cellText = $cellText -replace '<[^>]+>', ''
                $cellText = $cellText -replace '&nbsp;', ' '
                $cellText = $cellText -replace '\s+', ' '
                $cellText = $cellText.Trim()
                $cells += $cellText
            }
            
            # Check if this is the header row (title-diem)
            if (-not $headerFound -and $rowClass -match 'title-diem') {
                $headerFound = $true
                
                # Find column indices
                for ($i = 0; $i -lt $cells.Count; $i++) {
                    $header = $cells[$i].ToLower()
                    if ($header -eq 'stt') { $colIndices.STT = $i }
                    elseif ($header -match 'ma mon') { $colIndices.MaMon = $i }
                    elseif ($header -match 'ten mon') { $colIndices.TenMon = $i }
                    elseif ($header -eq 'tc') { $colIndices.TC = $i }
                    elseif ($header -match '% qt|phan tram qua trinh') { $colIndices.PhanTramQT = $i }
                    elseif ($header -match '% kt|phan tram kiem tra') { $colIndices.PhanTramKT = $i }
                    elseif ($header -match '% thi|phan tram thi') { $colIndices.PhanTramThi = $i }
                    elseif ($header -match 'bai tap') { $colIndices.BaiTap = $i }
                    elseif ($header -match 'kiem tra') { $colIndices.KiemTra = $i }
                    elseif ($header -match 'thi l1') { $colIndices.ThiL1 = $i }
                    elseif ($header -match 'tk1\(10\)') { $colIndices.TK1_10 = $i }
                    elseif ($header -match 'tk\(10\)' -and $colIndices.TK_10 -eq -1) { $colIndices.TK_10 = $i }
                    elseif ($header -match 'tk1\(ch\)') { $colIndices.TK1_CH = $i }
                    elseif ($header -match 'tk\(ch\)' -and $colIndices.TK_CH -eq -1) { $colIndices.TK_CH = $i }
                }
                continue
            }
            
            # Skip if header not found yet
            if (-not $headerFound) { continue }
            
            # Check if this is a data row (row-diem)
            if (-not ($rowClass -match 'row-diem')) {
                continue
            }
            
            # Skip rows with too few cells
            if ($cells.Count -lt 3) { continue }
            
            # Check if first cell is a number (STT) - indicates a data row
            $sttValue = ""
            if ($colIndices.STT -ge 0 -and $colIndices.STT -lt $cells.Count) {
                $sttValue = $cells[$colIndices.STT]
            } elseif ($cells.Count -gt 0) {
                $sttValue = $cells[0]
            }
            
            $sttNum = 0
            if (-not [int]::TryParse($sttValue, [ref]$sttNum)) {
                continue  # Not a data row
            }
            
            # Parse grade data - HCMIU format
            $grade = @{
                stt = 0
                maMonHoc = ""
                tenMonHoc = ""
                maHocKy = $currentMaHocKy
                soTinChi = 0
                phanTramQT = $null
                phanTramKT = $null
                phanTramThi = $null
                baiTap = ""
                kiemTra = ""
                thiL1 = ""
                tk1_10 = $null
                tk_10 = $null
                tk1_CH = ""
                tk_CH = ""
            }
            
            # Extract STT
            if ($colIndices.STT -ge 0 -and $colIndices.STT -lt $cells.Count) {
                $sttParsed = 0
                if ([int]::TryParse($cells[$colIndices.STT], [ref]$sttParsed)) {
                    $grade.stt = $sttParsed
                }
            }
            
            # Extract course code
            if ($colIndices.MaMon -ge 0 -and $colIndices.MaMon -lt $cells.Count) {
                $grade.maMonHoc = $cells[$colIndices.MaMon]
            } elseif ($cells.Count -gt 1) {
                $grade.maMonHoc = $cells[1]
            }
            
            # Extract course name
            if ($colIndices.TenMon -ge 0 -and $colIndices.TenMon -lt $cells.Count) {
                $grade.tenMonHoc = $cells[$colIndices.TenMon]
            } elseif ($cells.Count -gt 2) {
                $grade.tenMonHoc = $cells[2]
            }
            
            # Extract credits (TC)
            if ($colIndices.TC -ge 0 -and $colIndices.TC -lt $cells.Count) {
                $tcValue = $cells[$colIndices.TC]
                $parsed = 0
                if ([double]::TryParse($tcValue, [ref]$parsed)) {
                    $grade.soTinChi = $parsed
                }
            }
            
            # Extract % QT
            if ($colIndices.PhanTramQT -ge 0 -and $colIndices.PhanTramQT -lt $cells.Count) {
                $value = $cells[$colIndices.PhanTramQT]
                $parsed = $null
                if ([double]::TryParse($value, [ref]$parsed)) {
                    $grade.phanTramQT = $parsed
                }
            }
            
            # Extract % KT
            if ($colIndices.PhanTramKT -ge 0 -and $colIndices.PhanTramKT -lt $cells.Count) {
                $value = $cells[$colIndices.PhanTramKT]
                $parsed = $null
                if ([double]::TryParse($value, [ref]$parsed)) {
                    $grade.phanTramKT = $parsed
                }
            }
            
            # Extract % Thi
            if ($colIndices.PhanTramThi -ge 0 -and $colIndices.PhanTramThi -lt $cells.Count) {
                $value = $cells[$colIndices.PhanTramThi]
                $parsed = $null
                if ([double]::TryParse($value, [ref]$parsed)) {
                    $grade.phanTramThi = $parsed
                }
            }
            
            # Extract Bài tập
            if ($colIndices.BaiTap -ge 0 -and $colIndices.BaiTap -lt $cells.Count) {
                $value = $cells[$colIndices.BaiTap].Trim()
                if ($value -ne "" -and $value -ne "&nbsp;" -and $value -ne " ") {
                    $grade.baiTap = $value
                }
            }
            
            # Extract Kiểm tra
            if ($colIndices.KiemTra -ge 0 -and $colIndices.KiemTra -lt $cells.Count) {
                $value = $cells[$colIndices.KiemTra].Trim()
                if ($value -ne "" -and $value -ne "&nbsp;" -and $value -ne " ") {
                    $grade.kiemTra = $value
                }
            }
            
            # Extract Thi L1
            if ($colIndices.ThiL1 -ge 0 -and $colIndices.ThiL1 -lt $cells.Count) {
                $value = $cells[$colIndices.ThiL1].Trim()
                if ($value -ne "" -and $value -ne "&nbsp;" -and $value -ne " ") {
                    $grade.thiL1 = $value
                }
            }
            
            # Extract TK1(10)
            if ($colIndices.TK1_10 -ge 0 -and $colIndices.TK1_10 -lt $cells.Count) {
                $value = $cells[$colIndices.TK1_10].Trim()
                $parsed = $null
                if ([double]::TryParse($value, [ref]$parsed)) {
                    $grade.tk1_10 = $parsed
                } elseif ($value -ne "" -and $value -ne "&nbsp;" -and $value -ne " ") {
                    $grade.tk1_10 = $value
                }
            }
            
            # Extract TK(10) - final numeric grade
            if ($colIndices.TK_10 -ge 0 -and $colIndices.TK_10 -lt $cells.Count) {
                $value = $cells[$colIndices.TK_10].Trim()
                $parsed = $null
                if ([double]::TryParse($value, [ref]$parsed)) {
                    $grade.tk_10 = $parsed
                } elseif ($value -ne "" -and $value -ne "&nbsp;" -and $value -ne " ") {
                    $grade.tk_10 = $value
                }
            }
            
            # Extract TK1(CH)
            if ($colIndices.TK1_CH -ge 0 -and $colIndices.TK1_CH -lt $cells.Count) {
                $value = $cells[$colIndices.TK1_CH].Trim()
                if ($value -ne "" -and $value -ne "&nbsp;" -and $value -ne " ") {
                    $grade.tk1_CH = $value
                }
            }
            
            # Extract TK(CH) - final letter grade
            if ($colIndices.TK_CH -ge 0 -and $colIndices.TK_CH -lt $cells.Count) {
                $value = $cells[$colIndices.TK_CH].Trim()
                if ($value -ne "" -and $value -ne "&nbsp;" -and $value -ne " ") {
                    $grade.tk_CH = $value
                }
            }
            
            # Only add if we have course code and a grade (tk_CH or tk_10)
            # Filter out courses without final grades (courses that are registered but not yet graded)
            # Include courses with P grade as they are valid grades
            $hasGrade = -not [string]::IsNullOrWhiteSpace($grade.tk_CH) -or 
                       -not [string]::IsNullOrWhiteSpace($grade.tk_10)
            
            if (-not [string]::IsNullOrWhiteSpace($grade.maMonHoc) -and $hasGrade) {
                $grades += $grade
            }
        }
        
        return $grades
        
    } catch {
        throw "Failed to parse grades HTML: $($_.Exception.Message)"
    }
}

# Main execution
try {
    # Create a session to maintain cookies
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    
    # Add the session cookie
    $uri = New-Object System.Uri("https://edusoftweb.hcmiu.edu.vn")
    $cookieObj = New-Object System.Net.Cookie("ASP.NET_SessionId", $Cookie, "/", "edusoftweb.hcmiu.edu.vn")
    $session.Cookies.Add($uri, $cookieObj)
    
    [Console]::Error.WriteLine("Fetching grades from HCMIU...")
    
    # Get HTML content - use Invoke-WebRequest directly with session
    $baseUrl = "https://edusoftweb.hcmiu.edu.vn"
    $gradesUrl = "$baseUrl/Default.aspx?page=xemdiemthi"
    
    $headers = @{
        "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        "Accept-Language" = "en-US,en;q=0.9,vi;q=0.8"
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        "Referer" = "$baseUrl/Default.aspx"
    }
    
    $response = Invoke-WebRequest -Uri $gradesUrl -Method GET -Headers $headers -WebSession $session -UseBasicParsing -ErrorAction Stop
    $html = $response.Content
    
    # Parse grades
    $grades = Parse-GradesHTML -html $html
    
    if ($grades.Count -eq 0) {
        # Try alternative parsing - maybe grades are in a different format
        # Save HTML for debugging
        $htmlFile = $OutputFile -replace '\.json$', '_raw.html'
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($htmlFile, $html, $utf8NoBom)
        [Console]::Error.WriteLine("Warning: No grades found. Raw HTML saved to: $htmlFile")
    }
    
    # Create output structure
    $output = @{
        code = "200"
        msg = "Success"
        data = $grades
    }
    
    # Save to JSON file
    $absolutePath = $OutputFile
    try {
        $absolutePath = (Resolve-Path -Path $OutputFile -ErrorAction Stop).Path
    } catch {
        $absolutePath = $OutputFile
    }
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $jsonString = $output | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($absolutePath, $jsonString, $utf8NoBom)
    
    [Console]::Error.WriteLine("Successfully saved $($grades.Count) grade(s) to: $OutputFile")
    
    $result = @{
        success = $true
        output_file = $OutputFile
        record_count = $grades.Count
    }
    $result | ConvertTo-Json -Compress
    exit 0
    
} catch {
    $errorMessage = $_.Exception.Message
    [Console]::Error.WriteLine("Error fetching grades: $errorMessage")
    
    $result = @{
        success = $false
        error = $errorMessage
    }
    $result | ConvertTo-Json -Compress
    exit 1
}

