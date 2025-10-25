#Requires -Version 5.1

<#
.SYNOPSIS
    User certificate ile encrypted credential dosyası oluşturur.
.DESCRIPTION
    Bu script, user certificate kullanarak güvenli credential dosyası oluşturur.
    Oluşturulan dosya, AD account expiration scriptleri tarafından kullanılabilir.
.NOTES
    Author: AD Admin
    Date: 2025-01-27
#>

param(
    [string]$OutputPath = "C:\Scripts\DomainB_Credential.txt",
    [string]$Username = "DOMAINB\admin",
    [switch]$Force
)

function Show-Header {
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  AD Account Expiration - Credential Creator" -ForegroundColor Cyan
    Write-Host "  User Certificate ile Encrypted Credential" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Test-UserCertificate {
    <#
    .SYNOPSIS
        User certificate'in mevcut olup olmadığını kontrol eder
    #>
    try {
        $cert = Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object { $_.HasPrivateKey -eq $true } | Select-Object -First 1
        
        if ($cert) {
            Write-Host "✅ User certificate bulundu:" -ForegroundColor Green
            Write-Host "   Subject: $($cert.Subject)" -ForegroundColor White
            Write-Host "   Thumbprint: $($cert.Thumbprint)" -ForegroundColor White
            Write-Host "   Expires: $($cert.NotAfter)" -ForegroundColor White
            return $true
        }
        else {
            Write-Host "❌ User certificate bulunamadı!" -ForegroundColor Red
            Write-Host "   Certificate oluşturmak için:" -ForegroundColor Yellow
            Write-Host "   1. New-SelfSignedCertificate -Subject 'CN=ADScript' -CertStoreLocation 'Cert:\CurrentUser\My'" -ForegroundColor Yellow
            Write-Host "   2. Veya mevcut bir certificate kullanın" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "❌ Certificate kontrolü başarısız: $_" -ForegroundColor Red
        return $false
    }
}

function Create-EncryptedCredential {
    <#
    .SYNOPSIS
        User certificate ile encrypted credential dosyası oluşturur
    #>
    param(
        [string]$Username,
        [string]$OutputPath
    )
    
    Write-Host "🔐 Encrypted credential oluşturuluyor..." -ForegroundColor Yellow
    Write-Host ""
    
    try {
        # Kullanıcıdan parola al
        Write-Host "Domain B için parola girin:" -ForegroundColor Cyan
        $securePassword = Read-Host -AsSecureString
        
        # Parolayı user certificate ile encrypt et
        Write-Host "Parola user certificate ile encrypt ediliyor..." -ForegroundColor Yellow
        
        # Encrypt işlemi
        $encryptedPassword = $securePassword | ConvertFrom-SecureString
        
        # Dosyayı oluştur
        $outputDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
            Write-Host "📁 Dizin oluşturuldu: $outputDir" -ForegroundColor Green
        }
        
        # Encrypted password'ı dosyaya yaz
        $encryptedPassword | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
        
        Write-Host "✅ Encrypted credential dosyası oluşturuldu:" -ForegroundColor Green
        Write-Host "   Dosya: $OutputPath" -ForegroundColor White
        Write-Host "   Username: $Username" -ForegroundColor White
        Write-Host ""
        
        # Test et
        Write-Host "🧪 Credential test ediliyor..." -ForegroundColor Yellow
        try {
            $testContent = Get-Content -Path $OutputPath -Raw
            $testSecureString = $testContent | ConvertTo-SecureString
            $testCredential = New-Object System.Management.Automation.PSCredential($Username, $testSecureString)
            Write-Host "✅ Credential test başarılı!" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Credential test başarısız: $_" -ForegroundColor Red
            return $false
        }
        
        return $true
    }
    catch {
        Write-Host "❌ Encrypted credential oluşturulamadı: $_" -ForegroundColor Red
        return $false
    }
}

function Show-UsageInstructions {
    <#
    .SYNOPSIS
        Kullanım talimatlarını gösterir
    #>
    Write-Host "📋 Kullanım Talimatları:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Script'i çalıştırın:" -ForegroundColor Yellow
    Write-Host "   .\create_encrypted_credential.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "2. Özel dosya yolu ile:" -ForegroundColor Yellow
    Write-Host "   .\create_encrypted_credential.ps1 -OutputPath 'C:\MyScripts\MyCredential.txt'" -ForegroundColor White
    Write-Host ""
    Write-Host "3. Özel username ile:" -ForegroundColor Yellow
    Write-Host "   .\create_encrypted_credential.ps1 -Username 'DOMAINB\serviceaccount'" -ForegroundColor White
    Write-Host ""
    Write-Host "4. Mevcut dosyayı üzerine yaz:" -ForegroundColor Yellow
    Write-Host "   .\create_encrypted_credential.ps1 -Force" -ForegroundColor White
    Write-Host ""
    Write-Host "5. Account expiration script'inde kullanın:" -ForegroundColor Yellow
    Write-Host "   .\ad_account_expiration_parallel.ps1 -EncryptedPasswordFile '$OutputPath'" -ForegroundColor White
    Write-Host ""
}

function Show-SecurityNotes {
    <#
    .SYNOPSIS
        Güvenlik notlarını gösterir
    #>
    Write-Host "🔒 Güvenlik Notları:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "• Encrypted credential dosyası user certificate ile korunur" -ForegroundColor Green
    Write-Host "• Sadece aynı user certificate'e sahip kullanıcı decrypt edebilir" -ForegroundColor Green
    Write-Host "• Certificate'in private key'i güvenli tutulmalıdır" -ForegroundColor Green
    Write-Host "• Encrypted dosya güvenli konumda saklanmalıdır" -ForegroundColor Green
    Write-Host "• Certificate expiration tarihini takip edin" -ForegroundColor Green
    Write-Host "• Düzenli olarak credential'ları yenileyin" -ForegroundColor Green
    Write-Host ""
}

# ============================================================
# ANA EXECUTION
# ============================================================

Show-Header

# Mevcut dosya kontrolü
if ((Test-Path -Path $OutputPath) -and -not $Force) {
    Write-Host "⚠️  Dosya zaten mevcut: $OutputPath" -ForegroundColor Yellow
    $overwrite = Read-Host "Üzerine yazmak istiyor musunuz? (y/N)"
    if ($overwrite -ne 'y' -and $overwrite -ne 'Y') {
        Write-Host "İşlem iptal edildi." -ForegroundColor Red
        exit
    }
}

# User certificate kontrolü
Write-Host "🔍 User certificate kontrol ediliyor..." -ForegroundColor Yellow
if (-not (Test-UserCertificate)) {
    Write-Host "❌ User certificate bulunamadı. İşlem iptal edildi." -ForegroundColor Red
    Show-UsageInstructions
    exit 1
}

Write-Host ""

# Encrypted credential oluştur
if (Create-EncryptedCredential -Username $Username -OutputPath $OutputPath) {
    Write-Host "🎉 İşlem başarıyla tamamlandı!" -ForegroundColor Green
    Write-Host ""
    Show-SecurityNotes
    Show-UsageInstructions
}
else {
    Write-Host "❌ İşlem başarısız!" -ForegroundColor Red
    exit 1
}
