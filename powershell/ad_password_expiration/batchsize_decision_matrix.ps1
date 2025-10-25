#Requires -Version 5.1

<#
.SYNOPSIS
    BatchSize ve MaxConcurrentJobs değerlerini belirlemek için karar matrisi
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

function Get-UserCountEstimate {
    <#
    .SYNOPSIS
        Tahmini kullanıcı sayısını alır
    #>
    param(
        [string]$DomainName,
        [string]$OUPath
    )
    
    try {
        $userCount = (Get-ADUser -SearchBase $OUPath -Filter {Enabled -eq $true} -Server $DomainName).Count
        return $userCount
    }
    catch {
        Write-Warning "Kullanıcı sayısı alınamadı: $_"
        return 1000  # Default estimate
    }
}

function Get-OptimalSettings {
    <#
    .SYNOPSIS
        Sistem özelliklerine göre optimal ayarları önerir
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
                Scenario = "Düşük Özellikli Sistem"
                BatchSize = 25
                MaxConcurrentJobs = 2
                Reasoning = "Sınırlı kaynaklar nedeniyle küçük batch'ler ve az concurrent job"
                ExpectedPerformance = "Güvenli ama yavaş"
            }
        }
        "Standard" {
            $recommendations += @{
                Scenario = "Standart Sistem"
                BatchSize = 100
                MaxConcurrentJobs = 4
                Reasoning = "Dengeli performans ve kaynak kullanımı"
                ExpectedPerformance = "İyi performans"
            }
        }
        "High-Spec" {
            $recommendations += @{
                Scenario = "Yüksek Özellikli Sistem"
                BatchSize = 200
                MaxConcurrentJobs = 8
                Reasoning = "Yüksek kaynaklar nedeniyle büyük batch'ler ve çok concurrent job"
                ExpectedPerformance = "Maksimum performans"
            }
        }
    }
    
    # Kullanıcı sayısına göre ayarlamalar
    if ($EstimatedUserCount -lt 500) {
        $recommendations += @{
            Scenario = "Küçük Kullanıcı Tabanı (< 500)"
            BatchSize = [Math]::Min($recommendations[0].BatchSize, 50)
            MaxConcurrentJobs = [Math]::Min($recommendations[0].MaxConcurrentJobs, 3)
            Reasoning = "Az kullanıcı nedeniyle küçük batch'ler yeterli"
            ExpectedPerformance = "Hızlı işlem"
        }
    }
    elseif ($EstimatedUserCount -gt 10000) {
        $recommendations += @{
            Scenario = "Büyük Kullanıcı Tabanı (> 10,000)"
            BatchSize = [Math]::Max($recommendations[0].BatchSize, 150)
            MaxConcurrentJobs = [Math]::Max($recommendations[0].MaxConcurrentJobs, 6)
            Reasoning = "Çok kullanıcı nedeniyle büyük batch'ler ve çok concurrent job"
            ExpectedPerformance = "Optimize edilmiş performans"
        }
    }
    
    # RAM kullanımına göre ayarlamalar
    if ($SystemInfo.AvailableRAM -lt 2) {
        $recommendations += @{
            Scenario = "Düşük RAM Durumu"
            BatchSize = [Math]::Min($recommendations[0].BatchSize, 50)
            MaxConcurrentJobs = [Math]::Min($recommendations[0].MaxConcurrentJobs, 2)
            Reasoning = "Düşük RAM nedeniyle küçük batch'ler"
            ExpectedPerformance = "Bellek dostu"
        }
    }
    
    return $recommendations
}

function Show-RecommendationMatrix {
    <#
    .SYNOPSIS
        Öneri matrisini gösterir
    #>
    param(
        [array]$Recommendations,
        [hashtable]$SystemInfo,
        [int]$UserCount
    )
    
    Write-Host "=== BATCHSIZE VE MAXCONCURRENTJOBS KARAR MATRİSİ ===" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Sistem Bilgileri:" -ForegroundColor Yellow
    Write-Host "  CPU Çekirdek Sayısı: $($SystemInfo.CPUCores)"
    Write-Host "  Toplam RAM: $($SystemInfo.TotalRAM) GB"
    Write-Host "  Kullanılabilir RAM: $($SystemInfo.AvailableRAM) GB"
    Write-Host "  Sistem Tipi: $($SystemInfo.SystemType)"
    Write-Host "  Tahmini Kullanıcı Sayısı: $UserCount"
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
    
    Write-Host "🎯 EN İYİ ÖNERİ:" -ForegroundColor Green
    Write-Host "   BatchSize: $($bestRecommendation.BatchSize)"
    Write-Host "   MaxConcurrentJobs: $($bestRecommendation.MaxConcurrentJobs)"
    Write-Host ""
    
    Write-Host "Kullanım Örneği:" -ForegroundColor Cyan
    Write-Host ".\ad_password_expiration_parallel.ps1 -BatchSize $($bestRecommendation.BatchSize) -MaxConcurrentJobs $($bestRecommendation.MaxConcurrentJobs)"
    Write-Host ""
}

function Show-PerformanceGuidelines {
    <#
    .SYNOPSIS
        Performans rehberini gösterir
    #>
    
    Write-Host "=== PERFORMANS REHBERİ ===" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "BatchSize Seçimi:" -ForegroundColor Yellow
    Write-Host "• 25-50:   Küçük sistemler, düşük RAM"
    Write-Host "• 100-150:  Standart sistemler (ÖNERİLEN)"
    Write-Host "• 200-300: Yüksek performanslı sistemler"
    Write-Host "• 500+:    Sadece çok güçlü sistemler"
    Write-Host ""
    
    Write-Host "MaxConcurrentJobs Seçimi:" -ForegroundColor Yellow
    Write-Host "• 2-3:     Düşük özellikli sistemler"
    Write-Host "• 4-6:     Standart sistemler (ÖNERİLEN)"
    Write-Host "• 7-10:    Yüksek performanslı sistemler"
    Write-Host "• 10+:     Sadece çok güçlü sistemler"
    Write-Host ""
    
    Write-Host "Performans İpuçları:" -ForegroundColor Green
    Write-Host "• BatchSize × MaxConcurrentJobs = Toplam eşzamanlı kullanıcı"
    Write-Host "• Her job ~8-16 MB RAM kullanır"
    Write-Host "• CPU kullanımı: MaxConcurrentJobs × 10-15%"
    Write-Host "• AD DC'ye bağlantı: MaxConcurrentJobs × 2-3 bağlantı"
    Write-Host ""
    
    Write-Host "Test Önerileri:" -ForegroundColor Magenta
    Write-Host "1. Küçük değerlerle başlayın"
    Write-Host "2. Sistem kaynaklarını izleyin"
    Write-Host "3. Performansı ölçün"
    Write-Host "4. Değerleri kademeli olarak artırın"
    Write-Host "5. Optimum noktayı bulun"
}

# ============================================================
# ANA EXECUTION
# ============================================================

Write-Host "BatchSize ve MaxConcurrentJobs Karar Matrisi" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Sistem bilgilerini al
$systemInfo = Get-SystemInfo

# Kullanıcı sayısını tahmin et (opsiyonel)
$userCount = 1000  # Default
if ($args.Count -gt 0) {
    try {
        $userCount = Get-UserCountEstimate -DomainName $args[0] -OUPath $args[1]
    }
    catch {
        Write-Warning "Domain bilgileri alınamadı, varsayılan değer kullanılıyor: $userCount"
    }
}

# Optimal ayarları hesapla
$recommendations = Get-OptimalSettings -SystemInfo $systemInfo -EstimatedUserCount $userCount

# Sonuçları göster
Show-RecommendationMatrix -Recommendations $recommendations -SystemInfo $systemInfo -UserCount $userCount

# Performans rehberini göster
Show-PerformanceGuidelines
