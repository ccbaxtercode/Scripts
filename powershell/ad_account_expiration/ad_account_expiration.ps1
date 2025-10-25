#Requires -Version 5.1
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Active Directory kullanıcı hesaplarının account expiration sürelerini kontrol eder.
.DESCRIPTION
    İki farklı domain'den kullanıcıları okur ve account süresi 15 gün içinde dolacak kullanıcıları HTML raporu olarak export eder.
.NOTES
    Author: AD Admin
    Date: 2025-01-27
#>

# ============================================================
# PARAMETRE TANIMLARI
# ============================================================

# Script parametreleri
param(
    [string]$DomainA = "domainA.local",
    [string]$DomainB = "domainB.local",
    [string]$OUPathDomainA = "OU=Users,DC=domainA,DC=local",
    [string]$OUPathDomainB = "OU=Users,DC=domainB,DC=local",
    [string]$EncryptedPasswordFile = "C:\Scripts\DomainB_Credential.txt",
    [string]$UsernameForDomainB = "DOMAINB\admin",
    [int]$DaysThreshold = 15,
    [string]$OutputPath = "C:\Reports\AccountExpiration_$(Get-Date -Format 'yyyyMMdd_HHmmss').html",
    [string]$LogPath = "C:\Logs\AccountExpiration_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

# ============================================================
# LOG FONKSIYONU
# ============================================================

function Write-Log {
    <#
    .SYNOPSIS
        Log dosyasına mesaj yazar.
    .PARAMETER Message
        Yazılacak log mesajı
    .PARAMETER Level
        Log seviyesi (INFO, WARNING, ERROR)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Konsola yaz
    switch ($Level) {
        'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'INFO'    { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Log dosyasına yaz
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
# KULLANICI BİLGİLERİ OKUMA FONKSİYONU
# ============================================================

function Get-ADUsersAccountExpiration {
    <#
    .SYNOPSIS
        Belirtilen domain ve OU'dan kullanıcıların account expiration bilgilerini okur.
    .PARAMETER DomainName
        Domain adı
    .PARAMETER OUPath
        Kullanıcıların okunacağı OU path
    .PARAMETER Credential
        Domain erişimi için credential (opsiyonel)
    .PARAMETER DaysThreshold
        Kaç gün ve altı için uyarı verileceği
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$DomainName,
        
        [Parameter(Mandatory=$true)]
        [string]$OUPath,
        
        [Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]$Credential,
        
        [Parameter(Mandatory=$false)]
        [int]$DaysThreshold = 15
    )
    
    Write-Log "Domain: $DomainName - Kullanıcı account expiration bilgileri okunuyor..."
    
    $results = @()
    
    try {
        # AD bağlantı parametreleri
        $adParams = @{
            SearchBase = $OUPath
            Filter = {Enabled -eq $true -and AccountExpirationDate -ne $null}
            Properties = @('DisplayName', 'SamAccountName', 'mail', 'AccountExpirationDate', 'PasswordLastSet', 'LastLogonDate')
            Server = $DomainName
        }
        
        # Credential varsa ekle
        if ($Credential) {
            $adParams.Add('Credential', $Credential)
        }
        
        # Kullanıcıları oku
        $users = Get-ADUser @adParams
        Write-Log "Domain: $DomainName - $($users.Count) account expiration tarihi olan kullanıcı bulundu."
        
        foreach ($user in $users) {
            try {
                # Account expiration date hesapla
                $expiryDate = $null
                $daysRemaining = $null
                
                if ($user.AccountExpirationDate -ne $null) {
                    $expiryDate = $user.AccountExpirationDate
                    
                    # Sadece tarih kısmını al, saati göz ardı et
                    $expiryDateOnly = $expiryDate.Date
                    $todayDateOnly = (Get-Date).Date
                    $daysRemaining = ($expiryDateOnly - $todayDateOnly).Days
                    
                    # Sadece 0'dan büyük ve threshold altındaki kullanıcıları al
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
                        
                        Write-Log "Kullanıcı eklendi: $($user.SamAccountName) - Kalan gün: $daysRemaining" -Level INFO
                    }
                }
            }
            catch {
                Write-Log "Kullanıcı işlenirken hata: $($user.SamAccountName) - $_" -Level ERROR
            }
        }
        
        Write-Log "Domain: $DomainName - $($results.Count) kullanıcı threshold altında."
    }
    catch {
        Write-Log "Domain: $DomainName - Kullanıcı okuma hatası: $_" -Level ERROR
    }
    
    return $results
}

# ============================================================
# HTML OLUŞTURMA FONKSİYONU
# ============================================================

function Export-ToHTML {
    <#
    .SYNOPSIS
        Kullanıcı listesini HTML tablosu olarak export eder.
    .PARAMETER Data
        Export edilecek kullanıcı verileri
    .PARAMETER OutputPath
        HTML dosyasının kaydedileceği path
    #>
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
    <title>Account Expiration Raporu</title>
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
        .warning {
            background-color: #fff3cd;
            border: 1px solid #ffeaa7;
            padding: 10px;
            margin: 10px 0;
            border-radius: 4px;
        }
    </style>
</head>
<body>
    <h1>Active Directory Account Expiration Raporu</h1>
    <div class="info">
        Rapor Tarihi: $(Get-Date -Format "dd.MM.yyyy HH:mm:ss")<br>
        Toplam Kullanıcı Sayısı: $($Data.Count)
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
# ANA SCRIPT
# ============================================================

Write-Log "========== Account Expiration Script Başlatıldı =========="
Write-Log "Domain A: $DomainA"
Write-Log "Domain B: $DomainB"
Write-Log "Threshold: $DaysThreshold gün"

$allUsers = @()

# Domain A'dan kullanıcıları oku (Current credential ile)
try {
    Write-Log "Domain A kullanıcıları okunuyor..."
    $usersA = Get-ADUsersAccountExpiration -DomainName $DomainA -OUPath $OUPathDomainA -DaysThreshold $DaysThreshold
    $allUsers += $usersA
    Write-Log "Domain A'dan $($usersA.Count) kullanıcı eklendi."
}
catch {
    Write-Log "Domain A okuma hatası: $_" -Level ERROR
}

# Domain B'den kullanıcıları oku (User Certificate ile encrypted credential)
try {
    Write-Log "Domain B credential'ı user certificate ile yükleniyor..."
    
    if (Test-Path -Path $EncryptedPasswordFile) {
        try {
            # User certificate ile encrypted password'ı oku ve decrypt et
            $encryptedPasswordContent = Get-Content -Path $EncryptedPasswordFile -Raw
            $encryptedPassword = $encryptedPasswordContent | ConvertTo-SecureString
            $credentialB = New-Object System.Management.Automation.PSCredential($UsernameForDomainB, $encryptedPassword)
            
            Write-Log "Domain B kullanıcıları okunuyor..."
            $usersB = Get-ADUsersAccountExpiration -DomainName $DomainB -OUPath $OUPathDomainB -Credential $credentialB -DaysThreshold $DaysThreshold
            $allUsers += $usersB
            Write-Log "Domain B'den $($usersB.Count) kullanıcı eklendi."
        }
        catch {
            Write-Log "User certificate ile credential decrypt edilemedi: $_" -Level ERROR
            Write-Log "Certificate'in doğru olduğundan ve encrypted password dosyasının geçerli olduğundan emin olun." -Level ERROR
        }
    }
    else {
        Write-Log "Encrypted password dosyası bulunamadı: $EncryptedPasswordFile" -Level ERROR
        Write-Log "User certificate ile encrypted password dosyası oluşturmak için:" -Level WARNING
        Write-Log "Read-Host -AsSecureString | ConvertFrom-SecureString | Out-File '$EncryptedPasswordFile'" -Level WARNING
    }
}
catch {
    Write-Log "Domain B okuma hatası: $_" -Level ERROR
}

# Sonuçları HTML'e aktar
if ($allUsers.Count -gt 0) {
    Write-Log "Toplam $($allUsers.Count) kullanıcı bulundu. HTML raporu oluşturuluyor..."
    $htmlResult = Export-ToHTML -Data $allUsers -OutputPath $OutputPath
    
    if ($htmlResult) {
        Write-Log "İşlem başarıyla tamamlandı. Rapor: $OutputPath"
        Write-Log "Log dosyası: $LogPath"
    }
    else {
        Write-Log "HTML raporu oluşturulamadı!" -Level ERROR
    }
}
else {
    Write-Log "Account expiration süresi dolmak üzere olan kullanıcı bulunamadı." -Level WARNING
}

Write-Log "========== Account Expiration Script Tamamlandı =========="
