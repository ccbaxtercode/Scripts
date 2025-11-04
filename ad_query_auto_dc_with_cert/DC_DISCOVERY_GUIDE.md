# DC DISCOVERY - KULLANIM ÖRNEĞİ

## 🎯 Yenilik: Otomatik DC Bulma

Script artık DNS SRV query ile otomatik olarak DC hostname'i bulur.
Bu sayede sertifika hostname matching sorunu çözülür.

---

## 📋 Nasıl Çalışır?

### 1. Domain Girişi
```bash
python3 ad_query.py user test.local.net jdoe
```

### 2. DNS SRV Query
```
_ldap._tcp.dc._msdcs.test.local.net
```

### 3. DC Bulundu
```
dc1.test.local.net (priority=0, weight=100)
```

### 4. Bağlantı
```
ldaps://dc1.test.local.net:636
```

### 5. Sertifika Kontrolü
```
Certificate CN: dc1.test.local.net ✅
Hostname: dc1.test.local.net ✅
Match: OK
```

---

## 🔧 Gerekli Modül

```bash
pip install dnspython --break-system-packages
```

**Kontrol:**
```bash
python3 -c "import dns.resolver; print('✓ dnspython yüklü')"
```

---

## 📝 Test Komutları

### Test 1: dnspython Var
```bash
export AD_USER="administrator@test.local.net"
export AD_PASSWORD="P@ssw0rd"
export AD_QUERY_DEBUG="true"

python3 ad_query.py user test.local.net jdoe
```

**Beklenen Log:**
```
[INFO] ============================================================
[INFO] DC DISCOVERY
[INFO] ============================================================
[DEBUG] DNS SRV query: _ldap._tcp.dc._msdcs.test.local.net
[INFO] ✓ DC bulundu: dc1.test.local.net
[DEBUG] Toplam DC sayısı: 2
[DEBUG]   DC #1: dc1.test.local.net (priority=0, weight=100)
[DEBUG]   DC #2: dc2.test.local.net (priority=0, weight=50)
[INFO] Otomatik DC seçildi: dc1.test.local.net
[INFO] Bağlanılıyor: dc1.test.local.net
[INFO] ✓ LDAP bağlantısı başarılı
```

---

### Test 2: dnspython Yok (Fallback)
```bash
python3 ad_query.py user test.local.net jdoe
```

**Beklenen Log:**
```
[WARN] dnspython modülü yok, domain direkt kullanılacak
[DEBUG] pip install dnspython --break-system-packages
[INFO] Domain direkt kullanılıyor: test.local.net
[INFO] Bağlanılıyor: test.local.net
```

---

## 🎯 JSON Çıktısı

Artık `server` alanı da mevcut:

```json
{
  "success": true,
  "found": true,
  "object_type": "user",
  "domain": "test.local.net",
  "server": "dc1.test.local.net",
  "search_term": "jdoe",
  "dn": "CN=John Doe,OU=Users,DC=test,DC=local,DC=net",
  "attributes": {...}
}
```

---

## 🔍 DNS SRV Record Kontrol

Manuel kontrol için:

```bash
# Linux/Mac
dig +short SRV _ldap._tcp.dc._msdcs.test.local.net

# Windows
nslookup -type=SRV _ldap._tcp.dc._msdcs.test.local.net

# Python
python3 -c "
import dns.resolver
answers = dns.resolver.resolve('_ldap._tcp.dc._msdcs.test.local.net', 'SRV')
for rdata in answers:
    print(f'{rdata.target} (priority={rdata.priority}, weight={rdata.weight})')
"
```

**Örnek Çıktı:**
```
0 100 389 dc1.test.local.net.
0 50 389 dc2.test.local.net.
```

---

## ⚙️ Ansible Kullanımı

```yaml
- name: "AD User Sorgusu (Otomatik DC)"
  ansible.builtin.command:
    cmd: >
      python3 {{ role_path }}/files/ad_query.py
      user
      test.local.net
      {{ username }}
  environment:
    AD_USER: "{{ domain_admin }}"
    AD_PASSWORD: "{{ domain_password }}"
  register: ad_result_raw

- name: "Parse"
  ansible.builtin.set_fact:
    ad_result: "{{ ad_result_raw.stdout_lines[-1] | from_json }}"

- name: "Kullanılan Server Göster"
  ansible.builtin.debug:
    msg: "Bağlanılan DC: {{ ad_result.server }}"
```

---

## 🛠️ Troubleshooting

### DNS SRV Bulunamıyor
```
[WARN] DNS SRV kaydı bulunamadı: _ldap._tcp.dc._msdcs.test.local.net
[WARN] Domain direkt kullanılacak (DC auto-discovery devre dışı)
```

**Çözüm:**
- DNS server'da SRV kaydı var mı kontrol et
- Veya spesifik DC hostname kullan: `dc1.test.local.net`

---

### Sertifika Hatası Devam Ediyor
```
[ERROR] LDAP bağlantı hatası: certificate verify failed
```

**Kontrol:**
1. Bulunan DC: `dc1.test.local.net`
2. Sertifika CN/SAN: `openssl s_client -connect dc1.test.local.net:636 | grep CN`
3. Eşleşiyor mu?

---

## 📊 Avantajlar

✅ **Otomatik DC Seçimi:** Manuel DC belirtmeye gerek yok  
✅ **Sertifika Uyumluluğu:** Hostname matching sorunu çözüldü  
✅ **Fallback Desteği:** dnspython yoksa domain kullanılır  
✅ **Load Balancing:** Priority/weight'e göre DC seçimi  
✅ **Multi-DC Destek:** 2+ DC ortamında sorunsuz çalışır  

---

## 🔐 Güvenlik Notu

DC discovery sadece **hostname bulma** içindir.  
Sertifika doğrulaması hala aktif tutulabilir:

```python
# ad_query.py içinde değiştir:
ssl_context.check_hostname = True   # ← Aktif
ssl_context.verify_mode = ssl.CERT_REQUIRED
```

Bu durumda sertifika dosyası gerekir:
```bash
export AD_CERT_PATH="/etc/ssl/certs/ad_chain.crt"
```

