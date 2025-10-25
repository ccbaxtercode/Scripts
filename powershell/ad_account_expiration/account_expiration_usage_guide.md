# AD Account Expiration Monitoring - Kullanım Kılavuzu

## Genel Bakış

AD Account Expiration monitoring sistemi, Active Directory'deki kullanıcı hesaplarının expiration tarihlerini izler ve yaklaşan sona erme tarihleri için uyarılar üretir. Bu sistem, parola expiration'dan farklı olarak hesabın tamamen kilitlenmesi durumunu yönetir.

## Dosya Yapısı

```
ad_account_expiration/
├── ad_account_expiration.ps1                    # Temel script
├── ad_account_expiration_parallel.ps1          # Parallel processing versiyonu
├── create_encrypted_credential.ps1             # Credential oluşturma aracı
├── account_expiration_performance_comparison.ps1 # Performans karşılaştırma
├── account_expiration_decision_matrix.ps1        # Karar matrisi
└── account_expiration_usage_guide.md           # Bu kılavuz
```

## Temel Kullanım

### 0. Credential Hazırlığı
```powershell
# User certificate ile encrypted credential oluştur
.\create_encrypted_credential.ps1

# Özel dosya yolu ile
.\create_encrypted_credential.ps1 -OutputPath "C:\MyScripts\MyCredential.txt"

# Özel username ile
.\create_encrypted_credential.ps1 -Username "DOMAINB\serviceaccount"
```

### 1. Basit Kullanım
```powershell
# Varsayılan ayarlarla çalıştır
.\ad_account_expiration.ps1
```

### 2. Parametreli Kullanım
```powershell
# Özel domain ve threshold ile
.\ad_account_expiration.ps1 `
    -DomainA "contoso.com" `
    -DomainB "fabrikam.com" `
    -DaysThreshold 30 `
    -OutputPath "C:\Reports\MyReport.html"
```

### 3. Parallel Processing Kullanımı
```powershell
# Yüksek performans için
.\ad_account_expiration_parallel.ps1 `
    -DomainA "contoso.com" `
    -DomainB "fabrikam.com" `
    -BatchSize 100 `
    -MaxConcurrentJobs 5 `
    -DaysThreshold 15
```

## Parametreler

### Temel Parametreler
- `DomainA`: İlk domain adı
- `DomainB`: İkinci domain adı
- `OUPathDomainA/B`: Organizational Unit yolları
- `DaysThreshold`: Uyarı verilecek gün sayısı (varsayılan: 15)
- `OutputPath`: HTML raporu çıktı yolu
- `LogPath`: Log dosyası yolu

### Parallel Processing Parametreleri
- `BatchSize`: Her job'da işlenecek kullanıcı sayısı (varsayılan: 100)
- `MaxConcurrentJobs`: Maksimum eşzamanlı job sayısı (varsayılan: 5)
- `MaxRetries`: Başarısız işlemler için retry sayısı (varsayılan: 3)

## Account Expiration vs Password Expiration

| Özellik | Account Expiration | Password Expiration |
|---------|-------------------|-------------------|
| **Etki** | Hesap tamamen kilitlenir | Sadece parola değiştirilir |
| **Kritiklik** | Çok yüksek | Orta |
| **Kullanıcı Sayısı** | Genelde az | Çok |
| **Monitoring Sıklığı** | Günlük | Haftalık |
| **Uyarı Süresi** | 30 gün önceden | 15 gün önceden |

## Performans Optimizasyonu

### BatchSize Seçimi
```powershell
# Küçük sistemler için
-BatchSize 25

# Standart sistemler için
-BatchSize 100

# Yüksek performanslı sistemler için
-BatchSize 200
```

### MaxConcurrentJobs Seçimi
```powershell
# Düşük özellikli sistemler için
-MaxConcurrentJobs 2

# Standart sistemler için
-MaxConcurrentJobs 5

# Yüksek performanslı sistemler için
-MaxConcurrentJobs 8
```

## Senaryolar

### Senaryo 1: Küçük Şirket
```powershell
# 50-100 account expiration kullanıcı
.\ad_account_expiration_parallel.ps1 `
    -BatchSize 25 `
    -MaxConcurrentJobs 2 `
    -DaysThreshold 30
```

### Senaryo 2: Orta Ölçekli Şirket
```powershell
# 200-500 account expiration kullanıcı
.\ad_account_expiration_parallel.ps1 `
    -BatchSize 75 `
    -MaxConcurrentJobs 4 `
    -DaysThreshold 15
```

### Senaryo 3: Büyük Kurumsal
```powershell
# 500+ account expiration kullanıcı
.\ad_account_expiration_parallel.ps1 `
    -BatchSize 150 `
    -MaxConcurrentJobs 6 `
    -DaysThreshold 7
```

## Monitoring Stratejisi

### Uyarı Zamanlaması
- **30 gün önceden**: İlk uyarı
- **15 gün önceden**: Hatırlatma
- **7 gün önceden**: Son uyarı
- **1 gün önceden**: Kritik uyarı

### Otomatik Çalıştırma
```powershell
# Task Scheduler ile günlük çalıştırma
schtasks /create /tn "AD Account Expiration Check" /tr "powershell.exe -File C:\Scripts\ad_account_expiration_parallel.ps1" /sc daily /st 08:00
```

## HTML Rapor Özellikleri

### Rapor İçeriği
- Domain bilgisi
- Kullanıcı adı ve display name
- Account expiration tarihi
- Kalan gün sayısı
- E-posta adresi
- Son parola değişim tarihi
- Son giriş tarihi

### Rapor Stili
- Kırmızı başlık (kritik durum)
- Sarı hover efekti
- Responsive tasarım
- Performance bilgileri

## Hata Yönetimi

### Yaygın Hatalar
1. **Credential Hatası**: Encrypted password dosyası bulunamadı
2. **Domain Bağlantı Hatası**: Domain controller'a erişim yok
3. **Permission Hatası**: Yetersiz AD izinleri
4. **Memory Hatası**: Çok büyük batch size

### Çözümler
```powershell
# User certificate ile credential dosyası oluştur
.\create_encrypted_credential.ps1 -OutputPath "C:\Scripts\DomainB_Credential.txt"

# Permission kontrolü
Get-ADUser -Filter * -Server "domainB.local" | Select-Object -First 1

# Memory optimizasyonu
-BatchSize 50 -MaxConcurrentJobs 3
```

## Performans Testi

### Test Scripti Çalıştırma
```powershell
# Performans karşılaştırması
.\account_expiration_performance_comparison.ps1 -TestUserCount 1000

# Karar matrisi
.\account_expiration_decision_matrix.ps1 "contoso.com" "OU=Users,DC=contoso,DC=com"
```

### Performans Metrikleri
- İşlem süresi
- Bellek kullanımı
- CPU kullanımı
- Hata oranı
- Throughput (kullanıcı/saniye)

## Güvenlik

### Credential Yönetimi
- **User Certificate ile Encrypted Password**: En güvenli yöntem
- **Service Account'lar**: Minimum gerekli izinler
- **Düzenli Credential Rotation**: Aylık yenileme
- **Güvenli Dosya Konumları**: Sadece yetkili kullanıcılar erişebilir
- **Certificate Management**: Private key güvenliği kritik

### Log Güvenliği
- Log dosyalarında hassas bilgi bulunmaz
- Log dosyalarını güvenli konumlarda saklayın
- Düzenli log temizliği

## Troubleshooting

### Sorun Giderme Adımları
1. **Log dosyalarını kontrol edin**
2. **Sistem kaynaklarını izleyin**
3. **Network bağlantısını test edin**
4. **AD permissions'ları kontrol edin**
5. **Script parametrelerini optimize edin**

### Debug Modu
```powershell
# Verbose logging ile çalıştır
.\ad_account_expiration_parallel.ps1 -Verbose

# Test modu (küçük batch)
.\ad_account_expiration_parallel.ps1 -BatchSize 10 -MaxConcurrentJobs 1
```

## Best Practices

### 1. Monitoring
- Günlük otomatik çalıştırma
- Email bildirimleri
- Dashboard entegrasyonu
- Trend analizi

### 2. Performance
- Sistem kaynaklarını izleyin
- Batch size'ı optimize edin
- Concurrent job sayısını ayarlayın
- Regular performance testing

### 3. Security
- Encrypted credentials kullanın
- Minimum privilege principle
- Regular security reviews
- Audit logging

### 4. Maintenance
- Regular script updates
- Performance monitoring
- Error rate tracking
- Capacity planning

## Gelecek Geliştirmeler

### Planlanan Özellikler
- Email notification entegrasyonu
- Dashboard web interface
- REST API endpoints
- Machine learning optimizasyonu
- Cloud-based processing

### Gelişmiş Özellikler
- Real-time monitoring
- Predictive analytics
- Automated remediation
- Integration with ITSM tools
- Mobile notifications

Bu kılavuz, AD Account Expiration monitoring sistemini etkili bir şekilde kullanmanıza yardımcı olacaktır. Sorularınız için sistem yöneticinize başvurun.
