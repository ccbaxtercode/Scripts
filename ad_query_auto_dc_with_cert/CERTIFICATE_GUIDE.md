# AD Query - Sertifika Doğrulama ve Timeout Kullanımı

## ✅ Son Hal Özellikleri

### 🔐 Güvenlik
- ✅ SSL/TLS sertifika doğrulama (CERT_REQUIRED)
- ✅ Hostname kontrolü (check_hostname=True)
- ✅ AD chain certificate zorunlu
- ✅ DC auto-discovery (DNS SRV)

### ⏱️ Performans
- ✅ Connection timeout (varsayılan: 10s)
- ✅ Receive timeout
- ✅ Konfigüre edilebilir timeout değeri

---

## 🔧 Environment Variables

### Zorunlu:
```bash
AD_USER="administrator@test.local.net"
AD_PASSWORD="P@ssw0rd"
AD_CERT_PATH="/etc/ssl/certs/ad_chain.crt"
```

### Opsiyonel:
```bash
AD_QUERY_DEBUG="true"          # Debug mode
LDAP_TIMEOUT="10"              # Timeout (saniye)
```

---

## 🚀 Kullanım Örnekleri

### 1. Temel Kullanım (Sertifika ile)
```bash
export AD_USER="administrator@test.local.net"
export AD_PASSWORD="P@ssw0rd"
export AD_CERT_PATH="/etc/ssl/certs/ad_chain.crt"

python3 ad_query.py user test.local.net jdoe
```

**Beklenen Log:**
```
[INFO] ============================================================
[INFO] DC DISCOVERY
[INFO] ============================================================
[INFO] ✓ DC bulundu: dc1.test.local.net
[INFO] Otomatik DC seçildi: dc1.test.local.net
[INFO] ============================================================
[INFO] LDAP BAĞLANTISI KURULUYOR
[INFO] ============================================================
[INFO] ✓ SSL context oluşturuldu (certificate validation: ENABLED)
[INFO] Bağlanılıyor: dc1.test.local.net
[INFO] ✓ LDAP bağlantısı başarılı
[INFO] ✓ USER bulundu: jdoe
```

---

### 2. Custom Timeout
```bash
export LDAP_TIMEOUT="30"  # 30 saniye timeout

python3 ad_query.py user test.local.net jdoe
```

---

### 3. Debug Mode
```bash
export AD_QUERY_DEBUG="true"

python3 ad_query.py user test.local.net jdoe
```

**Debug Çıktısı:**
```
[DEBUG] ============================================================
[DEBUG] AD QUERY SCRIPT BAŞLATILIYOR
[DEBUG] ============================================================
[DEBUG] Object Type: user
[DEBUG] Domain: test.local.net
[DEBUG] DNS SRV query: _ldap._tcp.dc._msdcs.test.local.net
[DEBUG] Toplam DC sayısı: 2
[DEBUG]   DC #1: dc1.test.local.net (priority=0, weight=100)
[DEBUG]   DC #2: dc2.test.local.net (priority=0, weight=50)
[DEBUG] Sertifika dosyası: /etc/ssl/certs/ad_chain.crt
[DEBUG] LDAP Timeout: 10 saniye
[DEBUG]   Verify Mode: CERT_REQUIRED
[DEBUG]   Hostname Check: ENABLED
[DEBUG]   CA File: /etc/ssl/certs/ad_chain.crt
[DEBUG] LDAP Server: ldaps://dc1.test.local.net:636
[DEBUG] Connection timeout: 10s
[DEBUG] User: administrator@test.local.net
[DEBUG] Bind successful - Server: <Server(...)>
```

---

## 🎯 Ansible Entegrasyonu

### Task Örneği:
```yaml
- name: "AD User Sorgusu (Sertifika ile)"
  ansible.builtin.command:
    cmd: >
      python3 {{ role_path }}/files/ad_query.py
      user
      {{ domain_info[domain].fqdn }}
      {{ username }}
  environment:
    AD_USER: "{{ domain_info[domain].domain_admin }}"
    AD_PASSWORD: "{{ domain_info[domain].domain_password }}"
    AD_CERT_PATH: "/etc/ssl/certs/ad_chain.crt"
    LDAP_TIMEOUT: "15"
    AD_QUERY_DEBUG: "false"
  register: ad_result_raw
  changed_when: false

- name: "Parse JSON"
  ansible.builtin.set_fact:
    ad_result: "{{ ad_result_raw.stdout_lines[-1] | from_json }}"

- name: "Bağlanan DC'yi Göster"
  ansible.builtin.debug:
    msg: "DC: {{ ad_result.server }}"
```

---

## 📋 Sertifika Hazırlama

### 1. AD Chain Certificate Alma (Windows DC'den)
```powershell
# PowerShell (DC üzerinde)
certutil -ca.chain -f ad_chain.crt
```

### 2. Certificate Export (Linux)
```bash
# DC'den sertifikayı al
openssl s_client -connect dc1.test.local.net:636 -showcerts \
  </dev/null 2>/dev/null | \
  openssl x509 -outform PEM > /tmp/dc_cert.pem

# Root CA ve Intermediate CA'ları da ekle
cat /tmp/dc_cert.pem /tmp/root_ca.pem /tmp/intermediate_ca.pem > /etc/ssl/certs/ad_chain.crt
```

### 3. Sertifika Doğrulama
```bash
# Sertifikayı kontrol et
openssl x509 -in /etc/ssl/certs/ad_chain.crt -text -noout

# CN/SAN alanını kontrol et
openssl x509 -in /etc/ssl/certs/ad_chain.crt -text -noout | grep -A2 "Subject Alternative Name"
```

**Örnek Çıktı:**
```
Subject Alternative Name:
    DNS:dc1.test.local.net
    DNS:dc2.test.local.net
```

### 4. Test Bağlantı
```bash
# OpenSSL ile test
openssl s_client -connect dc1.test.local.net:636 \
  -CAfile /etc/ssl/certs/ad_chain.crt \
  -verify_return_error

# Başarılı ise:
# Verify return code: 0 (ok)
```

---

## ⚠️ Hata Senaryoları ve Çözümleri

### 1. Sertifika Dosyası Bulunamadı
```json
{
  "success": false,
  "error": "Sertifika dosyası bulunamadı: /etc/ssl/certs/ad_chain.crt",
  "details": "AD_CERT_PATH environment variable'ını kontrol edin"
}
```

**Çözüm:**
```bash
# Dosya var mı kontrol et
ls -l /etc/ssl/certs/ad_chain.crt

# Yoksa oluştur
export AD_CERT_PATH="/path/to/your/cert.crt"
```

---

### 2. SSL Sertifika Doğrulama Başarısız
```json
{
  "success": false,
  "error": "SSL sertifika doğrulama başarısız",
  "details": "Hostname mismatch veya sertifika geçersiz. Server: dc1.test.local.net, Cert: /etc/ssl/certs/ad_chain.crt"
}
```

**Çözüm:**
```bash
# 1. Sertifikadaki CN/SAN kontrol et
openssl x509 -in /etc/ssl/certs/ad_chain.crt -text -noout | grep -E "Subject:|DNS:"

# 2. Bulunan DC ile eşleşiyor mu?
export AD_QUERY_DEBUG="true"
python3 ad_query.py user test.local.net jdoe 2>&1 | grep "DC bulundu"

# 3. Manuel test
openssl s_client -connect dc1.test.local.net:636 -CAfile /etc/ssl/certs/ad_chain.crt
```

---

### 3. Timeout Hatası
```json
{
  "success": false,
  "error": "LDAP bağlantı timeout",
  "details": "Server dc1.test.local.net erişilebilir değil (timeout: 10s)"
}
```

**Çözüm:**
```bash
# 1. Network bağlantısı kontrol et
ping dc1.test.local.net
nc -zv dc1.test.local.net 636

# 2. Timeout süresini artır
export LDAP_TIMEOUT="30"

# 3. Firewall kontrol et
telnet dc1.test.local.net 636
```

---

### 4. dnspython Eksik
```
[WARN] dnspython modülü yok, domain direkt kullanılacak
```

**Çözüm:**
```bash
pip install dnspython --break-system-packages

# Kontrol
python3 -c "import dns.resolver; print('OK')"
```

---

## 🔍 Sertifika Chain Yapısı

```
ad_chain.crt içeriği:
┌─────────────────────────┐
│ DC Certificate          │  ← dc1.test.local.net
├─────────────────────────┤
│ Intermediate CA (opt)   │  ← Issuing CA
├─────────────────────────┤
│ Root CA                 │  ← Root CA
└─────────────────────────┘
```

**Örnek ad_chain.crt:**
```
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIJAL... (DC cert)
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDdDCCAlygAwIBAgIBAD... (Intermediate CA)
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFajCCA1KgAwIBAgIQAh... (Root CA)
-----END CERTIFICATE-----
```

---

## 📊 Performans ve Timeout Ayarları

### Önerilen Timeout Değerleri:

| Ortam | Timeout | Açıklama |
|-------|---------|----------|
| Hızlı LAN | 5-10s | Normal ofis ağı |
| Yavaş WAN | 15-30s | VPN veya uzak bağlantı |
| Çoklu DC | 10-15s | DC discovery + bağlantı |
| Production | 10s | Güvenilir ağ |
| Test | 30s | Debug için |

### Timeout Türleri:
- **connect_timeout:** İlk TCP bağlantısı
- **receive_timeout:** LDAP response bekleme

---

## 🎯 JSON Çıktı (Final)

```json
{
  "success": true,
  "found": true,
  "object_type": "user",
  "domain": "test.local.net",
  "server": "dc1.test.local.net",
  "search_term": "jdoe",
  "dn": "CN=John Doe,OU=Users,DC=test,DC=local,DC=net",
  "attributes": {
    "cn": "John Doe",
    "samaccountname": "jdoe",
    "mail": "jdoe@test.local.net",
    "lastlogon": "2024-11-04 15:30:00"
  }
}
```

---

## ✅ Checklist (Production Hazırlık)

- [ ] AD chain certificate hazır (`ad_chain.crt`)
- [ ] Sertifika doğru dizinde (`/etc/ssl/certs/`)
- [ ] dnspython yüklü (`pip install dnspython`)
- [ ] DNS SRV kayıtları çalışıyor
- [ ] DC'ler 636 portunda erişilebilir
- [ ] Timeout değerleri ayarlandı
- [ ] Test edildi (debug mode)
- [ ] Ansible task'ları güncellendi
- [ ] Vault'ta credentials saklandı

---

## 🔗 İlgili Komutlar

```bash
# Modül kontrolü
python3 -c "import ldap3, dns.resolver, ssl; print('✓ Tüm modüller yüklü')"

# Sertifika geçerlilik kontrolü
openssl x509 -in /etc/ssl/certs/ad_chain.crt -noout -dates

# DNS SRV test
dig +short SRV _ldap._tcp.dc._msdcs.test.local.net

# LDAPS port test
nc -zv dc1.test.local.net 636

# Full test
export AD_USER="admin@test.local.net"
export AD_PASSWORD="pass"
export AD_CERT_PATH="/etc/ssl/certs/ad_chain.crt"
export AD_QUERY_DEBUG="true"
python3 ad_query.py user test.local.net testuser
```

