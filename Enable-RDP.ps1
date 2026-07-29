# --- Pre-Execution Check (Popup) ---
Add-Type -AssemblyName System.Windows.Forms
$popupResult = [System.Windows.Forms.MessageBox]::Show(
    "Are you sure you are logged into the Virtual Training PC?",
    "Pre-Execution Check",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

if ($popupResult -eq 'No') {
    Write-Host "Script execution cancelled by user." -ForegroundColor Yellow
    Return
}

# --- Variables ---
# RDP Onboarding Variables
$rdpRoot = "C:\ProgramData\RDP-Onboarding"
$xmlUrl = "https://labdoc.blob.core.windows.net/courses/Intune/RDP-Onboarding-Startup.xml"
$xmlPath = Join-Path $rdpRoot "RDP-Onboarding-Startup.xml"

# Lab Files Variables
$labFilesPath = "C:\LabFiles"
$zipUrl = "https://labdoc.blob.core.windows.net/courses/Intune/Intune.zip"
$zipFilePath = Join-Path $labFilesPath "Intune.zip"


# ==========================================
# PART 1: RDP ONBOARDING TASK
# ==========================================
Write-Host "--- Starting Part 1: RDP Onboarding Setup ---" -ForegroundColor Yellow

# 1. Create Directory for RDP
Write-Host "Checking and creating directory: $rdpRoot" -ForegroundColor Cyan
try {
    New-Item -ItemType Directory -Path $rdpRoot -Force -ErrorAction Stop | Out-Null
    Write-Host "[SUCCESS] RDP Directory is ready." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to create RDP directory. Details: $($_.Exception.Message)" -ForegroundColor Red
    Return
}

# 2. Download XML File
Write-Host "Downloading XML file..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $xmlUrl -OutFile $xmlPath -UseBasicParsing -ErrorAction Stop
    Write-Host "[SUCCESS] XML file downloaded successfully." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to download the XML file. Details: $($_.Exception.Message)" -ForegroundColor Red
    Return
}

# 3. Apply XML Fixes (Remove LogonType and set Unicode)
Write-Host "Applying fixes to the XML file..." -ForegroundColor Cyan
try {
    $content = Get-Content $xmlPath -Raw -ErrorAction Stop
    $content = $content.Replace("<LogonType>ServiceAccount</LogonType>", "")
    Set-Content -Path $xmlPath -Value $content -Encoding Unicode -ErrorAction Stop
    Write-Host "[SUCCESS] XML file successfully patched and formatted." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to modify the XML file. Details: $($_.Exception.Message)" -ForegroundColor Red
    Return
}

# 4. Scheduled Tasks
Write-Host "Creating and executing Scheduled Task..." -ForegroundColor Cyan
schtasks /Create /TN "RDP Onboarding (Startup)" /XML $xmlPath /F | Out-Null
schtasks /Run /TN "RDP Onboarding (Startup)" | Out-Null
Write-Host "[SUCCESS] Scheduled task commands executed." -ForegroundColor Green
Write-Host ""


# ==========================================
# PART 2: INTUNE LAB FILES
# ==========================================
Write-Host "--- Starting Part 2: Intune Lab Files Setup ---" -ForegroundColor Yellow

# 1. Create Directory for Lab Files
Write-Host "Checking and creating directory: $labFilesPath" -ForegroundColor Cyan
try {
    New-Item -ItemType Directory -Path $labFilesPath -Force -ErrorAction Stop | Out-Null
    Write-Host "[SUCCESS] LabFiles directory is ready." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to create LabFiles directory. Details: $($_.Exception.Message)" -ForegroundColor Red
    Return
}

# 2. Download ZIP File
Write-Host "Downloading ZIP file ($zipUrl)..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipFilePath -UseBasicParsing -ErrorAction Stop
    Write-Host "[SUCCESS] ZIP file downloaded successfully." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to download the ZIP file. Details: $($_.Exception.Message)" -ForegroundColor Red
    Return
}

# 3. Extract ZIP File
Write-Host "Extracting ZIP file into $labFilesPath..." -ForegroundColor Cyan
try {
    Expand-Archive -Path $zipFilePath -DestinationPath $labFilesPath -Force -ErrorAction Stop
    Write-Host "[SUCCESS] ZIP file extracted successfully." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to extract the ZIP file. Details: $($_.Exception.Message)" -ForegroundColor Red
    Return
}
Write-Host ""


# ==========================================
# PART 3: REMOTE DESKTOP USERS CONFIGURATION
# ==========================================
Write-Host "--- Starting Part 3: RDP Group Configuration ---" -ForegroundColor Yellow
Write-Host "Adding 'Authenticated Users' to 'Remote Desktop Users' group..." -ForegroundColor Cyan

try {
    # We use SIDs instead of names to prevent errors on different OS languages (e.g. Dutch vs English)
    # SID S-1-5-32-555 = Remote Desktop Users
    # SID S-1-5-11     = Authenticated Users
    
    $rdpGroup = Get-LocalGroup | Where-Object { $_.SID.Value -eq "S-1-5-32-555" }
    
    if ($rdpGroup) {
        # Check if they are already a member to prevent error messages
        $currentMembers = Get-LocalGroupMember -Group $rdpGroup.Name
        
        if ($currentMembers.SID.Value -contains "S-1-5-11") {
            Write-Host "[SUCCESS] 'Authenticated Users' is already a member of the RDP group." -ForegroundColor Green
        } else {
            Add-LocalGroupMember -Group $rdpGroup.Name -Member "S-1-5-11" -ErrorAction Stop
            Write-Host "[SUCCESS] Successfully added 'Authenticated Users' to the RDP group." -ForegroundColor Green
        }
    } else {
        Write-Host "[ERROR] Could not find the Remote Desktop Users group on this system." -ForegroundColor Red
    }
} catch {
    Write-Host "[ERROR] Failed to modify group membership. Details: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""


# ==========================================
# PART 4: RDP REGISTRY CONFIGURATION
# ==========================================
Write-Host "--- Starting Part 4: RDP Registry Configuration ---" -ForegroundColor Yellow
Write-Host "Setting 'SecurityLayer' to 0 in the Registry..." -ForegroundColor Cyan

try {
    # Aangepast: Spatie toegevoegd in "Terminal Server"
    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
    $name = "SecurityLayer"
    $value = 0

    # Ensure the path exists before setting the property
    if (Test-Path $registryPath) {
        Set-ItemProperty -Path $registryPath -Name $name -Value $value -Type DWord -ErrorAction Stop
        Write-Host "[SUCCESS] Registry key 'SecurityLayer' successfully set to 0." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Registry path does not exist: $registryPath" -ForegroundColor Red
    }
} catch {
    Write-Host "[ERROR] Failed to modify Registry. Details: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "--- All tasks completed successfully! ---" -ForegroundColor Green