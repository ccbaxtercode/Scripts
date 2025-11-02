# 📁 Role Dizin Yapısı

```
api_request_role/
├── 📄 README.md                    # Ana dokümantasyon
├── 📄 QUICKSTART.md                # Hızlı başlangıç kılavuzu
├── 📄 CHANGELOG.md                 # Versiyon geçmişi
├── 📄 .gitignore                   # Git ignore kuralları
├── 📄 .ansible-lint                # Ansible lint yapılandırması
│
├── 📁 defaults/
│   └── main.yml                    # Varsayılan role değişkenleri
│
├── 📁 tasks/
│   └── main.yml                    # Ana task listesi
│
├── 📁 files/
│   ├── api_request.py              # Python API script
│   └── requirements.txt            # Python bağımlılıkları
│
├── 📁 meta/
│   └── main.yml                    # Role metadata (Galaxy info)
│
├── 📁 examples/
│   └── playbook.yml                # Örnek kullanım playbook'ları
│
└── 📁 tests/
    └── test.yml                    # Test suite playbook
```

## 📋 Dosya Açıklamaları

### Kök Dizin Dosyaları

| Dosya | Açıklama |
|-------|----------|
| `README.md` | Role'ün tam dokümantasyonu, tüm özellikler ve kullanım örnekleri |
| `QUICKSTART.md` | 5 dakikada başlama kılavuzu |
| `CHANGELOG.md` | Versiyon geçmişi ve değişiklikler |
| `.gitignore` | Git tarafından ignore edilecek dosyalar |
| `.ansible-lint` | Ansible linter yapılandırması |

### defaults/

**Varsayılan değişkenler** - Kullanıcı tarafından override edilebilir.

```yaml
# defaults/main.yml
api_url: "https://example.com/api"
api_method: "GET"
api_auth_type: "ntlm"
api_timeout_connection: 10
api_timeout_read: 30
# ... daha fazla değişken
```

### tasks/

**Ana task dosyası** - Role'ün çalıştırdığı işlemler.

```yaml
# tasks/main.yml
- name: Python bağımlılıkları kontrol
- name: Environment değişkenleri hazırla
- name: API çağrısı yap
- name: Response'u parse et
- name: Hata kontrolü
```

### files/

**Statik dosyalar** - Role tarafından kullanılan dosyalar.

| Dosya | Açıklama |
|-------|----------|
| `api_request.py` | Python script - API çağrıları yapar |
| `requirements.txt` | Python bağımlılıkları listesi |

### meta/

**Role metadata** - Ansible Galaxy için bilgiler.

```yaml
# meta/main.yml
galaxy_info:
  role_name: api_request
  author: Your Name
  description: API çağrı role'ü
  platforms: [Ubuntu, Debian, EL]
  galaxy_tags: [api, rest, ntlm]
```

### examples/

**Örnek playbook'lar** - Farklı kullanım senaryoları.

6 farklı örnek:
1. GET isteği (NTLM)
2. POST isteği (Basic Auth)
3. Çoklu API çağrısı
4. Response işleme
5. Özel timeout/retry
6. DELETE isteği

### tests/

**Test suite** - Role'ü test etmek için playbook.

```bash
# Test çalıştırma
ansible-playbook tests/test.yml
```

7 farklı test:
- GET, POST, PUT, DELETE
- Custom headers
- Timeout kontrolü
- Error handling

## 🔧 Kullanım

### Role'ü Yükleme

```bash
# Manuel
git clone https://github.com/username/ansible-role-api-request.git roles/api_request

# veya Galaxy
ansible-galaxy install username.api_request
```

### Playbook'ta Kullanım

```yaml
---
- name: API çağrısı
  hosts: localhost
  
  roles:
    - role: api_request
      api_url: "https://api.example.com/users"
      api_method: "GET"
      api_auth_type: "basic"
      api_username: "admin"
      api_password: "{{ vault_password }}"
```

## 📝 Önemli Notlar

1. **defaults/main.yml** - Tüm değişkenlerin varsayılan değerleri burada
2. **tasks/main.yml** - Ana logic burada, değiştirmeyin
3. **files/api_request.py** - Python script, özelleştirilebilir
4. **examples/** - Kopyala-yapıştır yapılabilir örnekler
5. **tests/** - Role'ü test etmek için kullanın

## 🚀 Hızlı Test

```bash
# 1. Role dizinine gidin
cd api_request_role

# 2. Test playbook'u çalıştırın
ansible-playbook tests/test.yml

# 3. Örnek playbook'u çalıştırın
ansible-playbook examples/playbook.yml --ask-vault-pass
```

## 📚 Daha Fazla Bilgi

- [README.md](README.md) - Tam dokümantasyon
- [QUICKSTART.md](QUICKSTART.md) - Hızlı başlangıç
- [examples/playbook.yml](examples/playbook.yml) - Örnekler
