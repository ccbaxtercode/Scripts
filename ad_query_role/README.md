# Ansible Role: ad_query

Active Directory obje sorgulama role'ü (Multi-DC, Retry, Certificate Fallback)

## Özellikler

✅ **Multi-DC Support:** DNS SRV ile tüm DC'leri bulur ve sırayla tarar  
✅ **Retry Logic:** Her DC için 3 retry (5s interval)  
✅ **Certificate Fallback:** Sertifika yoksa CERT_NONE ile devam eder  
✅ **Object Types:** User, Computer, Group  
✅ **Group Members:** Count + Sample (ilk N üye)  
✅ **Credential Test:** Tek seferlik bind, sonra multi-DC search  
✅ **Load Balancing:** Priority/weight sıralaması  
✅ **Attribute Normalization:** Timestamp, binary, null handling  

---

## Gereksinimler

### Python Modülleri:
```bash
pip3 install ldap3 --break-system-packages
pip3 install dnspython --break-system-packages
```

### Execution Environment:
```yaml
dependencies:
  python:
    - ldap3
    - dnspython
```

---

## Role Değişkenleri

### Zorunlu:
```yaml
ad_object_type: "user"           # user, computer, group
ad_domain: "test.local.net"      # Domain FQDN
ad_search_term: "jdoe"           # Aranacak obje
ad_user: "{{ vault_ad_user }}"   # Domain admin
ad_password: "{{ vault_ad_password }}"
```

### Opsiyonel:
```yaml
ad_custom_attributes: ""                    # Boş = default
ad_cert_path: "/etc/ssl/certs/ad_chain.crt"
ldap_timeout: 10                            # Saniye
ad_query_max_retries: 3
ad_query_retry_delay: 5
member_sample_size: 10
ad_query_debug: false
```

---

## Kullanım

### Playbook Örneği:

```yaml
---
- name: "AD Query Test"
  hosts: localhost
  gather_facts: false
  
  vars:
    ad_user: "{{ vault_ad_user }}"
    ad_password: "{{ vault_ad_password }}"
  
  tasks:
    # User sorgusu
    - name: "User Sorgula"
      ansible.builtin.include_role:
        name: ad_query
      vars:
        ad_object_type: "user"
        ad_domain: "test.local.net"
        ad_search_term: "jdoe"
    
    - name: "User Email Göster"
      ansible.builtin.debug:
        msg: "Email: {{ ad_object_info.mail }}"
      when: ad_query_result.found | bool
    
    # Computer sorgusu
    - name: "Computer Sorgula"
      ansible.builtin.include_role:
        name: ad_query
      vars:
        ad_object_type: "computer"
        ad_domain: "test.local.net"
        ad_search_term: "PC001"
    
    # Group sorgusu
    - name: "Group Sorgula"
      ansible.builtin.include_role:
        name: ad_query
      vars:
        ad_object_type: "group"
        ad_domain: "test.local.net"
        ad_search_term: "IT-Team"
    
    - name: "Group Member Sayısı"
      ansible.builtin.debug:
        msg: "Toplam üye: {{ ad_object_info.member.count }}"
      when:
        - ad_query_result.found | bool
        - ad_object_info.member.count is defined
```

---

## Dönen Değişkenler

### `ad_query_result` (dict):
```yaml
ad_query_result:
  success: true
  found: true
  object_type: "user"
  domain: "test.local.net"
  server: "dc2.test.local.net"
  credential_test_dc: "dc1.test.local.net"
  search_term: "jdoe"
  dn: "CN=John Doe,OU=Users,DC=test,DC=local,DC=net"
  tried_servers:
    - hostname: "dc1.test.local.net"
      status: "not_found"
      attempts: 1
    - hostname: "dc2.test.local.net"
      status: "success"
      attempts: 1
  attributes: {...}
```

### `ad_object_info` (dict - sadece found=true ise):
```yaml
ad_object_info:
  cn: "John Doe"
  mail: "jdoe@test.local.net"
  displayname: "John Doe"
  memberof: ["CN=IT,OU=Groups,..."]
  lastlogon: "2024-11-04 15:30:00"
```

---

## Custom Attributes

```yaml
- name: "Custom Attributes ile User Sorgula"
  ansible.builtin.include_role:
    name: ad_query
  vars:
    ad_object_type: "user"
    ad_domain: "test.local.net"
    ad_search_term: "jdoe"
    ad_custom_attributes: "cn,mail,department,manager"
```

---

## Group Member Sample

Group sorgusu yaparken `member` attribute'ü özel format döner:

```yaml
ad_object_info:
  member:
    count: 150                  # Toplam üye sayısı
    sample:                     # İlk N üye (default: 10)
      - "CN=User1,OU=Users,..."
      - "CN=User2,OU=Users,..."
```

**Sample size değiştirme:**
```yaml
member_sample_size: 20  # İlk 20 üye
```

---

## Debug Mode

```yaml
ad_query_debug: true
```

**Çıktı:**
```
[INFO] ============================================================
[INFO] DC DISCOVERY
[INFO] ============================================================
[DEBUG] DNS SRV query: _ldap._tcp.dc._msdcs.test.local.net
[INFO] ✓ 2 DC bulundu
[DEBUG]   DC #1: dc1.test.local.net (priority=0, weight=100)
[DEBUG]   DC #2: dc2.test.local.net (priority=0, weight=50)
...
```

---

## Hata Senaryoları

### 1. Object Bulunamadı
```yaml
ad_query_result:
  success: true
  found: false
  message: "User 'jdoe' hiçbir DC'de bulunamadı"
```

### 2. Credential Hatası
```yaml
ad_query_result:
  success: false
  error: "LDAP authentication başarısız"
  details: "Kullanıcı adı veya şifre hatalı"
```

### 3. Tüm DC'ler Erişilemez
```yaml
ad_query_result:
  success: false
  error: "Hiçbir DC'ye bağlanılamadı"
  tried_servers:
    - hostname: "dc1.test.local.net"
      status: "connection_failed"
      attempts: 3
```

---

## Sertifika Yönetimi

### Sertifika Varsa:
```yaml
ad_cert_path: "/etc/ssl/certs/ad_chain.crt"
```
→ SSL doğrulama ENABLED (CERT_REQUIRED)

### Sertifika Yoksa:
→ Otomatik fallback CERT_NONE  
⚠️ Warning log'u verilir

---

## Default Attributes

### User:
```
cn, samaccountname, displayname, mail, userprincipalname,
memberof, whencreated, lastlogon, useraccountcontrol
```

### Computer:
```
cn, dnshostname, operatingsystem, operatingsystemversion,
whencreated, lastlogon, description
```

### Group:
```
cn, distinguishedname, samaccountname, description,
member, memberof, whencreated, whenchanged, grouptype, mail
```

---

## Multi-DC Davranış

### Akış:
1. DNS SRV → Tüm DC'leri bul
2. İlk erişilebilir DC'de **credential test** (bind)
3. Credential OK → Tüm DC'leri **sırayla search**
4. İlk bulduğunda **dur**
5. Hiçbirinde yoksa **found=false**

### Retry:
- Her DC için **3 retry** (5s interval)
- Bağlantı hatası → retry → next DC
- Object yok → next DC (replication delay)

---

## License

MIT

## Author

Enterprise IT Team

