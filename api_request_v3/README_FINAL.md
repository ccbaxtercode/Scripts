# 🚀 API Request Script

NTLM, Basic Auth ve Bearer Token destekli API çağrı scripti.

## ✨ Özellikler

- 🔐 **3 Auth Türü**: Basic, NTLM, Bearer Token
- 🔄 **Retry**: 3 otomatik deneme (429, 500, 502, 503, 504)
- ⏱️ **Timeout**: Connection ve read timeout ayrı
- 🛡️ **SSL Kontrolü**: Esnek SSL doğrulama
- 📊 **DEBUG Logging**: Detaylı log
- 🎯 **7 HTTP Metodu**: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS

## 📦 Kurulum

```bash
pip install requests requests-ntlm urllib3
```

## 🎯 HTTP Metodları

### GET - Veri Çekme

**Basic Auth:**
```yaml
environment:
  API_URL: "https://api.example.com/users"
  API_METHOD: "GET"
  API_AUTH_TYPE: "basic"
  API_USERNAME: "admin"
  API_PASSWORD: "{{ vault_password }}"
command: python3 scripts/api_request.py
```

**Bearer Token:**
```yaml
environment:
  API_URL: "https://api.example.com/users/123"
  API_METHOD: "GET"
  API_AUTH_TYPE: "bearer"
  API_TOKEN: "{{ vault_token }}"
command: python3 scripts/api_request.py
```

**NTLM Auth:**
```yaml
environment:
  API_URL: "https://sharepoint.corp.com/_api/web/lists"
  API_METHOD: "GET"
  API_AUTH_TYPE: "ntlm"
  API_USERNAME: "john.doe"
  API_PASSWORD: "{{ vault_password }}"
  API_DOMAIN: "CORP"
  API_VERIFY_SSL: "false"
command: python3 scripts/api_request.py
```

### POST - Yeni Kayıt

**JSON Body ile:**
```yaml
environment:
  API_URL: "https://api.example.com/users"
  API_METHOD: "POST"
  API_AUTH_TYPE: "bearer"
  API_TOKEN: "{{ vault_token }}"
  API_DATA: |
    {
      "name": "Jane Doe",
      "email": "jane@example.com",
      "role": "developer"
    }
command: python3 scripts/api_request.py
```

**SharePoint örnek:**
```yaml
environment:
  API_URL: "https://sharepoint.corp.com/_api/web/lists/getbytitle('Tasks')/items"
  API_METHOD: "POST"
  API_AUTH_TYPE: "ntlm"
  API_USERNAME: "service.account"
  API_PASSWORD: "{{ vault_password }}"
  API_DOMAIN: "CORP"
  API_HEADERS: '{"Accept": "application/json;odata=verbose", "Content-Type": "application/json;odata=verbose"}'
  API_DATA: '{"__metadata": {"type": "SP.Data.TasksListItem"}, "Title": "New Task"}'
command: python3 scripts/api_request.py
```

### PUT - Tam Güncelleme

```yaml
environment:
  API_URL: "https://api.example.com/users/123"
  API_METHOD: "PUT"
  API_AUTH_TYPE: "bearer"
  API_TOKEN: "{{ vault_token }}"
  API_DATA: |
    {
      "name": "Jane Doe Updated",
      "email": "jane.new@example.com",
      "status": "active"
    }
command: python3 scripts/api_request.py
```

### PATCH - Kısmi Güncelleme

```yaml
environment:
  API_URL: "https://api.example.com/users/123"
  API_METHOD: "PATCH"
  API_AUTH_TYPE: "bearer"
  API_TOKEN: "{{ vault_token }}"
  API_DATA: '{"status": "inactive"}'
command: python3 scripts/api_request.py
```

### DELETE - Kayıt Silme

```yaml
environment:
  API_URL: "https://api.example.com/users/123"
  API_METHOD: "DELETE"
  API_AUTH_TYPE: "bearer"
  API_TOKEN: "{{ vault_token }}"
command: python3 scripts/api_request.py
```

### HEAD - Header Kontrolü

```yaml
environment:
  API_URL: "https://api.example.com/users/123"
  API_METHOD: "HEAD"
  API_AUTH_TYPE: "basic"
  API_USERNAME: "admin"
  API_PASSWORD: "{{ vault_password }}"
command: python3 scripts/api_request.py
```

### OPTIONS - İzin Kontrolü

```yaml
environment:
  API_URL: "https://api.example.com/users"
  API_METHOD: "OPTIONS"
  API_AUTH_TYPE: "bearer"
  API_TOKEN: "{{ vault_token }}"
command: python3 scripts/api_request.py
```

## 🔐 Authentication Türleri

### 1. Basic Authentication
```yaml
API_AUTH_TYPE: "basic"
API_USERNAME: "admin"
API_PASSWORD: "{{ vault_password }}"
```

### 2. NTLM Authentication
```yaml
API_AUTH_TYPE: "ntlm"
API_USERNAME: "john.doe"
API_PASSWORD: "{{ vault_password }}"
API_DOMAIN: "CORP"
```

### 3. Bearer Token
```yaml
API_AUTH_TYPE: "bearer"
API_TOKEN: "{{ vault_token }}"
```

## 📋 Environment Değişkenler

| Değişken | Zorunlu | Varsayılan | Açıklama |
|----------|---------|------------|----------|
| `API_URL` | ✅ | - | API endpoint |
| `API_METHOD` | ❌ | GET | GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS |
| `API_AUTH_TYPE` | ✅ | - | basic, ntlm, bearer |
| `API_TOKEN` | ⚠️ Bearer için | - | Bearer token |
| `API_USERNAME` | ⚠️ Basic/NTLM için | - | Kullanıcı adı |
| `API_PASSWORD` | ⚠️ Basic/NTLM için | - | Şifre |
| `API_DOMAIN` | ⚠️ NTLM için | - | Windows domain |
| `API_HEADERS` | ❌ | {} | JSON formatında headers |
| `API_DATA` | ❌ | - | JSON formatında body |
| `API_TIMEOUT` | ❌ | 10,30 | Connection,Read timeout (saniye) |
| `API_VERIFY_SSL` | ❌ | true | SSL doğrulama (true/false) |

## 🎯 Gerçek Dünya Örnekleri

### Microsoft Graph API
```yaml
- name: Azure AD kullanıcıları
  environment:
    API_URL: "https://graph.microsoft.com/v1.0/users"
    API_METHOD: "GET"
    API_AUTH_TYPE: "bearer"
    API_TOKEN: "{{ oauth_token }}"
  command: python3 scripts/api_request.py
  register: graph_users
```

### Jenkins CI/CD
```yaml
- name: Build tetikle
  environment:
    API_URL: "https://jenkins.company.com/job/MyProject/build"
    API_METHOD: "POST"
    API_AUTH_TYPE: "basic"
    API_USERNAME: "{{ jenkins_user }}"
    API_PASSWORD: "{{ jenkins_token }}"
  command: python3 scripts/api_request.py
```

### SharePoint REST API
```yaml
- name: Liste öğeleri
  environment:
    API_URL: "https://sharepoint.corp.com/_api/web/lists/getbytitle('Tasks')/items"
    API_METHOD: "GET"
    API_AUTH_TYPE: "ntlm"
    API_USERNAME: "{{ vault_username }}"
    API_PASSWORD: "{{ vault_password }}"
    API_DOMAIN: "CORP"
    API_VERIFY_SSL: "false"
  command: python3 scripts/api_request.py
```

## 📊 Response Formatı

**Başarılı:**
```json
{
  "status_code": 200,
  "ok": true,
  "elapsed_seconds": 0.45,
  "headers": {"Content-Type": "application/json"},
  "body": {"id": 1, "name": "John"}
}
```

**Hata:**
```json
{
  "error": "Timeout: HTTPConnectionPool..."
}
```

## 🔧 Response İşleme

```yaml
- name: API çağrısı
  environment:
    API_URL: "{{ api_url }}"
    API_METHOD: "GET"
    API_AUTH_TYPE: "bearer"
    API_TOKEN: "{{ vault_token }}"
  command: python3 scripts/api_request.py
  register: api_result

- set_fact:
    api_response: "{{ api_result.stdout | from_json }}"

- debug:
    msg: "Status: {{ api_response.status_code }}"

- fail:
    msg: "API hatası"
  when: api_response.status_code >= 400
```

## 🛡️ Güvenlik

### Ansible Vault
```bash
# Vault oluştur
ansible-vault create vars/vault.yml

# İçerik
vault_api_password: "SecretPass123"
vault_token: "eyJhbGciOiJIUzI1NiIs..."
```

### Playbook'ta Kullanım
```yaml
vars_files:
  - vars/vault.yml

tasks:
  - name: API çağrısı
    no_log: true  # ✅ ÖNEMLİ
    environment:
      API_PASSWORD: "{{ vault_api_password }}"
      API_TOKEN: "{{ vault_token }}"
    command: python3 scripts/api_request.py
```

## ⏱️ Timeout Ayarları

```yaml
# Varsayılan (10s connection, 30s read)
API_TIMEOUT: "10,30"

# Hızlı
API_TIMEOUT: "5,10"

# Uzun işlemler
API_TIMEOUT: "30,120"

# Her ikisi aynı
API_TIMEOUT: "20"
```

## 🔄 Retry Mekanizması

- **Otomatik:** 3 deneme
- **Backoff:** 1s → 2s → 4s
- **HTTP Kodları:** 429, 500, 502, 503, 504
- **Tüm metodlar** için çalışır

## 🐛 Troubleshooting

### requests_ntlm bulunamadı
```bash
pip install requests-ntlm
```

### SSL Certificate hatası
```yaml
API_VERIFY_SSL: "false"  # Geçici çözüm
```

### Timeout hatası
```yaml
API_TIMEOUT: "30,60"  # Süreyi artır
```

### NTLM başarısız
```yaml
# Kontrol:
API_DOMAIN: "CORP"       # Büyük harf
API_USERNAME: "john.doe"  # Domain prefix YOK
API_PASSWORD: "{{ vault_api_password }}"  # Vault kullanın
```

## 📚 Değişiklikler (v3.0)

- ✅ Bearer Token desteği eklendi
- ✅ PATCH metodu eklendi
- ✅ HEAD ve OPTIONS metodları eklendi
- ✅ Metod validasyonu eklendi
- ✅ Exception handling iyileştirildi
- ✅ HEAD için body kontrolü eklendi
- ✅ Retry `allowed_methods` kullanıyor

## 📄 Lisans

MIT
