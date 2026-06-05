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

# Convert 5-digit semester code (e.g. 20252) to 3-digit (e.g. 252)
function Get-ShortSemesterCode {
    param([string]$SemesterCode = "")
    
    if ([string]::IsNullOrWhiteSpace($SemesterCode)) {
        $SemesterCode = Get-DefaultSemester
    }
    
    if ($SemesterCode -match '^\d{5}$') {
        return $SemesterCode.Substring(2)
    }
    
    return $SemesterCode
}

# Build semester list from student ID: xx1 through current (e.g. 23xxxxx -> 231..252)
function Get-SemestersFromStudentId {
    param(
        [string]$StudentId,
        [string]$CurrentSemester = ""
    )
    
    if ([string]::IsNullOrWhiteSpace($StudentId) -or $StudentId.Length -lt 2) {
        return @()
    }
    
    $prefix = $StudentId.Substring(0, 2)
    if ($prefix -notmatch '^\d{2}$') {
        return @()
    }
    
    $currentShort = Get-ShortSemesterCode -SemesterCode $CurrentSemester
    if ($currentShort -notmatch '^\d{3}$') {
        return @()
    }
    
    $startYear = [int]$prefix
    $startSem = 1
    $currentYear = [int]$currentShort.Substring(0, 2)
    $currentSem = [int]$currentShort.Substring(2, 1)
    
    $semesters = @()
    for ($year = $startYear; $year -le $currentYear; $year++) {
        $firstSem = if ($year -eq $startYear) { $startSem } else { 1 }
        $lastSem = if ($year -eq $currentYear) { $currentSem } else { 3 }
        
        for ($sem = $firstSem; $sem -le $lastSem; $sem++) {
            $shortCode = "$year$sem"
            $semesters += "20$shortCode"
        }
    }
    
    return $semesters | Sort-Object -Descending
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
    if (-not [string]::IsNullOrWhiteSpace($StudentId)) {
        $fromStudent = Get-SemestersFromStudentId -StudentId $StudentId
        if ($fromStudent.Count -gt 0) {
            $fromStudent | ConvertTo-Json -Compress
            exit 0
        }
    }
    
    # Fallback to recent semesters when student ID is unavailable
    $recent = Get-RecentSemesters
    $recent | ConvertTo-Json -Compress
    exit 0
}

# Default: just return default semester
$default = Get-DefaultSemester
Write-Output $default

