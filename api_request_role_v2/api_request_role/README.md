# Ansible Role: api_request

NTLM ve Basic Auth destekli, profesyonel API çağrı role'ü. Retry mekanizması, SSL kontrolü, detaylı logging ve hata yönetimi içerir.

## Özellikler

- ✅ **Dual Authentication**: NTLM ve Basic Auth desteği
- ✅ **Retry Mekanizması**: Otomatik yeniden deneme (configurable)
- ✅ **Timeout Kontrolü**: Connection ve read timeout ayrı ayrı
- ✅ **SSL/TLS**: Esnek SSL doğrulama kontrolü
- ✅ **Error Handling**: Block/rescue ile güvenli hata yönetimi
- ✅ **JSON Support**: Request/response JSON desteği
- ✅ **Logging**: DEBUG seviyesi detaylı logging
- ✅ **HTTP Methods**: GET, POST, PUT, DELETE, PATCH

## Gereksinimler

### Sistem
- Ansible 2.9+
- Python 3.6+

### Python Paketleri
```bash
pip3 install -r files/requirements.txt
```

veya manuel:
```bash
pip3 install requests requests-ntlm urllib3
```

## Kurulum

### Ansible Galaxy (önerilen)
```bash
ansible-galaxy install username.api_request
```

### Manuel Kurulum
```bash
# Role'ü roles dizinine kopyalayın
git clone https://github.com/username/ansible-role-api-request.git roles/api_request
```

## Role Değişkenleri

### Zorunlu Değişkenler

| Değişken | Tip | Açıklama |
|----------|-----|----------|
| `api_url` | string | API endpoint URL'i |
| `api_username` | string | Kullanıcı adı |
| `api_password` | string | Şifre (Vault kullanın!) |
| `api_auth_type` | string | Auth türü: `ntlm` veya `basic` |

### Opsiyonel Değişkenler

| Değişken | Varsayılan | Açıklama |
|----------|------------|----------|
| `api_method` | `GET` | HTTP metodu |
| `api_domain` | - | NTLM için domain |
| `api_headers` | `{}` | Request headers |
| `api_data` | `{}` | Request body (POST/PUT) |
| `api_timeout_connection` | `10` | Connection timeout (saniye) |
| `api_timeout_read` | `30` | Read timeout (saniye) |
| `api_verify_ssl` | `true` | SSL doğrulama |
| `api_no_log` | `true` | Hassas bilgi loglama |
| `api_fail_on_error` | `true` | 4xx/5xx'de fail et |
| `api_retry_count` | `3` | Retry sayısı |
| `api_retry_backoff_factor` | `1` | Backoff çarpanı |

Tüm değişkenler için: `defaults/main.yml`

## Kullanım

### Basit Örnek (GET)

```yaml
- name: API GET isteği
  hosts: localhost
  
  vars_files:
    - vars/vault.yml
  
  roles:
    - role: api_request
      api_url: "https://api.example.com/users"
      api_method: "GET"
      api_auth_type: "ntlm"
      api_username: "myuser"
      api_password: "{{ vault_api_password }}"
      api_domain: "CORP"
```

### POST İsteği

```yaml
- name: API POST isteği
  hosts: localhost
  
  vars_files:
    - vars/vault.yml
  
  roles:
    - role: api_request
      api_url: "https://api.example.com/users"
      api_method: "POST"
      api_auth_type: "basic"
      api_username: "admin"
      api_password: "{{ vault_api_password }}"
      api_data:
        name: "John Doe"
        email: "john@example.com"
```

### Response Kullanımı

```yaml
- name: API çağrısı ve response işleme
  hosts: localhost
  
  tasks:
    - name: Kullanıcı listesini getir
      include_role:
        name: api_request
      vars:
        api_url: "https://api.example.com/users"
        api_auth_type: "basic"
        api_username: "{{ vault_username }}"
        api_password: "{{ vault_api_password }}"
    
    # api_response değişkeni otomatik olarak set edilir
    - name: Response'u göster
      debug:
        var: api_response.body
```

### Loop ile Çoklu İstek

```yaml
- name: Çoklu API çağrısı
  hosts: localhost
  
  tasks:
    - name: Her kullanıcıyı güncelle
      include_role:
        name: api_request
      vars:
        api_url: "https://api.example.com/users/{{ item }}"
        api_method: "PUT"
        api_auth_type: "ntlm"
        api_username: "admin"
        api_password: "{{ vault_api_password }}"
        api_domain: "CORP"
        api_data:
          status: "active"
      loop:
        - 1
        - 2
        - 3
```

## Response Formatı

Role çalıştıktan sonra `api_response` değişkeni otomatik olarak set edilir:

```yaml
api_response:
  status_code: 200
  ok: true
  elapsed_seconds: 0.45
  headers:
    Content-Type: "application/json"
  body:
    id: 1
    name: "John Doe"
```

## Örnekler

Daha fazla örnek için `examples/playbook.yml` dosyasına bakın:
- GET isteği (NTLM)
- POST isteği (Basic Auth)
- Çoklu API çağrısı
- Response işleme
- Özel timeout/retry
- DELETE isteği

## Güvenlik

### Ansible Vault Kullanımı

**Vault oluşturma:**
```bash
ansible-vault create vars/vault.yml
```

**Vault içeriği:**
```yaml
vault_api_password: "SuperSecretPassword123"
vault_username: "admin"
```

**Playbook'ta kullanım:**
```yaml
vars_files:
  - vars/vault.yml

roles:
  - role: api_request
    api_username: "{{ vault_username }}"
    api_password: "{{ vault_api_password }}"
```

### Best Practices
- ✅ **Asla** şifreleri düz metin olarak yazmayın
- ✅ `api_no_log: true` kullanın (varsayılan)
- ✅ Production'da SSL doğrulamayı açık tutun
- ✅ Sadece gerekli kullanıcılara Vault erişimi verin

## Troubleshooting

### Problem: requests_ntlm modülü bulunamadı

**Çözüm:**
```bash
pip3 install requests-ntlm
```

### Problem: SSL Certificate hatası

**Geçici çözüm (test için):**
```yaml
api_verify_ssl: false
```

**Kalıcı çözüm (production için):**
```bash
sudo cp your-cert.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

### Problem: Timeout hatası

**Çözüm:**
```yaml
api_timeout_connection: 30
api_timeout_read: 60
```

### Problem: NTLM Authentication başarısız

**Kontrol listesi:**
- Domain doğru mu? (`api_domain: "CORP"`)
- Username formatı: `john.doe` (domain prefix YOK)
- Şifre Vault'tan geliyor mu?
- NTLM desteği sunucuda açık mı?

## Bağımlılıklar

Bu role'ün başka role'lere bağımlılığı yoktur.

## Lisans

MIT

## Yazar Bilgisi

Bu role [Your Name] tarafından oluşturulmuştur.

## Katkıda Bulunma

1. Fork edin
2. Feature branch oluşturun (`git checkout -b feature/amazing-feature`)
3. Commit edin (`git commit -m 'Add amazing feature'`)
4. Push edin (`git push origin feature/amazing-feature`)
5. Pull Request açın

## Değişiklik Geçmişi

### v2.0.0 (2025-11-02)
- ✅ Role yapısına dönüştürüldü
- ✅ Retry mekanizması eklendi
- ✅ Timeout kontrolü iyileştirildi
- ✅ SSL warning susturma
- ✅ Response encoding düzeltme
- ✅ DEBUG logging eklendi

### v1.0.0 (2025-10-01)
- ✅ İlk sürüm
- ✅ NTLM ve Basic Auth desteği
- ✅ Temel hata yönetimi
