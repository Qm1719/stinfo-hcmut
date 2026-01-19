# Analyze Grades Script for HCMIU
# Extracts insights and statistics from the grades JSON file

param(
    [string]$InputFile = "all_grades.json",
    [string]$SubjectsFile = "all_subjects.json"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

try {
    if (-not (Test-Path $InputFile)) {
        Write-Host "Error: File '$InputFile' not found!" -ForegroundColor Red
        exit 1
    }
    
    # Read and parse JSON
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $jsonContent = [System.IO.File]::ReadAllText($InputFile, $utf8)
    $data = $jsonContent | ConvertFrom-Json
    
    if (-not $data.data -or $data.data.Count -eq 0) {
        Write-Host "No grade data found in file!" -ForegroundColor Yellow
        exit 0
    }
    
    $grades = $data.data
    
    # Deduplicate courses - keep only the latest grade for each course (by stt number)
    # This handles retakes where the same course appears multiple times
    $deduplicatedGrades = @{}
    foreach ($grade in $grades) {
        $courseCode = $grade.maMonHoc
        if (-not $deduplicatedGrades.ContainsKey($courseCode)) {
            $deduplicatedGrades[$courseCode] = $grade
        } else {
            # Keep the one with higher stt (later entry)
            if ($grade.stt -gt $deduplicatedGrades[$courseCode].stt) {
                $deduplicatedGrades[$courseCode] = $grade
            }
        }
    }
    $grades = $deduplicatedGrades.Values
    
    # Department/prefix map - maps course code prefixes to department names
    # Supports prefixes up to 4 characters
    $departmentMap = @{
        # 2-character prefixes
        "EE" = "Electrical Engineering"
        "EN" = "Languages"
        "MA" = "Mathematics"
        "PE" = "Political Education / Philosophy"
        "PH" = "Physics"
        "PT" = "Physical Training"
        "MP" = "Military Education"
        "BM" = "Biomedical Engineering"
        "CE" = "Civil Engineering and Management"
        "BT" = "Bio-Technology"
        "IT" = "Computer Science & Engineering"
        "IS" = "Information Systems"
        "IU" = "International University"
        "BA" = "Business Administration"
        "CH" = "Chemistry"
        "CM" = "Construction Management"
        "EL" = "English Language"
        # 3-character prefixes
        "EEA" = "Electrical Engineering (Advanced)"
        "ENT" = "English (Twinning Program)"
        "IEM" = "Industrial Engineering & Management"
        "CEE" = "Chemical and Environmental Engineering"
        "EFA" = "Economics, Finance and Accounting"
        "CHE" = "Chemical Engineering"
        # 4-character prefixes
        "EEAC" = "Electrical Engineering (Advanced)"
        "ENTP" = "English (Twinning Program)"
        "BTBC" = "Bio-Technology (Biochemistry)"
        "BTFT" = "Bio-Technology (Food Technology)"
        "ENEE" = "Environmental Engineering"
        "MAAS" = "Mathematics (Applied Statistics)"
        "MAFE" = "Mathematics (Financial Engineering)"
    }
    
    # Load prefix meanings from subjects file if available (overrides department map)
    $prefixMeanings = $departmentMap.Clone()
    if (Test-Path $SubjectsFile) {
        try {
            $subjectsContent = [System.IO.File]::ReadAllText($SubjectsFile, $utf8)
            $subjectsData = $subjectsContent | ConvertFrom-Json
            if ($subjectsData.prefixMeanings) {
                # Convert PSCustomObject to hashtable and merge with department map
                $subjectsData.prefixMeanings.PSObject.Properties | ForEach-Object {
                    $prefixMeanings[$_.Name] = $_.Value
                }
            }
        } catch {
            Write-Host "Warning: Could not load prefix meanings from $SubjectsFile" -ForegroundColor Yellow
            Write-Host "         Using default department map." -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "   GRADE ANALYSIS REPORT (HCMIU)" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""
    
    # Basic Statistics
    Write-Host "BASIC STATISTICS" -ForegroundColor Yellow
    Write-Host ("-" * 70)
    Write-Host "Total Courses: $($grades.Count)"
    
    # Filter courses with credits > 0 for main analysis
    $creditedCourses = $grades | Where-Object { $_.soTinChi -gt 0 }
    $zeroCreditCourses = $grades | Where-Object { $_.soTinChi -eq 0 }
    
    Write-Host "Courses with Credits: $($creditedCourses.Count)"
    Write-Host "Zero-Credit Courses: $($zeroCreditCourses.Count)"
    Write-Host ""
    
    # Accumulated Credits: C and above count, but excluding Physical Training (PT) courses
    # This matches HCMIU's "Số tín chỉ tích lũy" calculation
    # Note: Physical Training courses are NOT counted in accumulated credits, even if they have C and above
    # HCMIU does not have C+ grade; passing grade is C and above
    $accumulatedCreditsCourses = $creditedCourses | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.tk_CH) -and
        $_.tk_CH -ne "P" -and
        $_.tk_CH -match '^(A\+|A|B\+|B|C)$' -and
        $_.maMonHoc -notmatch '^PT'
    }
    $totalAccumulatedCredits = ($accumulatedCreditsCourses | Measure-Object -Property soTinChi -Sum).Sum
    
    # Total Credits (all courses with grades, excluding P and empty)
    $allGradedCourses = $creditedCourses | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.tk_CH) -and
        $_.tk_CH -ne "P"
    }
    $totalCredits = ($allGradedCourses | Measure-Object -Property soTinChi -Sum).Sum
    
    Write-Host "Total Credits (all graded courses): $totalCredits"
    Write-Host "Accumulated Credits (C and above, excluding PT): $totalAccumulatedCredits"
    Write-Host ""
    
    # GPA Calculation using HCMIU grade scale
    # HCMIU Official Grade Scale:
    #   A+ = 4.0 (90-100) - Xuất sắc (Excellent)
    #   A  = 3.5 (80-89)  - Giỏi (Very good)
    #   B+ = 3.0 (70-79)  - Khá (Good)
    #   B  = 2.5 (60-69)  - Trung bình Khá (Fair)
    #   C  = 2.0 (50-59)  - Trung bình (Average) - PASSING GRADE
    #   D+ = 1.5 (40-49)  - Yếu (Weak)
    #   D  = 1.0 (30-39)  - Kém (Very weak)
    #   F  = 0.0 (<30)    - Không đạt (No passing)
    # Note: HCMIU does NOT have C+ grade. Passing grade is C and above.
    $gradeMap = @{
        "A+" = 4.0; "A" = 3.5; "B+" = 3.0; "B" = 2.5
        "C" = 2.0; "D+" = 1.5; "D" = 1.0; "F" = 0.0
    }
    
    # Cumulative GPA Calculation (according to HCMIU description):
    # Cumulative GPA = sum(GPA_value × credits) / sum(credits) for ALL completed graded courses
    # Excludes: P grades, zero-credit courses
    $totalPoints = 0
    $totalCreditsForGPA = 0
    
    foreach ($course in $allGradedCourses) {
        if ($gradeMap.ContainsKey($course.tk_CH)) {
            $points = $gradeMap[$course.tk_CH]
            $credits = $course.soTinChi
            $totalPoints += $points * $credits
            $totalCreditsForGPA += $credits
        }
    }
    
    # Calculate Cumulative GPA (all graded courses, excluding F and PT)
    # According to HCMIU: Cumulative GPA = sum(GPA_value × credits) / sum(credits) for all completed graded courses
    # Note: Website excludes F courses and PT (Physical Training) courses from GPA calculation
    # D+ and D courses ARE included in GPA calculation (calculate GPA normally)
    # Accumulated credits display only counts passed subjects (C and above, excluding PT)
    $allGradedNoFNoPT = $allGradedCourses | Where-Object { $_.tk_CH -ne "F" -and $_.maMonHoc -notmatch '^PT' }
    $cumulativePointsNoF = 0
    $cumulativeCreditsNoF = 0
    foreach ($course in $allGradedNoFNoPT) {
        if ($gradeMap.ContainsKey($course.tk_CH)) {
            $points = $gradeMap[$course.tk_CH]
            $credits = $course.soTinChi
            $cumulativePointsNoF += $points * $credits
            $cumulativeCreditsNoF += $credits
        }
    }
    $cumulativeGPA = if ($cumulativeCreditsNoF -gt 0) { [math]::Round($cumulativePointsNoF / $cumulativeCreditsNoF, 2) } else { 0 }
    
    Write-Host "GPA: $cumulativeGPA / 4.0" -ForegroundColor Cyan
    Write-Host "ACCUMULATED CREDITS: $totalAccumulatedCredits" -ForegroundColor Cyan
    Write-Host ""
    
    # Grade Distribution
    Write-Host "GRADE DISTRIBUTION (Credited Courses)" -ForegroundColor Yellow
    Write-Host ("-" * 70)
    $gradeGroups = $creditedCourses | Group-Object -Property tk_CH | Sort-Object Count -Descending
    foreach ($group in $gradeGroups) {
        $percentage = [math]::Round(($group.Count / $creditedCourses.Count) * 100, 1)
        $bar = "#" * [math]::Floor($percentage / 2)
        $pct = $percentage.ToString("F1").PadLeft(5)
        $percentChar = [char]37  # % character
        $line = $group.Name.PadRight(3) + " : " + $group.Count.ToString().PadLeft(3) + " courses (" + $pct + $percentChar + ") " + $bar
        Write-Host $line
    }
    Write-Host ""
    
    # Helper function to get numeric score from tk_10 (handles "P" and "F" strings)
    function Get-NumericScore {
        param($score)
        if ($null -eq $score) { return $null }
        if ($score -is [string]) {
            if ($score -eq "P" -or $score -eq "F") { return $null }
            $parsed = 0
            if ([double]::TryParse($score, [ref]$parsed)) {
                return $parsed
            }
            return $null
        }
        return [double]$score
    }
    
    # Best and Worst Courses (exclude P grades)
    Write-Host "TOP PERFORMING COURSES" -ForegroundColor Yellow
    Write-Host ("-" * 70)
    $topCourses = @()
    foreach ($course in $creditedCourses) {
        if ($course.tk_CH -eq "P") { continue }
        $score = Get-NumericScore -score $course.tk_10
        if ($null -ne $score) {
            $topCourses += [PSCustomObject]@{
                Course = $course
                Score = $score
            }
        }
    }
    $topCourses = $topCourses | Sort-Object Score -Descending | Select-Object -First 5
    if ($topCourses.Count -gt 0) {
        $rank = 1
        foreach ($item in $topCourses) {
            $course = $item.Course
            Write-Host ("{0}. {1} ({2}) - {3} credits - Grade: {4} ({5})" -f 
                $rank, $course.tenMonHoc, $course.maMonHoc, $course.soTinChi, $course.tk_CH, $course.tk_10)
            $rank++
        }
    } else {
        Write-Host "No courses found (excluding P grades)."
    }
    Write-Host ""
    
    Write-Host "COURSES NEEDING ATTENTION" -ForegroundColor Yellow
    Write-Host ("-" * 70)
    $lowCourses = @()
    foreach ($course in $creditedCourses) {
        # Skip P grades and ENTP courses
        if ($course.tk_CH -eq "P" -or $course.maMonHoc -match '^ENTP') { continue }
        
        # Include failed courses (F, D, D+) - these always need attention
        $isFailed = $course.tk_CH -eq "F" -or $course.tk_CH -eq "D" -or $course.tk_CH -eq "D+"
        
        if ($isFailed) {
            $score = Get-NumericScore -score $course.tk_10
            $lowCourses += [PSCustomObject]@{
                Course = $course
                Score = $score
            }
        } else {
            # Also include courses with low scores (< 5.0 on 10-point scale or < 50 on 100-point scale)
            $score = Get-NumericScore -score $course.tk_10
            if ($null -ne $score -and ($score -lt 5.0 -or ($score -ge 10 -and $score -lt 50))) {
                $lowCourses += [PSCustomObject]@{
                    Course = $course
                    Score = $score
                }
            }
        }
    }
    # Sort by score (null scores go to end)
    if ($lowCourses.Count -gt 0) {
        $lowCourses = @($lowCourses | Sort-Object {
            if ($null -eq $_.Score) { [double]::MaxValue } else { $_.Score }
        } | Select-Object -First 5)
    }
    if ($lowCourses.Count -gt 0) {
        $rank = 1
        foreach ($item in $lowCourses) {
            $course = $item.Course
            Write-Host ("{0}. {1} ({2}) - {3} credits - Grade: {4} ({5})" -f 
                $rank, $course.tenMonHoc, $course.maMonHoc, $course.soTinChi, $course.tk_CH, $course.tk_10)
            $rank++
        }
    } else {
        Write-Host "None! Great job!" -ForegroundColor Green
    }
    Write-Host ""
    
    # Semester Analysis (if maHocKy is populated)
    $semesterGroups = $creditedCourses | Where-Object { -not [string]::IsNullOrWhiteSpace($_.maHocKy) } | Group-Object -Property maHocKy | Sort-Object Name
    if ($semesterGroups.Count -gt 0) {
        Write-Host "SEMESTER BREAKDOWN" -ForegroundColor Yellow
        Write-Host ("-" * 70)
        foreach ($semester in $semesterGroups) {
            $semCredits = ($semester.Group | Measure-Object -Property soTinChi -Sum).Sum
            $semScores = @()
            foreach ($course in $semester.Group) {
                $score = Get-NumericScore -score $course.tk_10
                if ($null -ne $score) {
                    $semScores += $score
                }
            }
            $semAvg = if ($semScores.Count -gt 0) { [math]::Round(($semScores | Measure-Object -Average).Average, 2) } else { "N/A" }
            Write-Host ("{0}: {1} courses, {2} credits, Avg Score: {3}" -f 
                $semester.Name, $semester.Count, $semCredits, $semAvg)
        }
        Write-Host ""
    }
    
    # Course Categories - Using prefix meanings from subjects file
    Write-Host "COURSE CATEGORIES" -ForegroundColor Yellow
    Write-Host ("-" * 70)
    
    # Group courses by department/prefix
    $categoryGroups = @{}
    foreach ($course in $creditedCourses) {
        # Extract prefix: try 4 chars first, then 3, then 2
        $prefix = ""
        if ($course.maMonHoc -match '^([A-Z]{4})') {
            $prefix = $matches[1]
        } elseif ($course.maMonHoc -match '^([A-Z]{3})') {
            $prefix = $matches[1]
        } elseif ($course.maMonHoc -match '^([A-Z]{2})') {
            $prefix = $matches[1]
        }
        
        if (-not [string]::IsNullOrWhiteSpace($prefix)) {
            $category = if ($prefixMeanings.ContainsKey($prefix)) {
                $prefixMeanings[$prefix]
            } else {
                "Other ($prefix)"
            }
            
            if (-not $categoryGroups.ContainsKey($category)) {
                $categoryGroups[$category] = @()
            }
            $categoryGroups[$category] += $course
        }
    }
    
    # Display categories sorted by course count (descending)
    $sortedCategories = $categoryGroups.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending
    
    foreach ($categoryEntry in $sortedCategories) {
        $category = $categoryEntry.Key
        $courses = $categoryEntry.Value
        $credits = ($courses | Measure-Object -Property soTinChi -Sum).Sum
        
        # Check if all courses are P grades first
        $pCount = ($courses | Where-Object { $_.tk_CH -eq "P" }).Count
        $allP = ($pCount -eq $courses.Count -and $pCount -gt 0)
        
        if ($allP) {
            # All courses are P grades
            Write-Host ("{0}: {1} courses, {2} credits (all P)" -f 
                $category, $courses.Count, $credits)
        } else {
            # Calculate average grade (excluding P grades and courses without scores)
            $scoredCourses = @()
            foreach ($course in $courses) {
                $score = Get-NumericScore -score $course.tk_10
                if ($null -ne $score -and $course.tk_CH -ne "P" -and -not [string]::IsNullOrWhiteSpace($course.tk_CH)) {
                    $scoredCourses += $score
                }
            }
            
            if ($scoredCourses.Count -gt 0) {
                $avg = ($scoredCourses | Measure-Object -Average).Average
                $avg = [math]::Round($avg, 2)
                Write-Host ("{0}: {1} courses, {2} credits, Avg: {3}" -f 
                    $category, $courses.Count, $credits, $avg)
            } else {
                # No scores available
                Write-Host ("{0}: {1} courses, {2} credits" -f 
                    $category, $courses.Count, $credits)
            }
        }
    }
    Write-Host ""
    
    # Failed Courses
    $failedCourses = $creditedCourses | Where-Object { $_.tk_CH -eq "F" -or $_.tk_CH -eq "D" -or $_.tk_CH -eq "D+" }
    if ($failedCourses.Count -gt 0) {
        Write-Host "FAILED COURSES" -ForegroundColor Red
        Write-Host ("-" * 70)
        foreach ($course in $failedCourses) {
            Write-Host ("- {0} ({1}) - {2} credits - Score: {3}" -f 
                $course.tenMonHoc, $course.maMonHoc, $course.soTinChi, $course.tk_10)
        }
        Write-Host ""
    }
    
    # Recommendations - GPA Improvement Plan
    Write-Host "RECOMMENDATIONS - GPA IMPROVEMENT PLAN" -ForegroundColor Yellow
    Write-Host ("-" * 70)
    
    # Function to determine target grade based on current grade
    function Get-TargetGrade {
        param(
            [string]$CurrentGrade,
            [double]$TargetGPA
        )
        
        # For 3.2 target: +2 grade points
        if ($TargetGPA -eq 3.2) {
            if (-not $gradeMap.ContainsKey($CurrentGrade)) {
                return $null
            }
            $currentPoints = $gradeMap[$CurrentGrade]
            $targetPoints = $currentPoints + 2
            
            # Cap at 4.0 (A+)
            if ($targetPoints -gt 4.0) {
                $targetPoints = 4.0
            }
            
            # Find the grade that matches the target points
                   $reverseGradeMap = @{
                       4.0 = "A+"
                       3.5 = "A"
                       3.0 = "B+"
                       2.5 = "B"
                       2.0 = "C"
                       1.5 = "D+"
                       1.0 = "D"
                       0.0 = "F"
                   }
            
            # Find closest grade point value
            $closestPoints = 0
            $minDiff = 999
            foreach ($points in $reverseGradeMap.Keys) {
                $diff = [math]::Abs($points - $targetPoints)
                if ($diff -lt $minDiff) {
                    $minDiff = $diff
                    $closestPoints = $points
                }
            }
            
            return $reverseGradeMap[$closestPoints]
        }
        
        # For 2.8 target: fixed mapping
        # Note: HCMIU doesn't have C+, so D+ maps to C (same as D and F)
        switch ($CurrentGrade) {
            "F" { return "C" }
            "D" { return "C" }
            "D+" { return "C" }
            "C" { return "B" }
            "B" { return "B+" }
            default { return $null }
        }
    }
    
    # Get courses that can be improved (excluding P, PT, and language courses that were skipped)
    # Exclude ENTP courses (Intensive English) as they are typically skipped with IELTS
    # For 3.2 target, check ALL courses (even B/B+) as they can still be improved
    $improvableCourses = $creditedCourses | Where-Object {
        $_.tk_CH -ne "P" -and 
        $_.tk_CH -ne "A+" -and  # A+ is already the highest
        $_.maMonHoc -notmatch '^PT' -and
        $_.maMonHoc -notmatch '^ENTP' -and
        $gradeMap.ContainsKey($_.tk_CH)
    }
    
    # Calculate improvement scenarios for target GPAs
    $targetGPAs = @(2.8, 3.2)
    
    foreach ($targetGPA in $targetGPAs) {
        if ($cumulativeGPA -ge $targetGPA) {
            Write-Host ("Target GPA {0}: Already achieved! Current GPA: {1}" -f $targetGPA, $cumulativeGPA) -ForegroundColor Green
            Write-Host ""
            continue
        }
        
        # Use the correct GPA calculation variables (excluding PT and F)
        $requiredPoints = $targetGPA * $cumulativeCreditsNoF
        $pointsNeeded = $requiredPoints - $cumulativePointsNoF
        $pointsNeeded = [math]::Round($pointsNeeded, 2)
        
        Write-Host "Target GPA: $targetGPA" -ForegroundColor Cyan
        Write-Host ("Current GPA: {0}, Points needed: {1}" -f $cumulativeGPA, $pointsNeeded)
        Write-Host ""
        
        # Create list of possible improvements
        $improvements = @()
        foreach ($course in $improvableCourses) {
            $currentGrade = $course.tk_CH
            $targetGrade = Get-TargetGrade -CurrentGrade $currentGrade -TargetGPA $targetGPA
            
            if ($targetGrade -and $gradeMap.ContainsKey($targetGrade)) {
                $currentPoints = $gradeMap[$currentGrade]
                $targetPoints = $gradeMap[$targetGrade]
                $pointsGain = ($targetPoints - $currentPoints) * $course.soTinChi
                
                # Only include if there's actual improvement
                if ($pointsGain -gt 0) {
                    $improvements += [PSCustomObject]@{
                        Course = $course
                        CurrentGrade = $currentGrade
                        TargetGrade = $targetGrade
                        Credits = $course.soTinChi
                        PointsGain = $pointsGain
                        CourseName = $course.tenMonHoc
                        CourseCode = $course.maMonHoc
                    }
                }
            }
        }
        
        # Sort by priority: failed courses first, then lower grades, then by points gain
        # Priority order: F > D > D+ > C > B > B+ > A (lower grades = higher priority)
        $gradePriority = @{
            "F" = 1; "D" = 2; "D+" = 3; "C" = 4; "B" = 5; "B+" = 6; "A" = 7; "A+" = 8
        }
        
        # Add priority to each improvement
        foreach ($imp in $improvements) {
            $priority = if ($gradePriority.ContainsKey($imp.CurrentGrade)) { $gradePriority[$imp.CurrentGrade] } else { 99 }
            $imp | Add-Member -NotePropertyName "Priority" -NotePropertyValue $priority -Force
        }
        
        # Sort: first by priority (ascending - lower number = higher priority), then by points gain (descending)
        $improvements = $improvements | Sort-Object Priority, @{Expression={-$_.PointsGain}}
        
        # Greedy algorithm: select minimum courses to reach target
        $selectedImprovements = @()
        $totalGain = 0
        $remainingNeeded = $pointsNeeded
        $usedCourses = @{}  # Track which courses we've already improved
        
        # Continue selecting until we reach target or run out of improvements
        while ($remainingNeeded -gt 0.01 -and $improvements.Count -gt 0) {
            $bestImprovement = $null
            $bestIndex = -1
            
            # Find the best improvement we haven't used yet
            # Prioritize: failed courses first, then lower grades, then by points gain
            for ($i = 0; $i -lt $improvements.Count; $i++) {
                $imp = $improvements[$i]
                $courseKey = $imp.CourseCode
                
                if (-not $usedCourses.ContainsKey($courseKey)) {
                    if ($bestImprovement -eq $null) {
                        $bestImprovement = $imp
                        $bestIndex = $i
                    } else {
                        # Compare: priority first (lower = better), then points gain
                        $impPriority = if ($imp.Priority) { $imp.Priority } else { 99 }
                        $bestPriority = if ($bestImprovement.Priority) { $bestImprovement.Priority } else { 99 }
                        
                        if ($impPriority -lt $bestPriority) {
                            # Lower priority number = higher priority (F=1 is better than B=5)
                            $bestImprovement = $imp
                            $bestIndex = $i
                        } elseif ($impPriority -eq $bestPriority -and $imp.PointsGain -gt $bestImprovement.PointsGain) {
                            # Same priority, choose higher points gain
                            $bestImprovement = $imp
                            $bestIndex = $i
                        }
                    }
                }
            }
            
            if ($bestImprovement -eq $null) {
                break  # No more improvements available
            }
            
            $selectedImprovements += $bestImprovement
            $totalGain += $bestImprovement.PointsGain
            $remainingNeeded -= $bestImprovement.PointsGain
            $usedCourses[$bestImprovement.CourseCode] = $true
        }
        
        if ($selectedImprovements.Count -eq 0) {
            Write-Host "  No feasible improvement path found with current courses." -ForegroundColor Yellow
        } else {
            Write-Host "  Minimum courses to improve: $($selectedImprovements.Count)" -ForegroundColor Green
            Write-Host ""
            Write-Host "  Recommended improvements:" -ForegroundColor Yellow
            $rank = 1
            foreach ($imp in $selectedImprovements) {
                Write-Host ("    {0}. {1} ({2})" -f $rank, $imp.CourseName, $imp.CourseCode) -ForegroundColor White
                Write-Host ("       Current: {0} -> Target: {1} ({2} credits, +{3} points)" -f 
                    $imp.CurrentGrade, $imp.TargetGrade, $imp.Credits, [math]::Round($imp.PointsGain, 2)) -ForegroundColor Gray
                $rank++
            }
            
            $newGPA = [math]::Round(($cumulativePointsNoF + $totalGain) / $cumulativeCreditsNoF, 2)
            Write-Host ""
            if ($newGPA -ge $targetGPA) {
                Write-Host ("  Projected GPA after improvements: {0} / 4.0 (Target achieved!)" -f $newGPA) -ForegroundColor Green
            } else {
                Write-Host ("  Projected GPA after improvements: {0} / 4.0 (Target: {1}, still need {2} more points)" -f 
                    $newGPA, $targetGPA, [math]::Round($remainingNeeded, 2)) -ForegroundColor Yellow
            }
        }
        Write-Host ""
    }
    
    # General recommendations
    if ($gpa -ge 3.5) {
        Write-Host "Excellent GPA! Keep up the great work!" -ForegroundColor Green
    } elseif ($gpa -ge 3.0) {
        Write-Host "Good GPA! You're doing well." -ForegroundColor Green
    } elseif ($gpa -ge 2.5) {
        Write-Host "Average GPA. Focus on the improvement plan above." -ForegroundColor Yellow
    } else {
        Write-Host "GPA needs improvement. Follow the improvement plan above." -ForegroundColor Red
    }
    
    if ($failedCourses.Count -gt 0) {
        Write-Host ("You have {0} failed course(s). Prioritize retaking them." -f $failedCourses.Count) -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""
    
} catch {
    Write-Host "Error analyzing grades: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    exit 1
}

