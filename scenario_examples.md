# BatchSize ve MaxConcurrentJobs Senaryo Örnekleri

## 🏢 Kurumsal Senaryolar

### **Senaryo 1: Küçük Şirket (100-500 kullanıcı)**
```powershell
# Sistem: 4 CPU, 8 GB RAM
.\ad_password_expiration_parallel.ps1 -BatchSize 50 -MaxConcurrentJobs 3

# Neden bu değerler?
# - Az kullanıcı = küçük batch'ler yeterli
# - Sınırlı kaynak = az concurrent job
# - Hızlı işlem = 30-60 saniye
```

### **Senaryo 2: Orta Ölçekli Şirket (1,000-5,000 kullanıcı)**
```powershell
# Sistem: 8 CPU, 16 GB RAM
.\ad_password_expiration_parallel.ps1 -BatchSize 100 -MaxConcurrentJobs 5

# Neden bu değerler?
# - Orta kullanıcı = orta batch'ler
# - Yeterli kaynak = orta concurrent job
# - Dengeli performans = 2-5 dakika
```

### **Senaryo 3: Büyük Kurumsal (10,000+ kullanıcı)**
```powershell
# Sistem: 16 CPU, 32 GB RAM
.\ad_password_expiration_parallel.ps1 -BatchSize 200 -MaxConcurrentJobs 8

# Neden bu değerler?
# - Çok kullanıcı = büyük batch'ler
# - Yüksek kaynak = çok concurrent job
# - Maksimum performans = 5-10 dakika
```

## 🔧 Teknik Senaryolar

### **Senaryo 4: Düşük Kaynaklı Sunucu**
```powershell
# Sistem: 2 CPU, 4 GB RAM
.\ad_password_expiration_parallel.ps1 -BatchSize 25 -MaxConcurrentJobs 2

# Neden bu değerler?
# - Sınırlı RAM = küçük batch'ler
# - Az CPU = az concurrent job
# - Güvenli işlem = yavaş ama kararlı
```

### **Senaryo 5: Yüksek Performanslı Sunucu**
```powershell
# Sistem: 32 CPU, 64 GB RAM
.\ad_password_expiration_parallel.ps1 -BatchSize 300 -MaxConcurrentJobs 12

# Neden bu değerler?
# - Çok RAM = büyük batch'ler
# - Çok CPU = çok concurrent job
# - Maksimum hız = 1-3 dakika
```

### **Senaryo 6: Dual Domain Environment**
```powershell
# İki domain, her biri 5,000 kullanıcı
.\ad_password_expiration_parallel.ps1 `
    -DomainA "contoso.com" `
    -DomainB "fabrikam.com" `
    -BatchSize 150 `
    -MaxConcurrentJobs 6

# Neden bu değerler?
# - İki domain = orta batch'ler
# - Toplam 10K kullanıcı = yüksek concurrent job
# - Paralel işlem = 3-6 dakika
```

## 📊 Performans Karşılaştırması

| Senaryo | BatchSize | MaxConcurrentJobs | Toplam Eşzamanlı | Beklenen Süre |
|---------|------------|-------------------|------------------|----------------|
| Küçük Şirket | 50 | 3 | 150 | 30-60 saniye |
| Orta Şirket | 100 | 5 | 500 | 2-5 dakika |
| Büyük Şirket | 200 | 8 | 1,600 | 5-10 dakika |
| Düşük Kaynak | 25 | 2 | 50 | 1-3 dakika |
| Yüksek Performans | 300 | 12 | 3,600 | 1-3 dakika |
| Dual Domain | 150 | 6 | 900 | 3-6 dakika |

## 🎯 Optimizasyon Stratejileri

### **Strateji 1: Kademeli Artırma**
```powershell
# 1. Adım: Güvenli başlangıç
.\ad_password_expiration_parallel.ps1 -BatchSize 50 -MaxConcurrentJobs 2

# 2. Adım: Performans testi
.\ad_password_expiration_parallel.ps1 -BatchSize 100 -MaxConcurrentJobs 4

# 3. Adım: Maksimum performans
.\ad_password_expiration_parallel.ps1 -BatchSize 200 -MaxConcurrentJobs 8
```

### **Strateji 2: Kaynak Bazlı Optimizasyon**
```powershell
# RAM kullanımına göre
if ($AvailableRAM -lt 4GB) {
    $BatchSize = 25
    $MaxConcurrentJobs = 2
}
elseif ($AvailableRAM -lt 16GB) {
    $BatchSize = 100
    $MaxConcurrentJobs = 4
}
else {
    $BatchSize = 200
    $MaxConcurrentJobs = 8
}
```

### **Strateji 3: Kullanıcı Sayısı Bazlı**
```powershell
# Kullanıcı sayısına göre
if ($UserCount -lt 1000) {
    $BatchSize = 50
    $MaxConcurrentJobs = 3
}
elseif ($UserCount -lt 10000) {
    $BatchSize = 100
    $MaxConcurrentJobs = 5
}
else {
    $BatchSize = 200
    $MaxConcurrentJobs = 8
}
```

## ⚠️ Dikkat Edilmesi Gerekenler

### **BatchSize Çok Büyükse:**
- ❌ Yüksek bellek kullanımı
- ❌ Uzun işlem süreleri
- ❌ Timeout riski
- ✅ Daha az job overhead

### **BatchSize Çok Küçükse:**
- ❌ Çok fazla job oluşturma
- ❌ Yüksek overhead
- ❌ Yavaş performans
- ✅ Düşük bellek kullanımı

### **MaxConcurrentJobs Çok Büyükse:**
- ❌ CPU overload
- ❌ Bellek tükenmesi
- ❌ AD DC'ye aşırı yük
- ✅ Maksimum paralellik

### **MaxConcurrentJobs Çok Küçükse:**
- ❌ Düşük CPU kullanımı
- ❌ Yavaş performans
- ❌ Kaynak israfı
- ✅ Kararlı sistem

## 🔍 Test ve Ölçüm

### **Performans Testi:**
```powershell
# Test scripti çalıştır
.\performance_comparison.ps1 -TestUserCount 1000

# Sonuçları analiz et
# - İşlem süresi
# - Bellek kullanımı
# - CPU kullanımı
# - Hata oranı
```

### **Optimum Değer Bulma:**
```powershell
# 1. Küçük değerlerle başla
$BatchSize = 25
$MaxConcurrentJobs = 2

# 2. Performansı ölç
$StartTime = Get-Date
# Script çalıştır
$EndTime = Get-Date
$Duration = $EndTime - $StartTime

# 3. Değerleri artır ve tekrar test et
# 4. En iyi performansı bul
```

## 📈 Beklenen Performans Artışları

| Mevcut Durum | Yeni Durum | Performans Artışı |
|---------------|------------|-------------------|
| Sequential | BatchSize=100, Jobs=5 | %70-80 |
| BatchSize=50 | BatchSize=200 | %30-40 |
| Jobs=2 | Jobs=8 | %60-70 |
| Tek Domain | Dual Domain Parallel | %50-60 |

Bu rehber, farklı ortamlar için optimal BatchSize ve MaxConcurrentJobs değerlerini belirlemenize yardımcı olacaktır.
