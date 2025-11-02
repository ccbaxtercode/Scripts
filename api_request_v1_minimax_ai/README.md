# Ansible Python API Client

Bu proje, Ansible playbook'ları içerisinden Python kodu kullanarak REST API çağrıları yapmak için geliştirilmiş bir çözümdür. Gelişmiş retry mekanizması, güvenli authentication (Basic ve NTLM), SSL kontrolü ve kapsamlı hata yönetimi özellikleri içerir.

## 🚀 Özellikler

### 🔧 **Temel Özellikler**
- ✅ **Multi-HTTP Method Desteği**: GET, POST, PUT, DELETE, PATCH
- ✅ **Authentication Desteği**: Basic Auth ve NTLM
- ✅ **JSON Body/Response**: Otomatik JSON parse ve serileştirme
- ✅ **SSL Kontrolü**: Self-signed sertifikaları destekler
- ✅ **Custom Headers**: Özel HTTP header desteği
- ✅ **JSON Output**: Ansible tarafından parse edilebilir çıktı

### 🔄 **Gelişmiş Retry Mekanizması**
- **Akıllı Retry**: 3 deneme hakkı (yapılandırılabilir)
- **Exponential Backoff**: Artan bekleme süreleri (1s, 2s, 4s...)
- **Farklı Hata Tipleri**: Network timeout, connection error, HTTP error
- **Retry Delay**: Sabit veya artan bekleme seçenekleri

### 🛡️ **Güvenlik Özellikleri**
- ✅ **Ansible Vault Uyumlu**: Şifreli değişkenler
- ✅ **Environment Variables**: Hassas bilgiler için güvenli yapı
- ✅ **no_log**: Log dosyalarında hassas bilgileri gizleme

## 📁 Dosya Yapısı

```
.
├── api_request.py          # Ana Python script (retry mekanizması)
├── api_playbook.yml        # Ansible playbook
├── README.md              # Bu dosya
└── vars/
    └── api_vars.yml       # API değişkenleri (opsiyonel)
```

## 🔧 Kurulum

### **1. Python Bağımlılıkları**
```bash
pip install requests requests-ntlm
```

### **2. Ansible Versiyonu**
Ansible 2.9+ önerilir.

## 📋 Kullanım

### **Basit Kullanım (Basic Auth)**
```bash
# Temel GET isteği
ansible-playbook api_playbook.yml \
  -e "api_url=https://api.example.com/users \
      api_auth_type=basic \
      api_username=admin \
      api_password=secret123"
```

### **Gelişmiş Kullanım (NTLM Auth)**
```bash
# NTLM authentication ile POST isteği
ansible-playbook api_playbook.yml \
  -e "api_url=https://api.example.com/create \
      api_auth_type=ntlm \
      api_username=user1 \
      api_password=secret123 \
      api_domain=CORP \
      api_method=POST \
      api_data='{\"name\": \"test\", \"value\": 123}' \
      api_max_retries=5 \
      api_retry_delay=3"
```

## ⚙️ Environment Variables

### **Temel Değişkenler**
| Değişken | Açıklama | Gerekli | Varsayılan |
|----------|----------|---------|------------|
| `API_URL` | API endpoint URL'i | ✅ | - |
| `API_METHOD` | HTTP method | ❌ | GET |
| `API_AUTH_TYPE` | Authentication tipi (basic/ntlm) | ✅ | - |
| `API_USERNAME` | Kullanıcı adı | ✅ | - |
| `API_PASSWORD` | Şifre | ✅ | - |

### **Opsiyonel Değişkenler**
| Değişken | Açıklama | Varsayılan |
|----------|----------|------------|
| `API_DOMAIN` | NTLM domain (NTLM için gerekli) | - |
| `API_HEADERS` | JSON format custom headers | - |
| `API_DATA` | JSON format request body | - |
| `API_TIMEOUT` | Timeout saniye cinsinden | 30 |
| `API_VERIFY_SSL` | SSL doğrulama (true/false) | true |
| `API_MAX_RETRIES` | Maksimum deneme sayısı | 3 |
| `API_RETRY_DELAY` | Denemeler arası bekleme (saniye) | 5 |
| `API_RETRY_BACKOFF` | Exponential backoff (true/false) | true |

### **Örnek Environment Variables**

```bash
export API_URL="https://api.example.com/data"
export API_METHOD="POST"
export API_AUTH_TYPE="basic"
export API_USERNAME="admin"
export API_PASSWORD="secret123"
export API_HEADERS='{"Content-Type": "application/json", "X-Custom-Header": "custom-value"}'
export API_DATA='{"id": 123, "name": "test"}'
export API_TIMEOUT="15"
export API_MAX_RETRIES="5"
export API_RETRY_DELAY="3"
export API_RETRY_BACKOFF="true"
export API_VERIFY_SSL="false"
```

## 🔄 Retry Mekanizması

### **Hata Tipleri**
- **Network Hataları**: Connection timeout, DNS error
- **HTTP Hataları**: 4xx, 5xx status codes
- **Timeout Hataları**: Request timeout

### **Exponential Backoff**
```bash
# Varsayılan (artar): 1s → 2s → 4s → 8s...
API_RETRY_BACKOFF=true

# Sabit bekleme
API_RETRY_BACKOFF=false
# 3s → 3s → 3s...
```

### **Retry Örneği**
```json
{
  "status_code": 503,
  "ok": false,
  "headers": {...},
  "body": {"error": "Service Temporarily Unavailable"},
  "attempt": 1,  // 3 deneme yapıldıysa attempt = 3
  "url": "https://api.example.com/endpoint",
  "method": "POST"
}
```

## 📊 Çıktı Formatı

### **Başarılı Response**
```json
{
  "status_code": 200,
  "ok": true,
  "headers": {
    "Content-Type": "application/json",
    "Server": "nginx"
  },
  "body": {
    "success": true,
    "data": {...}
  },
  "attempt": 1,
  "url": "https://api.example.com/endpoint",
  "method": "POST"
}
```

### **Hatalı Response**
```json
{
  "status_code": 401,
  "ok": false,
  "headers": {...},
  "body": {"error": "Unauthorized"},
  "attempt": 1,
  "url": "https://api.example.com/endpoint",
  "method": "GET"
}
```

### **Tüm Denemeler Başarısız**
```json
{
  "error": "HTTP 503 - Service Temporarily Unavailable",
  "status_code": 503,
  "body": {"error": "Service Unavailable"},
  "attempts": 3,
  "final": true
}
```

## 🛡️ Güvenlik

### **1. Ansible Vault Kullanımı**
```bash
# Şifreli dosya oluştur
ansible-vault create secrets.yml

# secrets.yml içeriği:
# vault_api_password: "şifreli_sifre"
```

```yaml
# api_playbook.yml
vars_files:
  - vars/api_vars.yml
  - secrets.yml  # Şifreli dosya

tasks:
  - name: API çağrısı
    environment:
      API_PASSWORD: "{{ vault_api_password }}"
```

### **2. no_log Özelliği**
```yaml
tasks:
  - name: Hassas işlem
    no_log: true  # Şifreler log'da görünmez
    command: python3 api_request.py
```

## 🔍 Troubleshooting

### **Sık Karşılaşılan Sorunlar**

#### **1. requests_ntlm Eksik**
```bash
pip install requests requests-ntlm
```

#### **2. SSL Sertifika Hatası**
```bash
# Self-signed sertifika için
export API_VERIFY_SSL=false
```

#### **3. NTLM Domain Sorunu**
```bash
# Doğru format: DOMAIN\username
export API_DOMAIN="CORP"
export API_USERNAME="user1"
```

#### **4. JSON Parse Hatası**
```bash
# API_DATA ve API_HEADERS JSON format olmalı
export API_DATA='{"key": "value"}'  # ✅ Doğru
export API_DATA='{"key": "value"}'  # ❌ Hatalı
```

### **Debug Modu**
```bash
# Ek log çıktısı için
export ANSIBLE_VERBOSITY=3
ansible-playbook api_playbook.yml -vvv
```

## 📈 Performans

### **Timeout Ayarları**
- **Kısa timeout (5-10s)**: Hızlı API'ler için
- **Orta timeout (15-30s)**: Genel kullanım
- **Uzun timeout (60s+)**: Büyük veri transferleri

### **Retry Stratejisi**
- **Az retry (1-2)**: Sabit API'ler için
- **Orta retry (3-4)**: Genel kullanım
- **Çok retry (5+)**: Kararsız API'ler için

## 🧪 Test Senaryoları

### **1. Başarılı API Testi**
```bash
ansible-playbook api_playbook.yml \
  -e "api_url=https://httpbin.org/get \
      api_auth_type=basic \
      api_username=test \
      api_password=test"
```

### **2. 500 Error Testi**
```bash
# httpbin.org/500 ile 500 error test edebilirsiniz
```

### **3. Timeout Testi**
```bash
# httpbin.org/delay/10 ile timeout test edebilirsiniz
```

### **4. Network Error Testi**
```bash
# Yanlış URL ile connection error test edebilirsiniz
```

## 📝 Log Analizi

### **Console Log Örnekleri**
```
[INFO] POST https://api.example.com/create
[INFO] Auth: BASIC, Timeout: 30s, Max Retries: 3
[INFO] Verify SSL: true, Retry Delay: 5s

[DENEME 1/3] API isteği gönderiliyor...
[TIMEOUT] Deneme 1: HTTPConnectionPool(host='api.example.com', port=80): Read timed out.
[YENIDEN DENEME] 5 saniye bekleniyor...
[BACKOFF] Artan bekleme süresi: 5s

[DENEME 2/3] API isteği gönderiliyor...
[BAŞARILI] HTTP 200 - Deneme 2
```

## 🔗 Örnek Kullanım Senaryoları

### **1. Jenkins API Entegrasyonu**
```bash
ansible-playbook api_playbook.yml \
  -e "api_url=https://jenkins.company.com/api/json \
      api_auth_type=basic \
      api_username=admin \
      api_password={{ vault_jenkins_password }}"
```

### **2. ServiceNow Entegrasyonu**
```bash
ansible-playbook api_playbook.yml \
  -e "api_url=https://instance.service-now.com/api/now/table/incident \
      api_auth_type=basic \
      api_username=admin \
      api_password={{ vault_servicenow_password }} \
      api_method=POST \
      api_data='{\"short_description\": \"Test incident\", \"priority\": 3}'"
```

### **3. GitHub API Kullanımı**
```bash
ansible-playbook api_playbook.yml \
  -e "api_url=https://api.github.com/repos/user/repo \
      api_auth_type=basic \
      api_username={{ vault_github_username }} \
      api_password={{ vault_github_token }}"
```

## 🤝 Katkıda Bulunma

1. Fork yapın
2. Feature branch oluşturun (`git checkout -b feature/amazing-feature`)
3. Değişikliklerinizi commit edin (`git commit -m 'Add amazing feature'`)
4. Branch'inizi push edin (`git push origin feature/amazing-feature`)
5. Pull Request oluşturun

## 📜 Lisans

Bu proje MIT lisansı altında lisanslanmıştır.

## 📞 Destek

Sorularınız için GitHub Issues kullanabilirsiniz.

---

**Not**: Bu proje üretim ortamında kullanılmadan önce test edilmelidir.