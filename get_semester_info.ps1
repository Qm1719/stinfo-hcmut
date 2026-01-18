# Semester Helper Functions
# Calculates default semester and gets available semesters

param(
    [switch]$GetDefault,
    [switch]$GetAvailable,
    [string]$AuthToken = "",
    [string]$Cookie = "",
    [string]$StudentId = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Calculate default semester based on current date
function Get-DefaultSemester {
    $now = Get-Date
    $month = $now.Month
    $year = $now.Year
    
    # Academic year logic (plus 1 to adjust cuz it's a grade fetching script):
    # Sem 1: Oct (10), Nov (11), Dec (12), Jan (1) - year starts from Oct
    # Sem 2: Feb (2), Mar (3), Apr (4), May (5), Jun (6), Jul (7)
    # Sem 3: Aug (8), Sep (9)
    # Year is counted from Sem 1, so if we're in Jan 2026, we're in 2025 academic year
    
    $academicYear = $year
    $semester = 1
    
    if ($month -ge 10 -or $month -eq 1) {
        # Sem 1: Oct, Nov, Dec, Jan
        $semester = 1
        if ($month -eq 1) {
            $academicYear = $year - 1
        }
    } elseif ($month -ge 2 -and $month -le 7) {
        # Sem 2: Feb, Mar, Apr, May, Jun, Jul
        $semester = 2
        $academicYear = $year - 1
    } elseif ($month -ge 8 -and $month -le 9) {
        # Sem 3: Aug, Sep
        $semester = 3
        $academicYear = $year - 1
    }
    
    # Format as 5 digits: YYYYS (e.g., 20251)
    $semesterCode = "$academicYear$semester"
    return $semesterCode
}

# Get available semesters from all_grades.json if it exists
function Get-AvailableSemestersFromFile {
    $gradesFile = "all_grades.json"
    if (Test-Path $gradesFile) {
        try {
            $utf8 = New-Object System.Text.UTF8Encoding $false
            $jsonContent = [System.IO.File]::ReadAllText($gradesFile, $utf8)
            $data = $jsonContent | ConvertFrom-Json
            
            if ($data.data -and $data.data.Count -gt 0) {
                $semesters = $data.data | Select-Object -ExpandProperty maHocKy -Unique | Sort-Object -Descending
                return $semesters
            }
        } catch {
            # If file exists but can't be parsed, return empty
            return @()
        }
    }
    return @()
}

# Generate recent semesters based on current date
function Get-RecentSemesters {
    $defaultSem = Get-DefaultSemester
    $semesters = @($defaultSem)
    
    # Extract year and semester from default
    $year = [int]($defaultSem.Substring(0, 4))
    $sem = [int]($defaultSem.Substring(4, 1))
    
    # Add previous semesters (up to 21 semesters back)
    for ($i = 1; $i -le 21; $i++) {
        $sem--
        if ($sem -lt 1) {
            $sem = 3
            $year--
        }
        $prevSem = "$year$sem"
        $semesters += $prevSem
    }
    
    return $semesters
}

# Main execution
if ($GetDefault) {
    $default = Get-DefaultSemester
    Write-Output $default
    exit 0
}

if ($GetAvailable) {
    # Try to get from file first
    $fromFile = Get-AvailableSemestersFromFile
    if ($fromFile.Count -gt 0) {
        # Output as JSON array for easy parsing
        $fromFile | ConvertTo-Json -Compress
        exit 0
    }
    
    # Fallback to recent semesters
    $recent = Get-RecentSemesters
    $recent | ConvertTo-Json -Compress
    exit 0
}

# Default: just return default semester
$default = Get-DefaultSemester
Write-Output $default

