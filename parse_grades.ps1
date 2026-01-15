# Parse and display grades (PowerShell)
# Reads JSON from stdin or file parameter

param(
    [string]$InputFile = ""
)

# Force UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Function to fix Vietnamese encoding errors - only fix the specific corrupted strings
function Fix-VietnameseEncoding {
    param([string]$text)
    
    # Only replace if we see the corrupted version, otherwise leave as-is
    # Replace corrupted header pattern
    if ($text -match 'K[^\x00-\x7F]+T QU[^\x00-\x7F]+ H[^\x00-\x7F]+C T[^\x00-\x7F]+P') {
        $text = $text -replace 'K[^\x00-\x7F]+T QU[^\x00-\x7F]+ H[^\x00-\x7F]+C T[^\x00-\x7F]+P', 'KẾT QUẢ HỌC TẬP'
    }
    
    # Replace corrupted "tín chỉ" pattern - be more specific to avoid false matches
    if ($text -match 't[^\x00-\x7F]+n ch[^\x00-\x7F]+' -and $text -notmatch 'tín chỉ') {
        $text = $text -replace 't[^\x00-\x7F]+n ch[^\x00-\x7F]+', 'tín chỉ'
    }
    
    return $text
}

try {
    $input = ""
    
    # If file parameter provided, read from file
    if ($InputFile -ne "" -and (Test-Path $InputFile)) {
        $input = Get-Content $InputFile -Raw -Encoding UTF8
    } else {
        # Try to read from stdin
        try {
            $input = [Console]::In.ReadToEnd()
        } catch {
            Write-Host "Error: Could not read input!" -ForegroundColor Red
            exit 1
        }
    }
    
    if ([string]::IsNullOrWhiteSpace($input)) {
        Write-Host "Error: No input data received!" -ForegroundColor Red
        exit 1
    }
    
    # Remove any BOM or leading whitespace
    $input = $input.TrimStart([char]0xFEFF)
    $input = $input.Trim()
    
    # Parse JSON
    try {
        $data = $input | ConvertFrom-Json
    } catch {
        Write-Host "Error: Invalid JSON format!" -ForegroundColor Red
        Write-Host "Response preview: $($input.Substring(0, [Math]::Min(200, $input.Length)))" -ForegroundColor Yellow
        exit 1
    }
    
    # Output header - use Unicode characters directly
    Write-Host ""
    Write-Host ("=" * 50)
    $header = "   " + [char]0x004B + [char]0x1EBE + [char]0x0054 + " " + [char]0x0051 + [char]0x0055 + [char]0x1EA2 + " " + [char]0x0048 + [char]0x1ECC + [char]0x0043 + " " + [char]0x0054 + [char]0x1EAC + [char]0x0050 + " - HCMUT"
    Write-Host $header
    Write-Host ("=" * 50)
    Write-Host ""
    
    if ($data.code -ne "200") {
        Write-Host "Error: $($data.msg)" -ForegroundColor Red
        exit 1
    }
    
    $subjects = $data.data
    
    if (-not $subjects -or $subjects.Count -eq 0) {
        Write-Host "Không tìm thấy môn học nào!" -ForegroundColor Yellow
        exit 0
    }
    
    $idx = 1
    foreach ($subject in $subjects) {
        $subjectInfo = $subject.subject
        $nameVi = $subjectInfo.nameVi
        $credits = $subjectInfo.numOfCredits
        
        # Output line - use Unicode for "tín chỉ" to avoid encoding issues
        $creditsText = [char]0x0074 + [char]0x00ED + [char]0x006E + " " + [char]0x0063 + [char]0x0068 + [char]0x1EC9
        $line = "[$idx] $nameVi ($($subjectInfo.code)) - $credits $creditsText"
        Write-Host $line
        
        $grades = $subject.studentSubjectGradeDetails
        foreach ($gradeDetail in $grades) {
            $gradeName = $gradeDetail.gradeColumnDictionary.nameVi
            $grade = $gradeDetail.grade
            $percentage = $gradeDetail.percentage
            
            $gradeLine = ""
            if ($gradeName -match "Tổng kết") {
                $gradeLine = "    -> $gradeName : $grade"
            } else {
                $gradeLine = "    - $gradeName : $grade ($percentage%)"
            }
            # Output grade line as-is (data is already correct)
            Write-Host $gradeLine
        }
        
        Write-Host ""
        $idx++
    }
    
    Write-Host ("=" * 50)
    
} catch {
    Write-Host "Error: Could not read JSON data!" -ForegroundColor Red
    Write-Host "Token may have expired, please login again!" -ForegroundColor Yellow
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
