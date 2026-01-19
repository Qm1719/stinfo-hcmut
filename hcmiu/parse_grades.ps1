# Parse and display grades for HCMIU (PowerShell)
# Reads JSON from stdin or file parameter

param(
    [string]$InputFile = ""
)

# Force UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

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
    $header = "   " + [char]0x004B + [char]0x1EBE + [char]0x0054 + " " + [char]0x0051 + [char]0x0055 + [char]0x1EA2 + " " + [char]0x0048 + [char]0x1ECC + [char]0x0043 + " " + [char]0x0054 + [char]0x1EAC + [char]0x0050 + " - HCMIU"
    Write-Host $header
    Write-Host ("=" * 50)
    Write-Host ""
    
    if ($data.code -ne "200") {
        Write-Host "Error: $($data.msg)" -ForegroundColor Red
        exit 1
    }
    
    $grades = $data.data
    
    if (-not $grades -or $grades.Count -eq 0) {
        # Construct Vietnamese text using Unicode to avoid encoding issues
        $noSubjectsMsg = [char]0x004B + [char]0x0068 + [char]0x00F4 + [char]0x006E + [char]0x0067 + " " + [char]0x0074 + [char]0x00EC + [char]0x006D + " " + [char]0x0074 + [char]0x0068 + [char]0x1EA5 + [char]0x0079 + " " + [char]0x006D + [char]0x00F4 + [char]0x006E + " " + [char]0x0068 + [char]0x1ECD + [char]0x0063 + " " + [char]0x006E + [char]0x00E0 + [char]0x006F + "!"
        Write-Host $noSubjectsMsg -ForegroundColor Yellow
        exit 0
    }
    
    # Group by semester
    $semesterGroups = $grades | Group-Object -Property maHocKy | Sort-Object Name
    
    $idx = 1
    foreach ($semesterGroup in $semesterGroups) {
        Write-Host "Học kỳ: $($semesterGroup.Name)" -ForegroundColor Cyan
        Write-Host ("-" * 50)
        
        foreach ($grade in $semesterGroup.Group) {
            $stt = $grade.stt
            $nameVi = $grade.tenMonHoc
            $code = $grade.maMonHoc
            $credits = $grade.soTinChi
            $tk10 = $grade.tk_10
            $tkCH = $grade.tk_CH
            
            # Output line - use Unicode for "tín chỉ" to avoid encoding issues
            $creditsText = [char]0x0074 + [char]0x00ED + [char]0x006E + " " + [char]0x0063 + [char]0x0068 + [char]0x1EC9
            
            $line = "[$stt] $nameVi ($code) - $credits $creditsText"
            
            # Show TK(10) if available
            if ($tk10 -ne $null) {
                if ($tk10 -is [double] -or $tk10 -is [int]) {
                    $line += " - TK(10): $tk10"
                } else {
                    $line += " - TK(10): $tk10"
                }
            }
            
            # Show TK(CH) if available
            if (-not [string]::IsNullOrWhiteSpace($tkCH)) {
                $line += " - TK(CH): $tkCH"
            }
            
            Write-Host $line
            
            $idx++
        }
        
        Write-Host ""
    }
    
    Write-Host ("=" * 50)
    
} catch {
    Write-Host "Error: Could not read JSON data!" -ForegroundColor Red
    Write-Host "Session may have expired, please login again!" -ForegroundColor Yellow
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

