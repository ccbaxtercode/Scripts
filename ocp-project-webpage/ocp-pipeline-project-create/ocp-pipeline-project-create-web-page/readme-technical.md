# Teknik Referans Dokümanı — Project Creator Web

Bu doküman, uygulamanın her kullanıcı etkileşiminde **hangi fonksiyonun, hangi dosyada, kaçıncı satırda çalıştığını** ve ne yaptığını adım adım açıklar.

---

## 1. Sayfa Yüklendiğinde

### Akış

```
Tarayıcı GET / → server.js (satır 377) → index.html serve edilir
                                            ↓
                            index.html <script> bloğu çalışır (satır 555)
                                            ↓
                            fetch('/api/users-groups') (satır 571)
                                            ↓
                            server.js /api/users-groups handler (satır 262)
                                            ↓
                            getUsersAndGroups() + getRoles()
                                            ↓
                            JSON response → initDropdowns() (satır 587)
```

### Detaylı Adımlar

| Adım | Dosya | Satır | Fonksiyon/Kod | Ne yapıyor |
|------|-------|-------|---------------|------------|
| 1 | server.js | 377 | `app.get('/')` | `public/index.html` dosyasını serve eder |
| 2 | server.js | 55-122 | `checkGroupAccess()` middleware | Her istekte `X-Remote-User` header'ından kullanıcı adını alır, `getUserGroups()` ile grup üyeliğini kontrol eder |
| 3 | server.js | 35-52 | `getUserGroups(username)` | `oc get groups -o json` çalıştırır, tüm grupları çeker, JS'de `Array.includes()` ile kullanıcıyı arar |
| 4 | index.html | 555-568 | Global değişken tanımları | `assignmentType`, `roleSelect`, `selectedUsers`, `selectedGroup` vb. |
| 5 | index.html | 571-585 | `fetch('/api/users-groups')` | Kullanıcı, grup ve rol listelerini API'den çeker |
| 6 | server.js | 262-266 | `app.get('/api/users-groups')` | `getUsersAndGroups()` ve `getRoles()` fonksiyonlarını çağırır |
| 7 | server.js | 131-152 | `getUsersAndGroups()` | `oc get users` ve `oc get groups` komutlarını çalıştırır, isimleri satır satır parse eder |
| 8 | server.js | 155-164 | `getRoles()` | `oc get clusterrole` çalıştırır, `ocp-` prefixli rolleri filtreler |
| 9 | index.html | 587-705 | `initDropdowns()` | Dropdown event listener'ları bağlar, rol listesini DOM'a yazar, user/group listelerini render eder |
| 10 | index.html | 692-701 | `initDropdowns()` → rol yükleme | `allRoles` dizisini döner, her rol için `<div class="list-item">` oluşturur |
| 11 | index.html | 1089 | `submitBtn.disabled = true` | Submit butonu başlangıçta devre dışı bırakılır |

### API Hata Durumu (sayfa yüklenirken)

| Adım | Dosya | Satır | Ne olur |
|------|-------|-------|---------|
| 1 | index.html | 579-585 | `.catch()` bloğu çalışır |
| 2 | index.html | 581-583 | Kırmızı hata mesajı gösterilir: "Failed to load users, groups, and roles" |
| 3 | index.html | 584 | `initDropdowns()` boş dizilerle çağrılır → dropdown'lar boş kalır |

---

## 2. Proje Adı Girildiğinde

### Akış

```
Kullanıcı input'a yazar
        ↓
debounce (500ms bekleme) — index.html satır 1036
        ↓
validateProjectName(name) — index.html satır 978
        ↓ (format geçerli ise)
checkProjectNameAvailability(name) — index.html satır 959
        ↓
fetch('/api/check-project-name/xxx') — index.html satır 968
        ↓
server.js /api/check-project-name/:name handler — satır 269
        ↓
Regex doğrulama + sanitizeForShell() + oc get project
        ↓
JSON response → UI güncelleme + modal gösterme
```

### Detaylı Adımlar

| Adım | Dosya | Satır | Fonksiyon/Kod | Ne yapıyor |
|------|-------|-------|---------------|------------|
| 1 | index.html | 1036 | `projectNameInput.addEventListener('input', debounce(..., 500))` | Her tuş vuruşunda 500ms bekler, son girişi işler |
| 2 | index.html | 943-950 | `debounce(func, delay)` | Closure ile timer tutar, her yeni input'ta önceki timer'ı iptal eder |
| 3 | index.html | 1037 | `const name = projectNameInput.value.trim()` | Input değerini alır, boşlukları temizler |
| 4 | index.html | 1080-1085 | Boşluk kontrolü | İsim boşsa: feedback temizlenir, ikon gizlenir, submit devre dışı |
| 5 | index.html | 978-1008 | `validateProjectName(name)` | **Client-side format validasyonu** (aşağıda detaylı) |
| 6 | index.html | 1041-1049 | Format hatalıysa | Feedback'e ilk hatayı yazar, kırmızı ✖ ikon gösterir, `showNameStatusModal()` ile modal açar, `return` ile durur — **API çağrısı yapılmaz** |
| 7 | index.html | 959-976 | `checkProjectNameAvailability(name)` | Feedback'e "Checking availability..." yazar, submit'i devre dışı bırakır, API çağırır |
| 8 | index.html | 960 | `encodeURIComponent(name)` | URL-safe encode (güvenlik) |
| 9 | index.html | 968 | `fetch(apiUrl)` | `GET /api/check-project-name/{name}` isteği gönderir |
| 10 | server.js | 269-290 | `app.get('/api/check-project-name/:name')` | Request handler |
| 11 | server.js | 273-276 | Regex kontrolü | `!/^[a-z][a-z0-9-]*[a-z0-9]$/` — format geçersizse 400 döner |
| 12 | server.js | 278 | `sanitizeForShell(name)` | Tehlikeli karakterleri temizler (command injection koruması) |
| 13 | server.js | 281 | `execSync('oc get project ...')` | OpenShift'te proje var mı kontrol eder (timeout: 10sn) |
| 14 | server.js | 284 | Proje varsa | `{ available: false }` döner |
| 15 | server.js | 288 | Proje yoksa | `{ available: true }` döner (catch bloğu — `oc get` hata verirse proje yok demek) |
| 16 | index.html | 1063-1069 | Müsait ise | Yeşil ✔ ikon, "Project name available!" feedback, submit aktif, yeşil modal |
| 17 | index.html | 1071-1078 | Müsait değilse | Kırmızı ✖ ikon, "Project name already exists." feedback, submit devre dışı, kırmızı modal |
| 18 | index.html | 1054-1062 | API erişilemezse | Sarı ⚠ ikon, "Could not verify" feedback, submit devre dışı |

### Client-Side Validasyon Kuralları (`validateProjectName` — satır 978-1008)

| Kural | Satır | Regex/Kontrol | Hata mesajı |
|-------|-------|---------------|-------------|
| Max 63 karakter | 983-985 | `name.length > 63` | "must be 63 characters or fewer" |
| RFC 1123 format | 988-990 | `/^[a-z][a-z0-9-]*[a-z0-9]$/` | "does not match RFC 1123" |
| `dev-` prefix zorunlu | 993-995 | `/^dev-/` | "must start with 'dev-' prefix" |
| Min 7 karakter | 998-1000 | `name.length < 7` (dev- sonrası min 3) | "must have at least 3 characters after 'dev-'" |

---

## 3. Assignment Type Seçildiğinde

### Akış

```
Kullanıcı "User" veya "Group" seçer
        ↓
assignmentType hidden input güncellenir — index.html satır 599
        ↓
'change' event dispatch edilir — index.html satır 603
        ↓
assignmentType change handler — index.html satır 738
        ↓
İlgili dropdown gösterilir/gizlenir
```

### Detaylı Adımlar

| Adım | Dosya | Satır | Ne yapıyor |
|------|-------|-------|------------|
| 1 | index.html | 592-605 | `assignmentTypeBtn` click handler | Dropdown açar/kapar, seçilen değeri hidden input'a yazar |
| 2 | index.html | 738-759 | `assignmentType.addEventListener('change')` | "user" seçildiyse user dropdown'ı gösterir, group gizler; "group" seçildiyse tersi |
| 3 | index.html | 746-748 | User seçildiğinde | `selectedGroup` sıfırlanır, `selectedUsers` temizlenir, user listesi render edilir |
| 4 | index.html | 752-754 | Group seçildiğinde | `selectedUsers` temizlenir, group listesi render edilir |

---

## 4. Kullanıcı/Grup Seçildiğinde

### User Seçimi

| Adım | Dosya | Satır | Fonksiyon | Ne yapıyor |
|------|-------|-------|-----------|------------|
| 1 | index.html | 637-650 | `userList.addEventListener('click')` | Tıklanan kullanıcıyı `selectedUsers` Set'ine ekler/çıkarır, `.selected` class'ını toggle eder |
| 2 | index.html | 733-736 | `updateUserDropdownText()` | Dropdown buton metnini seçili kullanıcı listesiyle günceller |
| 3 | index.html | 707-718 | `renderUserList(filter)` | Kullanıcı listesini filtreler ve DOM'a yazar, seçili olanları `.selected` class'ı ile işaretler |
| 4 | index.html | 633-635 | `userSearch.addEventListener('input')` | Arama kutusundaki her değişiklikte `renderUserList(filter)` çağırır |

### Group Seçimi

| Adım | Dosya | Satır | Fonksiyon | Ne yapıyor |
|------|-------|-------|-----------|------------|
| 1 | index.html | 665-674 | `groupList.addEventListener('click')` | Tıklanan grubu `selectedGroup` değişkenine atar, dropdown'ı kapar |
| 2 | index.html | 720-731 | `renderGroupList(filter)` | Grup listesini filtreler ve DOM'a yazar |
| 3 | index.html | 661-663 | `groupSearch.addEventListener('input')` | Arama kutusundaki her değişiklikte `renderGroupList(filter)` çağırır |

---

## 5. Form Submit Edildiğinde

### Akış

```
Submit butonuna tıklanır
        ↓
Form submit handler — index.html satır 890
        ↓
Client-side validasyon (4 kontrol)
        ↓ (geçerse)
getFormData() — index.html satır 761
        ↓
showApprovalModal(data) — index.html satır 780
        ↓
Kullanıcı "Confirm" tıklar
        ↓
createProject(data) — index.html satır 794
        ↓
fetch POST /api/create-project — index.html satır 802
        ↓
server.js /api/create-project handler — satır 300
        ↓
Server-side validasyon (4 kontrol)
        ↓ (geçerse)
triggerPipelineRun() — server.js satır 167
        ↓
YAML oluştur → oc apply → PipelineRun oluşturulur
        ↓
Response → pollPipelineRunStatus() başlar
```

### Detaylı Adımlar

| Adım | Dosya | Satır | Fonksiyon | Ne yapıyor |
|------|-------|-------|-----------|------------|
| 1 | index.html | 890 | `projectForm.addEventListener('submit')` | `e.preventDefault()` ile form'un normal submit'ini engeller |
| 2 | index.html | 894-898 | Validasyon #1 | `assignmentType.value` boşsa → hata mesajı, `return` |
| 3 | index.html | 899-903 | Validasyon #2 | "user" seçili ama `selectedUsers.size === 0` ise → hata |
| 4 | index.html | 904-908 | Validasyon #3 | "group" seçili ama `selectedGroup` boşsa → hata |
| 5 | index.html | 909-913 | Validasyon #4 | `roleSelect.value` boşsa → hata |
| 6 | index.html | 916 | `pendingData = getFormData()` | Form verilerini toplar |
| 7 | index.html | 761-778 | `getFormData()` | `projectName`, `assignmentType`, `userOrGroupName` (virgülle ayrılmış), `userOrGroupNames` (dizi), `role`, `quota` objesi oluşturur |
| 8 | index.html | 917 | `showApprovalModal(pendingData)` | Onay modalını açar |
| 9 | index.html | 780-790 | `showApprovalModal(data)` | `projectSummary` HTML'ini doldurur, modalı `display: flex` yapar |
| 10 | index.html | 920-927 | `btnConfirm.addEventListener('click')` | Modal kapatılır, `submitBtn` devre dışı, `createProject(pendingData)` çağrılır |
| 11 | index.html | 794-831 | `createProject(data)` | "⏳ Creating project..." mesajı gösterir, `POST /api/create-project` gönderir |
| 12 | index.html | 802-806 | `fetch()` çağrısı | JSON body ile POST isteği |
| 13 | server.js | 300-357 | `app.post('/api/create-project')` | Request handler |
| 14 | server.js | 304-307 | Zorunlu alan kontrolü | `projectName`, `assignmentType`, `userOrGroupName` yoksa 400 döner |
| 15 | server.js | 310-326 | Server-side validasyon | RFC 1123, `dev-` prefix, max 63, min 7 karakter kontrolü |
| 16 | server.js | 329-336 | `triggerPipelineRun()` çağrısı | 6 parametre ile çağırır, eksik değerlere default atar |
| 17 | server.js | 167-202 | `triggerPipelineRun()` | PipelineRun YAML objesi oluşturur, `/tmp/pipelinerun-xxx.yaml` dosyasına yazar, `oc apply -f` ile uygular |
| 18 | server.js | 168 | `sanitizedProject` | Proje adını `[^a-z0-9-]` regex'i ile temizler |
| 19 | server.js | 169 | `pipelineRunName` | `create-project-{name}-{timestamp}-{random6hex}` formatında benzersiz isim üretir |
| 20 | server.js | 192 | `yaml.dump(pipelineRun)` | JS objesini YAML'a çevirir |
| 21 | server.js | 195 | `execSync('oc apply -f ...')` | PipelineRun'ı OpenShift'e gönderir (timeout: 30sn) |
| 22 | server.js | 196 | `fs.unlinkSync(tempFile)` | Geçici YAML dosyasını siler |
| 23 | server.js | 246-259 | `getConsoleUrl(namespace, name)` | OpenShift Console URL'i oluşturur (`oc get consoles.operator.openshift.io`) |
| 24 | index.html | 810-814 | Başarılı response | "PipelineRun triggered" mesajı, `pollPipelineRunStatus()` başlatılır |
| 25 | index.html | 815-824 | Başarısız response | Hata mesajı + Console URL linki gösterilir |

---

## 6. PipelineRun Durum Takibi (Polling)

### Akış

```
pollPipelineRunStatus() başlar — index.html satır 833
        ↓ (her 5 saniyede bir)
fetch GET /api/pipelinerun-status/{name} — index.html satır 846
        ↓
server.js handler — satır 360
        ↓
Regex doğrulama + sanitize + getPipelineRunStatus()
        ↓
oc get pipelinerun → status parse → JSON response
        ↓
isComplete? → Evet: sonuç göster / Hayır: 5sn sonra tekrar
```

### Detaylı Adımlar

| Adım | Dosya | Satır | Fonksiyon | Ne yapıyor |
|------|-------|-------|-----------|------------|
| 1 | index.html | 833-888 | `pollPipelineRunStatus(name, formData)` | Recursive `setTimeout` ile polling başlatır |
| 2 | index.html | 835 | `maxRetries = 120` | 120 × 5sn = 10 dakika max bekleme |
| 3 | index.html | 839-843 | Timeout kontrolü | 120 denemeyi aşarsa "Timeout" hatası gösterir |
| 4 | index.html | 846 | `fetch('/api/pipelinerun-status/{name}')` | Durum sorgulama API'sini çağırır |
| 5 | server.js | 360-375 | `app.get('/api/pipelinerun-status/:name')` | Request handler |
| 6 | server.js | 364-367 | Regex doğrulama | `/^[a-z0-9][a-z0-9.-]*[a-z0-9]$/` — geçersizse 400 döner |
| 7 | server.js | 369 | `sanitizeForShell(name)` | İsmi temizler |
| 8 | server.js | 370 | `getPipelineRunStatus(safeName)` | Durumu sorgular |
| 9 | server.js | 205-244 | `getPipelineRunStatus(name)` | `oc get pipelinerun` çalıştırır, JSONPath ile condition, status, reason, namespace, completionTime çeker |
| 10 | server.js | 211 | Output parse | `:` ile ayırır: `conditionTypes:conditionStatuses:reason:namespace:completionTime` |
| 11 | server.js | 222-229 | Durum belirleme | `Succeeded && True` → Succeeded, `Failed || False` → Failed, aksi halde Running |
| 12 | server.js | 371-373 | Console URL ekleme | Status Unknown değilse `getConsoleUrl()` ile Console linki ekler |
| 13 | index.html | 848 | `data.isComplete` kontrolü | `true` ise polling durur, `false` ise devam |
| 14 | index.html | 850-864 | Succeeded durumu | Yeşil başarı mesajı: proje adı, rol ataması, kotalar gösterilir |
| 15 | index.html | 865-877 | Failed durumu | Kırmızı hata mesajı + Console URL linki |
| 16 | index.html | 880-881 | Running durumu | "⏳ Waiting..." mesajı güncellenir, `setTimeout(checkStatus, 5000)` ile 5sn sonra tekrar |

---

## 7. Güvenlik Katmanları — Kod Haritası

### Command Injection Koruması

| Koruma | Dosya | Satır | Ne yapıyor |
|--------|-------|-------|------------|
| `sanitizeForShell()` | server.js | 25-28 | `[^a-z0-9A-Z._@-]` dışındaki tüm karakterleri temizler |
| Proje adı regex | server.js | 273 | `/^[a-z][a-z0-9-]*[a-z0-9]$/` — geçersiz formatları reddeder |
| PipelineRun adı regex | server.js | 364 | `/^[a-z0-9][a-z0-9.-]*[a-z0-9]$/` — geçersiz formatları reddeder |
| `getUserGroups()` sabit komut | server.js | 40 | Kullanıcı girdisi shell'e interpolasyon yapılmıyor, JS'de filtreleniyor |

### Timeout Koruması

| Fonksiyon | Dosya | Satır | Timeout |
|-----------|-------|-------|---------|
| `getUserGroups()` | server.js | 41 | 10sn |
| `getUsersAndGroups()` - users | server.js | 136 | 10sn |
| `getUsersAndGroups()` - groups | server.js | 143 | 10sn |
| `getRoles()` | server.js | 157 | 10sn |
| `triggerPipelineRun()` - oc apply | server.js | 195 | 30sn |
| `getPipelineRunStatus()` | server.js | 209 | 10sn |
| `getConsoleUrl()` | server.js | 250 | 10sn |
| `check-project-name` - oc get | server.js | 281 | 10sn |

### Client-Side Validasyon (API çağrısı yapılmadan önce)

| Kontrol | Dosya | Satır | API çağrısı engellenir mi? |
|---------|-------|-------|---------------------------|
| Proje adı format kontrolü | index.html | 978-1008 | ✅ Evet — `return` ile durur |
| Assignment type seçimi | index.html | 894-898 | ✅ Evet — `return` ile durur |
| User/Group seçimi | index.html | 899-908 | ✅ Evet — `return` ile durur |
| Role seçimi | index.html | 909-913 | ✅ Evet — `return` ile durur |

---

## 8. Namespace Algılama

| Adım | Dosya | Satır | Ne yapıyor |
|------|-------|-------|------------|
| 1 | server.js | 14 | `/var/run/secrets/kubernetes.io/serviceaccount/namespace` dosyasını okumaya çalışır |
| 2 | server.js | 15 | Başarılıysa → `CURRENT_NAMESPACE` değişkenine atar |
| 3 | server.js | 17 | Başarısızsa → `process.env.NAMESPACE` veya fallback `'project-creator'` |
| 4 | server.js | 346, 354 | `getConsoleUrl(CURRENT_NAMESPACE, ...)` çağrılarında kullanılır |

---

## 9. Dosya → Fonksiyon Haritası

### server.js (380 satır)

| Satır | Fonksiyon/Handler | Tip |
|-------|-------------------|-----|
| 11-19 | Namespace algılama | Startup |
| 22 | `ALLOWED_GROUPS` parse | Startup |
| 25-28 | `sanitizeForShell(input)` | Yardımcı |
| 31-32 | `/health`, `/ready` | Endpoint (auth bypass) |
| 35-52 | `getUserGroups(username)` | Yardımcı |
| 55-122 | `checkGroupAccess(req, res, next)` | Middleware |
| 131-152 | `getUsersAndGroups()` | Yardımcı |
| 155-164 | `getRoles()` | Yardımcı |
| 167-202 | `triggerPipelineRun(...)` | Yardımcı |
| 205-244 | `getPipelineRunStatus(name)` | Yardımcı |
| 247-259 | `getConsoleUrl(namespace, name)` | Yardımcı |
| 262-266 | `GET /api/users-groups` | Endpoint |
| 269-290 | `GET /api/check-project-name/:name` | Endpoint |
| 293-297 | `GET /api/me` | Endpoint |
| 300-357 | `POST /api/create-project` | Endpoint |
| 360-375 | `GET /api/pipelinerun-status/:name` | Endpoint |
| 377 | `GET /` | Endpoint |
| 379 | `app.listen()` | Startup |

### index.html — JavaScript bölümü (satır 555-1090)

| Satır | Fonksiyon | Tip |
|-------|-----------|-----|
| 555-568 | Global değişkenler | Tanım |
| 571-585 | `fetch('/api/users-groups')` | Startup API çağrısı |
| 587-705 | `initDropdowns()` | UI başlatma |
| 707-718 | `renderUserList(filter)` | UI render |
| 720-731 | `renderGroupList(filter)` | UI render |
| 733-736 | `updateUserDropdownText()` | UI güncelleme |
| 738-759 | `assignmentType.change` handler | Event handler |
| 761-778 | `getFormData()` | Veri toplama |
| 780-790 | `showApprovalModal(data)` | UI modal |
| 792 | `hideModal()` | UI modal |
| 794-831 | `createProject(data)` | API çağrısı |
| 833-888 | `pollPipelineRunStatus(name, data)` | Polling |
| 890-918 | Form submit handler | Event handler |
| 920-927 | Confirm butonu handler | Event handler |
| 929-932 | Cancel butonu handler | Event handler |
| 934-936 | Modal dışı tıklama handler | Event handler |
| 943-950 | `debounce(func, delay)` | Yardımcı |
| 959-976 | `checkProjectNameAvailability(name)` | API çağrısı |
| 978-1008 | `validateProjectName(name)` | Client validasyon |
| 1010-1025 | `showNameStatusModal(...)` | UI modal |
| 1027-1029 | `hideNameStatusModal()` | UI modal |
| 1036-1086 | `projectNameInput` input handler | Event handler + iş mantığı |
