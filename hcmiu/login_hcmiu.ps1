# HCMIU Login Script (PowerShell)
# Handles ASP.NET authentication for edusoftweb.hcmiu.edu.vn

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
    
    [Parameter(Mandatory=$true)]
    [string]$Password
)

# Set encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

function Login-HCMIU {
    param(
        [string]$Username,
        [string]$Password
    )
    
    $baseUrl = "https://edusoftweb.hcmiu.edu.vn"
    $loginUrl = "$baseUrl/Default.aspx"
    
    try {
        # Step 1: Get the login page to extract ViewState and other form fields
        $loginPage = Invoke-WebRequest -Uri $loginUrl -Method GET -SessionVariable session -UseBasicParsing -ErrorAction Stop
        
        # Extract ViewState, ViewStateGenerator, and EventValidation
        $html = $loginPage.Content
        
        # Extract ViewState
        $viewStateMatch = [regex]::Match($html, 'name="__VIEWSTATE"\s+id="__VIEWSTATE"\s+value="([^"]+)"')
        if (-not $viewStateMatch.Success) {
            $viewStateMatch = [regex]::Match($html, 'name="__VIEWSTATE"\s+value="([^"]+)"')
        }
        
        # Extract ViewStateGenerator
        $viewStateGenMatch = [regex]::Match($html, 'name="__VIEWSTATEGENERATOR"\s+id="__VIEWSTATEGENERATOR"\s+value="([^"]+)"')
        if (-not $viewStateGenMatch.Success) {
            $viewStateGenMatch = [regex]::Match($html, 'name="__VIEWSTATEGENERATOR"\s+value="([^"]+)"')
        }
        
        # Extract EventValidation
        $eventValidationMatch = [regex]::Match($html, 'name="__EVENTVALIDATION"\s+id="__EVENTVALIDATION"\s+value="([^"]+)"')
        if (-not $eventValidationMatch.Success) {
            $eventValidationMatch = [regex]::Match($html, 'name="__EVENTVALIDATION"\s+value="([^"]+)"')
        }
        
        # Extract form field names for username and password
        # HCMIU uses: ctl00$ContentPlaceHolder1$ctl00$ucDangNhap$txtTaiKhoa
        $usernameFieldMatch = [regex]::Match($html, 'name="([^"]+)"[^>]*id="[^"]*txtTaiKhoa|name="([^"]+)"[^>]*id="[^"]*txtUserName|name="([^"]+)"[^>]*id="[^"]*txtUsername')
        $passwordFieldMatch = [regex]::Match($html, 'name="([^"]+)"[^>]*id="[^"]*txtMatKhau|name="([^"]+)"[^>]*id="[^"]*txtPassword|name="([^"]+)"[^>]*id="[^"]*Password')
        
        $usernameField = if ($usernameFieldMatch.Success) { 
            if ($usernameFieldMatch.Groups[1].Value) { $usernameFieldMatch.Groups[1].Value }
            elseif ($usernameFieldMatch.Groups[2].Value) { $usernameFieldMatch.Groups[2].Value }
            else { $usernameFieldMatch.Groups[3].Value }
        } else { 
            # Fallback: try to find by pattern
            $fallbackMatch = [regex]::Match($html, 'name="([^"]*txtTaiKhoa[^"]*)"')
            if ($fallbackMatch.Success) { $fallbackMatch.Groups[1].Value } else { 'ctl00$ContentPlaceHolder1$ctl00$ucDangNhap$txtTaiKhoa' }
        }
        
        $passwordField = if ($passwordFieldMatch.Success) { 
            if ($passwordFieldMatch.Groups[1].Value) { $passwordFieldMatch.Groups[1].Value }
            elseif ($passwordFieldMatch.Groups[2].Value) { $passwordFieldMatch.Groups[2].Value }
            else { $passwordFieldMatch.Groups[3].Value }
        } else { 
            # Fallback: try to find by pattern
            $fallbackMatch = [regex]::Match($html, 'name="([^"]*txtMatKhau[^"]*)"')
            if ($fallbackMatch.Success) { $fallbackMatch.Groups[1].Value } else { 'ctl00$ContentPlaceHolder1$ctl00$ucDangNhap$txtMatKhau' }
        }
        
        # Extract button name/id for login
        $loginButtonMatch = [regex]::Match($html, 'name="([^"]+)"[^>]*id="[^"]*btnDangNhap|name="([^"]+)"[^>]*id="[^"]*btnLogin|name="([^"]+)"[^>]*value="[^"]*Dang Nh')
        $loginButton = if ($loginButtonMatch.Success) {
            if ($loginButtonMatch.Groups[1].Value) { $loginButtonMatch.Groups[1].Value }
            elseif ($loginButtonMatch.Groups[2].Value) { $loginButtonMatch.Groups[2].Value }
            else { $loginButtonMatch.Groups[3].Value }
        } else { 
            # Fallback: try to find by pattern
            $fallbackMatch = [regex]::Match($html, 'name="([^"]*btnDangNhap[^"]*)"')
            if ($fallbackMatch.Success) { $fallbackMatch.Groups[1].Value } else { 'ctl00$ContentPlaceHolder1$ctl00$ucDangNhap$btnDangNhap' }
        }
        
        $viewState = if ($viewStateMatch.Success) { $viewStateMatch.Groups[1].Value } else { "" }
        $viewStateGen = if ($viewStateGenMatch.Success) { $viewStateGenMatch.Groups[1].Value } else { "" }
        $eventValidation = if ($eventValidationMatch.Success) { $eventValidationMatch.Groups[1].Value } else { "" }
        
        # Step 2: Build form data for login
        $formData = @{
            "__VIEWSTATE" = $viewState
            "__VIEWSTATEGENERATOR" = $viewStateGen
            "__EVENTVALIDATION" = $eventValidation
            $usernameField = $Username
            $passwordField = $Password
        }
        
        # Add login button click event (value from HTML is "Dang Nh?p")
        $formData[$loginButton] = "Dang Nh?p"
        
        # Convert to URL-encoded form data
        # Use PowerShell's built-in URL encoding
        $formBodyParts = @()
        foreach ($key in $formData.Keys) {
            $encodedKey = [System.Uri]::EscapeDataString($key)
            $encodedValue = [System.Uri]::EscapeDataString($formData[$key])
            $formBodyParts += "$encodedKey=$encodedValue"
        }
        $formBody = $formBodyParts -join "&"
        
        $headers = @{
            "Content-Type" = "application/x-www-form-urlencoded"
            "Referer" = $loginUrl
            "Origin" = $baseUrl
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        }
        
        # Step 3: Submit login form
        $loginResponse = $null
        try {
            $loginResponse = Invoke-WebRequest -Uri $loginUrl -Method POST -Headers $headers -Body $formBody -WebSession $session -UseBasicParsing -ErrorAction Stop
        } catch {
            # For redirects (302), PowerShell throws an exception but we can still get the response
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode.value__
                if ($statusCode -eq 302) {
                    # Redirect after login - this is good, continue
                    $loginResponse = $_.Exception.Response
                } else {
                    return @{
                        success = $false
                        error = "Login failed: HTTP $statusCode - $($_.Exception.Message)"
                    }
                }
            } else {
                return @{
                    success = $false
                    error = "Login failed: $($_.Exception.Message)"
                }
            }
        }
        
        # Step 4: Check if login was successful by checking for redirect or error message
        # Try to access the grades page to verify login
        $gradesUrl = "$baseUrl/Default.aspx?page=xemdiemthi"
        $gradesPage = $null
        try {
            $gradesPage = Invoke-WebRequest -Uri $gradesUrl -Method GET -WebSession $session -UseBasicParsing -ErrorAction Stop
            
            # Check if we're still on login page (login failed)
            if ($gradesPage.Content -match "Dang Nh|Login|txtTaiKhoa|txtMatKhau|ucDangNhap") {
                # Extract error message if any
                $errorMatch = [regex]::Match($gradesPage.Content, 'lblError[^>]*>([^<]+)|lblMessage[^>]*>([^<]+)|class="error"[^>]*>([^<]+)')
                $errorMsg = if ($errorMatch.Success) {
                    if ($errorMatch.Groups[1].Value) { $errorMatch.Groups[1].Value }
                    elseif ($errorMatch.Groups[2].Value) { $errorMatch.Groups[2].Value }
                    else { $errorMatch.Groups[3].Value }
                } else { "Invalid credentials - still on login page" }
                
                return @{
                    success = $false
                    error = $errorMsg
                }
            }
        } catch {
            # If we can't access grades page, login might have failed
            # But also check if we got a redirect from login (which is good)
            if ($loginResponse -and $loginResponse.StatusCode -eq 200) {
                # Login response was OK, but can't access grades - might be a session issue
                return @{
                    success = $false
                    error = "Login appeared successful but cannot access grades page: $($_.Exception.Message)"
                }
            } else {
                return @{
                    success = $false
                    error = "Could not verify login: $($_.Exception.Message)"
                }
            }
        }
        
        # Step 5: Extract session cookie (ASP.NET_SessionId)
        $cookie = $null
        $cookies = $session.Cookies.GetCookies($baseUrl)
        foreach ($c in $cookies) {
            if ($c.Name -eq "ASP.NET_SessionId") {
                $cookie = $c.Value
                break
            }
        }
        
        # Also try to get any authentication cookie
        if (-not $cookie) {
            foreach ($c in $cookies) {
                if ($c.Name -match "Auth|Session|Token") {
                    $cookie = $c.Value
                    break
                }
            }
        }
        
        # Extract student ID from the page if possible
        $studentId = $null
        # Use simpler pattern to avoid encoding issues
        $studentIdMatch = [regex]::Match($gradesPage.Content, 'M[^<]*s[^<]*sinh vi[^<]*n[^:]*:?\s*([A-Z0-9]+)|Student ID[^:]*:?\s*([A-Z0-9]+)|MSSV[^:]*:?\s*([A-Z0-9]+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($studentIdMatch.Success) {
            $studentId = if ($studentIdMatch.Groups[1].Value) { $studentIdMatch.Groups[1].Value }
                        elseif ($studentIdMatch.Groups[2].Value) { $studentIdMatch.Groups[2].Value }
                        else { $studentIdMatch.Groups[3].Value }
        }
        
        # For HCMIU, we'll use the session as the auth token
        $authToken = $cookie
        
        return @{
            success = $true
            auth_token = $authToken
            cookie = $cookie
            student_id = $studentId
        }
        
    } catch {
        return @{
            success = $false
            error = $_.Exception.Message
        }
    }
}

# Main execution
try {
    $result = Login-HCMIU -Username $Username -Password $Password
    
    if ($null -eq $result) {
        $output = @{
            success = $false
            error = "Login function returned null"
        }
        $output | ConvertTo-Json -Compress
        exit 1
    }
    
    if ($result.success) {
        $output = @{
            success = $true
            auth_token = $result.auth_token
            cookie = $result.cookie
            student_id = $result.student_id
        }
        $output | ConvertTo-Json -Compress
        exit 0
    } else {
        $output = @{
            success = $false
            error = if ($result.error) { $result.error } else { "Login failed. Please check your credentials." }
        }
        $output | ConvertTo-Json -Compress
        exit 1
    }
} catch {
    $output = @{
        success = $false
        error = $_.Exception.Message
    }
    $output | ConvertTo-Json -Compress
    exit 1
}

