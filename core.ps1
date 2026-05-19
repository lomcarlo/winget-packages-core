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
        $dir = Split-Path $path
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
        [bool]$Ask = $true
    )

	$title = Show-CenteredBox -action $Name
	$message = "Vuoi procedere con l'installazione?"

    if ($Ask) {
        $decision = $host.UI.PromptForChoice($title, $message, $choices, 1)
    } else {
        # Se $Ask è false, forziamo la decisione a 0 (Installa)
		Write-Host $title
        $decision = 0
    }

    switch ($decision) {
        0 {
            Write-Host "Procedo con l'installazione di $Name..." -ForegroundColor Cyan
            winget install -e --id $Id --accept-package-agreements --silent
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

#--------------------------------------START-------------------------------------------

Invoke-Action -Name "Disabilitazione di OOBE" -Description "Verrà disabilitato il questionario iniziale di Windows" -ScriptBlock {
    $RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE"
    if (-not (Test-ProgramPath $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }
    Set-ItemProperty -Path $RegistryPath -Name "DisablePrivacyExperience" -Value 1 -Type DWORD -Force
}

Invoke-Action -Name "Eliminazione automatica vecchi account" -Description "Verrà programmata l'eliminazione degli account in disuso da almeno 90 giorni" -ScriptBlock {
	Set-Location $Global:LocalScriptRoot
	$psPath = (Join-Path (Get-Location).Path "\manutenzioneAccount.ps1")
	$destinazione = "C:\Program Files\ManutenzioneAccount"
	if (!(Test-ProgramPath $destinazione)) {
		New-Item -Path $destinazione -ItemType Directory
	}
	Copy-Item -Path $psPath -Destination $destinazione -Force
	
	# 1. Definisci il percorso completo dove hai salvato lo script
	$ScriptPath = Join-Path $destinazione "manutenzioneAccount.ps1"

	# Usiamo le virgolette interne per proteggere il percorso con spazi
	$Command = "PowerShell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \`"$ScriptPath\`""

	# Esecuzione del comando schtasks
	schtasks.exe /Create /TN "PuliziaAccountInattivi" /TR $Command /SC MONTHLY /D 1 /ST 03:00 /RU "SYSTEM" /RL HIGHEST /F	
}

Invoke-Action -Name "Impostazione dell'immagine UniPV" -Description "Verrà impostata l'immagine coordinata dell'Università di Pavia" -ScriptBlock {
	# Cartella script
	Set-Location $Global:LocalScriptRoot

	# Percorsi sorgente
	$bg_path = Join-Path (Get-Location).Path "grafica_unipv\unipv_bg.jpg"
	$logo_bmp = Join-Path (Get-Location).Path "grafica_unipv\unipv_logo.bmp"
	$logo_png = Join-Path (Get-Location).Path "grafica_unipv\unipv_logo.png"

	# Destinazioni standard Windows
	$wallpaperPath = "C:\Windows\Web\Wallpaper\unipv_bg.jpg"
	$lockScreenPath = "C:\Windows\Web\Screen\unipv_lock.jpg"

	# --------------------------------------------------
	# 1. Copia file (wallpaper + lockscreen)
	# --------------------------------------------------
	Copy-Item $bg_path -Destination $wallpaperPath -Force
	Copy-Item $bg_path -Destination $lockScreenPath -Force

	# --------------------------------------------------
	# 2. Immagini account (opzionale, ma ok tenerlo)
	# --------------------------------------------------
	$accountPath = "$env:PROGRAMDATA\Microsoft\User Account Pictures"

	Copy-Item $logo_bmp -Destination "$accountPath\user.bmp" -Force
	Copy-Item $logo_bmp -Destination "$accountPath\guest.bmp" -Force
	Copy-Item $logo_png -Destination "$accountPath\user.png" -Force
	Copy-Item $logo_png -Destination "$accountPath\guest.png" -Force

	# --------------------------------------------------
	# 3. Wallpaper globale (TUTTI gli utenti)
	# --------------------------------------------------
	New-Item -Path "HKLM:\Software\Policies\Microsoft\Windows\System" -Force | Out-Null

	Set-ItemProperty `
	  -Path "HKLM:\Software\Policies\Microsoft\Windows\System" `
	  -Name "Wallpaper" `
	  -Value $wallpaperPath

	Set-ItemProperty `
	  -Path "HKLM:\Software\Policies\Microsoft\Windows\System" `
	  -Name "WallpaperStyle" `
	  -Value "2"   # 2 = Stretch (puoi cambiare)

	# --------------------------------------------------
	# 4. Lock screen globale (Win+L)
	# --------------------------------------------------
	New-Item -Path "HKLM:\Software\Policies\Microsoft\Windows\Personalization" -Force | Out-Null

	Set-ItemProperty `
	  -Path "HKLM:\Software\Policies\Microsoft\Windows\Personalization" `
	  -Name "LockScreenImage" `
	  -Value $lockScreenPath

	Set-ItemProperty `
	  -Path "HKLM:\Software\Policies\Microsoft\Windows\Personalization" `
	  -Name "NoChangingLockScreen" `
	  -Value 1

	Set-ItemProperty `
	  -Path "HKLM:\Software\Policies\Microsoft\Windows\Personalization" `
	  -Name "NoChangingDesktopBackground" `
	  -Value 1

	Set-ItemProperty `
	  -Path "HKLM:\Software\Policies\Microsoft\Windows\Personalization" `
	  -Name "LockScreenOverlaysDisabled" `
	  -Value 1

	# --------------------------------------------------
	# 5. Blocca modifica wallpaper
	# --------------------------------------------------
	New-Item -Path "HKLM:\Software\Policies\Microsoft\Windows\ActiveDesktop" -Force | Out-Null

	Set-ItemProperty `
	  -Path "HKLM:\Software\Policies\Microsoft\Windows\ActiveDesktop" `
	  -Name "NoChangingWallpaper" `
	  -Value 1

	# --------------------------------------------------
	# 6. Applica subito le modifiche
	# --------------------------------------------------
	RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters
	gpupdate /force
}

Invoke-Action -Name "Aggiunta di un utente Ospite" -Description "Verrà aggiunto un utente Ospite con password scelta" -ScriptBlock {
	$username = "Ospite"

	if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
		Write-Host "L'utente '$username' esiste già." -ForegroundColor Yellow
	} else {
		$userCreated = $false
		
		# Continua a chiedere finché l'utente non viene creato con successo
		while (-not $userCreated) {
			try {
				$Password = Read-Host -AsSecureString "Inserisci la password per il nuovo utente (deve rispettare i criteri di sicurezza)"
				
				# Tentativo di creazione
				New-LocalUser -Name $username `
							  -Password $Password `
							  -UserMayNotChangePassword `
							  -AccountNeverExpires `
							  -PasswordNeverExpires `
							  -Description "Account utente Ospite" `
							  -ErrorAction Stop
				
				# Se arriviamo qui, l'utente è stato creato
				Add-LocalGroupMember -Group "Guests" -Member $username
				Write-Host "Account '$username' creato con successo e attivato." -ForegroundColor Green
				
				$userCreated = $true # Esce dal ciclo
			} catch {
				Write-Host "`nERRORE: La password non soddisfa i requisiti di sistema o si è verificato un errore." -ForegroundColor Red
				Write-Host "Dettaglio: $($_.Exception.Message)" -ForegroundColor Red
				Write-Host "Riprova...`n" -ForegroundColor Yellow
			}
		}
	}
}

Invoke-Action -Name "Installazione di software Essenziali" -Description "Verranno installai software essenziali come`r`nWinget AutoUpdate, Google Drive, Google Chrome, 7Zip e Zoom" -Rows 3 -ScriptBlock {
	Install-Sw "Winget AutoUpdate" "Romanitho.Winget-AutoUpdate" $false
    # Configurazione Esclusioni per WAU
    $wauPath = "$env:ProgramData\WAU"
    $exclusionFileSource = Join-Path $Global:LocalScriptRoot "excluded_apps.txt"
    $exclusionFileDest = Join-Path $wauPath "excluded_apps.txt"

    if (Test-ProgramPath $exclusionFileSource) {
        Write-Host "Configurazione file di esclusione per Winget-AutoUpdate..." -ForegroundColor Cyan
        # Crea la cartella WAU se non esiste (solitamente creata dall'installer, ma per sicurezza...)
        if (-not (Test-ProgramPath $wauPath)) {
            New-Item -Path $wauPath -ItemType Directory -Force | Out-Null
        }
        # Copia il file delle esclusioni
        Copy-Item -Path $exclusionFileSource -Destination $exclusionFileDest -Force
        Write-Host "File excluded_apps.txt configurato correttamente." -ForegroundColor Green
    } else {
        Write-Warning "File excluded_apps.txt non trovato nella cartella dello script. Salto la configurazione esclusioni."
    }
	Install-Sw "WAU Settings GUI" "KnifMelti.WAU-Settings-GUI" $false
	Install-Sw "Google Drive" "Google.GoogleDrive" $false
	Install-Sw "Google Chrome" "Google.Chrome" $false
	Install-Sw "7zip" "7zip.7zip" $false
	Install-Sw "Zoom Workplace" "Zoom.Zoom" $false
    Install-Sw "PDFsam Basic" "PDFsam.PDFsam" $false
}

Install-Sw "Microsoft 365 Copilot" "9WZDNCRD29V9"
Install-Sw "Microsoft Teams" "XP8BT8DW290MPQ"
Install-Sw "Adobe Acrobat Reader" "Adobe.Acrobat.Reader.64-bit"
Install-Sw "Firma Digitale InfoCamere" "Bit4id.Firma4ng.InfoCamere"
Install-Sw "WhatsApp" "9NKSQGP7F2NH"
Install-Sw "Eset Security (Antivirus)" "ESET.Nod32"

Invoke-Action -Name "Installazione di software di utilità" -Description "Verranno installati con singola conferma i software di utilità come`r`nNotepad++, " -Rows 3 -ScriptBlock {
    Install-Sw "Notepad++" "Notepad++.Notepad++"
    Install-Sw "Mendeley Reference Manager" "Elsevier.MendeleyReferenceManager"
    Install-Sw "Advanced Renamer", "HulubuluSoftware.AdvancedRenamer"
    # Download-Install-Sw "AutoHotkey", "https://www.autohotkey.com/download/ahk-v2.exe", "C:\Program Files\AutoHotkey\UX\AutoHotkeyUX.exe"
}

Invoke-Action -Name "Installazione di software Statistici" -Description "Verranno installati con singola conferma i software statistici come`r`nStata 19, Jasp, GPower, R con R-Studio, Orange, Python o Jupyter Notebook" -Rows 3 -ScriptBlock {
	Install-Sw "JASP" "UniversityOfAmsterdam.JASP"
	Install-Sw "R Project" "RProject.R"
	Install-Sw "GPower" "GPower.GPower"
	Install-Sw "RStudio" "Posit.RStudio"
	Install-Sw "Orange" "UniversityOfLjubljana.Orange"
	Install-Sw "Python" "Python.Launcher"
	Install-Sw "Jupyter Notebook" "ProjectJupyter.JupyterLab"
}

Invoke-Action -Name "Installazione di software Audio/Video" -Description "Verranno installati con singola conferma i software Audio/Video come`r`nAudacity, DaVinci Resolve, Gimp, K-Lite Codec Pack" -Rows 3 -ScriptBlock {
	Install-Sw "Audacity" "Audacity.Audacity"
    Download-Install-Sw "DaVinci Resolve", "https://swr.cloud.blackmagicdesign.com/DaVinciResolve/v20.3.2/DaVinci_Resolve_Studio_20.3.2_Windows.zip?verify=1776845685-WkzawoQH%2BTwhVO2ezjJekuc7OfwHTj1tEGxsSefc5L0%3D", "C:\Program Files\Blackmagic Design\DaVinci Resolve\Resolve.exe"	Install-Sw "R Project" "RProject.R"
	Install-Sw "VLC Video Player" "VLC.VLC" $false
	Install-Sw "Gimp" "GIMP.GIMP.3"
	Install-Sw "K-Lite Codec Pack Standard" "CodecGuide.K-LiteCodecPack.Standard"
    Install-Sw "Avidemux (Montaggio Video)" "Avidemux.Avidemux"
    Install-Sw "OBS Studio (Registrazione dello schermo)" "OBSProject.OBSStudio"
}

Invoke-Action -Name "Installazione di software 3D" -Description "Verranno installati con singola conferma i software grafici 3D come`r`nFusion 360, Prusa Slicer, OpenSCAD, Shapr3D" -Rows 3 -ScriptBlock {
    Download-Install-Sw "Fusion 360", "https://dl.appstreaming.autodesk.com/production/installers/Fusion%20Client%20Downloader.exe", "$env:LOCALAPPDATA\Autodesk\webdeploy\production\"
    Install-Sw "PrusaSlicer" "Prusa3D.PrusaSlicer"
    Install-Sw "OpenSCAD", "OpenSCAD.OpenSCAD"
    Install-Sw "Shapr3D", "Shapr3D.Shapr3D"
}

Invoke-Action -Name "Installazione di software di programmazione" -Description "Verranno installati con singola conferma i software di programmazione come`r`nVisual Studio Code, Docker, " -Rows 3 -ScriptBlock {
    Install-Sw "Microsoft Visual Studio Code", "Microsoft.VisualStudioCode"
    Install-Sw "Docker Desktop", "Docker.DockerDesktop"
    Install-Sw "", ""
}
#--------------------------------------START-------------------------------------------

$action = "Installazione di Microsoft Office"
$description = "Verrà installata la versione scelta di Microsoft Office"
$title = Show-CenteredBox -action $action
$message = "Vuoi procedere alla ${action}?`n`r$description"
$choicesOffice = [System.Management.Automation.Host.ChoiceDescription[]]@(
    New-Object System.Management.Automation.Host.ChoiceDescription "Sì, Office &365", "Office 365."
    New-Object System.Management.Automation.Host.ChoiceDescription "Sì, Office &2016", "Office Professional Plus 2016 64bit."
    New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Salta questa operazione."
    New-Object System.Management.Automation.Host.ChoiceDescription "&Esci", "Interrompe l'intero script."
)

$decision = $host.UI.PromptForChoice($title, $message, $choicesOffice, 2)

switch ($decision) {
	0 {
		Write-Host "Procedo con la $action..." -ForegroundColor Cyan
		#---INIZIO COMANDI---
		
		Write-Host "Installazione interattiva di Office 365, seguire la procedura guidata che si aprirà..." -ForegroundColor Cyan
		winget install -e --id Microsoft.Office --source winget --accept-package-agreements
		
		#---FINE COMANDI---
		Write-Host "$action completata." -ForegroundColor Green
	}
	1 {
		Write-Host "Procedo con la $action..." -ForegroundColor Cyan
		#---INIZIO COMANDI---
		
		# Controllo se Office 2016 (esempio: Word) è già installato
		$OfficeInstalled = Test-ProgramPath "C:\Program Files\Microsoft Office\Office16\WINWORD.EXE" -or Test-ProgramPath "C:\Program Files (x86)\Microsoft Office\Office16\WINWORD.EXE"
		if ($OfficeInstalled) {
			Write-Host "Office 2016 sembra essere già installato. Salto l'installazione." -ForegroundColor Yellow
		} else {
			$OfficePath = "$Global:LocalScriptRoot\Office Professional Plus 2016 64bit Ita\setup.exe"
			if (Test-ProgramPath $OfficePath) {
				Write-Host "Installazione interattiva di Office 2016, seguire la procedura guidata che si aprirà..." -ForegroundColor Cyan
				Start-Process $OfficePath -Wait
				Write-Host "Installazione di Office 2016 completata. Ricordati di inserire la chiave di licenza." -ForegroundColor Green
			} else {
				Write-Warning "File di installazione di Office 2016 non trovato al percorso $OfficePath. Salto l'installazione."
			}
		}
		
		#---FINE COMANDI---
		Write-Host "$action completata." -ForegroundColor Green
	}
	2 {
		Write-Host "$action saltata." -ForegroundColor Yellow
	}
	3 {
		Write-Host "Uscita in corso..." -ForegroundColor Red
		exit 
	}
}

#--------------------------------------END-------------------------------------------

$action = "Installazione di pGina"
$description = "Verrà installata la versione scelta di pGina, software per l'accesso a Windows tramite LDAP, MySQL, ecc."
$title = Show-CenteredBox -action $action
$message = "Vuoi procedere alla ${action}?`n`r$description"

$choicesPGina = [System.Management.Automation.Host.ChoiceDescription[]]@(
	New-Object System.Management.Automation.Host.ChoiceDescription "Sì, pGina &originale 3.1.8.0", "pGina originale."
	New-Object System.Management.Automation.Host.ChoiceDescription "Sì, pGina &fork 3.9.9.12", "pGina Fork."
	New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Salta questa operazione."
	New-Object System.Management.Automation.Host.ChoiceDescription "&Esci", "Interrompe l'intero script."
)

$decision = $host.UI.PromptForChoice($title, $message, $choicesPGina, 2)

switch ($decision) {
	0 {
		$name = "pGina 3.1.8.0"
		$installed = Test-ProgramPath "C:\Program Files\pGina.fork\pGina.Configuration.exe"
		if ($installed) {
			Write-Host "$name sembra essere già installato. Salto l'installazione." -ForegroundColor Yellow
		} else {
			$path = "$Global:LocalScriptRoot\pgina\pGinaSetup.exe"
			$dir = Split-Path $path
			if (!(Test-ProgramPath $dir)) { New-Item -ItemType Directory -Path $dir -Force }
			Invoke-WebRequest -Uri "https://github.com/pgina/pgina/releases/download/v3.1.8.0/pGinaSetup-3.1.8.0.exe" -OutFile $path
			if (Test-ProgramPath $path) {
				Write-Host "Procedo con l'installazione di $name. Ricordati di chiuderlo per continuare lo script..." -ForegroundColor Cyan
				Start-Process $path -Wait
				Set-Location $Global:LocalScriptRoot
				$user_img_path = (Join-Path (Get-Location).Path "\grafica_unipv\unipv_logo_RGB.bmp")
				Copy-Item $user_img_path -Destination "C:\unipv_logo_RGB.bmp" -Force
				Write-Host "Installazione di $name completata." -ForegroundColor Green
			} else {
				Write-Warning "File di installazione non trovato al percorso $path. Salto l'installazione."
			}
		}
	}
	1 {
		$name = "pGina fork 3.9.9.12"
		$installed = Test-ProgramPath "C:\Program Files\pGina\pGina.Configuration.exe"
		if ($installed) {
			Write-Host "$name sembra essere già installato. Salto l'installazione." -ForegroundColor Yellow
		} else {
			$path = "$Global:LocalScriptRoot\pgina.fork\pGinaSetup.exe"
			$dir = Split-Path $path
			if (!(Test-ProgramPath $dir)) { New-Item -ItemType Directory -Path $dir -Force }
			Invoke-WebRequest -Uri "https://github.com/MutonUfoAI/pgina/releases/download/3.9.9.12/pGinaSetup-3.9.9.12.exe" -OutFile $path
			if (Test-ProgramPath $path) {
				Write-Host "Procedo con l'installazione di $name. Ricordati di chiuderlo per continuare lo script..." -ForegroundColor Cyan
				Start-Process $path -Wait
				Set-Location $Global:LocalScriptRoot
				$user_img_path = (Join-Path (Get-Location).Path "\grafica_unipv\unipv_logo_RGB.bmp")
				Copy-Item $user_img_path -Destination "C:\unipv_logo_RGB.bmp" -Force
				Write-Host "Installazione di $name completata." -ForegroundColor Green
			} else {
				Write-Warning "File di installazione non trovato al percorso $path. Salto l'installazione."
			}
		}
	}
	2 {
		Write-Host "$action saltata." -ForegroundColor Yellow
	}
	3 {
		Write-Host "Uscita in corso..." -ForegroundColor Red
		exit 
	}
}

Invoke-Action -Name "Installazione di Supremo Control" -Description "Verrà installato il software di accesso remoto Supremo Control" -ScriptBlock {
	$installed = Test-ProgramPath "C:\Program Files (x86)\Supremo\Supremo.exe"
	if ($installed) {
		Write-Host "Supremo sembra essere già installato. Salto l'installazione." -ForegroundColor Yellow
	} else {
		$path = "$Global:LocalScriptRoot\supremo\supremo.exe"
		$dir = Split-Path $path
		if (!(Test-ProgramPath $dir)) { New-Item -ItemType Directory -Path $dir -Force }
		Invoke-WebRequest -Uri "https://www.nanosystems.it/public/download/Supremo.exe" -OutFile $path
		if (Test-ProgramPath $path) {
			Write-Host "Procedo con l'installazione di Supremo. Ricordati di chiuderlo per continuare lo script..." -ForegroundColor Cyan
			Start-Process $path -Wait
			Write-Host "Installazione di Supremo completata." -ForegroundColor Green
		} else {
			Write-Warning "File di installazione non trovato al percorso $path. Salto l'installazione."
		}
	}
}

Invoke-Action -Name "Installazione di Stampante Canon iR C3226" -Description "Verrà installata la Stampante Canon iR C3226 di Scienze Motorie" -ScriptBlock {
	$PortName = "Canon iR C3226 Scienze motorie"
	$DriverPath = "$Global:LocalScriptRoot\Canon_IR_C3226_PCL6_Driver_V330_32_64_00\x64\Driver\CNP60MA64.INF"
	$DriverModel = "Canon Generic Plus PCL6"
	$IPAddress = "193.206.72.226"
	$PrinterName = "Canon IR C3226"

	Write-Host "Procedo con l'installazione della stampante..." -ForegroundColor Green

	# 1. Tenta di aggiungere la porta (con gestione dell'errore 'già esistente')
	try {
		Add-PrinterPort -Name $PortName -PrinterHostAddress $IPAddress -ErrorAction Stop
		Write-Host "Porta creata." -ForegroundColor Green
	}
	catch {
		# Cattura l'errore 0x800700b7 (La porta specificata esiste già)
		if ($_.Exception.HResult -eq -2147024713) {
			Write-Host "La porta $PortName esiste già. Procedo con la configurazione."
		} else {
			Write-Warning "Errore imprevisto durante l'aggiunta della porta: $($_.Exception.Message)"
		}
	}

	# 2. Disabilito lo stato SNMP sulla porta (essenziale e va eseguito anche se la porta esisteva)
	# Eseguo un controllo per assicurarmi che la porta sia configurabile prima di modificarla
	if (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue) {
		Set-PrinterPort -Name $PortName -SNMP $false
		Write-Host "SNMP disabilitato sulla porta."
	} else {
		Write-Warning "Impossibile configurare SNMP: la porta $PortName non è stata trovata."
	}
	
	# 3. Aggiungo la stampante utilizzando il driver (se il driver è disponibile)
	if (Test-ProgramPath $DriverPath) {
		rundll32 printui.dll,PrintUIEntry /if /b $PrinterName /f $DriverPath /r $PortName /m $DriverModel
		Write-Host "Stampante installata." -ForegroundColor Green
	} else {
		Write-Warning "File driver non trovato al percorso $DriverPath. La stampante non è stata installata."
	}
}

Invoke-Action -Name "Installazione di Stampante HP LaserJet MFP E72425" -Description "Verrà installata la Stampante HP LaserJet MFP E72425 di Biostatistica" -ScriptBlock {
	$PortName = "HP LaserJet MFP E72425 [44B668] Biostatistica"
	$DriverPath = "$Global:LocalScriptRoot\LJE72425-E72430\hponef2a4_x64.inf"
	$DriverModel = "HP LaserJet MFP E72425 E72430 PCL-6 (V4)"
	$IPAddress = "193.206.68.205"
	$PrinterName = "HP LaserJet MFP E72425"

	Write-Host "Procedo con l'installazione della stampante..." -ForegroundColor Green

	# 1. Tenta di aggiungere la porta (con gestione dell'errore 'già esistente')
	try {
		Add-PrinterPort -Name $PortName -PrinterHostAddress $IPAddress -ErrorAction Stop
		Write-Host "Porta creata." -ForegroundColor Green
	}
	catch {
		# Cattura l'errore 0x800700b7 (La porta specificata esiste già)
		if ($_.Exception.HResult -eq -2147024713) {
			Write-Host "La porta $PortName esiste già. Procedo." -ForegroundColor Green
		} else {
			Write-Warning "Errore imprevisto durante l'aggiunta della porta: $($_.Exception.Message)"
		}
	}
	
	# 2. Aggiungo la stampante utilizzando il driver (se il driver è disponibile)
	if (Test-ProgramPath $DriverPath) {
		rundll32 printui.dll,PrintUIEntry /if /b $PrinterName /f $DriverPath /r $PortName /m $DriverModel
		Write-Host "Stampante installata."
	} else {
		Write-Warning "File driver non trovato al percorso $DriverPath. La stampante non è stata installata."
	}
}
Write-Host (Show-CenteredBox -action "INSTALLAZIONE COMPLETATA" -rows 3)
pause
