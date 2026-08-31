# ============================================================================
# 1. GESTIONE FINESTRA E PRIVILEGI ADMINISTRATOR
# ============================================================================
$WindowTitle = "*powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Maximized -File*"
$ParentProcess = Get-Process | Where-Object { $_.MainWindowTitle -like $WindowTitle }
if ($ParentProcess) { $ParentProcess | Stop-Process -Force }

# Forza Massimizzazione
$cmd = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
$type = Add-Type -MemberDefinition $cmd -Name "Win32ShowWindow" -Namespace "Win32" -PassThru
$handle = (Get-Process -Id $PID).MainWindowHandle
$type::ShowWindow($handle, 3)
Clear-Host 

# Controllo privilegi Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath)
    exit
}

# ============================================================================
# 2. FUNZIONI UTILITY E INTERFACCIA
# ============================================================================
function Show-CenteredBox {
    param(
        [string]$action, 
        [int]$rows = 1
    )
    $width = 78
    $lines = $action -split "`r`n"
    $result = "╔$($('═' * $width))╗`r`n"

    $emptyRowsTop = [math]::Floor(($rows - 1) / 2)
    for ($i = 0; $i -lt $emptyRowsTop; $i++) {
        $result += "║$(' ' * $width)║`r`n"
    }

    foreach ($line in $lines) {
        $currentLine = $line
        if ($currentLine.Length -gt $width) {
            $currentLine = $currentLine.Substring(0, $width - 3) + "..."
        }
        $paddingTotal = $width - $currentLine.Length
        $padLeft = [math]::Floor($paddingTotal / 2)
        $padRight = $paddingTotal - $padLeft
        $spacesLeft = " " * $padLeft
        $spacesRight = " " * $padRight
        $result += "║$spacesLeft$currentLine$spacesRight║`r`n"
    }

    $emptyRowsBottom = ($rows - 1) - $emptyRowsTop
    for ($i = 0; $i -lt $emptyRowsBottom; $i++) {
        $result += "║$(' ' * $width)║`r`n"
    }

    $result += "╚$($('═' * $width))╝"
    return $result
}

function Get-ScriptPath {
    if ($PSVersionTable.PSVersion.Major -ge 3) {
        return $PSScriptRoot
    } else {
        return Split-Path -Parent $MyInvocation.MyCommand.Definition
    }
}

if ([string]::IsNullOrEmpty($Global:LocalScriptRoot)) {
    $Global:LocalScriptRoot = Get-ScriptPath
}

function Test-ProgramPath {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $false }
    return Test-Path $Path
}

# Opzioni di scelta standard
$Global:Choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
    New-Object System.Management.Automation.Host.ChoiceDescription "&Sì", "Esegue l'operazione."
    New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Salta questa operazione."
    New-Object System.Management.Automation.Host.ChoiceDescription "&Esci", "Interrompe lo script."
)

# ============================================================================
# 3. STRUTTURA OGGETTO UNICO PER SOFTWARE/CONFIGURAZIONI
# ============================================================================
function New-AppDefinition {
    param(
        [string]$Name,
        [string]$Category,
        [string]$Type = "Winget",             # Winget, Download, Script
        [string]$Id = "",                     # ID Winget
        [string]$Source = "winget",
        [string]$Url = "",                    # URL per Download
        [string]$InstallPath = "",            # Percorso di verifica
        [scriptblock]$InstallScript = $null,  # Script per installazioni custom
        [string]$UninstallType = "Winget",   # Winget, Script, None
        [string]$UninstallId = "",            # ID Winget per disinstallazione (se diverso)
        [scriptblock]$UninstallScript = $null # Script per disinstallazioni custom
    )

    return [PSCustomObject]@{
        Name            = $Name
        Category        = $Category
        Type            = $Type
        Id              = $Id
        Source          = $Source
        Url             = $Url
        InstallPath     = $InstallPath
        InstallScript   = $InstallScript
        UninstallType   = $UninstallType
        UninstallId     = if ($UninstallId) { $UninstallId } else { $Id }
        UninstallScript = $UninstallScript
    }
}

# List per la coda di installazione
$Global:InstallQueue = [System.Collections.Generic.List[PSCustomObject]]::new()

# ============================================================================
# 4. FUNZIONI DI ESECUZIONE (INSTALLAZIONE E DISINSTALLAZIONE)
# ============================================================================
function Download-Install-Sw {
    param(
        [string]$Name,
        [string]$Url,
        [string]$InstallPath
    )
    if (Test-ProgramPath $InstallPath) {
        Write-Host "$Name sembra essere già installato. Salto." -ForegroundColor Yellow
        return
    }
    $cleanPath = ([System.Uri]$Url).AbsolutePath
    $filename = Split-Path $cleanPath -Leaf
    $destination = Join-Path $env:TEMP $filename
    $dir = Split-Path $destination
    if (!(Test-ProgramPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    
    Invoke-WebRequest -Uri $Url -OutFile $destination
    if (Test-ProgramPath $destination) {
        Write-Host "Procedo con l'installazione di $Name..." -ForegroundColor Cyan
        Start-Process $destination -Wait
        Write-Host "Installazione di $Name completata." -ForegroundColor Green
    } else {
        Write-Warning "File non trovato a $destination. Salto."
    }
}

function Invoke-AppInstall {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$App,
        [bool]$Ask = $true
    )

    $title = Show-CenteredBox -action "INSTALLAZIONE: $($App.Name)"
    $message = "Vuoi procedere con l'installazione di '$($App.Name)'?"
    
    $proceed = $false

    if ($Ask) {
        $decision = $host.UI.PromptForChoice($title, $message, $Global:Choices, 1)
        switch ($decision) {
            0 { $proceed = $true }
            1 { Write-Host "Installazione di '$($App.Name)' saltata." -ForegroundColor Yellow; return }
            2 { Write-Host "Uscita in corso..." -ForegroundColor Red; exit }
        }
    } else {
        Write-Host $title
        Write-Host "Esecuzione automatica (senza conferma)..." -ForegroundColor Cyan
        $proceed = $true
    }

    if ($proceed) {
        Write-Host "Procedo con l'installazione di '$($App.Name)'..." -ForegroundColor Cyan
        switch ($App.Type) {
            "Winget" {
                winget install -e --id $App.Id --source $App.Source --accept-package-agreements --accept-source-agreements --silent
            }
            "Download" {
                Download-Install-Sw -Name $App.Name -Url $App.Url -InstallPath $App.InstallPath
            }
            "Script" {
                if ($App.InstallScript) {
                    & $App.InstallScript
                } else {
                    Write-Warning "Nessuno script di installazione definito per $($App.Name)."
                }
            }
        }
        Write-Host "Operazione su '$($App.Name)' completata." -ForegroundColor Green
    }
}

function Invoke-AppUninstall {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$App,
        [bool]$Ask = $true
    )

    if ($App.UninstallType -eq "None") {
        Write-Host "L'elemento '$($App.Name)' non supporta la disinstallazione automatica." -ForegroundColor Yellow
        return
    }

    $title = Show-CenteredBox -action "DISINSTALLAZIONE: $($App.Name)"
    $message = "Vuoi procedere con la disinstallazione di '$($App.Name)'?"
    
    $proceed = $false

    if ($Ask) {
        $decision = $host.UI.PromptForChoice($title, $message, $Global:Choices, 1)
        switch ($decision) {
            0 { $proceed = $true }
            1 { Write-Host "Disinstallazione di '$($App.Name)' saltata." -ForegroundColor Yellow; return }
            2 { Write-Host "Uscita in corso..." -ForegroundColor Red; exit }
        }
    } else {
        Write-Host $title
        Write-Host "Disinstallazione automatica (senza conferma)..." -ForegroundColor Cyan
        $proceed = $true
    }

    if ($proceed) {
        Write-Host "Procedo con la disinstallazione di '$($App.Name)'..." -ForegroundColor Cyan
        switch ($App.UninstallType) {
            "Winget" {
                $installedPackage = winget list --id $App.UninstallId --source $App.Source
                if ($installedPackage) {
                    winget uninstall --id $App.UninstallId --source $App.Source --accept-source-agreements --silent
                    Write-Host "Disinstallazione di '$($App.Name)' completata." -ForegroundColor Green
                } else {
                    Write-Host "'$($App.Name)' non risulta installato. Salto." -ForegroundColor Yellow
                }
            }
            "Script" {
                if ($App.UninstallScript) {
                    & $App.UninstallScript
                } else {
                    Write-Warning "Nessuno script di disinstallazione definito per $($App.Name)."
                }
            }
        }
    }
}

# ============================================================================
# 5. CATALOGO GENERALE SOFTWARE E CONFIGURAZIONI (OGGETTI UNICI)
# ============================================================================
$Global:AppCatalog = @(
    # CONFIGURAZIONE SISTEMA
    (New-AppDefinition -Name "Disabilitazione OOBE" -Category "CONFIGURAZIONE SISTEMA" -Type "Script" -UninstallType "None" -InstallScript {
        $RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE"
        if (-not (Test-ProgramPath $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }
        Set-ItemProperty -Path $RegistryPath -Name "DisablePrivacyExperience" -Value 1 -Type DWORD -Force
        Write-Host "OOBE disabilitato." -ForegroundColor Green
    }),
    (New-AppDefinition -Name "Eliminazione automatica vecchi account" -Category "CONFIGURAZIONE SISTEMA" -Type "Script" -UninstallType "None" -InstallScript {
        Set-Location $Global:LocalScriptRoot
        $psPath = Join-Path (Get-Location).Path "manutenzioneAccount.ps1"
        $destinazione = "C:\Program Files\ManutenzioneAccount"
        if (!(Test-ProgramPath $destinazione)) { New-Item -Path $destinazione -ItemType Directory | Out-Null }
        Copy-Item -Path $psPath -Destination $destinazione -Force
        $ScriptPath = Join-Path $destinazione "manutenzioneAccount.ps1"
        $Command = "PowerShell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
        schtasks.exe /Create /TN "PuliziaAccountInattivi" /TR $Command /SC MONTHLY /D 1 /ST 03:00 /RU "SYSTEM" /RL HIGHEST /F
        Write-Host "Task scheduler programmato." -ForegroundColor Green
    }),
    (New-AppDefinition -Name "Impostazione immagine UniPV" -Category "CONFIGURAZIONE SISTEMA" -Type "Script" -UninstallType "None" -InstallScript {
        Set-Location $Global:LocalScriptRoot
        $bg_path = Join-Path (Get-Location).Path "grafica_unipv\unipv_bg.jpg"
        $logo_bmp = Join-Path (Get-Location).Path "grafica_unipv\unipv_logo.bmp"
        $logo_png = Join-Path (Get-Location).Path "grafica_unipv\unipv_logo.png"
        $wallpaperPath = "C:\Windows\Web\Wallpaper\unipv_bg.jpg"
        $lockScreenPath = "C:\Windows\Web\Screen\unipv_lock.jpg"
        
        Copy-Item $bg_path -Destination $wallpaperPath -Force
        Copy-Item $bg_path -Destination $lockScreenPath -Force
        $accountPath = "$env:PROGRAMDATA\Microsoft\User Account Pictures"
        Copy-Item $logo_bmp -Destination "$accountPath\user.bmp" -Force
        Copy-Item $logo_bmp -Destination "$accountPath\guest.bmp" -Force
        Copy-Item $logo_png -Destination "$accountPath\user.png" -Force
        Copy-Item $logo_png -Destination "$accountPath\guest.png" -Force
        
        New-Item -Path "HKLM:\Software\Policies\Microsoft\Windows\System" -Force | Out-Null
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\System" -Name "Wallpaper" -Value $wallpaperPath
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\System" -Name "WallpaperStyle" -Value "2"
        New-Item -Path "HKLM:\Software\Policies\Microsoft\Windows\Personalization" -Force | Out-Null
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\Personalization" -Name "LockScreenImage" -Value $lockScreenPath
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\Personalization" -Name "NoChangingLockScreen" -Value 1
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\Personalization" -Name "NoChangingDesktopBackground" -Value 1
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\Personalization" -Name "LockScreenOverlaysDisabled" -Value 1
        New-Item -Path "HKLM:\Software\Policies\Microsoft\Windows\ActiveDesktop" -Force | Out-Null
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\ActiveDesktop" -Name "NoChangingWallpaper" -Value 1
        
        RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters
        gpupdate /force
        Write-Host "Tema UniPV applicato." -ForegroundColor Green
    }),
    (New-AppDefinition -Name "Aggiunta utente Ospite" -Category "CONFIGURAZIONE SISTEMA" -Type "Script" -UninstallType "None" -InstallScript {
        $username = "Ospite"
        if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
            Write-Host "L'utente '$username' esiste già." -ForegroundColor Yellow
        } else {
            $userCreated = $false
            while (-not $userCreated) {
                try {
                    $Password = Read-Host -AsSecureString "Inserisci la password per il nuovo utente"
                    New-LocalUser -Name $username -Password $Password -UserMayNotChangePassword -AccountNeverExpires -PasswordNeverExpires -Description "Account utente Ospite" -ErrorAction Stop
                    Add-LocalGroupMember -Group "Guests" -Member $username
                    Write-Host "Account '$username' creato con successo." -ForegroundColor Green
                    $userCreated = $true
                } catch {
                    Write-Host "ERRORE: Password non valida." -ForegroundColor Red
                }
            }
        }
    }),
    (New-AppDefinition -Name "Abilitazione account Administrator" -Category "CONFIGURAZIONE SISTEMA" -Type "Script" -UninstallType "None" -InstallScript {
        $adminUser = "Administrator"
        $adminAccount = Get-LocalUser -Name $adminUser -ErrorAction SilentlyContinue
        if ($adminAccount) {
            if ($adminAccount.Enabled) {
                Write-Host "L'account '$adminUser' è già abilitato." -ForegroundColor Yellow
            } else {
                Enable-LocalUser -Name $adminUser
                Write-Host "L'account '$adminUser' è stato abilitato." -ForegroundColor Green
            }
        }
    }),
    (New-AppDefinition -Name "pGina (Login alternativo)" -Category "CONFIGURAZIONE SISTEMA" -Type "Script" -UninstallType "Script" -UninstallScript { Show-PGinaMenu } -InstallScript { Show-PGinaMenu }),

    # SOFTWARE ESSENZIALI
    (New-AppDefinition -Name "Winget AutoUpdate" -Category "SOFTWARE ESSENZIALI" -Type "Script" -UninstallType "Winget" -UninstallId "Romanitho.Winget-AutoUpdate" -InstallScript {
        winget install -e --id Romanitho.Winget-AutoUpdate --source winget --accept-package-agreements --silent
        $wauPath = "$env:ProgramData\WAU"
        $exclusionFileSource = Join-Path $Global:LocalScriptRoot "excluded_apps.txt"
        $exclusionFileDest = Join-Path $wauPath "excluded_apps.txt"
        if (Test-ProgramPath $exclusionFileSource) {
            if (-not (Test-ProgramPath $wauPath)) { New-Item -Path $wauPath -ItemType Directory -Force | Out-Null }
            Copy-Item -Path $exclusionFileSource -Destination $exclusionFileDest -Force
            Write-Host "File excluded_apps.txt configurato." -ForegroundColor Green
        }
    }),
    (New-AppDefinition -Name "WAU Settings GUI" -Category "SOFTWARE ESSENZIALI" -Id "KnifMelti.WAU-Settings-GUI"),
    (New-AppDefinition -Name "Google Drive" -Category "SOFTWARE ESSENZIALI" -Id "Google.GoogleDrive"),
    (New-AppDefinition -Name "Google Chrome" -Category "SOFTWARE ESSENZIALI" -Id "Google.Chrome"),
    (New-AppDefinition -Name "7zip" -Category "SOFTWARE ESSENZIALI" -Id "7zip.7zip"),
    (New-AppDefinition -Name "Zoom Workplace" -Category "SOFTWARE ESSENZIALI" -Id "Zoom.Zoom"),

    # SOFTWARE OFFICE & COMUNICAZIONE
    (New-AppDefinition -Name "Microsoft 365 Copilot" -Category "SOFTWARE OFFICE & COMUNICAZIONE" -Id "9WZDNCRD29V9"),
    (New-AppDefinition -Name "Microsoft 365" -Category "SOFTWARE OFFICE & COMUNICAZIONE" -Id "Microsoft.Office"),
    (New-AppDefinition -Name "Microsoft Office 2016 Professional Plus" -Category "SOFTWARE OFFICE & COMUNICAZIONE" -Type "Script" -UninstallType "None" -InstallScript {
        $OfficeInstalled = Test-ProgramPath "C:\Program Files\Microsoft Office\Office16\WINWORD.EXE" -or Test-ProgramPath "C:\Program Files (x86)\Microsoft Office\Office16\WINWORD.EXE"
        if ($OfficeInstalled) {
            Write-Host "Office 2016 risulta già installato." -ForegroundColor Yellow
        } else {
            $OfficePath = "$Global:LocalScriptRoot\Office Professional Plus 2016 64bit Ita\setup.exe"
            if (Test-ProgramPath $OfficePath) {
                Start-Process $OfficePath -Wait
                Write-Host "Installazione completata." -ForegroundColor Green
            } else {
                Write-Warning "File di installazione non trovato a $OfficePath"
            }
        }
    }),
    (New-AppDefinition -Name "Microsoft Teams" -Category "SOFTWARE OFFICE & COMUNICAZIONE" -Id "XP8BT8DW290MPQ"),
    (New-AppDefinition -Name "Adobe Acrobat Reader" -Category "SOFTWARE OFFICE & COMUNICAZIONE" -Id "Adobe.Acrobat.Reader.64-bit"),
    (New-AppDefinition -Name "LibreOffice" -Category "SOFTWARE OFFICE & COMUNICAZIONE" -Id "TheDocumentFoundation.LibreOffice"),
    (New-AppDefinition -Name "WhatsApp" -Category "SOFTWARE OFFICE & COMUNICAZIONE" -Id "9NKSQGP7F2NH"),
    (New-AppDefinition -Name "PDFsam Basic" -Category "SOFTWARE OFFICE & COMUNICAZIONE" -Id "PDFsam.PDFsam"),
    (New-AppDefinition -Name "Firma Digitale InfoCamiere" -Category "SOFTWARE OFFICE & COMUNICAZIONE" -Id "Bit4id.Firma4ng.InfoCamiere"),
    (New-AppDefinition -Name "Eset Security (Antivirus)" -Category "SOFTWARE OFFICE & COMUNICAZIONE" -Id "ESET.Nod32"),

    # SOFTWARE UTILITÀ
    (New-AppDefinition -Name "ShareX" -Category "SOFTWARE UTILITÀ" -Id "ShareX.ShareX"),
    (New-AppDefinition -Name "Everything" -Category "SOFTWARE UTILITÀ" -Id "voidtools.Everything"),
    (New-AppDefinition -Name "KeePassXC" -Category "SOFTWARE UTILITÀ" -Id "KeePassXCTeam.KeePassXC"),
    (New-AppDefinition -Name "Notepad++" -Category "SOFTWARE UTILITÀ" -Id "Notepad++.Notepad++"),
    (New-AppDefinition -Name "Mendeley Reference Manager" -Category "SOFTWARE UTILITÀ" -Id "Elsevier.MendeleyReferenceManager"),
    (New-AppDefinition -Name "Advanced Renamer" -Category "SOFTWARE UTILITÀ" -Id "HulubuluSoftware.AdvancedRenamer"),
    (New-AppDefinition -Name "AutoHotkey" -Category "SOFTWARE UTILITÀ" -Type "Download" -Url "https://www.autohotkey.com/download/ahk-v2.exe" -InstallPath "C:\Program Files\AutoHotkey\UX\AutoHotkeyUX.exe" -UninstallType "Winget" -UninstallId "AutoHotkey.AutoHotkey"),
    (New-AppDefinition -Name "VirtualBox" -Category "SOFTWARE UTILITÀ" -Id "Oracle.VirtualBox"),
    (New-AppDefinition -Name "WinSCP" -Category "SOFTWARE UTILITÀ" -Id "WinSCP.WinSCP"),
    (New-AppDefinition -Name "Putty" -Category "SOFTWARE UTILITÀ" -Id "PuTTY.PuTTY"),
    (New-AppDefinition -Name "Supremo Control" -Category "SOFTWARE UTILITÀ" -Type "Download" -Url "https://www.nanosystems.it/public/download/Supremo.exe" -InstallPath "C:\Program Files (x86)\Supremo\Supremo.exe" -UninstallType "None"),

    # SOFTWARE STATISTICI
    (New-AppDefinition -Name "JASP" -Category "SOFTWARE STATISTICI" -Id "UniversityOfAmsterdam.JASP"),
    (New-AppDefinition -Name "R Project" -Category "SOFTWARE STATISTICI" -Id "RProject.R"),
    (New-AppDefinition -Name "GPower" -Category "SOFTWARE STATISTICI" -Id "GPower.GPower"),
    (New-AppDefinition -Name "RStudio" -Category "SOFTWARE STATISTICI" -Id "Posit.RStudio"),
    (New-AppDefinition -Name "Orange" -Category "SOFTWARE STATISTICI" -Id "UniversityOfLjubljana.Orange"),
    (New-AppDefinition -Name "Python" -Category "SOFTWARE STATISTICI" -Id "Python.Launcher"),
    (New-AppDefinition -Name "Jupyter Notebook" -Category "SOFTWARE STATISTICI" -Id "ProjectJupyter.JupyterLab"),

    # MULTIMEDIA
    (New-AppDefinition -Name "Audacity" -Category "MULTIMEDIA" -Id "Audacity.Audacity"),
    (New-AppDefinition -Name "Avidemux" -Category "MULTIMEDIA" -Id "Avidemux.Avidemux"),
    (New-AppDefinition -Name "DaVinci Resolve" -Category "MULTIMEDIA" -Type "Download" -Url "https://swr.cloud.blackmagicdesign.com/DaVinciResolve/v20.3.2/DaVinci_Resolve_Studio_20.3.2_Windows.zip" -InstallPath "C:\Program Files\Blackmagic Design\DaVinci Resolve\DaVinci Resolve.exe" -UninstallType "None"),
    (New-AppDefinition -Name "Gimp" -Category "MULTIMEDIA" -Id "GIMP.GIMP.3"),
    (New-AppDefinition -Name "K-Lite Codec Pack Standard" -Category "MULTIMEDIA" -Id "CodecGuide.K-LiteCodecPack.Standard"),
    (New-AppDefinition -Name "OBS Studio" -Category "MULTIMEDIA" -Id "OBSProject.OBSStudio"),
    (New-AppDefinition -Name "VLC Player" -Category "MULTIMEDIA" -Id "VLC.VLC"),
    (New-AppDefinition -Name "Shutter Encoder" -Category "MULTIMEDIA" -Id "PaulPacifico.ShutterEncoder"),
    (New-AppDefinition -Name "Subtitle Edit" -Category "MULTIMEDIA" -Id "Nikse.SubtitleEdit"),

    # SOFTWARE 3D
    (New-AppDefinition -Name "Fusion 360" -Category "SOFTWARE 3D" -Type "Download" -Url "https://dl.appstreaming.autodesk.com/production/installers/Fusion%20Client%20Downloader.exe" -InstallPath "$env:LOCALAPPDATA\Autodesk\webdeploy\production\Fusion360.exe" -UninstallType "None"),
    (New-AppDefinition -Name "PrusaSlicer" -Category "SOFTWARE 3D" -Id "Prusa3D.PrusaSlicer"),
    (New-AppDefinition -Name "OpenSCAD" -Category "SOFTWARE 3D" -Id "OpenSCAD.OpenSCAD"),
    (New-AppDefinition -Name "Shapr3D" -Category "SOFTWARE 3D" -Id "Shapr3D.Shapr3D"),
    (New-AppDefinition -Name "Blender" -Category "SOFTWARE 3D" -Id "Blender.Blender"),
    (New-AppDefinition -Name "Meshmixer" -Category "SOFTWARE 3D" -Id "Autodesk.Meshmixer"),
    (New-AppDefinition -Name "Ultimaker Cura" -Category "SOFTWARE 3D" -Id "Ultimaker.Cura"),

    # SOFTWARE PROGRAMMAZIONE
    (New-AppDefinition -Name "draw.io" -Category "SOFTWARE PROGRAMMAZIONE" -Id "jgraph.drawio"),
    (New-AppDefinition -Name "Visual Studio Code" -Category "SOFTWARE PROGRAMMAZIONE" -Id "Microsoft.VisualStudioCode"),
    (New-AppDefinition -Name "Docker Desktop" -Category "SOFTWARE PROGRAMMAZIONE" -Id "Docker.DockerDesktop"),
    (New-AppDefinition -Name "GitHub Desktop" -Category "SOFTWARE PROGRAMMAZIONE" -Id "GitHub.GitHubDesktop"),
    (New-AppDefinition -Name "Node.js" -Category "SOFTWARE PROGRAMMAZIONE" -Id "OpenJSFoundation.NodeJS.LTS"),
    (New-AppDefinition -Name "FileZilla" -Category "SOFTWARE PROGRAMMAZIONE" -Id "FileZilla.FileZilla.Client"),
    (New-AppDefinition -Name "Postman" -Category "SOFTWARE PROGRAMMAZIONE" -Id "Postman.Postman"),
    (New-AppDefinition -Name "OpenAI Codex" -Category "SOFTWARE PROGRAMMAZIONE" -Id "OpenAI.Codex"),
    (New-AppDefinition -Name "XAMPP" -Category "SOFTWARE PROGRAMMAZIONE" -Type "Download" -Url "https://www.apachefriends.org/xampp-files/8.2.4/xampp-windows-x64-8.2.4-0-VS16-installer.exe" -InstallPath "C:\xampp\xampp-control.exe" -UninstallType "None"),

    # STAMPANTI
    (New-AppDefinition -Name "Stampante Canon iR C3226" -Category "STAMPANTI" -Type "Script" -UninstallType "None" -InstallScript {
        $PortName = "Canon iR C3226 Scienze motorie"
        $DriverPath = "$Global:LocalScriptRoot\Canon_IR_C3226_PCL6_Driver_V330_32_64_00\x64\Driver\CNP60MA64.INF"
        $DriverModel = "Canon Generic Plus PCL6"
        $IPAddress = "193.206.72.226"
        $PrinterName = "Canon IR C3226"
        try { Add-PrinterPort -Name $PortName -PrinterHostAddress $IPAddress -ErrorAction Stop } catch {}
        if (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue) { Set-PrinterPort -Name $PortName -SNMP $false }
        if (Test-ProgramPath $DriverPath) {
            rundll32 printui.dll,PrintUIEntry /if /b $PrinterName /f $DriverPath /r $PortName /m $DriverModel
            Write-Host "Stampante Canon installata." -ForegroundColor Green
        }
    }),
    (New-AppDefinition -Name "Stampante HP LaserJet E72425" -Category "STAMPANTI" -Type "Script" -UninstallType "None" -InstallScript {
        $PortName = "HP LaserJet MFP E72425 [44B668] Biostatistica"
        $DriverPath = "$Global:LocalScriptRoot\LJE72425-E72430\hponef2a4_x64.inf"
        $DriverModel = "HP LaserJet MFP E72425 E72430 PCL-6 (V4)"
        $IPAddress = "193.206.68.205"
        $PrinterName = "HP LaserJet MFP E72425"
        try { Add-PrinterPort -Name $PortName -PrinterHostAddress $IPAddress -ErrorAction Stop } catch {}
        if (Test-ProgramPath $DriverPath) {
            rundll32 printui.dll,PrintUIEntry /if /b $PrinterName /f $DriverPath /r $PortName /m $DriverModel
            Write-Host "Stampante HP installata." -ForegroundColor Green
        }
    })
)

# ============================================================================
# 6. SISTEMA DI MENU INTERATTIVO E GESTIONE CODA
# ============================================================================
function Show-MainMenu {
    do {
        Clear-Host
        $headerText = "MENU PRINCIPALE`r`nInstallazione Pacchetti Software Windows"
        if ($Global:InstallQueue.Count -gt 0) {
            $headerText += "`r`n[ Elementi in Coda: $($Global:InstallQueue.Count) ]"
        }
        Write-Host (Show-CenteredBox -action $headerText -rows 4) -ForegroundColor Cyan
        Write-Host "`n"

        $categories = $Global:AppCatalog.Category | Select-Object -Unique | Sort-Object
        $index = 1

        foreach ($cat in $categories) {
            Write-Host "  [$index] $cat" -ForegroundColor Yellow
            $index++
        }

        Write-Host "`n  [Q] Gestione / Esecuzione Coda ($($Global:InstallQueue.Count) elementi)" -ForegroundColor Green
        Write-Host "  [U] Disinstallazione Software" -ForegroundColor Magenta
        Write-Host "  [0] Esci" -ForegroundColor Red
        Write-Host "`n"

        $choice = Read-Host "Seleziona un'opzione"

        if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) {
            Write-Host "Uscita in corso..." -ForegroundColor Red
            exit
        } elseif ($choice -eq "Q" -or $choice -eq "q") {
            Show-QueueMenu
        } elseif ($choice -eq "U" -or $choice -eq "u") {
            Show-UninstallMenu
        } else {
            $catIndex = [int]$choice - 1
            if ($catIndex -ge 0 -and $catIndex -lt $categories.Count) {
                Show-SubMenu -Category $categories[$catIndex]
            } else {
                Write-Host "Scelta non valida." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}

function Show-SubMenu {
    param([string]$Category)

    do {
        Clear-Host
        Write-Host (Show-CenteredBox -action $Category -rows 3) -ForegroundColor Cyan
        Write-Host "`n"

        $items = $Global:AppCatalog | Where-Object { $_.Category -eq $Category }
        $idx = 1

        foreach ($item in $items) {
            $inQueue = if ($Global:InstallQueue.Contains($item)) { " [in Coda]" } else { "" }
            Write-Host "  [$idx] $($item.Name)$inQueue" -ForegroundColor Green
            $idx++
        }

        Write-Host "`n  [A] Aggiungi TUTTI gli elementi della categoria alla coda" -ForegroundColor Yellow
        Write-Host "  [I] Installa TUTTI immediatamente (con conferma)" -ForegroundColor Cyan
        Write-Host "  [X] Installa TUTTI immediatamente (senza conferma)" -ForegroundColor DarkRed
        Write-Host "  [0] Torna al menu principale" -ForegroundColor Red
        Write-Host "`n"

        $choice = Read-Host "Seleziona uno o piu numeri (es. 1,3) oppure un'azione"

        if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }

        if ($choice -eq "A" -or $choice -eq "a") {
            foreach ($item in $items) {
                if (-not $Global:InstallQueue.Contains($item)) { $Global:InstallQueue.Add($item) }
            }
            Write-Host "`nAggiunti tutti gli elementi alla coda!" -ForegroundColor Green
            Start-Sleep -Seconds 1
        }
        elseif ($choice -eq "I" -or $choice -eq "i") {
            foreach ($item in $items) { Invoke-AppInstall -App $item -Ask $true }
            Read-Host "Operazioni completate. Premi Invio per proseguire"
        }
        elseif ($choice -eq "X" -or $choice -eq "x") {
            foreach ($item in $items) { Invoke-AppInstall -App $item -Ask $false }
            Read-Host "Operazioni completate. Premi Invio per proseguire"
        }
        else {
            # Gestione selezione singola o multipla
            $indices = $choice.Split(',').Trim() | ForEach-Object {
                $n = 0
                if ([int]::TryParse($_, [ref]$n)) { $n - 1 }
            }

            foreach ($i in $indices) {
                if ($i -ge 0 -and $i -lt $items.Count) {
                    $selectedApp = $items[$i]
                    Write-Host "`nSelezionato: $($selectedApp.Name)" -ForegroundColor Cyan
                    Write-Host "1. Installa subito (con conferma)"
                    Write-Host "2. Installa subito (senza conferma)"
                    Write-Host "3. Aggiungi alla coda di installazione"
                    $act = Read-Host "Scegli azione (Default: 1)"

                    switch ($act) {
                        "2" { Invoke-AppInstall -App $selectedApp -Ask $false }
                        "3" { 
                            if (-not $Global:InstallQueue.Contains($selectedApp)) {
                                $Global:InstallQueue.Add($selectedApp)
                                Write-Host "Aggiunto alla coda." -ForegroundColor Green
                            }
                        }
                        default { Invoke-AppInstall -App $selectedApp -Ask $true }
                    }
                }
            }
            Start-Sleep -Seconds 1
        }
    } while ($true)
}

# ============================================================================
# 7. MENU GESTIONE CODA DI INSTALLAZIONE
# ============================================================================
function Show-QueueMenu {
    do {
        Clear-Host
        Write-Host (Show-CenteredBox -action "CODA DI INSTALLAZIONE ($($Global:InstallQueue.Count) elementi)" -rows 3) -ForegroundColor Green
        Write-Host "`n"

        if ($Global:InstallQueue.Count -eq 0) {
            Write-Host "La coda è attualmente vuota.`n" -ForegroundColor Yellow
            Write-Host "  [0] Torna al menu principale" -ForegroundColor Red
            Read-Host
            return
        }

        $i = 1
        foreach ($app in $Global:InstallQueue) {
            Write-Host "  [$i] $($app.Name) [$($app.Category)]" -ForegroundColor Green
            $i++
        }

        Write-Host "`n  [1] Esegui installazione della Coda (CON conferma per ciascuno)" -ForegroundColor Cyan
        Write-Host "  [2] Esegui installazione della Coda (SENZA conferma - Automatico)" -ForegroundColor DarkRed
        Write-Host "  [R] Rimuovi un elemento dalla coda" -ForegroundColor Yellow
        Write-Host "  [C] Svuota completamente la coda" -ForegroundColor Red
        Write-Host "  [0] Torna al menu principale" -ForegroundColor White
        Write-Host "`n"

        $choice = Read-Host "Seleziona un'opzione"

        if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }

        switch ($choice) {
            "1" {
                foreach ($app in @($Global:InstallQueue)) {
                    Invoke-AppInstall -App $app -Ask $true
                }
                $Global:InstallQueue.Clear()
                Read-Host "`nEsecuzione coda completata. Premi Invio per proseguire"
                return
            }
            "2" {
                foreach ($app in @($Global:InstallQueue)) {
                    Invoke-AppInstall -App $app -Ask $false
                }
                $Global:InstallQueue.Clear()
                Read-Host "`nEsecuzione automatica coda completata. Premi Invio per proseguire"
                return
            }
            "R" {
                $remIdx = Read-Host "Inserisci il numero dell'elemento da rimuovere"
                $num = 0
                if ([int]::TryParse($remIdx, [ref]$num) -and $num -ge 1 -and $num -le $Global:InstallQueue.Count) {
                    $removed = $Global:InstallQueue[$num - 1]
                    $Global:InstallQueue.RemoveAt($num - 1)
                    Write-Host "Rimosso '$($removed.Name)' dalla coda." -ForegroundColor Green
                    Start-Sleep -Seconds 1
                }
            }
            "C" {
                $Global:InstallQueue.Clear()
                Write-Host "Coda svuotata." -ForegroundColor Green
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}

# ============================================================================
# 8. MENU DISINSTALLAZIONE SOFTWARE
# ============================================================================
function Show-UninstallMenu {
    do {
        Clear-Host
        Write-Host (Show-CenteredBox -action "MENU DISINSTALLAZIONE SOFTWARE" -rows 3) -ForegroundColor Magenta
        Write-Host "`n"

        $uninstallable = $Global:AppCatalog | Where-Object { $_.UninstallType -ne "None" }
        $idx = 1

        foreach ($app in $uninstallable) {
            Write-Host "  [$idx] $($app.Name)" -ForegroundColor Yellow
            $idx++
        }

        Write-Host "`n  [0] Torna al menu principale" -ForegroundColor Red
        Write-Host "`n"

        $choice = Read-Host "Seleziona l'elemento da disinstallare (o piu numeri separati da virgola)"

        if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }

        $indices = $choice.Split(',').Trim() | ForEach-Object {
            $n = 0
            if ([int]::TryParse($_, [ref]$n)) { $n - 1 }
        }

        foreach ($i in $indices) {
            if ($i -ge 0 -and $i -lt $uninstallable.Count) {
                Invoke-AppUninstall -App $uninstallable[$i] -Ask $true
            }
        }
        Read-Host "`nOperazione completata. Premi Invio per continuare"
    } while ($true)
}

# Submenu speciale per pGina
function Show-PGinaMenu {
    $action = "Installazione di pGina"
    $title = Show-CenteredBox -action $action
    $message = "Scegli la versione di pGina da installare:"

    $choicesPGina = [System.Management.Automation.Host.ChoiceDescription[]]@(
        New-Object System.Management.Automation.Host.ChoiceDescription "Sì, pGina &originale 3.1.8.0", "pGina originale."
        New-Object System.Management.Automation.Host.ChoiceDescription "Sì, pGina &fork 3.9.9.12", "pGina Fork."
        New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Salta."
        New-Object System.Management.Automation.Host.ChoiceDescription "&Esci", "Interrompe lo script."
    )

    $decision = $host.UI.PromptForChoice($title, $message, $choicesPGina, 2)

    switch ($decision) {
        0 {
            Download-Install-Sw -Name "pGina 3.1.8.0" -Url "https://github.com/pgina/pgina/releases/download/v3.1.8.0/pGinaSetup-3.1.8.0.exe" -InstallPath "C:\Program Files\pGina\pGina.Configuration.exe"
        }
        1 {
            Download-Install-Sw -Name "pGina fork 3.9.9.12" -Url "https://github.com/MutonUfoAI/pgina/releases/download/3.9.9.12/pGinaSetup-3.9.9.12.exe" -InstallPath "C:\Program Files\pGina.fork\pGina.Configuration.exe"
        }
        2 { Write-Host "Operazione pGina saltata." -ForegroundColor Yellow }
        3 { exit }
    }
}

# ============================================================================
# AVVIO DELLO SCRIPT
# ============================================================================
Show-MainMenu
Write-Host (Show-CenteredBox -action "OPERAZIONI COMPLETATE" -rows 3) -ForegroundColor Green
pause
