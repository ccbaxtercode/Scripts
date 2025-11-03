# AD Query Tool - Kullanım Dokümantasyonu

## 📋 Genel Bakış

`ad_query.py` - Active Directory user ve computer obje sorgulama aracı.

**Özellikler:**
- ✅ User ve Computer objesi sorgulama
- ✅ LDAPS (636) güvenli bağlantı
- ✅ Otomatik Base DN üretimi
- ✅ Attribute normalizasyonu (timestamp, binary, null handling)
- ✅ JSON çıktı formatı
- ✅ Debug mode desteği
- ✅ Türkçe karakter desteği

---

## 🚀 Kullanım

### Komut Yapısı
```bash
python3 ad_query.py <object_type> <domain> <search_term> [attributes]
```

### Parametreler

| Parametre | Zorunlu | Açıklama | Örnek |
|-----------|---------|----------|-------|
| `object_type` | ✅ | user veya computer | `user` |
| `domain` | ✅ | Domain FQDN | `test.local.com` |
| `search_term` | ✅ | Aranacak isim | `jdoe` veya `PC001` |
| `attributes` | ❌ | Virgülle ayrılmış attribute listesi | `cn,mail,memberOf` |

### Environment Variables

| Variable | Zorunlu | Açıklama |
|----------|---------|----------|
| `AD_USER` | ✅ | Domain admin kullanıcı adı |
| `AD_PASSWORD` | ✅ | Domain admin şifresi |
| `AD_QUERY_DEBUG` | ❌ | Debug mode (true/false) |

---

## 📝 Örnekler

### 1. User Sorgusu (Default Attributes)
```bash
export AD_USER="administrator@test.local.com"
export AD_PASSWORD="P@ssw0rd"

python3 ad_query.py user test.local.com jdoe
```

**Default User Attributes:**
- cn
- sAMAccountName
- displayName
- mail
- userPrincipalName
- memberOf
- whenCreated
- lastLogon
- userAccountControl

### 2. Computer Sorgusu (Default Attributes)
```bash
python3 ad_query.py computer domain1.local PC001
```

**Default Computer Attributes:**
- cn
- dNSHostName
- operatingSystem
- operatingSystemVersion
- whenCreated
- lastLogon
- description

### 3. Custom Attributes
```bash
python3 ad_query.py user test.local.com jdoe "cn,mail,department,manager,title"
```

### 4. Debug Mode
```bash
export AD_QUERY_DEBUG="true"
python3 ad_query.py user test.local.com jdoe
```

---

## 📤 Çıktı Formatı

### Başarılı Sorgu (Object Bulundu)
```json
{
  "success": true,
  "found": true,
  "object_type": "user",
  "domain": "test.local.com",
  "search_term": "jdoe",
  "dn": "CN=John Doe,OU=Users,DC=test,DC=local,DC=com",
  "attributes": {
    "cn": "John Doe",
    "samaccountname": "jdoe",
    "displayname": "John Doe",
    "mail": "jdoe@test.local.com",
    "userprincipalname": "jdoe@test.local.com",
    "memberof": [
      "CN=IT Team,OU=Groups,DC=test,DC=local,DC=com",
      "CN=Developers,OU=Groups,DC=test,DC=local,DC=com"
    ],
    "whencreated": "2024-01-15 10:30:00",
    "lastlogon": "2024-11-03 14:30:00",
    "useraccountcontrol": "512"
  }
}
```

### Object Bulunamadı
```json
{
  "success": true,
  "found": false,
  "object_type": "user",
  "domain": "test.local.com",
  "search_term": "nonexistent",
  "message": "User 'nonexistent' AD'de bulunamadı"
}
```

### Hata Durumu
```json
{
  "success": false,
  "error": "LDAP bağlantı hatası",
  "details": "Connection timeout"
}
```

---

## 🔧 Attribute Normalizasyonu

### 1. Boş Değerler
```json
"description": "N/A"  // Boş string veya null
"telephonenumber": "N/A"  // Yok
```

### 2. Timestamp Dönüşümü
```json
// Windows FILETIME → Readable
"lastlogon": "2024-11-03 14:30:00"
"pwdlastset": "2024-10-15 09:15:30"

// Hiç login olmamış
"lastlogon": "N/A"
```

### 3. Binary Değerler
```json
// objectGUID, objectSid → Hex string
"objectguid": "a1b2c3d4e5f6..."
```

### 4. Liste Değerleri
```json
// Normal
"memberof": ["CN=Group1...", "CN=Group2..."]

// Boş liste
"memberof": "N/A"

// Null temizleme
["Group1", null, "Group2"] → ["Group1", "Group2"]
```

---

## 🎯 Ansible Kullanımı

### Basit Örnek
```yaml
- name: "AD User Sorgusu"
  ansible.builtin.command:
    cmd: >
      python3 {{ role_path }}/files/ad_query.py
      user
      "{{ domain_info[domain].fqdn }}"
      "{{ username }}"
  environment:
    AD_USER: "{{ domain_info[domain].domain_admin }}"
    AD_PASSWORD: "{{ domain_info[domain].domain_password }}"
  register: ad_result_raw
  changed_when: false

- name: "Parse JSON"
  ansible.builtin.set_fact:
    ad_result: "{{ ad_result_raw.stdout_lines[-1] | from_json }}"

- name: "Dinamik Obje Oluştur"
  ansible.builtin.set_fact:
    ad_user_info: "{{ ad_result.attributes }}"
  when:
    - ad_result.success | bool
    - ad_result.found | bool

- name: "Attribute Kullan"
  ansible.builtin.debug:
    msg: "Email: {{ ad_user_info.mail }}"
```

### Hata Yönetimi
```yaml
- name: "Fail Check"
  ansible.builtin.fail:
    msg: "AD sorgusu başarısız: {{ ad_result.error }}"
  when: not ad_result.success | bool

- name: "Object Bulunamadı Kontrolü"
  ansible.builtin.fail:
    msg: "User '{{ username }}' AD'de bulunamadı"
  when:
    - ad_result.success | bool
    - not ad_result.found | bool
```

---

## ⚠️ Hata Kodları ve Anlamları

| Exit Code | Durum | Açıklama |
|-----------|-------|----------|
| 0 | Success | İşlem başarılı (object bulundu veya bulunamadı) |
| 1 | Error | Modül eksik, parametre hatası, bağlantı hatası |

### Yaygın Hatalar

**1. ldap3 modülü yüklü değil**
```json
{
  "success": false,
  "error": "ldap3 modülü yüklü değil",
  "details": "pip install ldap3 --break-system-packages"
}
```

**2. LDAP authentication başarısız**
```json
{
  "success": false,
  "error": "LDAP authentication başarısız",
  "details": "Kullanıcı adı veya şifre hatalı"
}
```

**3. LDAP bağlantı timeout**
```json
{
  "success": false,
  "error": "LDAP bağlantı timeout",
  "details": "Domain test.local.com erişilebilir değil"
}
```

**4. Parametre eksik**
```json
{
  "success": false,
  "error": "AD_OBJECT parametresi eksik",
  "details": "Kullanım: ad_query.py <user|computer> <domain> <search> [attributes]"
}
```

---

## 🔍 Debug Mode

Debug mode aktif edildiğinde stderr'e detaylı loglar yazılır:

```bash
export AD_QUERY_DEBUG="true"
python3 ad_query.py user test.local.com jdoe 2>&1
```

**Debug Çıktısı:**
```
[DEBUG] ============================================================
[DEBUG] AD QUERY SCRIPT BAŞLATILIYOR
[DEBUG] ============================================================
[DEBUG] Object Type: user
[DEBUG] Domain: test.local.com
[DEBUG] Search Term: jdoe
[DEBUG] Custom Attributes: None (using defaults)
[DEBUG] Base DN oluşturuldu: DC=test,DC=local,DC=com
[INFO] Base DN: DC=test,DC=local,DC=com
[INFO] ============================================================
[INFO] LDAP BAĞLANTISI KURULUYOR
[INFO] ============================================================
[DEBUG] SSL context oluşturuldu (certificate validation: disabled)
[DEBUG] LDAP Server: ldaps://test.local.com:636
[DEBUG] LDAP Server objesi oluşturuldu
[INFO] Domain'e bağlanılıyor: test.local.com
[DEBUG] User: administrator@test.local.com
[INFO] ✓ LDAP bağlantısı başarılı
[DEBUG] Bind successful - Server: <Server(...)>
[INFO] ============================================================
[INFO] USER SORGUSU
[INFO] ============================================================
[DEBUG] Search Filter: (&(objectClass=user)(objectCategory=person)(sAMAccountName=jdoe))
[DEBUG] Base DN: DC=test,DC=local,DC=com
[DEBUG] Attributes: cn, samaccountname, displayname, mail, ...
[INFO] Aranıyor: jdoe
[DEBUG] Search tamamlandı - Sonuç sayısı: 1
[INFO] ✓ USER bulundu: jdoe
[DEBUG] DN: CN=John Doe,OU=Users,DC=test,DC=local,DC=com
[DEBUG] Attribute 'cn': str - 'John Doe'
[DEBUG] Attribute 'mail': str - 'jdoe@test.local.com'
...
[INFO] ============================================================
[INFO] SORGU TAMAMLANDI
[INFO] ============================================================
```

---

## 💡 İpuçları

1. **Attribute İsimleri:** LDAP attribute isimleri case-insensitive'dir, ancak script otomatik lowercase'e çevirir.

2. **Boş Değer Kontrolü:** Ansible'da boş değerleri kontrol ederken:
   ```yaml
   when: ad_user_info.mail != "N/A"
   ```

3. **Liste Kontrolü:** memberOf gibi liste değerleri:
   ```yaml
   when: 
     - ad_user_info.memberof != "N/A"
     - ad_user_info.memberof | length > 0
   ```

4. **Timestamp Kullanımı:** lastLogon değeri readable format'ta gelir, karşılaştırma yapmak için parse edin.

5. **Custom Attributes:** İhtiyacınız olan minimum attribute'leri seçerek sorgu süresini azaltabilirsiniz.

---

## 🔐 Güvenlik Notları

1. **Credentials:** AD_USER ve AD_PASSWORD environment variable'lardan alınır, Ansible vault kullanın.

2. **LDAPS:** Script sadece LDAPS (636) kullanır, plain LDAP (389) desteklenmez.

3. **Certificate Validation:** Self-signed certificate'lar için validation kapatılmıştır.

4. **Log Güvenliği:** Şifreler loglara yazılmaz.

---

## 📚 İlgili Dokümantasyon

- [ldap3 Documentation](https://ldap3.readthedocs.io/)
- [Ansible Command Module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/command_module.html)
- [Active Directory Attributes](https://learn.microsoft.com/en-us/windows/win32/ad/active-directory-schema)

---

## 🐛 Sorun Giderme

### Script çalışmıyor
1. Python 3 ve ldap3 yüklü mü kontrol edin
2. Domain erişilebilir mi kontrol edin: `ping test.local.com`
3. Port 636 açık mı kontrol edin: `nc -zv test.local.com 636`

### Object bulunamıyor ama var
1. Search term doğru mu? (case-sensitive değil ama tam eşleşme gerekli)
2. Base DN doğru üretildi mi? Debug mode ile kontrol edin
3. Credentials doğru mu?

### Attribute boş geliyor
1. Attribute AD'de gerçekten boş olabilir (normal)
2. Attribute ismini yanlış yazmış olabilirsiniz (debug mode kontrol)
3. Read yetkisi olmayabilir (permissions)

---

## 📞 Destek

Sorun yaşarsanız:
1. `AD_QUERY_DEBUG=true` ile debug mode'u aktif edin
2. Stderr çıktısını inceleyin
3. JSON çıktısını kontrol edin

