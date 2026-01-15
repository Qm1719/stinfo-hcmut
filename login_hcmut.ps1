# HCMUT Login Script (PowerShell)
# Handles CAS SSO authentication and extracts credentials

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
    
    [Parameter(Mandatory=$true)]
    [string]$Password,
    
    [string]$SemesterYear = ""
)

# Set encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

function Decode-JWTPayload {
    param([string]$Token)
    
    try {
        $parts = $Token.Split('.')
        if ($parts.Length -ne 3) { return $null }
        
        $payload = $parts[1]
        # Add padding if needed
        $mod = $payload.Length % 4
        if ($mod -gt 0) {
            $payload += "=" * (4 - $mod)
        }
        
        $bytes = [System.Convert]::FromBase64String($payload)
        $json = [System.Text.Encoding]::UTF8.GetString($bytes)
        return $json | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Login-HCMUT {
    param(
        [string]$Username,
        [string]$Password
    )
    
    $serviceUrl = "https://sso.hcmut.edu.vn/cas/login?service=https%3A%2F%2Fmybk.hcmut.edu.vn%2Fapp%2Flogin%2Fcas"
    
    try {
        # Step 1: Get the CAS login page to extract form tokens
        $loginPage = Invoke-WebRequest -Uri $serviceUrl -Method GET -SessionVariable session -UseBasicParsing -ErrorAction Stop
        
        # Extract form fields: lt (login ticket) and execution
        $html = $loginPage.Content
        $ltMatch = [regex]::Match($html, 'name="lt"\s+value="([^"]+)"')
        $executionMatch = [regex]::Match($html, 'name="execution"\s+value="([^"]+)"')
        
        if (-not $ltMatch.Success -or -not $executionMatch.Success) {
            return $null
        }
        
        $lt = $ltMatch.Groups[1].Value
        $execution = $executionMatch.Groups[1].Value
        
        # Step 2: Submit login form
        $formData = @{
            username = $Username
            password = $Password
            lt = $lt
            execution = $execution
            _eventId = "submit"
        }
        
        $headers = @{
            "Content-Type" = "application/x-www-form-urlencoded"
            "Referer" = $serviceUrl
            "Origin" = "https://sso.hcmut.edu.vn"
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        
        # Submit login (will get redirect, allow multiple redirects)
        try {
            $finalResponse = Invoke-WebRequest -Uri $serviceUrl -Method POST -Headers $headers -Body $formData -WebSession $session -MaximumRedirection 5 -UseBasicParsing -ErrorAction Stop
        } catch {
            return @{
                success = $false
                error = "Login failed: $($_.Exception.Message)"
            }
        }
        
        # Step 4: Extract JWT token from the response HTML
        $jwtPattern = 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'
        $tokenMatch = [regex]::Match($finalResponse.Content, $jwtPattern)
        
        if (-not $tokenMatch.Success) {
            return $null
        }
        
        $authToken = $tokenMatch.Value
        
        # Step 5: Extract studentId from JWT payload
        $payload = Decode-JWTPayload -Token $authToken
        $studentId = $null
        if ($payload) {
            $studentId = $payload.sub
            if (-not $studentId) {
                $studentId = $payload.studentId
            }
            if (-not $studentId) {
                $studentId = $payload.userId
            }
        }
        
        # Step 6: Extract cookie (JSESSIONID or SESSION)
        $cookie = $null
        $cookies = $session.Cookies.GetCookies("https://mybk.hcmut.edu.vn")
        foreach ($c in $cookies) {
            if ($c.Name -eq "JSESSIONID") {
                $cookie = $c.Value
                break
            }
            if ($c.Name -eq "SESSION" -and -not $cookie) {
                $cookie = $c.Value
            }
        }
        
        # Cookie is optional but we'll try to get it
        if (-not $cookie) {
            $cookie = "SESSION"  # Placeholder
        }
        
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
    $result = Login-HCMUT -Username $Username -Password $Password
    
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

