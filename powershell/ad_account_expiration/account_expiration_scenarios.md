# AD Account Expiration - Senaryo Örnekleri

## 🏢 Kurumsal Senaryolar

### **Senaryo 1: Küçük Şirket (10-50 Account Expiration Kullanıcı)**
```powershell
# Sistem: 4 CPU, 8 GB RAM
.\ad_account_expiration_parallel.ps1 -BatchSize 25 -MaxConcurrentJobs 2 -DaysThreshold 30

# Neden bu değerler?
# - Az account expiration kullanıcı = küçük batch'ler yeterli
# - Sınırlı kaynak = az concurrent job
# - 30 gün önceden uyarı = güvenli margin
```

**Özellikler:**
- Geçici personel hesapları
- Stajyer hesapları
- Proje bazlı hesaplar
- Sözleşmeli personel

### **Senaryo 2: Orta Ölçekli Şirket (100-500 Account Expiration Kullanıcı)**
```powershell
# Sistem: 8 CPU, 16 GB RAM
.\ad_account_expiration_parallel.ps1 -BatchSize 75 -MaxConcurrentJobs 4 -DaysThreshold 15

# Neden bu değerler?
# - Orta account expiration kullanıcı = orta batch'ler
# - Yeterli kaynak = orta concurrent job
# - 15 gün önceden uyarı = dengeli yaklaşım
```

**Özellikler:**
- Çok sayıda geçici personel
- Sezonluk işçiler
- Dış kaynak personel
- Test hesapları

### **Senaryo 3: Büyük Kurumsal (500+ Account Expiration Kullanıcı)**
```powershell
# Sistem: 16 CPU, 32 GB RAM
.\ad_account_expiration_parallel.ps1 -BatchSize 150 -MaxConcurrentJobs 6 -DaysThreshold 7

# Neden bu değerler?
# - Çok account expiration kullanıcı = büyük batch'ler
# - Yüksek kaynak = çok concurrent job
# - 7 gün önceden uyarı = kritik monitoring
```

**Özellikler:**
- Büyük geçici personel tabanı
- Çoklu proje ekipleri
- Global operasyonlar
- Karmaşık organizasyon yapısı

## 🔧 Teknik Senaryolar

### **Senaryo 4: Düşük Kaynaklı Sunucu**
```powershell
# Sistem: 2 CPU, 4 GB RAM
.\ad_account_expiration_parallel.ps1 -BatchSize 15 -MaxConcurrentJobs 1 -DaysThreshold 30

# Neden bu değerler?
# - Sınırlı RAM = çok küçük batch'ler
# - Az CPU = tek concurrent job
# - 30 gün önceden uyarı = güvenli margin
```

### **Senaryo 5: Yüksek Performanslı Sunucu**
```powershell
# Sistem: 32 CPU, 64 GB RAM
.\ad_account_expiration_parallel.ps1 -BatchSize 200 -MaxConcurrentJobs 10 -DaysThreshold 5

# Neden bu değerler?
# - Çok RAM = büyük batch'ler
# - Çok CPU = çok concurrent job
# - 5 gün önceden uyarı = hızlı response
```

### **Senaryo 6: Dual Domain Environment**
```powershell
# İki domain, her biri 200+ account expiration kullanıcı
.\ad_account_expiration_parallel.ps1 `
    -DomainA "contoso.com" `
    -DomainB "fabrikam.com" `
    -BatchSize 100 `
    -MaxConcurrentJobs 5 `
    -DaysThreshold 10

# Neden bu değerler?
# - İki domain = orta batch'ler
# - Toplam 400+ kullanıcı = yüksek concurrent job
# - 10 gün önceden uyarı = dengeli monitoring
```

## 📊 Performans Karşılaştırması

| Senaryo | BatchSize | MaxConcurrentJobs | Toplam Eşzamanlı | Beklenen Süre | Uyarı Süresi |
|---------|-----------|-------------------|------------------|----------------|--------------|
| Küçük Şirket | 25 | 2 | 50 | 30-60 saniye | 30 gün |
| Orta Şirket | 75 | 4 | 300 | 1-2 dakika | 15 gün |
| Büyük Şirket | 150 | 6 | 900 | 2-5 dakika | 7 gün |
| Düşük Kaynak | 15 | 1 | 15 | 1-3 dakika | 30 gün |
| Yüksek Performans | 200 | 10 | 2,000 | 30-60 saniye | 5 gün |
| Dual Domain | 100 | 5 | 500 | 2-4 dakika | 10 gün |

## 🎯 Özel Kullanım Senaryoları

### **Senaryo 7: Geçici Hesaplar (Contractors)**
```powershell
# Sık değişen contractor hesapları
.\ad_account_expiration_parallel.ps1 `
    -BatchSize 50 `
    -MaxConcurrentJobs 3 `
    -DaysThreshold 14 `
    -OutputPath "C:\Reports\ContractorExpiration.html"
```

**Özellikler:**
- Sık değişen hesaplar
- Kısa süreli projeler
- Dış kaynak personel
- Esnek süreler

### **Senaryo 8: Test Hesapları**
```powershell
# Test ortamı hesapları
.\ad_account_expiration_parallel.ps1 `
    -BatchSize 25 `
    -MaxConcurrentJobs 2 `
    -DaysThreshold 7 `
    -OutputPath "C:\Reports\TestAccountExpiration.html"
```

**Özellikler:**
- Test ortamı hesapları
- Geliştirici hesapları
- Demo hesapları
- Kısa süreli testler

### **Senaryo 9: Sezonluk İşçiler**
```powershell
# Sezonluk işçi hesapları
.\ad_account_expiration_parallel.ps1 `
    -BatchSize 100 `
    -MaxConcurrentJobs 4 `
    -DaysThreshold 21 `
    -OutputPath "C:\Reports\SeasonalWorkerExpiration.html"
```

**Özellikler:**
- Sezonluk işçiler
- Geçici personel
- Proje bazlı hesaplar
- Uzun süreli monitoring

## 🔍 Optimizasyon Stratejileri

### **Strateji 1: Kademeli Artırma**
```powershell
# 1. Adım: Güvenli başlangıç
.\ad_account_expiration_parallel.ps1 -BatchSize 25 -MaxConcurrentJobs 2

# 2. Adım: Performans testi
.\ad_account_expiration_parallel.ps1 -BatchSize 75 -MaxConcurrentJobs 4

# 3. Adım: Maksimum performans
.\ad_account_expiration_parallel.ps1 -BatchSize 150 -MaxConcurrentJobs 6
```

### **Strateji 2: Kaynak Bazlı Optimizasyon**
```powershell
# RAM kullanımına göre
if ($AvailableRAM -lt 4GB) {
    $BatchSize = 25
    $MaxConcurrentJobs = 2
}
elseif ($AvailableRAM -lt 16GB) {
    $BatchSize = 75
    $MaxConcurrentJobs = 4
}
else {
    $BatchSize = 150
    $MaxConcurrentJobs = 6
}
```

### **Strateji 3: Kullanıcı Sayısı Bazlı**
```powershell
# Account expiration kullanıcı sayısına göre
if ($AccountExpirationUserCount -lt 100) {
    $BatchSize = 25
    $MaxConcurrentJobs = 2
}
elseif ($AccountExpirationUserCount -lt 500) {
    $BatchSize = 75
    $MaxConcurrentJobs = 4
}
else {
    $BatchSize = 150
    $MaxConcurrentJobs = 6
}
```

## ⚠️ Dikkat Edilmesi Gerekenler

### **Account Expiration Özel Durumları**

#### **BatchSize Çok Büyükse:**
- ❌ Yüksek bellek kullanımı
- ❌ Uzun işlem süreleri
- ❌ Timeout riski
- ✅ Daha az job overhead

#### **BatchSize Çok Küçükse:**
- ❌ Çok fazla job oluşturma
- ❌ Yüksek overhead
- ❌ Yavaş performans
- ✅ Düşük bellek kullanımı

#### **MaxConcurrentJobs Çok Büyükse:**
- ❌ CPU overload
- ❌ Bellek tükenmesi
- ❌ AD DC'ye aşırı yük
- ✅ Maksimum paralellik

#### **MaxConcurrentJobs Çok Küçükse:**
- ❌ Düşük CPU kullanımı
- ❌ Yavaş performans
- ❌ Kaynak israfı
- ✅ Kararlı sistem

## 📈 Beklenen Performans Artışları

| Mevcut Durum | Yeni Durum | Performans Artışı |
|---------------|------------|-------------------|
| Sequential | BatchSize=75, Jobs=4 | %70-80 |
| BatchSize=25 | BatchSize=150 | %40-50 |
| Jobs=2 | Jobs=6 | %60-70 |
| Tek Domain | Dual Domain Parallel | %50-60 |

## 🚀 Gelişmiş Senaryolar

### **Senaryo 10: Kritik Hesaplar**
```powershell
# Kritik hesaplar için özel monitoring
.\ad_account_expiration_parallel.ps1 `
    -BatchSize 50 `
    -MaxConcurrentJobs 3 `
    -DaysThreshold 30 `
    -OutputPath "C:\Reports\CriticalAccountExpiration.html"
```

### **Senaryo 11: Compliance Monitoring**
```powershell
# Compliance için detaylı monitoring
.\ad_account_expiration_parallel.ps1 `
    -BatchSize 100 `
    -MaxConcurrentJobs 5 `
    -DaysThreshold 45 `
    -OutputPath "C:\Reports\ComplianceAccountExpiration.html"
```

### **Senaryo 12: Emergency Response**
```powershell
# Acil durum monitoring
.\ad_account_expiration_parallel.ps1 `
    -BatchSize 200 `
    -MaxConcurrentJobs 8 `
    -DaysThreshold 3 `
    -OutputPath "C:\Reports\EmergencyAccountExpiration.html"
```

Bu senaryo örnekleri, farklı ortamlar için optimal Account Expiration monitoring stratejileri sunar. Sistem özelliklerinize ve ihtiyaçlarınıza göre en uygun senaryoyu seçebilirsiniz.
