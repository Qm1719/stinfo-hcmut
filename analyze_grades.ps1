# Analyze Grades Script
# Extracts insights and statistics from the grades JSON file

param(
    [string]$InputFile = "all_grades.json"
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
    
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "   GRADE ANALYSIS REPORT" -ForegroundColor Cyan
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
    
    # Total Credits (all courses including MT)
    $totalCredits = ($creditedCourses | Measure-Object -Property soTinChi -Sum).Sum
    Write-Host "Total Credits: $totalCredits"
    Write-Host ""
    
    # GPA Calculation (weighted by credits, excluding MT grades)
    # MT grades count for credits but not for GPA points
    $totalPoints = 0
    $totalCreditsForGPA = 0
    $gradeMap = @{
        "A+" = 4.0; "A" = 4.0; "B+" = 3.5; "B" = 3.0; "C+" = 2.5
        "C" = 2.0; "D+" = 1.5; "D" = 1.0; "F" = 0.0
    }
    
    foreach ($course in $creditedCourses) {
        # Skip MT grades - they don't count in GPA but count in total credits
        if ($course.diemChu -eq "MT") {
            continue
        }
        
        if ($gradeMap.ContainsKey($course.diemChu)) {
            $points = $gradeMap[$course.diemChu]
            $credits = $course.soTinChi
            $totalPoints += $points * $credits
            $totalCreditsForGPA += $credits
        }
    }
    
    $gpa = if ($totalCreditsForGPA -gt 0) { [math]::Round($totalPoints / $totalCreditsForGPA, 2) } else { 0 }
    Write-Host "GPA (Weighted by Credits, excluding MT): $gpa / 4.0"
    Write-Host "Total Credits for GPA: $totalCreditsForGPA / $totalCredits"
    Write-Host ""
    Write-Host "TOTAL GPA: $gpa / 4.0" -ForegroundColor Cyan
    Write-Host ""
    
    # Grade Distribution
    Write-Host "GRADE DISTRIBUTION (Credited Courses)" -ForegroundColor Yellow
    Write-Host ("-" * 70)
    $gradeGroups = $creditedCourses | Group-Object -Property diemChu | Sort-Object Count -Descending
    foreach ($group in $gradeGroups) {
        $percentage = [math]::Round(($group.Count / $creditedCourses.Count) * 100, 1)
        $bar = "#" * [math]::Floor($percentage / 2)
        $pct = $percentage.ToString("F1").PadLeft(5)
        $percentChar = [char]37  # % character
        $line = $group.Name.PadRight(3) + " : " + $group.Count.ToString().PadLeft(3) + " courses (" + $pct + $percentChar + ") " + $bar
        Write-Host $line
    }
    Write-Host ""
    
    # Best and Worst Courses (exclude MT grades)
    Write-Host "TOP PERFORMING COURSES" -ForegroundColor Yellow
    Write-Host ("-" * 70)
    $topCourses = $creditedCourses | Where-Object { 
        $_.diemSo -ne $null -and $_.diemChu -ne "MT" 
    } | Sort-Object diemSo -Descending | Select-Object -First 5
    if ($topCourses.Count -gt 0) {
        $rank = 1
        foreach ($course in $topCourses) {
            Write-Host ("{0}. {1} ({2}) - {3} credits - Grade: {4} ({5})" -f 
                $rank, $course.tenMonHoc, $course.maMonHoc, $course.soTinChi, $course.diemChu, $course.diemSo)
            $rank++
        }
    } else {
        Write-Host "No courses found (excluding MT grades)."
    }
    Write-Host ""
    
    Write-Host "COURSES NEEDING ATTENTION" -ForegroundColor Yellow
    Write-Host ("-" * 70)
    $lowCourses = $creditedCourses | Where-Object { 
        $_.diemSo -ne $null -and ($_.diemSo -lt 5.0 -or $_.diemChu -eq "F" -or $_.diemChu -eq "D" -or $_.diemChu -eq "D+")
    } | Sort-Object diemSo | Select-Object -First 5
    if ($lowCourses.Count -gt 0) {
        $rank = 1
        foreach ($course in $lowCourses) {
            Write-Host ("{0}. {1} ({2}) - {3} credits - Grade: {4} ({5})" -f 
                $rank, $course.tenMonHoc, $course.maMonHoc, $course.soTinChi, $course.diemChu, $course.diemSo)
            if ($course.ghiChu) {
                Write-Host ("   Note: {0}" -f $course.ghiChu) -ForegroundColor Gray
            }
            $rank++
        }
    } else {
        Write-Host "None! Great job!" -ForegroundColor Green
    }
    Write-Host ""
    
    # Semester Analysis
    Write-Host "SEMESTER BREAKDOWN" -ForegroundColor Yellow
    Write-Host ("-" * 70)
    $semesterGroups = $creditedCourses | Group-Object -Property maHocKy | Sort-Object Name
    foreach ($semester in $semesterGroups) {
        $semCredits = ($semester.Group | Measure-Object -Property soTinChi -Sum).Sum
        $semAvg = ($semester.Group | Where-Object { $_.diemSo -ne $null } | Measure-Object -Property diemSo -Average).Average
        $semAvg = if ($semAvg) { [math]::Round($semAvg, 2) } else { "N/A" }
        Write-Host ("{0}: {1} courses, {2} credits, Avg Score: {3}" -f 
            $semester.Name, $semester.Count, $semCredits, $semAvg)
    }
    Write-Host ""
    
    # Course Categories - Using complete department mapping
    Write-Host "COURSE CATEGORIES" -ForegroundColor Yellow
    Write-Host ("-" * 70)
    
    # Complete Department Mapping (same as analyze_subjects_complete.ps1)
    $departmentMap = @{
        'ME' = 'Mechanical Engineering'
        'GE' = 'Geology & Petroleum'
        'EE' = 'Electrical & Electronics'
        'TR' = 'Transportation Engineering'
        'CH' = 'Chemical Engineering'
        'EN' = 'Environment & Resources'
        'CO' = 'Computer Science'
        'CI' = 'Civil Engineering'
        'IM' = 'Industrial Management'
        'AS' = 'Applied Sciences'
        'MA' = 'Materials Technology'
        'LA' = 'Language Center'
        'IU' = 'Industrial Maintenance'
        'MT' = 'Mathematics'
        'PH' = 'Physics'
        'SP' = 'Social Philosophy'
        'SK' = 'Social Knowledge'
        'SA' = 'Student Activity'
        'GK' = 'General/Common'
        'PE' = 'Physical Education'
    }
    
    # Group courses by department
    $categoryGroups = @{}
    foreach ($course in $creditedCourses) {
        if ($course.maMonHoc -match '^([A-Z]{2,4})') {
            $prefix = $matches[1]
            $category = if ($departmentMap.ContainsKey($prefix)) {
                $departmentMap[$prefix]
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
        
        # Check if all courses are MT grades first
        $mtCount = ($courses | Where-Object { $_.diemChu -eq "MT" }).Count
        $allMT = ($mtCount -eq $courses.Count -and $mtCount -gt 0)
        
        if ($allMT) {
            # All courses are MT grades
            Write-Host ("{0}: {1} courses, {2} credits (all MT)" -f 
                $category, $courses.Count, $credits)
        } else {
            # Calculate average grade (excluding MT grades and courses without scores)
            # Use foreach to ensure we catch all courses with scores
            $scoredCourses = @()
            foreach ($course in $courses) {
                if ($course.diemSo -ne $null -and 
                    $course.diemChu -ne "MT" -and 
                    $course.diemChu -ne $null) {
                    $scoredCourses += $course
                }
            }
            
            if ($scoredCourses.Count -gt 0) {
                # Has scored courses - always show average (even if just 1 course)
                # For 1 course, the average is just that course's grade
                $avg = ($scoredCourses | Measure-Object -Property diemSo -Average).Average
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
    $failedCourses = $creditedCourses | Where-Object { $_.diemChu -eq "F" -or ($_.diemDat -eq "0" -and $_.diemSo -lt 4.0) }
    if ($failedCourses.Count -gt 0) {
        Write-Host "FAILED COURSES" -ForegroundColor Red
        Write-Host ("-" * 70)
        foreach ($course in $failedCourses) {
            Write-Host ("- {0} ({1}) - {2} credits - Score: {3}" -f 
                $course.tenMonHoc, $course.maMonHoc, $course.soTinChi, $course.diemSo)
            if ($course.ghiChu) {
                Write-Host ("  Note: {0}" -f $course.ghiChu) -ForegroundColor Gray
            }
        }
        Write-Host ""
    }
    
    # Special Notes
    Write-Host "SPECIAL NOTES" -ForegroundColor Yellow
    Write-Host ("-" * 70)
    $coursesWithNotes = $grades | Where-Object { $_.ghiChu -ne $null -and $_.ghiChu -ne "" }
    if ($coursesWithNotes.Count -gt 0) {
        foreach ($course in $coursesWithNotes) {
            Write-Host ("- {0}: {1}" -f $course.tenMonHoc, $course.ghiChu)
        }
    } else {
        Write-Host "No special notes found."
    }
    Write-Host ""
    
    # Recommendations - GPA Improvement Plan
    Write-Host "RECOMMENDATIONS - GPA IMPROVEMENT PLAN" -ForegroundColor Yellow
    Write-Host ("-" * 70)
    
    # Function to determine target grade based on current grade
    function Get-TargetGrade {
        param(
            [string]$CurrentGrade,
            [double]$TargetGPA
        )
        
        # For 3.2 target: +1.5 grade points
        if ($TargetGPA -eq 3.2) {
            if (-not $gradeMap.ContainsKey($CurrentGrade)) {
                return $null
            }
            $currentPoints = $gradeMap[$CurrentGrade]
            $targetPoints = $currentPoints + 1.5
            
            # Cap at 4.0 (A/A+)
            if ($targetPoints -gt 4.0) {
                $targetPoints = 4.0
            }
            
            # Find the grade that matches the target points
            $reverseGradeMap = @{
                4.0 = "A"
                3.5 = "B+"
                3.0 = "B"
                2.5 = "C+"
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
        switch ($CurrentGrade) {
            "F" { return "D+" }
            "D" { return "D+" }
            "D+" { return "C+" }
            "C" { return "C+" }
            "C+" { return "B" }
            default { return $null }
        }
    }
    
    # Get courses that can be improved (excluding MT)
    $improvableCourses = $creditedCourses | Where-Object {
        $_.diemChu -ne "MT" -and 
        $_.diemChu -ne "B" -and 
        $_.diemChu -ne "B+" -and 
        $_.diemChu -ne "A" -and 
        $_.diemChu -ne "A+" -and
        $gradeMap.ContainsKey($_.diemChu)
    }
    
    # Calculate improvement scenarios for target GPAs
    $targetGPAs = @(2.8, 3.2)
    
    foreach ($targetGPA in $targetGPAs) {
        if ($gpa -ge $targetGPA) {
            Write-Host ("Target GPA {0}: Already achieved! Current GPA: {1}" -f $targetGPA, $gpa) -ForegroundColor Green
            Write-Host ""
            continue
        }
        
        $requiredPoints = $targetGPA * $totalCreditsForGPA
        $pointsNeeded = $requiredPoints - $totalPoints
        $pointsNeeded = [math]::Round($pointsNeeded, 2)
        
        Write-Host "Target GPA: $targetGPA" -ForegroundColor Cyan
        Write-Host ("Current GPA: {0}, Points needed: {1}" -f $gpa, $pointsNeeded)
        Write-Host ""
        
        # Create list of possible improvements
        $improvements = @()
        foreach ($course in $improvableCourses) {
            $currentGrade = $course.diemChu
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
        
        # Sort by points gain (descending) to prioritize high-impact courses
        $improvements = $improvements | Sort-Object PointsGain -Descending
        
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
            for ($i = 0; $i -lt $improvements.Count; $i++) {
                $imp = $improvements[$i]
                $courseKey = $imp.CourseCode
                
                if (-not $usedCourses.ContainsKey($courseKey)) {
                    if ($bestImprovement -eq $null -or $imp.PointsGain -gt $bestImprovement.PointsGain) {
                        $bestImprovement = $imp
                        $bestIndex = $i
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
            
            $newGPA = [math]::Round(($totalPoints + $totalGain) / $totalCreditsForGPA, 2)
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
    exit 1
}
