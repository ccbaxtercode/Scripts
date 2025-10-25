#Requires -Version 5.1

<#
.SYNOPSIS
    BatchSize ve MaxConcurrentJobs değerlerini belirlemek için karar matrisi (Account Expiration)
.DESCRIPTION
    Sistem özelliklerine göre optimal BatchSize ve MaxConcurrentJobs değerlerini önerir
.NOTES
    Author: AD Admin
    Date: 2025-01-27
#>

function Get-SystemInfo {
    <#
    .SYNOPSIS
        Sistem bilgilerini toplar
    #>
    $cpuCores = (Get-WmiObject -Class Win32_Processor).NumberOfLogicalProcessors
    $totalRAM = [Math]::Round((Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
    $availableRAM = [Math]::Round((Get-WmiObject -Class Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)
    
    return @{
        CPUCores = $cpuCores
        TotalRAM = $totalRAM
        AvailableRAM = $availableRAM
        SystemType = if ($cpuCores -le 2 -or $totalRAM -le 4) { "Low-Spec" }
                    elseif ($cpuCores -le 6 -or $totalRAM -le 16) { "Standard" }
                    else { "High-Spec" }
    }
}

function Get-AccountExpirationUserCountEstimate {
    <#
    .SYNOPSIS
        Tahmini account expiration tarihi olan kullanıcı sayısını alır
    #>
    param(
        [string]$DomainName,
        [string]$OUPath
    )
    
    try {
        $userCount = (Get-ADUser -SearchBase $OUPath -Filter {Enabled -eq $true -and AccountExpirationDate -ne $null} -Server $DomainName).Count
        return $userCount
    }
    catch {
        Write-Warning "Account expiration kullanıcı sayısı alınamadı: $_"
        return 100  # Default estimate (account expiration is less common)
    }
}

function Get-OptimalAccountExpirationSettings {
    <#
    .SYNOPSIS
        Sistem özelliklerine göre optimal account expiration ayarlarını önerir
    #>
    param(
        [hashtable]$SystemInfo,
        [int]$EstimatedUserCount
    )
    
    $recommendations = @()
    
    # Sistem tipine göre öneriler
    switch ($SystemInfo.SystemType) {
        "Low-Spec" {
            $recommendations += @{
                Scenario = "Düşük Özellikli Sistem (Account Expiration)"
                BatchSize = 25
                MaxConcurrentJobs = 2
                Reasoning = "Sınırlı kaynaklar nedeniyle küçük batch'ler ve az concurrent job"
                ExpectedPerformance = "Güvenli ama yavaş"
            }
        }
        "Standard" {
            $recommendations += @{
                Scenario = "Standart Sistem (Account Expiration)"
                BatchSize = 75
                MaxConcurrentJobs = 4
                Reasoning = "Dengeli performans ve kaynak kullanımı"
                ExpectedPerformance = "İyi performans"
            }
        }
        "High-Spec" {
            $recommendations += @{
                Scenario = "Yüksek Özellikli Sistem (Account Expiration)"
                BatchSize = 150
                MaxConcurrentJobs = 6
                Reasoning = "Yüksek kaynaklar nedeniyle büyük batch'ler ve çok concurrent job"
                ExpectedPerformance = "Maksimum performans"
            }
        }
    }
    
    # Kullanıcı sayısına göre ayarlamalar (Account expiration genelde daha az kullanıcı)
    if ($EstimatedUserCount -lt 100) {
        $recommendations += @{
            Scenario = "Küçük Account Expiration Tabanı (< 100)"
            BatchSize = [Math]::Min($recommendations[0].BatchSize, 25)
            MaxConcurrentJobs = [Math]::Min($recommendations[0].MaxConcurrentJobs, 2)
            Reasoning = "Az account expiration kullanıcı nedeniyle küçük batch'ler yeterli"
            ExpectedPerformance = "Hızlı işlem"
        }
    }
    elseif ($EstimatedUserCount -gt 1000) {
        $recommendations += @{
            Scenario = "Büyük Account Expiration Tabanı (> 1,000)"
            BatchSize = [Math]::Max($recommendations[0].BatchSize, 100)
            MaxConcurrentJobs = [Math]::Max($recommendations[0].MaxConcurrentJobs, 4)
            Reasoning = "Çok account expiration kullanıcı nedeniyle büyük batch'ler"
            ExpectedPerformance = "Optimize edilmiş performans"
        }
    }
    
    # RAM kullanımına göre ayarlamalar
    if ($SystemInfo.AvailableRAM -lt 2) {
        $recommendations += @{
            Scenario = "Düşük RAM Durumu (Account Expiration)"
            BatchSize = [Math]::Min($recommendations[0].BatchSize, 25)
            MaxConcurrentJobs = [Math]::Min($recommendations[0].MaxConcurrentJobs, 2)
            Reasoning = "Düşük RAM nedeniyle küçük batch'ler"
            ExpectedPerformance = "Bellek dostu"
        }
    }
    
    return $recommendations
}

function Show-AccountExpirationRecommendationMatrix {
    <#
    .SYNOPSIS
        Account expiration öneri matrisini gösterir
    #>
    param(
        [array]$Recommendations,
        [hashtable]$SystemInfo,
        [int]$UserCount
    )
    
    Write-Host "=== ACCOUNT EXPIRATION BATCHSIZE VE MAXCONCURRENTJOBS KARAR MATRİSİ ===" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Sistem Bilgileri:" -ForegroundColor Yellow
    Write-Host "  CPU Çekirdek Sayısı: $($SystemInfo.CPUCores)"
    Write-Host "  Toplam RAM: $($SystemInfo.TotalRAM) GB"
    Write-Host "  Kullanılabilir RAM: $($SystemInfo.AvailableRAM) GB"
    Write-Host "  Sistem Tipi: $($SystemInfo.SystemType)"
    Write-Host "  Tahmini Account Expiration Kullanıcı Sayısı: $UserCount"
    Write-Host ""
    
    Write-Host "Önerilen Ayarlar:" -ForegroundColor Green
    Write-Host ""
    
    foreach ($rec in $Recommendations) {
        Write-Host "📋 $($rec.Scenario)" -ForegroundColor Magenta
        Write-Host "   BatchSize: $($rec.BatchSize)"
        Write-Host "   MaxConcurrentJobs: $($rec.MaxConcurrentJobs)"
        Write-Host "   Açıklama: $($rec.Reasoning)"
        Write-Host "   Beklenen Performans: $($rec.ExpectedPerformance)"
        Write-Host ""
    }
    
    # En iyi öneriyi seç
    $bestRecommendation = $Recommendations[0]
    
    Write-Host "🎯 EN İYİ ÖNERİ (Account Expiration):" -ForegroundColor Green
    Write-Host "   BatchSize: $($bestRecommendation.BatchSize)"
    Write-Host "   MaxConcurrentJobs: $($bestRecommendation.MaxConcurrentJobs)"
    Write-Host ""
    
    Write-Host "Kullanım Örneği:" -ForegroundColor Cyan
    Write-Host ".\ad_account_expiration_parallel.ps1 -BatchSize $($bestRecommendation.BatchSize) -MaxConcurrentJobs $($bestRecommendation.MaxConcurrentJobs)"
    Write-Host ""
}

function Show-AccountExpirationPerformanceGuidelines {
    <#
    .SYNOPSIS
        Account expiration performans rehberini gösterir
    #>
    
    Write-Host "=== ACCOUNT EXPIRATION PERFORMANS REHBERİ ===" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Account Expiration Özellikleri:" -ForegroundColor Yellow
    Write-Host "• Account expiration tarihi olan kullanıcılar daha az sayıda"
    Write-Host "• Genellikle geçici hesaplar veya sözleşmeli personel"
    Write-Host "• Kritik işlem - hesap tamamen kilitlenir"
    Write-Host "• Daha dikkatli monitoring gerektirir"
    Write-Host ""
    
    Write-Host "BatchSize Seçimi (Account Expiration):" -ForegroundColor Yellow
    Write-Host "• 25-50:   Küçük sistemler, düşük RAM"
    Write-Host "• 75-100:  Standart sistemler (ÖNERİLEN)"
    Write-Host "• 150-200: Yüksek performanslı sistemler"
    Write-Host "• 300+:    Sadece çok güçlü sistemler"
    Write-Host ""
    
    Write-Host "MaxConcurrentJobs Seçimi (Account Expiration):" -ForegroundColor Yellow
    Write-Host "• 2-3:     Düşük özellikli sistemler"
    Write-Host "• 4-6:     Standart sistemler (ÖNERİLEN)"
    Write-Host "• 6-8:     Yüksek performanslı sistemler"
    Write-Host "• 8+:      Sadece çok güçlü sistemler"
    Write-Host ""
    
    Write-Host "Account Expiration İpuçları:" -ForegroundColor Green
    Write-Host "• BatchSize × MaxConcurrentJobs = Toplam eşzamanlı kullanıcı"
    Write-Host "• Her job ~6-12 MB RAM kullanır (daha az veri)"
    Write-Host "• CPU kullanımı: MaxConcurrentJobs × 8-12%"
    Write-Host "• AD DC'ye bağlantı: MaxConcurrentJobs × 1-2 bağlantı"
    Write-Host ""
    
    Write-Host "Monitoring Stratejisi:" -ForegroundColor Magenta
    Write-Host "• 30 gün önceden uyarı"
    Write-Host "• 15 gün önceden hatırlatma"
    Write-Host "• 7 gün önceden son uyarı"
    Write-Host "• 1 gün önceden kritik uyarı"
    Write-Host "• Otomatik email bildirimleri"
    Write-Host ""
    
    Write-Host "Test Önerileri:" -ForegroundColor Magenta
    Write-Host "1. Küçük değerlerle başlayın"
    Write-Host "2. Sistem kaynaklarını izleyin"
    Write-Host "3. Performansı ölçün"
    Write-Host "4. Değerleri kademeli olarak artırın"
    Write-Host "5. Optimum noktayı bulun"
    Write-Host "6. Email bildirimlerini test edin"
}

function Show-AccountExpirationScenarios {
    <#
    .SYNOPSIS
        Account expiration senaryolarını gösterir
    #>
    
    Write-Host "`n=== ACCOUNT EXPIRATION SENARYOLARI ===" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Senaryo 1: Küçük Şirket (10-50 account expiration kullanıcı)" -ForegroundColor Yellow
    Write-Host "  BatchSize: 25, MaxConcurrentJobs: 2"
    Write-Host "  Neden: Az kullanıcı, sınırlı kaynak, hızlı işlem"
    Write-Host ""
    
    Write-Host "Senaryo 2: Orta Ölçekli Şirket (100-500 account expiration kullanıcı)" -ForegroundColor Yellow
    Write-Host "  BatchSize: 75, MaxConcurrentJobs: 4"
    Write-Host "  Neden: Orta kullanıcı, yeterli kaynak, dengeli performans"
    Write-Host ""
    
    Write-Host "Senaryo 3: Büyük Kurumsal (500+ account expiration kullanıcı)" -ForegroundColor Yellow
    Write-Host "  BatchSize: 150, MaxConcurrentJobs: 6"
    Write-Host "  Neden: Çok kullanıcı, yüksek kaynak, maksimum performans"
    Write-Host ""
    
    Write-Host "Senaryo 4: Geçici Hesaplar (Contractors, Interns)" -ForegroundColor Yellow
    Write-Host "  BatchSize: 50, MaxConcurrentJobs: 3"
    Write-Host "  Neden: Sık değişen hesaplar, dikkatli monitoring"
    Write-Host ""
    
    Write-Host "Senaryo 5: Test Hesapları" -ForegroundColor Yellow
    Write-Host "  BatchSize: 25, MaxConcurrentJobs: 2"
    Write-Host "  Neden: Test ortamı, sınırlı kaynak"
    Write-Host ""
}

# ============================================================
# ANA EXECUTION
# ============================================================

Write-Host "Account Expiration BatchSize ve MaxConcurrentJobs Karar Matrisi" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""

# Sistem bilgilerini al
$systemInfo = Get-SystemInfo

# Account expiration kullanıcı sayısını tahmin et (opsiyonel)
$userCount = 100  # Default
if ($args.Count -gt 0) {
    try {
        $userCount = Get-AccountExpirationUserCountEstimate -DomainName $args[0] -OUPath $args[1]
    }
    catch {
        Write-Warning "Domain bilgileri alınamadı, varsayılan değer kullanılıyor: $userCount"
    }
}

# Optimal ayarları hesapla
$recommendations = Get-OptimalAccountExpirationSettings -SystemInfo $systemInfo -EstimatedUserCount $userCount

# Sonuçları göster
Show-AccountExpirationRecommendationMatrix -Recommendations $recommendations -SystemInfo $systemInfo -UserCount $userCount

# Performans rehberini göster
Show-AccountExpirationPerformanceGuidelines

# Senaryoları göster
Show-AccountExpirationScenarios
