# vCenter VM Oluşturma Otomasyonu

## Genel Bakış
Bu Ansible role, AWX/Tower üzerinden vCenter'da otomatik sanal makine oluşturmayı sağlar.

## Özellikler

### ✅ Tamamlanan Özellikler
- **VM parametreleri belirleme**: vCenter, datacenter, network, spec, template
- **Personal VM isimlendirme**: Otomatik VDI-KADIR01 formatı (01-99)
- **Hybrid kontrol**: AD (role) + vCenter (Python async)
- **Preflight checks**: Servis erişim kontrolü
- **Datacenter-aware**: Yerleşke bazlı datacenter/cluster/folder seçimi
- **Error safety**: Rescue block ile hata güvenliği

## Klasör Yapısı

```
vcenter_vm_automation/
├── roles/
│   └── vcenter_vm_create/
│       ├── defaults/
│       │   └── main.yml                       # Sabit değişkenler
│       ├── tasks/
│       │   ├── main.yml                       # Ana task akışı
│       │   ├── find_personal_vm_name.yml      # Preflight + Loop
│       │   └── check_single_index.yml         # AD → vCenter → Decision
│       ├── files/
│       │   ├── preflight_vcenters.py          # vCenter connectivity test
│       │   └── check_vcenter.py               # Single VM check
│       └── README.md
├── playbook.yml
├── Dockerfile                                  # AWX EE
└── requirements.txt                            # Python dependencies
```

## Gereksinimler

### Ansible Collections
```bash
ansible-galaxy collection install community.vmware
ansible-galaxy collection install ansible.windows
ansible-galaxy collection install community.windows
```

### Python Modülleri
```bash
pip install pyvmomi
```

### Ansible Roles (Dış Bağımlılık)
- **ad_computer_check**: AD'de computer object kontrolü
  - Input: `computer_name`, `domain_admin`, `domain_password`, `domain_fqdn`
  - Output: `ad_computer_found` (boolean)

### Sistem Gereksinimleri
- Ansible 2.11+ (break_when için)
- Python 3.8+
- vCenter API erişimi (TCP 443)

## AWX Survey Parametreleri

| Parametre | Tip | Açıklama | Örnek |
|-----------|-----|----------|-------|
| `vm_name` | text | VM adı (Personal client için `personal` yazın) | `SRV-WEB01` veya `personal` |
| `vm_spec` | choice | VM kaynak seviyesi | `standart`, `advanced`, `dev` |
| `domain` | choice | Domain seçimi | `domain1`, `domain2` |
| `yerleske` | choice | Yerleşke (datacenter belirler) | `a`, `b`, `c` |
| `os` | choice | İşletim sistemi | `windows10`, `ubuntu2004`, `ubuntu2204`, `centos` |
| `username` | text | Personal VM: Makine sahibi / Diğer: Talep sahibi | `kadir`, `ahmet.yilmaz` |
| `service_desk_no` | text | Talep numarası | `INC0012345` |
| `task` | text | **"otomasyon"** = Client / **IP adresi** = Server | `otomasyon` veya `192.168.1.100/24,192.168.1.1,8.8.8.8` |

## Mimari Tasarım

### Datacenter Yapısı
- **vCenter1**: 2 datacenter (a, b)
- **vCenter2**: 1 datacenter (c)
- Her datacenter: Kendi cluster, client/server folder, client/server network

```yaml
datacenter_config:
  a:  # yerleşke
    datacenter_name: "DC-A"
    datacenter_path: "/DC-A/vm"
    cluster: "Cluster-A"
    folders:
      clients: "Clients"
      servers: "Servers"
    networks:
      client: "VLAN-A-Client"
      server: "VLAN-A-Server"
```

### İş Akışı

#### 1. OS Type Belirleme
```
task = "otomasyon" → Client (DHCP)
task = "IP adresi" → Server (Static IP)
```

#### 2. Personal VM İsimlendirme (Opsiyonel)
**Tetiklenme**: `vm_name = "personal"` VE `task = "otomasyon"`

**Kontrol Sırası**:
```
For index 01-99:
  1. AD kontrolü (Windows ise)
     → Varsa: Skip
  2. vCenter kontrolü (Python paralel)
     → Varsa: Skip
     → Script hata: Güvenli skip
  3. Her ikisi de yok: Kullan!
```

**İsimlendirme**:
- Windows: `VDI-<KULLANICIADI>XX` (VDI-KADIR01)
- Linux: `L-<KULLANICIADI>XX` (L-KADIR01)

#### 3. Preflight Checks
- **vCenter**: Paralel connectivity test (Python)
- **AD**: Dummy VM ile connection test (Role)
- Başarısız: Job durur, detaylı hata

#### 4. VM Parametreleri
- Yerleşke → Datacenter, Cluster
- OS Type → Folder (clients/servers), Network (client/server)
- VM Spec → CPU, RAM, Disk
- OS → Template, Guest ID
- Windows → Domain Join, OU Path

## Kullanım

### Standart Server VM
```bash
ansible-playbook playbook.yml \
  -e "vm_name=SRV-WEB01" \
  -e "vm_spec=advanced" \
  -e "yerleske=a" \
  -e "domain=domain1" \
  -e "os=ubuntu2204" \
  -e "username=admin" \
  -e "service_desk_no=INC123456" \
  -e "task=192.168.1.100/24,192.168.1.1,8.8.8.8"
```

### Personal Client VM (Windows)
```bash
ansible-playbook playbook.yml \
  -e "vm_name=personal" \
  -e "vm_spec=standart" \
  -e "yerleske=b" \
  -e "domain=domain1" \
  -e "os=windows10" \
  -e "username=kadir" \
  -e "service_desk_no=INC789012" \
  -e "task=otomasyon"
# Otomatik: VDI-KADIR01
```

## AWX Execution Environment

### Build
```bash
# Dockerfile ve requirements.txt hazır
docker build -t vcenter-automation-ee:1.0 .
docker push registry.example.com/vcenter-automation-ee:1.0
```

### Configure AWX
```
1. Administration > Execution Environments > Add
2. Image: registry.example.com/vcenter-automation-ee:1.0
3. Job Template > Execution Environment: vcenter-automation-ee
```

## Hata Kontrolü

### Preflight Hataları
```
vCenter timeout → FAIL (detaylı log)
AD connection error → FAIL (Windows için)
```

### Personal VM Hataları
```
99 VM dolu → FAIL
vCenter script error → Skip index (güvenli)
```

## Performans

### Normal Senaryo (Index 02 boş)
```
Preflight: 1.5s (paralel)
Index 01: AD 0.3s → Skip
Index 02: AD 0.3s + vCenter 0.5s = 0.8s
Total: 2.6s
```

### Avantajlar
- AD öncelikli kontrol (vCenter'a sorguyu atlar)
- Paralel vCenter sorguları
- Connection pooling
- Early exit (break_when)
- Rescue block (script hatalarında güvenli)

## Notlar

### Güvenlik
- Credentials: Environment variables (güvenli)
- Vault kullanımı: vCenter ve domain şifreleri
- Minimum yetki prensibi

### Özelleştirme
- `defaults/main.yml`: Tüm sabit değerler
- Datacenter config: Her yerleşke için cluster, folder, network
- VM specs: CPU, RAM, Disk ayarları
- Domain info: OU paths, AD credentials

## Destek
- ServiceDesk: support@example.com
- Documentation: https://wiki.example.com/vcenter-automation
