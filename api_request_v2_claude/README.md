# 🚀 Ansible API Request Script

NTLM ve Basic Auth destekli, profesyonel API çağrı scripti. Retry mekanizması, SSL kontrolü, detaylı logging ve hata yönetimi içerir.

---

## 📋 İçindekiler

- [Özellikler](#-özellikler)
- [Gereksinimler](#-gereksinimler)
- [Kurulum](#-kurulum)
- [Hızlı Başlangıç](#-hızlı-başlangıç)
- [Kullanım Kılavuzu](#-kullanım-kılavuzu)
- [Environment Değişkenler](#-environment-değişkenler)
- [Örnekler](#-örnekler)
- [Hata Yönetimi](#-hata-yönetimi)
- [Güvenlik](#-güvenlik)
- [Troubleshooting](#-troubleshooting)

---

## ✨ Özellikler

### 🔐 Authentication
- **NTLM Authentication** (Windows Domain)
- **Basic Authentication** (Username/Password)

### 🔄 Retry Mekanizması
- **Otomatik yeniden deneme**: 3 kez (429, 500, 502, 503, 504 HTTP kodları için)
- **Exponential backoff**: 1s → 2s → 4s
- **Tüm HTTP metodları** için destek

### ⏱️ Timeout Kontrolü
- **Connection timeout**: Bağlantı kurma süresi (varsayılan: 10s)
- **Read timeout**: Yanıt okuma süresi (varsayılan: 30s)
- **Esnek yapılandırma**: ENV variable ile özelleştirilebilir

### 🛡️ SSL/TLS
- **SSL doğrulama** açma/kapama
- **Self-signed sertifika** desteği
- **InsecureRequestWarning** otomatik susturma

### 📊 Logging
- **DEBUG seviyesi** logging
- **Request/Response** detayları
- **Elapsed time** tracking
- **JSON formatında** çıktı

### 🎯 HTTP Metodları
- GET, POST, PUT, DELETE, PATCH
- JSON body desteği
- Custom headers

---

## 📦 Gereksinimler

### Sistem Gereksinimleri
```bash
- Python 3.6+
- Ansible 2.9+
- Linux/Unix işletim sistemi
```

### Python Kütüphaneleri
```bash
- requests
- requests-ntlm
- urllib3
```

---

## 🛠️ Kurulum

### 1. Python Bağımlılıklarını Yükleyin

```bash
pip install requests requests-ntlm urllib3
```

veya `requirements.txt` ile:

```bash
# requirements.txt oluşturun
cat > requirements.txt << EOF
requests>=2.28.0
requests-ntlm>=1.2.0
urllib3>=1.26.0
EOF

pip install -r requirements.txt
```

### 2. Proje Yapısını Oluşturun

```bash
mkdir -p ansible-api-project/scripts
cd ansible-api-project

# Script dosyasını kopyalayın
cp api_request_improved.py scripts/
chmod +x scripts/api_request_improved.py

# Playbook dosyasını kopyalayın
cp main_improved.yml .
```

### 3. Ansible Vault Oluşturun

```bash
# Vault dosyası oluştur
ansible-vault create vars/vault.yml

# İçeriğe şifreleri ekleyin:
vault_api_password: "YourSecretPassword123"
```

### 4. Proje Yapısı

```
ansible-api-project/
├── scripts/
│   └── api_request_improved.py
├── vars/
│   └── vault.yml (şifreli)
├── main_improved.yml
├── README.md
└── requirements.txt
```

---

## ⚡ Hızlı Başlangıç

### Basit GET İsteği (NTLM Auth)

```bash
ansible-playbook main_improved.yml --ask-vault-pass
```

### Playbook İçeriği (Minimal)

```yaml
---
- name: API Test
  hosts: localhost
  gather_facts: no
  
  vars_files:
    - vars/vault.yml
  
  tasks:
    - name: API çağrısı
      no_log: true
      environment:
        API_URL: "https://api.example.com/users"
        API_METHOD: "GET"
        API_AUTH_TYPE: "ntlm"
        API_USERNAME: "myuser"
        API_PASSWORD: "{{ vault_api_password }}"
        API_DOMAIN: "CORP"
      command: python3 "{{ playbook_dir }}/scripts/api_request_improved.py"
      register: api_result
    
    - debug:
        msg: "{{ api_result.stdout | from_json }}"
```

---

## 📚 Kullanım Kılavuzu

### Environment Değişkenler

| Değişken | Zorunlu | Varsayılan | Açıklama |
|----------|---------|------------|----------|
| `API_URL` | ✅ Evet | - | API endpoint URL'i |
| `API_METHOD` | ❌ Hayır | `GET` | HTTP metodu (GET, POST, PUT, DELETE) |
| `API_AUTH_TYPE` | ✅ Evet | - | Auth türü (`basic` veya `ntlm`) |
| `API_USERNAME` | ✅ Evet | - | Kullanıcı adı |
| `API_PASSWORD` | ✅ Evet | - | Şifre (Vault kullanın!) |
| `API_DOMAIN` | ⚠️ NTLM için | - | Windows domain adı |
| `API_HEADERS` | ❌ Hayır | `{}` | JSON formatında headers |
| `API_DATA` | ❌ Hayır | - | JSON formatında body (POST/PUT için) |
| `API_TIMEOUT` | ❌ Hayır | `10,30` | Connection,Read timeout (saniye) |
| `API_VERIFY_SSL` | ❌ Hayır | `true` | SSL doğrulama (`true`/`false`) |

---

## 🎯 Örnekler

### Örnek 1: GET İsteği (NTLM Auth)

```yaml
- name: Kullanıcı listesini getir
  environment:
    API_URL: "https://intranet.corp.com/api/users"
    API_METHOD: "GET"
    API_AUTH_TYPE: "ntlm"
    API_USERNAME: "john.doe"
    API_PASSWORD: "{{ vault_api_password }}"
    API_DOMAIN: "CORP"
    API_HEADERS: '{"Accept": "application/json"}'
    API_VERIFY_SSL: "false"  # self-signed sertifika için
  command: python3 "{{ playbook_dir }}/scripts/api_request_improved.py"
  register: users_result
```

### Örnek 2: POST İsteği (Basic Auth)

```yaml
- name: Yeni kullanıcı oluştur
  environment:
    API_URL: "https://api.example.com/users"
    API_METHOD: "POST"
    API_AUTH_TYPE: "basic"
    API_USERNAME: "admin"
    API_PASSWORD: "{{ vault_api_password }}"
    API_HEADERS: '{"Content-Type": "application/json"}'
    API_DATA: |
      {
        "name": "Jane Doe",
        "email": "jane@example.com",
        "role": "developer"
      }
    API_TIMEOUT: "15,45"  # 15s connection, 45s read
  command: python3 "{{ playbook_dir }}/scripts/api_request_improved.py"
  register: create_result
```

### Örnek 3: PUT İsteği (Güncelleme)

```yaml
- name: Kullanıcı bilgilerini güncelle
  environment:
    API_URL: "https://api.example.com/users/123"
    API_METHOD: "PUT"
    API_AUTH_TYPE: "ntlm"
    API_USERNAME: "admin"
    API_PASSWORD: "{{ vault_api_password }}"
    API_DOMAIN: "MYDOMAIN"
    API_DATA: '{"status": "active", "department": "IT"}'
  command: python3 "{{ playbook_dir }}/scripts/api_request_improved.py"
  register: update_result
```

### Örnek 4: DELETE İsteği

```yaml
- name: Kullanıcıyı sil
  environment:
    API_URL: "https://api.example.com/users/123"
    API_METHOD: "DELETE"
    API_AUTH_TYPE: "basic"
    API_USERNAME: "admin"
    API_PASSWORD: "{{ vault_api_password }}"
  command: python3 "{{ playbook_dir }}/scripts/api_request_improved.py"
  register: delete_result
```

### Örnek 5: Custom Headers ve Timeout

```yaml
- name: Özel header ile istek
  environment:
    API_URL: "https://api.example.com/data"
    API_METHOD: "GET"
    API_AUTH_TYPE: "basic"
    API_USERNAME: "user"
    API_PASSWORD: "{{ vault_api_password }}"
    API_HEADERS: |
      {
        "Accept": "application/json",
        "X-Custom-Header": "MyValue",
        "X-Request-ID": "12345"
      }
    API_TIMEOUT: "5,10"  # Hızlı timeout
  command: python3 "{{ playbook_dir }}/scripts/api_request_improved.py"
  register: custom_result
```

---

## 🔒 Güvenlik

### 1. Ansible Vault Kullanımı

**Vault dosyası oluşturma:**
```bash
ansible-vault create vars/vault.yml
```

**Vault dosyasını düzenleme:**
```bash
ansible-vault edit vars/vault.yml
```

**Vault içeriği örneği:**
```yaml
# vars/vault.yml
vault_api_password: "SuperSecretPassword123!"
vault_api_username: "admin"
```

### 2. no_log Kullanımı

**Hassas bilgileri loglamayın:**
```yaml
- name: API çağrısı
  no_log: true  # ⚠️ ÖNEMLİ: Şifreleri loglarda göstermez
  environment:
    API_PASSWORD: "{{ vault_api_password }}"
  command: python3 scripts/api_request_improved.py
```

### 3. SSL Doğrulama

**Production ortamda SSL'i AÇIK tutun:**
```yaml
API_VERIFY_SSL: "true"  # ✅ Varsayılan ve önerilen
```

**Sadece test ortamında kapatın:**
```yaml
API_VERIFY_SSL: "false"  # ⚠️ Sadece development için
```

---

## 🛡️ Hata Yönetimi

### Playbook İçinde Hata Yakalama

```yaml
- name: API işlemleri
  block:
    - name: API çağrısı
      environment:
        API_URL: "{{ api_endpoint }}"
        API_METHOD: "POST"
        API_AUTH_TYPE: "ntlm"
        API_USERNAME: "{{ api_user }}"
        API_PASSWORD: "{{ vault_api_password }}"
        API_DOMAIN: "{{ api_domain }}"
        API_DATA: "{{ request_body | to_json }}"
      command: python3 "{{ playbook_dir }}/scripts/api_request_improved.py"
      register: api_result
      failed_when: api_result.rc not in [0]

    - name: JSON parse et
      set_fact:
        api_json: "{{ api_result.stdout | from_json }}"

    - name: HTTP hata kontrolü
      fail:
        msg: "API hatası: HTTP {{ api_json.status_code }}"
      when: api_json.status_code >= 400

    - name: Başarılı sonuç
      debug:
        msg: "✅ İşlem başarılı: {{ api_json.status_code }}"

  rescue:
    - name: Hata loglama
      debug:
        msg: |
          ❌ API çağrısı başarısız!
          Return Code: {{ api_result.rc | default('N/A') }}
          Stdout: {{ api_result.stdout | default('') }}
          Stderr: {{ api_result.stderr | default('') }}

    - name: E-posta bildirimi gönder (opsiyonel)
      mail:
        to: admin@example.com
        subject: "API Hatası - {{ inventory_hostname }}"
        body: "{{ api_result.stderr }}"
      when: send_email_on_error | default(false)

    - name: İşlemi sonlandır
      fail:
        msg: "API çağrısı başarısız, playbook durduruluyor"
```

### HTTP Status Code Kontrolü

```yaml
- name: Sadece 2xx kabul et
  fail:
    msg: "Beklenmeyen HTTP kodu: {{ api_json.status_code }}"
  when: api_json.status_code < 200 or api_json.status_code >= 300

- name: 404 özel mesaj
  debug:
    msg: "⚠️ Kaynak bulunamadı (404)"
  when: api_json.status_code == 404

- name: 401/403 auth hatası
  fail:
    msg: "🔒 Yetkilendirme hatası: {{ api_json.status_code }}"
  when: api_json.status_code in [401, 403]
```

---

## 🔍 Troubleshooting

### Problem 1: `requests_ntlm` modülü bulunamadı

**Hata:**
```
HATA: 'requests_ntlm' modülü eksik. Kurulum: pip install requests requests-ntlm
```

**Çözüm:**
```bash
pip install requests-ntlm
# veya
pip3 install requests-ntlm
```

### Problem 2: SSL Certificate hatası

**Hata:**
```
SSL: CERTIFICATE_VERIFY_FAILED
```

**Çözüm 1 (Geçici - Test için):**
```yaml
API_VERIFY_SSL: "false"
```

**Çözüm 2 (Kalıcı - Production için):**
```bash
# Sertifikayı sisteme ekleyin
sudo cp your-cert.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

### Problem 3: Timeout hatası

**Hata:**
```
Timeout hatası: HTTPSConnectionPool... Read timed out
```

**Çözüm:**
```yaml
# Timeout süresini artırın
API_TIMEOUT: "30,60"  # connection: 30s, read: 60s
```

### Problem 4: NTLM Authentication başarısız

**Hata:**
```
401 Unauthorized
```

**Kontrol listesi:**
```yaml
# 1. Domain doğru mu?
API_DOMAIN: "CORP"  # Büyük harf önemli!

# 2. Username formatı doğru mu?
API_USERNAME: "john.doe"  # CORP\john.doe DEĞİL!

# 3. Şifre Vault'tan geliyor mu?
API_PASSWORD: "{{ vault_api_password }}"

# 4. Script doğru konumda mı?
command: python3 "{{ playbook_dir }}/scripts/api_request_improved.py"
```

### Problem 5: JSON parse hatası

**Hata:**
```
HATA: API_DATA geçersiz JSON
```

**Çözüm:**
```yaml
# YANLIŞ ❌
API_DATA: {"key": "value"}

# DOĞRU ✅
API_DATA: '{"key": "value"}'

# veya multi-line
API_DATA: |
  {
    "key": "value",
    "number": 123
  }
```

### Problem 6: Yavaş yanıt süreleri

**Optimizasyon:**
```yaml
# 1. Retry azalt (script içinde)
total=1  # 3 yerine

# 2. Timeout azalt
API_TIMEOUT: "5,10"

# 3. Connection pooling kullan (otomatik)
```

---

## 📊 Çıktı Formatı

### Başarılı İstek
```json
{
  "status_code": 200,
  "ok": true,
  "elapsed_seconds": 0.45,
  "headers": {
    "Content-Type": "application/json",
    "Content-Length": "1234"
  },
  "body": {
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com"
  }
}
```

### Başarısız İstek
```json
{
  "error": "Timeout: HTTPSConnectionPool(host='api.example.com', port=443): Read timed out. (read timeout=30)"
}
```

---

## 🚀 Gelişmiş Kullanım

### 1. Dinamik URL Oluşturma

```yaml
vars:
  api_base_url: "https://api.example.com"
  user_id: 123

tasks:
  - name: Kullanıcı detayını getir
    environment:
      API_URL: "{{ api_base_url }}/users/{{ user_id }}"
      API_METHOD: "GET"
      # ...
```

### 2. Loop ile Çoklu İstek

```yaml
- name: Tüm kullanıcıları işle
  environment:
    API_URL: "https://api.example.com/users/{{ item.id }}"
    API_METHOD: "PUT"
    API_AUTH_TYPE: "basic"
    API_USERNAME: "admin"
    API_PASSWORD: "{{ vault_api_password }}"
    API_DATA: '{"status": "active"}'
  command: python3 "{{ playbook_dir }}/scripts/api_request_improved.py"
  loop:
    - { id: 1 }
    - { id: 2 }
    - { id: 3 }
  register: update_results
```

### 3. Conditional Execution

```yaml
- name: API çağrısı (sadece production)
  environment:
    API_URL: "{{ api_url }}"
    # ...
  command: python3 scripts/api_request_improved.py
  when: 
    - environment == "production"
    - api_enabled | default(true)
```

### 4. Response Caching

```yaml
- name: Cache kontrol
  stat:
    path: "/tmp/api_cache_{{ user_id }}.json"
  register: cache_file

- name: API çağrısı (cache yoksa)
  environment:
    API_URL: "{{ api_endpoint }}"
    # ...
  command: python3 scripts/api_request_improved.py
  register: api_result
  when: not cache_file.stat.exists

- name: Cache'e yaz
  copy:
    content: "{{ api_result.stdout }}"
    dest: "/tmp/api_cache_{{ user_id }}.json"
  when: api_result is changed
```

---

## 📝 Log Örnekleri

### DEBUG Modu Aktif
```
[INFO] 2025-11-02 10:15:30 - Request: GET https://api.example.com/users (timeout: 10s connect, 30s read, verify_ssl=True)
[DEBUG] 2025-11-02 10:15:30 - Auth: NTLM (CORP\john.doe)
[DEBUG] 2025-11-02 10:15:30 - Headers: {'Accept': 'application/json'}
[INFO] 2025-11-02 10:15:31 - Response: 200 OK (0.45s)
[DEBUG] 2025-11-02 10:15:31 - Encoding düzeltildi: utf-8
[DEBUG] 2025-11-02 10:15:31 - Sonuç JSON olarak stdout'a yazıldı
```

### Retry Durumunda
```
[INFO] 2025-11-02 10:20:15 - Request: POST https://api.example.com/items
[WARNING] 2025-11-02 10:20:16 - 503 Service Unavailable - Retry 1/3 (1s sonra)
[WARNING] 2025-11-02 10:20:18 - 503 Service Unavailable - Retry 2/3 (2s sonra)
[INFO] 2025-11-02 10:20:22 - Response: 200 OK (7.12s)
```

---

## 🔧 Yapılandırma Örnekleri

### Production Ortamı
```yaml
environment:
  API_URL: "https://api.prod.company.com/v1/endpoint"
  API_METHOD: "POST"
  API_AUTH_TYPE: "ntlm"
  API_USERNAME: "svc_ansible"
  API_PASSWORD: "{{ vault_prod_password }}"
  API_DOMAIN: "PROD"
  API_HEADERS: '{"Accept": "application/json", "X-Environment": "production"}'
  API_TIMEOUT: "15,45"
  API_VERIFY_SSL: "true"  # ✅ Production'da AÇIK
```

### Development Ortamı
```yaml
environment:
  API_URL: "https://api.dev.company.com/v1/endpoint"
  API_METHOD: "GET"
  API_AUTH_TYPE: "basic"
  API_USERNAME: "testuser"
  API_PASSWORD: "{{ vault_dev_password }}"
  API_TIMEOUT: "5,10"  # Hızlı test için
  API_VERIFY_SSL: "false"  # ⚠️ Self-signed sertifika için
```

---

## 📞 Destek ve Katkı

### Sorun Bildirme
1. Hata mesajını tam olarak kaydedin
2. Ansible playbook çıktısını toplayın (`-vvv` ile)
3. Python script log'larını kontrol edin
4. Environment değişkenlerini kontrol edin (şifreler hariç!)

### Best Practices
- ✅ Ansible Vault kullanın
- ✅ `no_log: true` ekleyin
- ✅ Production'da SSL doğrulamayı açık tutun
- ✅ Timeout değerlerini test edin
- ✅ Error handling ekleyin
- ✅ Log seviyesini ayarlayın

---

## 📄 Lisans

Bu script özgürce kullanılabilir.

---

## 🎓 Ek Kaynaklar

- [Ansible Documentation](https://docs.ansible.com/)
- [requests Library](https://docs.python-requests.org/)
- [requests-ntlm](https://github.com/requests/requests-ntlm)
- [Ansible Vault Guide](https://docs.ansible.com/ansible/latest/user_guide/vault.html)

---

**Son güncelleme:** 2025-11-02  
**Versiyon:** 2.0
