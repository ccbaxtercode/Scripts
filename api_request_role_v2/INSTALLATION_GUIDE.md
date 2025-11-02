# 🎯 API Request Ansible Role - Kurulum Rehberi

## 📦 Paket İçeriği

Tebrikler! **api_request** Ansible Role'ünü başarıyla oluşturdunuz. Bu paket şunları içerir:

### ✅ Ana Dosyalar
- ✨ **Python Script** - Gelişmiş API çağrı scripti (retry, timeout, SSL)
- ✨ **Ansible Tasks** - Role görevleri
- ✨ **Defaults** - Özelleştirilebilir değişkenler
- ✨ **Meta** - Ansible Galaxy bilgileri

### 📚 Dokümantasyon
- 📖 **README.md** - Tam dokümantasyon (107 sayfa)
- 🚀 **QUICKSTART.md** - 5 dakikada başla
- 📋 **STRUCTURE.md** - Dizin yapısı açıklaması
- 📝 **CHANGELOG.md** - Versiyon geçmişi

### 🎓 Örnekler ve Testler
- 💡 **examples/playbook.yml** - 6 farklı kullanım senaryosu
- 🧪 **tests/test.yml** - 7 test case

---

## 🚀 Hızlı Kurulum (3 Adım)

### 1️⃣ Role'ü Kopyalayın
```bash
# Ansible projesi dizininize gidin
cd /path/to/your/ansible/project

# Role'ü roles/ dizinine kopyalayın
cp -r api_request_role roles/api_request
```

### 2️⃣ Python Bağımlılıklarını Yükleyin
```bash
pip3 install -r roles/api_request/files/requirements.txt
```

Veya manuel:
```bash
pip3 install requests requests-ntlm urllib3
```

### 3️⃣ İlk Playbook'unuzu Oluşturun
```bash
cat > test.yml << 'EOF'
---
- name: API Test
  hosts: localhost
  gather_facts: no
  
  roles:
    - role: api_request
      api_url: "https://httpbin.org/get"
      api_method: "GET"
      api_auth_type: "basic"
      api_username: "test"
      api_password: "test123"
      api_no_log: false
EOF

# Çalıştır!
ansible-playbook test.yml
```

---

## 📁 Role Yapısı

```
api_request/
├── README.md              ← Ana dokümantasyon
├── QUICKSTART.md          ← Hızlı başlangıç
├── STRUCTURE.md           ← Dizin yapısı
├── CHANGELOG.md           ← Değişiklik geçmişi
│
├── defaults/
│   └── main.yml           ← Değişken tanımları
│
├── tasks/
│   └── main.yml           ← Ana görevler
│
├── files/
│   ├── api_request.py     ← Python script
│   └── requirements.txt   ← Bağımlılıklar
│
├── meta/
│   └── main.yml           ← Galaxy metadata
│
├── examples/
│   └── playbook.yml       ← 6 örnek
│
└── tests/
    └── test.yml           ← Test suite
```

---

## 💡 Kullanım Örnekleri

### Örnek 1: GET İsteği (NTLM)
```yaml
- hosts: localhost
  roles:
    - role: api_request
      api_url: "https://intranet.company.com/api/users"
      api_method: "GET"
      api_auth_type: "ntlm"
      api_username: "john.doe"
      api_password: "{{ vault_password }}"
      api_domain: "CORP"
```

### Örnek 2: POST İsteği (JSON Body)
```yaml
- hosts: localhost
  roles:
    - role: api_request
      api_url: "https://api.example.com/users"
      api_method: "POST"
      api_auth_type: "basic"
      api_username: "admin"
      api_password: "{{ vault_password }}"
      api_data:
        name: "Jane Doe"
        email: "jane@example.com"
```

### Örnek 3: Response'u Kullanma
```yaml
- hosts: localhost
  tasks:
    - include_role:
        name: api_request
      vars:
        api_url: "https://api.example.com/data"
        api_method: "GET"
        api_auth_type: "basic"
        api_username: "user"
        api_password: "{{ vault_password }}"
    
    # api_response değişkeni otomatik set edilir
    - debug:
        msg: "Status: {{ api_response.status_code }}"
    
    - debug:
        var: api_response.body
```

---

## 🔒 Güvenlik (Önemli!)

### Ansible Vault Kullanın
```bash
# 1. Vault oluştur
ansible-vault create vars/vault.yml

# 2. İçeriğe şifreleri ekle
vault_api_password: "YourSecretPassword123"

# 3. Playbook'ta kullan
- hosts: localhost
  vars_files:
    - vars/vault.yml
  roles:
    - role: api_request
      api_password: "{{ vault_api_password }}"
```

---

## 🧪 Test Etme

### Tüm Testleri Çalıştır
```bash
ansible-playbook roles/api_request/tests/test.yml
```

### Tek Test
```bash
ansible-playbook test.yml -vvv  # Debug mode
```

---

## 🎯 Özellikler

| Özellik | Açıklama |
|---------|----------|
| 🔐 **NTLM + Basic Auth** | İki auth türü desteği |
| 🔄 **Retry** | 3 otomatik deneme |
| ⏱️ **Timeout** | Connection + read timeout |
| 🛡️ **SSL Control** | SSL doğrulama açma/kapama |
| 📊 **Logging** | DEBUG seviyesi detaylı log |
| 🎯 **HTTP Methods** | GET, POST, PUT, DELETE, PATCH |
| 📝 **JSON** | Request/response JSON desteği |
| ❌ **Error Handling** | Block/rescue hata yönetimi |

---

## 📚 Dokümantasyon

| Dosya | Açıklama |
|-------|----------|
| [README.md](roles/api_request/README.md) | Tam dokümantasyon (tüm özellikler) |
| [QUICKSTART.md](roles/api_request/QUICKSTART.md) | 5 dakikada başla |
| [STRUCTURE.md](roles/api_request/STRUCTURE.md) | Dizin yapısı |
| [examples/playbook.yml](roles/api_request/examples/playbook.yml) | 6 kullanım örneği |
| [tests/test.yml](roles/api_request/tests/test.yml) | Test suite |

---

## 🛠️ Troubleshooting

### Problem: requests_ntlm bulunamadı
```bash
pip3 install requests-ntlm
```

### Problem: SSL hatası
```yaml
api_verify_ssl: false  # Geçici çözüm
```

### Problem: Timeout
```yaml
api_timeout_connection: 30
api_timeout_read: 60
```

### Problem: NTLM auth başarısız
- Domain doğru mu? `api_domain: "CORP"`
- Username: `john.doe` (domain prefix YOK)
- Vault kullanıyor musunuz?

---

## 🎓 Sonraki Adımlar

1. ✅ [QUICKSTART.md](roles/api_request/QUICKSTART.md) okuyun
2. ✅ Test suite'i çalıştırın
3. ✅ Kendi playbook'unuzu yazın
4. ✅ Production'a deploy edin

---

## 📞 Destek

- 📖 Dokümantasyon: README.md
- 💡 Örnekler: examples/playbook.yml
- 🐛 Sorun: GitHub Issues
- 💬 Soru: Discussions

---

## ✨ Öne Çıkanlar

- ✅ **Production-ready**: Retry, timeout, error handling
- ✅ **Güvenli**: Vault zorunlu, no_log aktif
- ✅ **Esnek**: 30+ özelleştirilebilir değişken
- ✅ **Dokümante**: 4 ayrıntılı dokümantasyon
- ✅ **Test edilmiş**: 7 test case

---

**Başarılar! 🎉**

İlk API çağrınızı yapmaya hazırsınız!

```bash
ansible-playbook test.yml
```
