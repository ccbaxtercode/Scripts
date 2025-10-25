#Requires -Version 5.1
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Active Directory kullanıcı hesaplarının account expiration sürelerini kontrol eder (Parallel Processing).
.DESCRIPTION
    İki farklı domain'den kullanıcıları okur ve account süresi 15 gün içinde dolacak kullanıcıları HTML raporu olarak export eder.
    Parallel processing ile büyük kullanıcı tabanları için optimize edilmiştir.
.NOTES
    Author: AD Admin
    Date: 2025-01-27
    Version: 2.0 (Parallel Processing)
#>

# ============================================================
# PARAMETRE TANIMLARI
# ============================================================

param(
    [string]$DomainA = "domainA.local",
    [string]$DomainB = "domainB.local",
    [string]$OUPathDomainA = "OU=Users,DC=domainA,DC=local",
    [string]$OUPathDomainB = "OU=Users,DC=domainB,DC=local",
    [string]$EncryptedPasswordFile = "C:\Scripts\DomainB_Credential.txt",
    [string]$UsernameForDomainB = "DOMAINB\admin",
    [int]$DaysThreshold = 15,
    [string]$OutputPath = "C:\Reports\AccountExpiration_$(Get-Date -Format 'yyyyMMdd_HHmmss').html",
    [string]$LogPath = "C:\Logs\AccountExpiration_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",
    [int]$MaxConcurrentJobs = 5,
    [int]$BatchSize = 100,
    [int]$MaxRetries = 3
)

# ============================================================
# LOG FONKSIYONU
# ============================================================

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'INFO'    { Write-Host $logMessage -ForegroundColor Green }
    }
    
    try {
        $logDir = Split-Path -Path $LogPath -Parent
        if (-not (Test-Path -Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        Add-Content -Path $LogPath -Value $logMessage -Encoding UTF8
    }
    catch {
        Write-Warning "Log dosyasına yazılamadı: $_"
    }
}

# ============================================================
# PARALLEL PROCESSING FONKSIYONLARI
# ============================================================

function Start-ParallelADAccountQuery {
    <#
    .SYNOPSIS
        Parallel olarak AD account expiration bilgilerini sorgular.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$DomainName,
        
        [Parameter(Mandatory=$true)]
        [string]$OUPath,
        
        [Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]$Credential,
        
        [Parameter(Mandatory=$false)]
        [int]$DaysThreshold = 15,
        
        [Parameter(Mandatory=$false)]
        [int]$BatchSize = 100
    )
    
    Write-Log "Domain: $DomainName - Account expiration parallel processing başlatılıyor..."
    
    $results = @()
    $jobs = @()
    
    try {
        # İlk olarak toplam kullanıcı sayısını al
        $adParams = @{
            SearchBase = $OUPath
            Filter = {Enabled -eq $true -and AccountExpirationDate -ne $null}
            Properties = @('SamAccountName')
            Server = $DomainName
        }
        
        if ($Credential) {
            $adParams.Add('Credential', $Credential)
        }
        
        $totalUsers = (Get-ADUser @adParams).Count
        Write-Log "Domain: $DomainName - Toplam $totalUsers account expiration tarihi olan kullanıcı bulundu."
        
        if ($totalUsers -eq 0) {
            return $results
        }
        
        # Batch'ler halinde kullanıcıları işle
        $batches = [Math]::Ceiling($totalUsers / $BatchSize)
        Write-Log "Domain: $DomainName - $batches batch oluşturuluyor..."
        
        for ($i = 0; $i -lt $batches; $i++) {
            $skip = $i * $BatchSize
            $take = [Math]::Min($BatchSize, $totalUsers - $skip)
            
            # Parallel job başlat
            $job = Start-Job -ScriptBlock {
                param($DomainName, $OUPath, $Credential, $DaysThreshold, $Skip, $Take, $LogPath)
                
                # Job içinde log fonksiyonu
                function Write-JobLog {
                    param([string]$Message, [string]$Level = 'INFO')
                    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    $logMessage = "[$timestamp] [$Level] [JOB] $Message"
                    Add-Content -Path $LogPath -Value $logMessage -Encoding UTF8
                }
                
                try {
                    # AD modülünü import et
                    Import-Module ActiveDirectory -Force
                    
                    $batchResults = @()
                    
                    # AD parametreleri
                    $adParams = @{
                        SearchBase = $OUPath
                        Filter = {Enabled -eq $true -and AccountExpirationDate -ne $null}
                        Properties = @('DisplayName', 'SamAccountName', 'mail', 'AccountExpirationDate', 'PasswordLastSet', 'LastLogonDate')
                        Server = $DomainName
                        First = $Take
                        Skip = $Skip
                    }
                    
                    if ($Credential) {
                        $adParams.Add('Credential', $Credential)
                    }
                    
                    Write-JobLog "Account expiration batch işleniyor: Skip=$Skip, Take=$Take"
                    
                    # Kullanıcıları oku
                    $users = Get-ADUser @adParams
                    Write-JobLog "Batch'te $($users.Count) kullanıcı bulundu"
                    
                    foreach ($user in $users) {
                        try {
                            $expiryDate = $null
                            $daysRemaining = $null
                            
                            if ($user.AccountExpirationDate -ne $null) {
                                $expiryDate = $user.AccountExpirationDate
                                $expiryDateOnly = $expiryDate.Date
                                $todayDateOnly = (Get-Date).Date
                                $daysRemaining = ($expiryDateOnly - $todayDateOnly).Days
                                
                                if ($daysRemaining -gt 0 -and $daysRemaining -le $DaysThreshold) {
                                    $batchResults += [PSCustomObject]@{
                                        Domain = $DomainName
                                        DisplayName = $user.DisplayName
                                        SamAccountName = $user.SamAccountName
                                        AccountExpirationDate = $expiryDate.ToString("dd.MM.yyyy")
                                        DaysRemaining = $daysRemaining
                                        Mail = $user.mail
                                        PasswordLastSet = if ($user.PasswordLastSet) { $user.PasswordLastSet.ToString("dd.MM.yyyy") } else { "Never" }
                                        LastLogonDate = if ($user.LastLogonDate) { $user.LastLogonDate.ToString("dd.MM.yyyy") } else { "Never" }
                                    }
                                }
                            }
                        }
                        catch {
                            Write-JobLog "Kullanıcı işlenirken hata: $($user.SamAccountName) - $_" -Level ERROR
                        }
                    }
                    
                    Write-JobLog "Account expiration batch tamamlandı: $($batchResults.Count) kullanıcı threshold altında"
                    return $batchResults
                }
                catch {
                    Write-JobLog "Account expiration batch işleme hatası: $_" -Level ERROR
                    return @()
                }
            } -ArgumentList $DomainName, $OUPath, $Credential, $DaysThreshold, $skip, $take, $LogPath
            
            $jobs += $job
            
            # Maksimum concurrent job sayısını kontrol et
            if ($jobs.Count -ge $MaxConcurrentJobs) {
                Write-Log "Maksimum concurrent job sayısına ulaşıldı ($MaxConcurrentJobs). Bekleniyor..."
                
                # Job'ları bekle ve sonuçları al
                $completedJobs = $jobs | Where-Object { $_.State -eq 'Completed' }
                foreach ($completedJob in $completedJobs) {
                    $jobResults = Receive-Job -Job $completedJob
                    $results += $jobResults
                    Remove-Job -Job $completedJob
                }
                
                # Tamamlanan job'ları listeden çıkar
                $jobs = $jobs | Where-Object { $_.State -ne 'Completed' }
            }
        }
        
        # Kalan job'ları bekle
        Write-Log "Domain: $DomainName - Kalan job'lar bekleniyor..."
        $jobs | Wait-Job | Out-Null
        
        # Tüm sonuçları al
        foreach ($job in $jobs) {
            $jobResults = Receive-Job -Job $job
            $results += $jobResults
            Remove-Job -Job $job
        }
        
        Write-Log "Domain: $DomainName - Account expiration parallel processing tamamlandı. $($results.Count) kullanıcı bulundu."
    }
    catch {
        Write-Log "Domain: $DomainName - Account expiration parallel processing hatası: $_" -Level ERROR
    }
    
    return $results
}

function Start-ParallelDomainAccountProcessing {
    <#
    .SYNOPSIS
        İki domain'i parallel olarak account expiration için işler.
    #>
    param(
        [string]$DomainA,
        [string]$DomainB,
        [string]$OUPathDomainA,
        [string]$OUPathDomainB,
        [string]$EncryptedPasswordFile,
        [string]$UsernameForDomainB,
        [int]$DaysThreshold,
        [int]$BatchSize
    )
    
    $allUsers = @()
    $domainJobs = @()
    
    # Domain A job'ı başlat
    Write-Log "Domain A account expiration parallel job başlatılıyor..."
    $jobA = Start-Job -ScriptBlock {
        param($DomainName, $OUPath, $DaysThreshold, $BatchSize, $LogPath)
        
        function Write-JobLog {
            param([string]$Message, [string]$Level = 'INFO')
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $logMessage = "[$timestamp] [$Level] [DOMAIN-A] $Message"
            Add-Content -Path $LogPath -Value $logMessage -Encoding UTF8
        }
        
        try {
            Import-Module ActiveDirectory -Force
            Write-JobLog "Domain A account expiration processing başlatılıyor..."
            
            # Domain A için batch processing
            $results = @()
            $adParams = @{
                SearchBase = $OUPath
                Filter = {Enabled -eq $true -and AccountExpirationDate -ne $null}
                Properties = @('DisplayName', 'SamAccountName', 'mail', 'AccountExpirationDate', 'PasswordLastSet', 'LastLogonDate')
                Server = $DomainName
            }
            
            $users = Get-ADUser @adParams
            Write-JobLog "Domain A'da $($users.Count) account expiration tarihi olan kullanıcı bulundu"
            
            # Batch'ler halinde işle
            $batches = [Math]::Ceiling($users.Count / $BatchSize)
            for ($i = 0; $i -lt $batches; $i++) {
                $batchUsers = $users | Select-Object -Skip ($i * $BatchSize) -First $BatchSize
                
                foreach ($user in $batchUsers) {
                    try {
                        if ($user.AccountExpirationDate -ne $null) {
                            $expiryDate = $user.AccountExpirationDate
                            $expiryDateOnly = $expiryDate.Date
                            $todayDateOnly = (Get-Date).Date
                            $daysRemaining = ($expiryDateOnly - $todayDateOnly).Days
                            
                            if ($daysRemaining -gt 0 -and $daysRemaining -le $DaysThreshold) {
                                $results += [PSCustomObject]@{
                                    Domain = $DomainName
                                    DisplayName = $user.DisplayName
                                    SamAccountName = $user.SamAccountName
                                    AccountExpirationDate = $expiryDate.ToString("dd.MM.yyyy")
                                    DaysRemaining = $daysRemaining
                                    Mail = $user.mail
                                    PasswordLastSet = if ($user.PasswordLastSet) { $user.PasswordLastSet.ToString("dd.MM.yyyy") } else { "Never" }
                                    LastLogonDate = if ($user.LastLogonDate) { $user.LastLogonDate.ToString("dd.MM.yyyy") } else { "Never" }
                                }
                            }
                        }
                    }
                    catch {
                        Write-JobLog "Kullanıcı işlenirken hata: $($user.SamAccountName) - $_" -Level ERROR
                    }
                }
            }
            
            Write-JobLog "Domain A account expiration tamamlandı: $($results.Count) kullanıcı"
            return $results
        }
        catch {
            Write-JobLog "Domain A account expiration hatası: $_" -Level ERROR
            return @()
        }
    } -ArgumentList $DomainA, $OUPathDomainA, $DaysThreshold, $BatchSize, $LogPath
    
    $domainJobs += $jobA
    
    # Domain B job'ı başlat
    Write-Log "Domain B account expiration parallel job başlatılıyor..."
    $jobB = Start-Job -ScriptBlock {
        param($DomainName, $OUPath, $EncryptedPasswordFile, $UsernameForDomainB, $DaysThreshold, $BatchSize, $LogPath)
        
        function Write-JobLog {
            param([string]$Message, [string]$Level = 'INFO')
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $logMessage = "[$timestamp] [$Level] [DOMAIN-B] $Message"
            Add-Content -Path $LogPath -Value $logMessage -Encoding UTF8
        }
        
        try {
            Import-Module ActiveDirectory -Force
            Write-JobLog "Domain B account expiration processing başlatılıyor..."
            
            # Credential yükle - User Certificate ile decrypt
            $credentialB = $null
            try {
                if (Test-Path -Path $EncryptedPasswordFile) {
                    # User certificate ile encrypted password'ı oku ve decrypt et
                    $encryptedPasswordContent = Get-Content -Path $EncryptedPasswordFile -Raw
                    $encryptedPassword = $encryptedPasswordContent | ConvertTo-SecureString
                    $credentialB = New-Object System.Management.Automation.PSCredential($UsernameForDomainB, $encryptedPassword)
                    Write-JobLog "Domain B credential user certificate ile yüklendi"
                }
                else {
                    Write-JobLog "Encrypted password dosyası bulunamadı: $EncryptedPasswordFile" -Level ERROR
                    return @()
                }
            }
            catch {
                Write-JobLog "Credential yükleme hatası: $_" -Level ERROR
                Write-JobLog "User certificate ile decrypt edilemedi. Certificate'in doğru olduğundan emin olun." -Level ERROR
                return @()
            }
            
            $results = @()
            $adParams = @{
                SearchBase = $OUPath
                Filter = {Enabled -eq $true -and AccountExpirationDate -ne $null}
                Properties = @('DisplayName', 'SamAccountName', 'mail', 'AccountExpirationDate', 'PasswordLastSet', 'LastLogonDate')
                Server = $DomainName
                Credential = $credentialB
            }
            
            $users = Get-ADUser @adParams
            Write-JobLog "Domain B'de $($users.Count) account expiration tarihi olan kullanıcı bulundu"
            
            # Batch'ler halinde işle
            $batches = [Math]::Ceiling($users.Count / $BatchSize)
            for ($i = 0; $i -lt $batches; $i++) {
                $batchUsers = $users | Select-Object -Skip ($i * $BatchSize) -First $BatchSize
                
                foreach ($user in $batchUsers) {
                    try {
                        if ($user.AccountExpirationDate -ne $null) {
                            $expiryDate = $user.AccountExpirationDate
                            $expiryDateOnly = $expiryDate.Date
                            $todayDateOnly = (Get-Date).Date
                            $daysRemaining = ($expiryDateOnly - $todayDateOnly).Days
                            
                            if ($daysRemaining -gt 0 -and $daysRemaining -le $DaysThreshold) {
                                $results += [PSCustomObject]@{
                                    Domain = $DomainName
                                    DisplayName = $user.DisplayName
                                    SamAccountName = $user.SamAccountName
                                    AccountExpirationDate = $expiryDate.ToString("dd.MM.yyyy")
                                    DaysRemaining = $daysRemaining
                                    Mail = $user.mail
                                    PasswordLastSet = if ($user.PasswordLastSet) { $user.PasswordLastSet.ToString("dd.MM.yyyy") } else { "Never" }
                                    LastLogonDate = if ($user.LastLogonDate) { $user.LastLogonDate.ToString("dd.MM.yyyy") } else { "Never" }
                                }
                            }
                        }
                    }
                    catch {
                        Write-JobLog "Kullanıcı işlenirken hata: $($user.SamAccountName) - $_" -Level ERROR
                    }
                }
            }
            
            Write-JobLog "Domain B account expiration tamamlandı: $($results.Count) kullanıcı"
            return $results
        }
        catch {
            Write-JobLog "Domain B account expiration hatası: $_" -Level ERROR
            return @()
        }
    } -ArgumentList $DomainB, $OUPathDomainB, $EncryptedPasswordFile, $UsernameForDomainB, $DaysThreshold, $BatchSize, $LogPath
    
    $domainJobs += $jobB
    
    # Job'ları bekle
    Write-Log "Domain account expiration job'ları bekleniyor..."
    $domainJobs | Wait-Job | Out-Null
    
    # Sonuçları al
    foreach ($job in $domainJobs) {
        $jobResults = Receive-Job -Job $job
        $allUsers += $jobResults
        Remove-Job -Job $job
    }
    
    return $allUsers
}

# ============================================================
# HTML OLUŞTURMA FONKSİYONU
# ============================================================

function Export-ToHTML {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Data,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    Write-Log "HTML raporu oluşturuluyor..."
    
    $htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Account Expiration Raporu (Parallel Processing)</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
            font-size: 13px;
        }
        h1 {
            color: #333;
            text-align: center;
            margin-bottom: 10px;
        }
        .info {
            text-align: center;
            color: #666;
            margin-bottom: 20px;
        }
        .performance-info {
            background-color: #e8f4fd;
            border: 1px solid #0078d4;
            padding: 10px;
            margin: 10px 0;
            border-radius: 4px;
        }
        .warning {
            background-color: #fff3cd;
            border: 1px solid #ffeaa7;
            padding: 10px;
            margin: 10px 0;
            border-radius: 4px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            background-color: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            border: 2px solid #333;
        }
        th {
            background-color: #dc3545;
            color: white;
            padding: 8px;
            text-align: left;
            font-weight: bold;
            border: 2px solid #333;
        }
        td {
            padding: 6px 8px;
            border: 2px solid #333;
        }
        tr:hover {
            background-color: #ffff00;
        }
        .summary {
            margin: 20px 0;
            padding: 15px;
            background-color: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
    </style>
</head>
<body>
    <h1>Active Directory Account Expiration Raporu (Parallel Processing)</h1>
    <div class="info">
        Rapor Tarihi: $(Get-Date -Format "dd.MM.yyyy HH:mm:ss")<br>
        Toplam Kullanıcı Sayısı: $($Data.Count)
    </div>
    <div class="performance-info">
        <strong>Performance Bilgileri:</strong><br>
        • Parallel Processing: Aktif<br>
        • Batch Size: $BatchSize<br>
        • Max Concurrent Jobs: $MaxConcurrentJobs<br>
        • Processing Method: PowerShell Jobs
    </div>
    <div class="warning">
        <strong>⚠️ Uyarı:</strong> Bu rapor, hesabı $DaysThreshold gün veya daha az süre içinde sona erecek kullanıcıları göstermektedir.
    </div>
    <div class="summary">
        <strong>Özet:</strong> Bu rapor, hesabı $DaysThreshold gün veya daha az süre içinde sona erecek kullanıcıları göstermektedir.
    </div>
    <table>
        <thead>
            <tr>
                <th>Domain</th>
                <th>Display Name</th>
                <th>SAM Account Name</th>
                <th>Account Bitiş Tarihi</th>
                <th>Kalan Gün</th>
                <th>E-posta</th>
                <th>Son Parola Değişimi</th>
                <th>Son Giriş Tarihi</th>
            </tr>
        </thead>
        <tbody>
"@

    $htmlBody = ""
    
    foreach ($item in $Data | Sort-Object DaysRemaining) {
        $htmlBody += @"
            <tr>
                <td>$($item.Domain)</td>
                <td>$($item.DisplayName)</td>
                <td>$($item.SamAccountName)</td>
                <td>$($item.AccountExpirationDate)</td>
                <td>$($item.DaysRemaining)</td>
                <td>$($item.Mail)</td>
                <td>$($item.PasswordLastSet)</td>
                <td>$($item.LastLogonDate)</td>
            </tr>
"@
    }
    
    $htmlFooter = @"
        </tbody>
    </table>
</body>
</html>
"@

    $htmlContent = $htmlHeader + $htmlBody + $htmlFooter
    
    try {
        $outputDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        $htmlContent | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Log "HTML raporu oluşturuldu: $OutputPath"
        return $true
    }
    catch {
        Write-Log "HTML raporu oluşturulamadı: $_" -Level ERROR
        return $false
    }
}

# ============================================================
# ANA SCRIPT (PARALLEL PROCESSING)
# ============================================================

$startTime = Get-Date
Write-Log "========== Account Expiration Parallel Processing Script Başlatıldı =========="
Write-Log "Domain A: $DomainA"
Write-Log "Domain B: $DomainB"
Write-Log "Threshold: $DaysThreshold gün"
Write-Log "Batch Size: $BatchSize"
Write-Log "Max Concurrent Jobs: $MaxConcurrentJobs"

# Parallel domain processing
$allUsers = Start-ParallelDomainAccountProcessing -DomainA $DomainA -DomainB $DomainB -OUPathDomainA $OUPathDomainA -OUPathDomainB $OUPathDomainB -EncryptedPasswordFile $EncryptedPasswordFile -UsernameForDomainB $UsernameForDomainB -DaysThreshold $DaysThreshold -BatchSize $BatchSize

$endTime = Get-Date
$processingTime = $endTime - $startTime

Write-Log "Toplam işlem süresi: $($processingTime.TotalSeconds) saniye"
Write-Log "Toplam $($allUsers.Count) kullanıcı bulundu"

# Sonuçları HTML'e aktar
if ($allUsers.Count -gt 0) {
    Write-Log "HTML raporu oluşturuluyor..."
    $htmlResult = Export-ToHTML -Data $allUsers -OutputPath $OutputPath
    
    if ($htmlResult) {
        Write-Log "İşlem başarıyla tamamlandı. Rapor: $OutputPath"
        Write-Log "Log dosyası: $LogPath"
        Write-Log "Performance: $($processingTime.TotalSeconds) saniyede $($allUsers.Count) kullanıcı işlendi"
    }
    else {
        Write-Log "HTML raporu oluşturulamadı!" -Level ERROR
    }
}
else {
    Write-Log "Account expiration süresi dolmak üzere olan kullanıcı bulunamadı." -Level WARNING
}

Write-Log "========== Account Expiration Parallel Processing Script Tamamlandı =========="
