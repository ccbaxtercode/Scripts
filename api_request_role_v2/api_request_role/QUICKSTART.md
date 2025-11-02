# 🚀 Hızlı Başlangıç Kılavuzu

## 5 Dakikada Çalıştır!

### 1. Role'ü Kopyalayın
```bash
# Proje dizininize gidin
cd /path/to/your/ansible/project

# Role'ü kopyalayın
cp -r api_request_role roles/api_request
```

### 2. Python Bağımlılıklarını Yükleyin
```bash
pip3 install -r roles/api_request/files/requirements.txt
```

### 3. Vault Oluşturun
```bash
# Vault dosyası oluştur
mkdir -p vars
ansible-vault create vars/vault.yml

# Şifrenizi ekleyin (Vault editor açılacak)
vault_api_password: "YourSecretPassword"
```

### 4. İlk Playbook'unuzu Oluşturun
```bash
cat > test_api.yml << 'EOF'
---
- name: İlk API testim
  hosts: localhost
  gather_facts: no
  
  vars_files:
    - vars/vault.yml
  
  roles:
    - role: api_request
      api_url: "https://httpbin.org/get"
      api_method: "GET"
      api_auth_type: "basic"
      api_username: "test"
      api_password: "{{ vault_api_password }}"
      api_no_log: false
  
  tasks:
    - name: Sonucu göster
      debug:
        msg: "✅ API çağrısı başarılı! Status: {{ api_response.status_code }}"
EOF
```

### 5. Çalıştırın!
```bash
ansible-playbook test_api.yml --ask-vault-pass
```

## 🎯 Gerçek Kullanım Örneği

### NTLM ile Corporate API
```yaml
---
- name: Corporate API çağrısı
  hosts: localhost
  gather_facts: no
  
  vars_files:
    - vars/vault.yml
  
  roles:
    - role: api_request
      api_url: "https://intranet.company.com/api/users"
      api_method: "GET"
      api_auth_type: "ntlm"
      api_username: "{{ vault_username }}"
      api_password: "{{ vault_api_password }}"
      api_domain: "CORP"
      api_verify_ssl: false  # Self-signed cert varsa
```

## 💡 İpuçları

### 1. Debug Modu
```bash
# Detaylı çıktı için
ansible-playbook your_playbook.yml -vvv
```

### 2. Vault Şifresi Dosyadan
```bash
# Şifreyi dosyaya kaydet
echo "your-vault-password" > .vault_pass
chmod 600 .vault_pass

# Playbook'u çalıştır
ansible-playbook test_api.yml --vault-password-file .vault_pass
```

### 3. Hızlı Test
```bash
# httpbin.org ile hızlı test
ansible-playbook roles/api_request/tests/test.yml
```

## 🔧 Sorun mu var?

### Python modülü eksik
```bash
pip3 install requests requests-ntlm
```

### Ansible bulunamadı
```bash
pip3 install ansible
```

### Role bulunamadı
```bash
# roles/ dizininde olduğundan emin olun
ls -la roles/api_request
```

## 📚 Sonraki Adımlar

1. ✅ [README.md](README.md) - Tüm özellikler
2. ✅ [examples/playbook.yml](examples/playbook.yml) - Daha fazla örnek
3. ✅ [tests/test.yml](tests/test.yml) - Test suite

**Tebrikler! İlk API çağrınızı yaptınız! 🎉**
