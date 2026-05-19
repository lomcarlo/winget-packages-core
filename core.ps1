# 1. Gestione finestra precedente
$WindowTitle = "*powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Maximized -File*"
$ParentProcess = Get-Process | Where-Object { $_.MainWindowTitle -like $WindowTitle }
if ($ParentProcess) { $ParentProcess | Stop-Process -Force }

# 2. Forza Massimizzazione
$cmd = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
$type = Add-Type -MemberDefinition $cmd -Name "Win32ShowWindow" -Namespace "Win32" -PassThru
$handle = (Get-Process -Id $PID).MainWindowHandle
$type::ShowWindow($handle, 3)
Clear-Host 

function Show-CenteredBox {
    param(
        [string]$action, 
        [int]$rows = 1
    )

    $width = 78  # Larghezza interna della cornice
    $lines = $action -split "`r`n"
    $outputLines = @()

    # 1. Costruzione del bordo superiore
    $result = "╔$($('═' * $width))╗`r`n"

    # 2. Aggiunta di eventuali righe vuote sopra (se $rows > 1)
    # Ne aggiungiamo (rows - 1) divise tra sopra e sotto per centrare verticalmente
    $emptyRowsTop = [math]::Floor(($rows - 1) / 2)
    for ($i = 0; $i -lt $emptyRowsTop; $i++) {
        $result += "║$(' ' * $width)║`r`n"
    }

    # 3. Elaborazione di ogni riga di testo (gestisce lo split \r\n)
    foreach ($line in $lines) {
        $currentLine = $line
        
        # Tronca se troppo lunga
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

    # 4. Aggiunta di eventuali righe vuote sotto
    $emptyRowsBottom = ($rows - 1) - $emptyRowsTop
    for ($i = 0; $i -lt $emptyRowsBottom; $i++) {
        $result += "║$(' ' * $width)║`r`n"
    }

    # 5. Bordo inferiore
    $result += "╚$($('═' * $width))╝"

    return $result
}

# -----------------------------

$testo = "PROGRAMMA DI INSTALLAZIONE PACCHETTI SOFTWARE WINDOWS 10+`r`nBy Carlo Lombardo"
Write-Host (Show-CenteredBox -action $testo -rows 3) -ForegroundColor White

# Controllo privilegi Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath)
    exit
}

function Get-ScriptPath {
    <#
    .SYNOPSIS
        Restituisce la cartella contenente lo script corrente.
    #>
    if ($PSVersionTable.PSVersion.Major -ge 3) {
        # Metodo consigliato per PowerShell 3.0 e versioni successive
        return $PSScriptRoot
    }
    else {
        # Metodo compatibile con PowerShell 2.0
        return Split-Path -Parent $MyInvocation.MyCommand.Definition
    }
}

# 1. Se la variabile globale non esiste o è vuota, prova il fallback
if ([string]::IsNullOrEmpty($Global:LocalScriptRoot)) {
    
    # Visualizza il box di avviso 
    Write-Host (Show-CenteredBox -action "`$Global:LocalScriptRoot non presente. Provo con Get-ScriptPath" -rows 1) -ForegroundColor Red
    
    # Assegnazione corretta con un solo uguale '='
    $Global:LocalScriptRoot = Get-ScriptPath
}

# 2. Se è ancora vuota dopo il primo tentativo, manda il secondo avviso
if ([string]::IsNullOrEmpty($Global:LocalScriptRoot)) {
    Write-Host (Show-CenteredBox -action "Non funziona nemmeno Get-ScriptPath" -rows 1) -ForegroundColor Red
}

# Funzione per verificare l'esistenza di un programma nel percorso di installazione standard
function Test-ProgramPath {
    param(
        [string]$Path
    )
	if([string]::IsNullOrEmpty($Path)) {
		return false
	}else{
		return Test-Path $Path
	}
}

$choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
    New-Object System.Management.Automation.Host.ChoiceDescription "&Sì", "Esegue l'operazione descritta."
    New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Salta questa operazione."
    New-Object System.Management.Automation.Host.ChoiceDescription "&Esci", "Interrompe l'intero script."
)

function Invoke-Action {
    param(
        [string]$Name,
        [string]$Description,
        [scriptblock]$ScriptBlock,
		[int]$Rows = 1
    )

    $title = Show-CenteredBox -action "$Name`r`n$Description" -rows $Rows
    $message = "Vuoi procedere?"
    
    # Usa la variabile globale $choices definita all'inizio dello script
    $decision = $host.UI.PromptForChoice($title, $message, $choices, 1)

    switch ($decision) {
        0 {
            Write-Host "Procedo con: $Name..." -ForegroundColor Cyan
            & $ScriptBlock
            Write-Host "Operazione '$Name' completata." -ForegroundColor Green
        }
        1 {
            Write-Host "Operazione '$Name' saltata." -ForegroundColor Yellow
        }
        2 {
            Write-Host "Uscita in corso..." -ForegroundColor Red
            exit
        }
    }
}

function Download-Install-Sw {
    param(
        [string]$Name,
        [string]$Url,
        [string]$InstallPath
    )
    $installed = Test-ProgramPath $InstallPath
    if ($installed) {
        Write-Host "$Name sembra essere già installato. Salto l'installazione." -ForegroundColor Yellow
    } else {
        # Trasforma la stringa in un oggetto URI e prende solo il "AbsolutePath"
        $cleanPath = ([System.Uri]$Url).AbsolutePath

        # Estrae il nome del file (es: DaVinci_Resolve_Studio_20.3.2_Windows.zip)
        $filename = Split-Path $cleanPath -Leaf

        # Crea il percorso finale nella cartella Temp
        $destination = Join-Path $env:TEMP $filename
        $dir = Split-Path $destination
        if (!(Test-ProgramPath $dir)) { New-Item -ItemType Directory -Path $dir -Force }
        Invoke-WebRequest -Uri $Url -OutFile $destination
        if (Test-ProgramPath $destination) {
            Write-Host "Procedo con l'installazione di $Name. Ricordati di chiuderlo per continuare lo script..." -ForegroundColor Cyan
            Start-Process $destination -Wait
            Write-Host "Installazione di $Name completata." -ForegroundColor Green
        } else {
            Write-Warning "File di installazione non trovato al percorso $destination Salto l'installazione."
        }
    }
}

function Install-Sw {
    param(
        [string]$Name,
        [string]$Id,
        [bool]$Ask = $false,
        [string]$Source = "winget"
    )

	$title = Show-CenteredBox -action $Name
	$message = "Vuoi procedere con l'installazione?"

    if ($Ask) {
        $decision = $host.UI.PromptForChoice($title, $message, $choices, 1)
    } else {
        # Se $Ask è false, forziamo la decisione a 0 (Installa senza chiedere)
		Write-Host $title
        $decision = 0
    }

    switch ($decision) {
        0 {
            Write-Host "Procedo con l'installazione di $Name..." -ForegroundColor Cyan
            winget install -e --id $Id --source $Source --accept-package-agreements --silent
            Write-Host "Installazione di $Name completata." -ForegroundColor Green
        }
        1 {
            Write-Host "Installazione di $Name saltata." -ForegroundColor Yellow
        }
        2 {
            Write-Host "Uscita in corso..." -ForegroundColor Red
            exit 
        }
    }
}

# ============================================================================
# MENU PRINCIPALE - SISTEMA INTERATTIVO
# ============================================================================

$MenuItems = @{
    "CONFIGURAZIONE SISTEMA" = @(
        @{ Name = "Disabilitazione OOBE"; ScriptBlock = {
            $RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE"
            if (-not (Test-ProgramPath $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }
            Set-ItemProperty -Path $RegistryPath -Name "DisablePrivacyExperience" -Value 1 -Type DWORD -Force
            Write-Host "OOBE disabilitato." -ForegroundColor Green
        }}
        @{ Name = "Impostazione immagine UniPV"; ScriptBlock = {
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
        }}
        @{ Name = "Aggiunta utente Ospite"; ScriptBlock = {
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
                        Write-Host "`nERRORE: La password non soddisfa i requisiti." -ForegroundColor Red
                        Write-Host "Dettaglio: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
        }}
    )
    
    "SOFTWARE ESSENZIALI" = @(
        @{ Name = "Winget AutoUpdate"; ScriptBlock = {
            Install-Sw "Winget AutoUpdate" "Romanitho.Winget-AutoUpdate"
            $wauPath = "$env:ProgramData\WAU"
            $exclusionFileSource = Join-Path $Global:LocalScriptRoot "excluded_apps.txt"
            $exclusionFileDest = Join-Path $wauPath "excluded_apps.txt"
            if (Test-ProgramPath $exclusionFileSource) {
                Write-Host "Configurazione file di esclusione per Winget-AutoUpdate..." -ForegroundColor Cyan
                if (-not (Test-ProgramPath $wauPath)) {
                    New-Item -Path $wauPath -ItemType Directory -Force | Out-Null
                }
                Copy-Item -Path $exclusionFileSource -Destination $exclusionFileDest -Force
                Write-Host "File excluded_apps.txt configurato." -ForegroundColor Green
            }
        }}
        @{ Name = "Google Drive"; ScriptBlock = { Install-Sw "Google Drive" "Google.GoogleDrive" } }
        @{ Name = "Google Chrome"; ScriptBlock = { Install-Sw "Google Chrome" "Google.Chrome" } }
        @{ Name = "7zip"; ScriptBlock = { Install-Sw "7zip" "7zip.7zip" } }
        @{ Name = "Zoom"; ScriptBlock = { Install-Sw "Zoom Workplace" "Zoom.Zoom" } }
        @{ Name = "VLC Player"; ScriptBlock = { Install-Sw "VLC Video Player" "VLC.VLC" } }
    )
    
    "SOFTWARE OFFICE & COMUNICAZIONE" = @(
        @{ Name = "Microsoft Teams"; ScriptBlock = { Install-Sw "Microsoft Teams" "XP8BT8DW290MPQ" } }
        @{ Name = "Adobe Acrobat Reader"; ScriptBlock = { Install-Sw "Adobe Acrobat Reader" "Adobe.Acrobat.Reader.64-bit" } }
        @{ Name = "WhatsApp"; ScriptBlock = { Install-Sw "WhatsApp" "9NKSQGP7F2NH" } }
    )
    
    "SOFTWARE UTILITÀ" = @(
        @{ Name = "Notepad++"; ScriptBlock = { Install-Sw "Notepad++" "Notepad++.Notepad++" } }
        @{ Name = "Mendeley Reference Manager"; ScriptBlock = { Install-Sw "Mendeley Reference Manager" "Elsevier.MendeleyReferenceManager" } }
        @{ Name = "Advanced Renamer"; ScriptBlock = { Install-Sw "Advanced Renamer" "HulubuluSoftware.AdvancedRenamer" } }
    )
    
    "SOFTWARE STATISTICI" = @(
        @{ Name = "JASP"; ScriptBlock = { Install-Sw "JASP" "UniversityOfAmsterdam.JASP" } }
        @{ Name = "R Project"; ScriptBlock = { Install-Sw "R Project" "RProject.R" } }
        @{ Name = "GPower"; ScriptBlock = { Install-Sw "GPower" "GPower.GPower" } }
        @{ Name = "RStudio"; ScriptBlock = { Install-Sw "RStudio" "Posit.RStudio" } }
        @{ Name = "Orange"; ScriptBlock = { Install-Sw "Orange" "UniversityOfLjubljana.Orange" } }
        @{ Name = "Python"; ScriptBlock = { Install-Sw "Python" "Python.Launcher" } }
        @{ Name = "Jupyter Notebook"; ScriptBlock = { Install-Sw "Jupyter Notebook" "ProjectJupyter.JupyterLab" } }
    )
    
    "MULTIMEDIA" = @(
        @{ Name = "Audacity"; ScriptBlock = { Install-Sw "Audacity" "Audacity.Audacity" } }
        @{ Name = "Gimp"; ScriptBlock = { Install-Sw "Gimp" "GIMP.GIMP.3" } }
        @{ Name = "K-Lite Codec Pack"; ScriptBlock = { Install-Sw "K-Lite Codec Pack Standard" "CodecGuide.K-LiteCodecPack.Standard" } }
        @{ Name = "Avidemux"; ScriptBlock = { Install-Sw "Avidemux (Montaggio Video)" "Avidemux.Avidemux" } }
        @{ Name = "OBS Studio"; ScriptBlock = { Install-Sw "OBS Studio (Registrazione dello schermo)" "OBSProject.OBSStudio" } }
    )
    
    "SOFTWARE 3D" = @(
        @{ Name = "PrusaSlicer"; ScriptBlock = { Install-Sw "PrusaSlicer" "Prusa3D.PrusaSlicer" } }
        @{ Name = "OpenSCAD"; ScriptBlock = { Install-Sw "OpenSCAD" "OpenSCAD.OpenSCAD" } }
        @{ Name = "Shapr3D"; ScriptBlock = { Install-Sw "Shapr3D" "Shapr3D.Shapr3D" } }
    )
    
    "SOFTWARE PROGRAMMAZIONE" = @(
        @{ Name = "Visual Studio Code"; ScriptBlock = { Install-Sw "Microsoft Visual Studio Code" "Microsoft.VisualStudioCode" } }
        @{ Name = "Docker Desktop"; ScriptBlock = { Install-Sw "Docker Desktop" "Docker.DockerDesktop" } }
    )
    
    "STAMPANTI" = @(
        @{ Name = "Stampante Canon iR C3226"; ScriptBlock = {
            $PortName = "Canon iR C3226 Scienze motorie"
            $DriverPath = "$Global:LocalScriptRoot\Canon_IR_C3226_PCL6_Driver_V330_32_64_00\x64\Driver\CNP60MA64.INF"
            $DriverModel = "Canon Generic Plus PCL6"
            $IPAddress = "193.206.72.226"
            $PrinterName = "Canon IR C3226"
            
            try {
                Add-PrinterPort -Name $PortName -PrinterHostAddress $IPAddress -ErrorAction Stop
                Write-Host "Porta creata." -ForegroundColor Green
            } catch {
                if ($_.Exception.HResult -eq -2147024713) {
                    Write-Host "La porta esiste già." -ForegroundColor Yellow
                }
            }
            
            if (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue) {
                Set-PrinterPort -Name $PortName -SNMP $false
            }
            
            if (Test-ProgramPath $DriverPath) {
                rundll32 printui.dll,PrintUIEntry /if /b $PrinterName /f $DriverPath /r $PortName /m $DriverModel
                Write-Host "Stampante Canon installata." -ForegroundColor Green
            }
        }}
        @{ Name = "Stampante HP LaserJet E72425"; ScriptBlock = {
            $PortName = "HP LaserJet MFP E72425 [44B668] Biostatistica"
            $DriverPath = "$Global:LocalScriptRoot\LJE72425-E72430\hponef2a4_x64.inf"
            $DriverModel = "HP LaserJet MFP E72425 E72430 PCL-6 (V4)"
            $IPAddress = "193.206.68.205"
            $PrinterName = "HP LaserJet MFP E72425"
            
            try {
                Add-PrinterPort -Name $PortName -PrinterHostAddress $IPAddress -ErrorAction Stop
                Write-Host "Porta creata." -ForegroundColor Green
            } catch {
                if ($_.Exception.HResult -eq -2147024713) {
                    Write-Host "La porta esiste già." -ForegroundColor Yellow
                }
            }
            
            if (Test-ProgramPath $DriverPath) {
                rundll32 printui.dll,PrintUIEntry /if /b $PrinterName /f $DriverPath /r $PortName /m $DriverModel
                Write-Host "Stampante HP installata." -ForegroundColor Green
            }
        }}
    )
}

# ============================================================================
# FUNZIONE MENU
# ============================================================================

function Show-MainMenu {
    do {
        Clear-Host
        Write-Host (Show-CenteredBox -action "MENU PRINCIPALE`r`nInstallazione Pacchetti Software Windows" -rows 3) -ForegroundColor Cyan
        Write-Host "`n"
        
        $categoryIndex = 1
        $categories = @()
        
        foreach ($category in $MenuItems.Keys) {
            Write-Host "  [$categoryIndex] $category" -ForegroundColor Yellow
            $categories += $category
            $categoryIndex++
        }
        
        Write-Host "  [0] Esci" -ForegroundColor Red
        Write-Host "`n"
        $choice = Read-Host "Seleziona una categoria (numero)"
        
        if ($choice -eq "0") {
            Write-Host "Uscita in corso..." -ForegroundColor Red
            exit
        }
        
        $categoryIndex = [int]$choice - 1
        
        if ($categoryIndex -ge 0 -and $categoryIndex -lt $categories.Count) {
            $selectedCategory = $categories[$categoryIndex]
            Show-SubMenu -Category $selectedCategory
        } else {
            Write-Host "Scelta non valida. Premi un tasto per continuare..." -ForegroundColor Red
            Read-Host
        }
        
    } while ($true)
}

function Show-SubMenu {
    param([string]$Category)
    
    do {
        Clear-Host
        Write-Host (Show-CenteredBox -action $Category -rows 2) -ForegroundColor Cyan
        Write-Host "`n"
        
        $items = $MenuItems[$Category]
        $itemIndex = 1
        
        foreach ($item in $items) {
            Write-Host "  [$itemIndex] $($item.Name)" -ForegroundColor Green
            $itemIndex++
        }
        
        Write-Host "  [$itemIndex] Installa Tutti (con conferma)" -ForegroundColor Cyan
        $installAllIndex = $itemIndex
        $itemIndex++
        
        Write-Host "  [$itemIndex] Installa Tutti Senza Conferma" -ForegroundColor Red
        $installAllNoConfirmIndex = $itemIndex
        $itemIndex++
        
        Write-Host "  [0] Torna al menu principale" -ForegroundColor Red
        Write-Host "`n"
        
        $choice = Read-Host "Seleziona un'opzione (numero)"
        
        if ($choice -eq "0") {
            return
        }
        
        $itemIndex = [int]$choice - 1
        
        # Opzione "Installa Tutti (con conferma)"
        if ($itemIndex -eq $installAllIndex) {
            Write-Host "`nInstallazione di tutti i software della categoria con conferma..." -ForegroundColor Cyan
            foreach ($item in $items) {
                & $item.ScriptBlock
            }
            Write-Host "`nInstallazione di tutti i software completata. Premi un tasto per continuare..." -ForegroundColor Green
            Read-Host
        }
        # Opzione "Installa Tutti Senza Conferma"
        elseif ($itemIndex -eq $installAllNoConfirmIndex) {
            Write-Host "`nInstallazione di tutti i software della categoria senza conferma..." -ForegroundColor Red
            foreach ($item in $items) {
                # Verifica se lo scriptblock contiene una chiamata Install-Sw
                $itemScriptString = $item.ScriptBlock.ToString()
                if ($itemScriptString -like "*Install-Sw*") {
                    # Esegui con Ask = $false (senza conferma)
                    & $item.ScriptBlock
                } else {
                    # Per altri script (non Install-Sw), esegui normalmente
                    & $item.ScriptBlock
                }
            }
            Write-Host "`nInstallazione di tutti i software completata. Premi un tasto per continuare..." -ForegroundColor Green
            Read-Host
        }
        # Opzione singolo software
        elseif ($itemIndex -ge 0 -and $itemIndex -lt $items.Count) {
            $selectedItem = $items[$itemIndex]
            Write-Host "`nEsecuzione: $($selectedItem.Name)..." -ForegroundColor Cyan
            & $selectedItem.ScriptBlock
            Write-Host "`nOperazione completata. Premi un tasto per continuare..." -ForegroundColor Green
            Read-Host
        } else {
            Write-Host "Scelta non valida. Premi un tasto per continuare..." -ForegroundColor Red
            Read-Host
        }
        
    } while ($true)
}

# ============================================================================
# AVVIA IL MENU
# ============================================================================
Show-MainMenu
Write-Host (Show-CenteredBox -action "INSTALLAZIONE COMPLETATA" -rows 3) -ForegroundColor Green
pause
