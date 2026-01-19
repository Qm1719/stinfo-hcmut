# Parse all_subjects.txt and create JSON for HCMIU
# HCMIU format: Header row, category headers, course rows (starting with tab), detail rows
# Category headers like "EFA - Economics, Finance and Accounting" provide prefix meanings

param(
    [string]$InputFile = "all_subjects.txt",
    [string]$OutputFile = "all_subjects.json"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

try {
    if (-not (Test-Path $InputFile)) {
        Write-Host "Error: File '$InputFile' not found!" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Reading subjects from: $InputFile"
    
    $lines = Get-Content $InputFile -Encoding UTF8
    $subjects = @{}
    $sttCounter = 1
    
    # First pass: Extract category headers and build prefix meanings
    $categoryMeanings = @{}  # Maps category prefix to meaning
    $categoryPrefixes = @{}  # Maps course prefix to category prefix (for courses under that category)
    
    Write-Host "Extracting category headers..."
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^([A-Z]{2,4})\s*-\s*(.+)$') {
            $categoryPrefix = $matches[1]
            $categoryMeaning = $matches[2].Trim()
            $categoryMeanings[$categoryPrefix] = $categoryMeaning
            Write-Host "  Found category: $categoryPrefix - $categoryMeaning"
        }
    }
    
    # Parse header to find column indices
    $headerLine = $lines[0]
    $headerFields = $headerLine -split "`t+"
    
    $idxMaMH = 1
    $idxTenMonHoc = 2
    $idxSTC = 5
    
    Write-Host "Column indices - Ma MH: $idxMaMH, Ten Mon Hoc: $idxTenMonHoc, STC: $idxSTC"
    
    # Track current category
    $currentCategory = ""
    
    # Process lines
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        
        # Skip empty lines
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        
        # Check if this is a category header (2-4 characters)
        if ($line -match '^([A-Z]{2,4})\s*-\s*(.+)$') {
            $currentCategory = $matches[1]
            continue
        }
        
        # Skip detail rows (they don't start with tab and aren't category headers)
        if (-not ($line -match '^\t')) { continue }
        
        # This is a course row (starts with tab)
        $fields = $line -split "`t+"
        
        # Remove empty first field (from leading tab)
        if ($fields.Count -gt 0 -and [string]::IsNullOrWhiteSpace($fields[0])) {
            $fields = $fields[1..($fields.Count-1)]
        }
        
        # Check if we have enough fields
        if ($fields.Count -le $idxSTC) { continue }
        
        # Extract course data
        # After removing empty first field from tab, data rows are:
        # [0]Ma MH [1]Ma MH dup [2]Ten mon hoc [3]NMH [4]TTH [5]STC
        # So: Ma MH is at index 0, Ten mon hoc is at index 2, STC is at index 5
        $maMonHoc = if ($fields.Count -gt 0) { $fields[0].Trim() } else { "" }
        $tenMonHoc = if ($fields.Count -gt 2) { $fields[2].Trim() } else { "" }
        $soTinChiStr = if ($fields.Count -gt 5) { $fields[5].Trim() } else { "0" }
        
        # Skip if course code is empty
        if ([string]::IsNullOrWhiteSpace($maMonHoc)) { continue }
        
        # Parse credits
        $credits = 0
        [double]::TryParse($soTinChiStr, [ref]$credits) | Out-Null
        
        # Extract prefix from course code (first 2-4 letters)
        # Try 4 chars first, then 3, then 2
        $prefix = ""
        if ($maMonHoc -match '^([A-Z]{4})') {
            $prefix = $matches[1]
        } elseif ($maMonHoc -match '^([A-Z]{3})') {
            $prefix = $matches[1]
        } elseif ($maMonHoc -match '^([A-Z]{2})') {
            $prefix = $matches[1]
        }
        
        # Use course code as key to deduplicate (same course appears multiple times for different sections)
        if (-not $subjects.ContainsKey($maMonHoc)) {
            # Determine prefix meaning:
            # 1. If current category exists and matches the course prefix, use category meaning
            # 2. Otherwise, if category meanings has an entry for the prefix, use it
            # 3. Otherwise, use "Unknown"
            $prefixMeaning = "Unknown / Chưa xác định"
            
            if (-not [string]::IsNullOrWhiteSpace($currentCategory) -and $categoryMeanings.ContainsKey($currentCategory)) {
                # Use current category meaning
                $prefixMeaning = $categoryMeanings[$currentCategory]
                # Also map this course prefix to the category for future reference
                if (-not $categoryPrefixes.ContainsKey($prefix)) {
                    $categoryPrefixes[$prefix] = $currentCategory
                }
            } elseif ($categoryMeanings.ContainsKey($prefix)) {
                # Direct match (prefix is a category)
                $prefixMeaning = $categoryMeanings[$prefix]
            } elseif ($categoryPrefixes.ContainsKey($prefix)) {
                # Use mapped category
                $mappedCategory = $categoryPrefixes[$prefix]
                if ($categoryMeanings.ContainsKey($mappedCategory)) {
                    $prefixMeaning = $categoryMeanings[$mappedCategory]
                }
            }
            
            $subject = @{
                stt = $sttCounter++
                maMonHoc = $maMonHoc
                tenMonHoc = $tenMonHoc
                soTinChi = $credits
                prefix = $prefix
            }
            
            $subjects[$maMonHoc] = $subject
        }
    }
    
    # Convert hashtable to array
    $subjectsArray = $subjects.Values | Sort-Object stt
    
    Write-Host "Parsed $($subjectsArray.Count) unique subjects"
    
    # Create output structure with extracted prefix meanings
    $output = @{
        total = $subjectsArray.Count
        code = "200"
        msg = "Success"
        data = $subjectsArray
        prefixMeanings = $categoryMeanings
    }
    
    # Save to JSON
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $jsonString = $output | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($OutputFile, $jsonString, $utf8NoBom)
    
    Write-Host "Successfully saved to: $OutputFile" -ForegroundColor Green
    
    # Show summary
    Write-Host ""
    Write-Host "Summary by prefix:"
    $prefixGroups = $subjectsArray | Group-Object -Property prefix | Sort-Object Count -Descending
    foreach ($group in $prefixGroups) {
        # Get meaning from first subject in group
        $firstSubject = $group.Group[0]
        $meaning = $firstSubject.prefixMeaning
        Write-Host "  $($group.Name): $($group.Count) courses - $meaning"
    }
    
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    exit 1
}
