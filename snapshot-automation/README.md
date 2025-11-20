# Snapshot Otomasyon Projesi

VMware vCenter ortamlarında otomatik snapshot alma işlemlerini gerçekleştiren Ansible + Python tabanlı otomasyon projesi.

## Proje Yapısı

```
snapshot-automation/
├── main.yaml                        # Ana playbook - parametre kontrolleri
├── snapshot_create.yaml             # Snapshot alma işlemleri
├── files/
│   └── find_vms_for_snapshot.py    # Python - VM bulma ve parametre toplama
└── vars/
    └── vcenter_mapping.yaml        # vCenter/domain/datacenter mapping
```

## Ortam Bilgileri

- **vCenter Sayısı**: 2 adet
- **Domain Sayısı**: 2 adet (domain1, domain2)
- **AWX Versiyonu**: 24.4.0 (K3s üzerinde)

### vCenter ve Domain Yapısı

- **domain1**: vCenter1 (DC1, DC2) ve vCenter2 (DC3) üzerinde bulunur
- **domain2**: Sadece vCenter2 (DC3) üzerinde `/DC3/vm/Domain2` klasöründe bulunur

## Survey Parametreleri

| Parametre | Açıklama | Kısıtlama |
|-----------|----------|-----------|
| `username` | İşlemi yapan kullanıcı adı | - |
| `snapshot_retention_days` | Snapshot tutulma süresi | 1-15 gün arası |
| `service_desk_no` | Servis desk numarası (unique) | Schedule adı olarak kullanılır |
| `domain` | Domain bilgisi | domain1 veya domain2 |
| `server_names` | Sunucu isimleri | Virgülle ayrılmış, max 10 adet |

**Not**: `operation` parametresi kaldırıldı. Şimdilik sadece snapshot alma işlemi yapılıyor.

## İş Akışı

### Snapshot Alma

```
1. Parametreleri doğrula (sunucu sayısı: max 10, gün sayısı: 1-15)
2. Domain'e göre arama yapılacak vCenter'ları belirle
3. Python script'i çalıştır:
   - Her VM için domain'e uygun vCenter/datacenter'larda ara
   - Birden fazla VM bulunursa hata ver ve atla
   - Bulunan VM'lerin parametrelerini topla (vcenter, datacenter, uuid, folder vb.)
   - JSON formatında sonuç döndür
4. Bulunan VM'lerde snapshot al
5. Snapshot'ların alındığını doğrula
6. AWX'te silme işi için schedule oluştur
   - Schedule'a VM parametrelerini de ekle (silme işinde VM bulma olmayacak)
7. Kapsamlı rapor oluştur
```

**Snapshot İsimlendirme**: `{service_desk_no}_{tarih}_{saat}`

**Schedule İsimlendirme**: `{service_desk_no}`

**Önemli**: Silme işlemi henüz implement edilmedi. Schedule oluşturulacak ancak silme playbook'u daha sonra eklenecek.

## VM Bulma Stratejisi (Python Script)

### Domain1 Seçildiğinde:
1. vCenter1/DC1'de ara
2. vCenter1/DC2'de ara
3. vCenter2/DC3'te ara
4. İlk bulduğunda dur

### Domain2 Seçildiğinde:
1. Sadece vCenter2/DC3'te `/DC3/vm/Domain2` klasöründe ara

### Birden Fazla VM Kontrolü:
- Aynı datacenter'da aynı isimde birden fazla VM varsa → Hata ver, VM'i atla
- Farklı datacenter'larda aynı isimde VM varsa → İlk bulunanı kullan

### Toplanan VM Parametreleri:
```json
{
  "name": "vm-name",
  "vcenter": "vcenter1",
  "vcenter_hostname": "vcenter1.example.com",
  "datacenter": "DC1",
  "folder": "/DC1/vm/folder/path",
  "uuid": "vm-uuid",
  "instance_uuid": "instance-uuid",
  "power_state": "poweredOn",
  "guest_id": "rhel8_64Guest",
  "num_cpu": 4,
  "memory_mb": 8192,
  "vm_path": "[datastore] vm/vm.vmx"
}
```

Bu parametreler snapshot silme işi için AWX schedule'ına kaydedilir.

## Gerekli Credential'lar

Playbook çalıştırılırken aşağıdaki değişkenler sağlanmalıdır:

### vCenter Credential'ları (Environment Variables)
```bash
export VC_USER="vcenter_kullanici_adi"
export VC_PASS="vcenter_sifre"
```

veya Ansible extra_vars:
```yaml
vcenter_username: "vcenter_kullanici_adi"
vcenter_password: "vcenter_sifre"
```

### AWX Credential'ları
```yaml
awx_host: "https://awx.example.com"
awx_username: "awx_kullanici_adi"
awx_password: "awx_sifre"
```

### Python Gereksinimleri
```bash
pip install pyvmomi pyVim
```

## Rapor Formatı

Her işlem sonunda aşağıdaki bilgileri içeren detaylı rapor oluşturulur:

```
===========================================
    SNAPSHOT İŞLEM RAPORU
===========================================

İşlem Bilgileri:
  - Başlangıç: 2025-01-15T10:30:00Z
  - Bitiş: 2025-01-15T10:35:00Z
  - Kullanıcı: john.doe
  - Servis Desk No: SD123456
  - İşlem Tipi: CREATE
  - Domain: domain1
  - Snapshot Tutma Süresi: 7 gün

Sunucu İstatistikleri:
  - İstenen Sunucu Sayısı: 5
  - Bulunan Sunucu Sayısı: 4
  - Bulunamayan Sunucu Sayısı: 1
  - Başarılı İşlem Sayısı: 4
  - Başarısız İşlem Sayısı: 0

Detaylar:
  İstenen Sunucular: server1, server2, server3, server4, server5
  Bulunan Sunucular: server1, server2, server3, server4
  Bulunamayan Sunucular: server5
  Başarılı İşlemler: server1, server2, server3, server4
  Başarısız İşlemler: YOK

Hatalar:
  Hata yok

===========================================
```

## Hata Yönetimi

- **Block/Rescue yapısı** kullanılır
- Her kritik adım için hata yakalama mevcuttur
- Hatalar raporda listelenir
- Tek bir VM'deki hata diğer VM'leri etkilemez

## Özellikler

✅ Domain bazlı vCenter seçimi  
✅ Datacenter bazlı VM arama (Python ile)  
✅ Folder path filtreleme (domain2 için)  
✅ Birden fazla VM kontrolü  
✅ Detaylı VM parametre toplama (uuid, folder, power_state vb.)  
✅ UUID bazlı snapshot işlemleri  
✅ Snapshot doğrulama  
✅ Otomatik schedule oluşturma (VM parametreleri dahil)  
✅ Kapsamlı hata yönetimi  
✅ Detaylı raporlama  
✅ Maksimum 10 sunucu desteği  
✅ 1-15 gün snapshot retention  
✅ Loop işlemleri Python tarafında (performans)

## Gelecek Özellikler

⏳ Snapshot silme işlemi (schedule tarafından tetiklenecek)  
⏳ Mail bildirimleri  

## Kullanım Örneği

### AWX Survey Değerleri:

```yaml
username: "john.doe"
snapshot_retention_days: 7
service_desk_no: "SD123456"
domain: "domain1"
server_names: "web-server-01, db-server-02, app-server-03"
```

### İşlem Akışı:

1. **Parametre Kontrolü**: 3 sunucu (max 10), 7 gün (1-15 arası) ✓
2. **Python Script**: 3 VM domain1'e uygun vCenter'larda aranır
3. **VM Bulundu**: Her VM için parametreler toplandı (vcenter, datacenter, uuid vb.)
4. **Snapshot Alma**: 3 VM'de snapshot alındı
5. **Doğrulama**: Snapshot'lar doğrulandı
6. **Schedule**: 7 gün sonra silme işi oluşturuldu (VM parametreleri dahil)
7. **Rapor**: Detaylı rapor görüntülendi

## Notlar

- Schedule adı servis desk numarası ile aynıdır (unique)
- Schedule'a VM parametreleri eklenir (silme işi için VM bulma gerekmez)
- Python script VM aramayı paralel yapar (hızlı)
- Loop işlemleri Python içinde yapılır (Ansible loop'tan daha performanslı)
- UUID kullanılarak snapshot işlemleri yapılır (daha güvenli)
- Snapshot silme işlemi henüz implement edilmedi
- vCenter credential'ları environment variable veya extra_vars olarak verilebilir
- Python 3.6+ ve pyvmomi kütüphanesi gereklidir

## Geliştirici Notları

### Ansible Gereksinimleri
- Ansible 2.9+
- community.vmware collection
- awx.awx collection

### Python Gereksinimleri
- Python 3.6+
- pyvmomi
- pyVim

### Kurulum
```bash
# Ansible collections
ansible-galaxy collection install community.vmware
ansible-galaxy collection install awx.awx

# Python packages
pip3 install pyvmomi
```

### Python Script Kullanımı
```bash
# Manuel test için
export VC_USER="username"
export VC_PASS="password"

python3 files/find_vms_for_snapshot.py \
  '["vm1", "vm2"]' \
  '[{"name":"vcenter1","hostname":"vc1.example.com","datacenters":[{"name":"DC1","domain":"domain1","folder":null}]}]' \
  'domain1'
```

### Dosya İzinleri
Python script'in çalıştırılabilir olması gerekir:
```bash
chmod +x files/find_vms_for_snapshot.py
```
