# Teknik Referans Dokümanı — Project Creator Web

Bu doküman, uygulamanın her kullanıcı etkileşiminde **hangi fonksiyonun, hangi dosyada, kaçıncı satırda çalıştığını** ve ne yaptığını adım adım açıklar.

**Dosya boyutları:** server.js — 480 satır | index.html — 1351 satır

---

## 0. Mimari ve Güvenlik Modeli

```
Kullanıcı → Route (HTTPS) → OAuth Proxy (SAR + Cookie) → Node.js App (Express)
                 ↓                              ↓                ↓
          Keycloak Login            X-Forwarded-User       Business Logic
                                    X-Remote-User (fallback)
```

### Güvenlik Katmanları

| Katman | Bileşen | Kontrol |
|--------|---------|---------|
| Auth | OAuth Proxy — `--openshift-sar` | Kullanıcının service üzerinde `get` yetkisi var mı? |
| Session | OAuth Proxy — cookie | 8 saat expire, 15 dk refresh |
| App | `checkGroupAccess()` middleware | `x-forwarded-user` header var mı? (sadece login kontrolü) |
| Team | `/api/check-team-access/:team` | Kullanıcı group-dev/test/prod üyesi mi? |
| Create | `/api/create-project` | CSRF + rate limit + input validasyonu + team yetkisi |
| API | ClusterRole `project-creator-web-access` | SA bazında API izinleri (oc komutları) |

---

## 1. Sayfa Yüklendiğinde

### Akış

```
Tarayıcı → OAuth Proxy (SAR) → GET / → server.js:478 → index.html serve
                                            ↓
                              <script> bloğu çalışır (satır 620)
                                            ↓
                    ┌─ fetch /api/users-groups (satır 656) ─┐
                    │  → server.js:283 → getUsersAndGroups()│
                    │  → 5dk cache → JSON → initDropdowns()│
                    └────────────────────────────────────────┘
                    ┌─ fetch /api/csrf-token (satır 673) ───┐
                    │  → server.js:337 → HMAC token         │
                    └────────────────────────────────────────┘
                                            ↓
                              submitBtn.disabled = true (satır 1341)
```

### Detaylı Adımlar

| Adım | Dosya | Satır | Fonksiyon | Ne yapıyor |
|------|-------|-------|-----------|------------|
| 1 | server.js | 478 | `app.get('/')` | `public/index.html` serve eder |
| 2 | server.js | 208-240 | `checkGroupAccess()` | `x-forwarded-user` veya `x-remote-user` header'ından kullanıcı adını alır. Header yoksa 401 döner. **Not:** Eskiden ALLOWED_GROUPS kontrolü yapılırdı, artık bunu SAR üstleniyor. |
| 3 | server.js | 78-103 | `getUserGroups(username)` | `sanitizeForShell()` ile temizler, `oc get groups -o json \| jq` çalıştırır. Per-user 5dk cache (satır 75-76). |
| 4 | index.html | 620-636 | Global değişkenler | `csrfToken`, `selectedUsers` (Set), `selectedGroup`, `selectedTeam`, `currentPrefix`, `projectNameValid` |
| 5 | index.html | 656-671 | `fetch('/api/users-groups')` | Kullanıcı, grup ve rol listesini API'den çeker |
| 6 | server.js | 283-285 | `/api/users-groups` handler | `getUsersAndGroups()` çağırır |
| 7 | server.js | 252-276 | `getUsersAndGroups()` | `oc get users`, `oc get groups`, `oc get clusterrole` çalıştırır. 5dk cache (satır 30). |
| 8 | index.html | 673-677 | `fetch('/api/csrf-token')` | CSRF token'ı alır, `csrfToken` değişkenine kaydeder |
| 9 | server.js | 337-344 | `/api/csrf-token` handler | `HMAC(username.timestamp, CSRF_SECRET)` ile token üretir, 8 saat geçerli |
| 10 | index.html | 679-734 | `initDropdowns()` | Dropdown event listener'ları bağlar, rol listesini DOM'a yazar, user/group render eder |
| 11 | index.html | 1341 | `submitBtn.disabled = true` | Submit butonu başlangıçta devre dışı |

### API Hata Durumu

| Adım | Dosya | Satır | Ne olur |
|------|-------|-------|---------|
| 1 | index.html | 665-670 | `/api/users-groups` başarısız → kırmızı hata: "Failed to load..." |
| 2 | index.html | 677 | `/api/csrf-token` başarısız → console.error, token boş kalır → POST 403 alır |

---

## 2. Takım Seçildiğinde

### Akış

```
Kullanıcı "dev" seçer (dropdown)
        ↓
teamList click handler → index.html satır 685
        ↓
fetch /api/check-team-access/dev (satır 696)
        ↓
server.js:289 → TEAM_CONFIG kontrolü → getUserGroups(username) → cache
        ↓
authorized? → prefix + erişim durumu döner
        ↓
Evet: prefix otomatik eklenir, project input aktif olur
Hayır: "Access denied — not a member of group-dev"
```

### Detaylı Adımlar

| Adım | Dosya | Satır | Ne yapıyor |
|------|-------|-------|------------|
| 1 | index.html | 681-683 | `teamBtn` click → dropdown açar/kapar |
| 2 | index.html | 685-734 | `teamList` click → takım seçilir |
| 3 | index.html | 691-693 | "Checking team access..." feedback gösterir |
| 4 | index.html | 696 | `fetch('/api/check-team-access/${team}')` |
| 5 | server.js | 289-303 | Handler: `TEAM_CONFIG[team]` validasyonu, `getUserGroups(username)` ile grup kontrolü |
| 6 | server.js | 301-302 | `authorized` = `userGroups.includes(requiredGroup)` |
| 7 | index.html | 698-714 | Yetkili ise: prefix UI'a yazılır, project name input aktif |
| 8 | index.html | 716-727 | Yetkisiz ise: "Access denied — not a member of group-X" |

**Not:** `getUserGroups()` 5dk per-user cache kullanır. Aynı kullanıcı için tekrarlı API çağrısı yapılmaz.

---

## 3. Proje Adı Girildiğinde

### Akış

```
Kullanıcı input'a yazar
        ↓
debounce (500ms) — index.html satır 1276
        ↓
validateProjectName(name) — index.html satır 1218
        ↓ (format geçerli ise)
checkProjectNameAvailability(name) — index.html satır 1199
        ↓
fetch /api/check-project-name/xxx → server.js:306
        ↓
Server: regex → sanitizeForShell() → oc get project
        ↓
JSON → UI güncelleme + modal
```

### Client-Side Validasyon (`validateProjectName` — satır 1218-1248)

| Kural | Satır | Kontrol | Hata |
|-------|-------|---------|------|
| Max 63 karakter | 1223-1225 | `name.length > 63` | "must be 63 characters or fewer" |
| RFC 1123 | 1228-1230 | `/^[a-z][a-z0-9-]*[a-z0-9]$/` | "does not match RFC 1123" |
| Team prefix | 1233-1235 | `name.startsWith(currentPrefix)` | "must start with 'dev-' prefix" |
| Min uzunluk | 1238-1240 | `name.length < prefix.length + 3` | "must have at least 3 chars after prefix" |

### Server-Side Doğrulama (satır 306-324)

| Adım | Satır | Ne yapıyor |
|------|-------|------------|
| Regex | 311-313 | `/^[a-z][a-z0-9-]*[a-z0-9]$/` → geçersizse 400 |
| sanitize | 316 | `sanitizeForShell(name)` |
| oc get | 319 | `oc get project {safeName}` → varsa available:false |

---

## 4. Form Doldurma — Assignment Type, User/Group, Role

### Assignment Type Seçimi

| Adım | Dosya | Satır | Ne yapıyor |
|------|-------|-------|------------|
| 1 | index.html | 737-743 | `assignmentTypeBtn` click → dropdown açar |
| 2 | index.html | 744-753 | `assignmentTypeList` click → hidden input güncellenir, change event dispatch |
| 3 | index.html | 892-914 | change handler: "user" → user dropdown göster, group gizle; "group" → tersi |

### User Seçimi (multi-select)

| Adım | Dosya | Satır | Ne yapıyor |
|------|-------|-------|------------|
| 1 | index.html | 778-784 | `userBtn` click → dropdown açar |
| 2 | index.html | 782-784 | `userSearch` input → `renderUserList(filter)` |
| 3 | index.html | 786-800 | `userList` click → toggle `selectedUsers` Set, `.selected` class |
| 4 | index.html | 861-872 | `renderUserList(filter)` → filtreler, DOM yazar, seçili olanları işaretler |
| 5 | index.html | 887-890 | `updateUserDropdownText()` → buton metnini günceller |

### Group Seçimi (single-select)

| Adım | Dosya | Satır | Ne yapıyor |
|------|-------|-------|------------|
| 1 | index.html | 803-805 | `groupBtn` click → dropdown açar |
| 2 | index.html | 807-809 | `groupSearch` input → `renderGroupList(filter)` |
| 3 | index.html | 811-820 | `groupList` click → `selectedGroup` atanır, dropdown kapanır |
| 4 | index.html | 874-884 | `renderGroupList(filter)` → filtreler, DOM yazar |

### Role Seçimi

| Adım | Dosya | Satır | Ne yapıyor |
|------|-------|-------|------------|
| 1 | index.html | 756-758 | `roleBtn` click → dropdown açar |
| 2 | index.html | 759-766 | `roleList` click → `roleSelect.value` güncellenir, `updateSubmitButtonState()` |

### Submit Buton Durumu (`updateSubmitButtonState` — satır 638-654)

Butonun aktif olması için **tüm** koşullar sağlanmalı:
- `selectedTeam !== ''`
- `assignmentType.value !== ''`
- `roleSelect.value !== ''`
- Assignment type'a göre user/group seçilmiş
- `projectNameValid === true`
- Proje adı dolu

---

## 5. Form Submit — Create Project (En Kritik Bölüm)

### Tam Akış

```
Submit butonu tıklanır
        ↓
Form submit handler (index.html:1125) → client validasyon (5 kontrol)
        ↓ (geçerse)
getFormData() (index.html:916) → showApprovalModal()
        ↓
Kullanıcı "Confirm" tıklar → btnConfirm handler (index.html:1160)
        ↓
createProject(data) → fetch POST /api/create-project
        ↓
server.js POST handler (satır 346): 7 katmanlı kontrol zinciri
        ├─ 1. Zorunlu alanlar (satır 350) → 400
        ├─ 2. CSRF token (satır 355) → 403
        ├─ 3. Rate limit (satır 361) → 429
        ├─ 4. userOrGroupName validasyonu (satır 366) → 400
        ├─ 5. Quota validasyonu (satır 378) → 400
        ├─ 6. Proje adı format (satır 395) → 400
        ├─ 7. Team yetki kontrolü (satır 406) → 403
        ↓ (hepsi geçerse)
triggerPipelineRun() → YAML oluştur → oc apply → PipelineRun
        ↓
Response → pollPipelineRunStatus() başlar
```

### Server-Side Güvenlik Zinciri (server.js satır 346-457)

| # | Kontrol | Satır | Ne yapıyor | Hata |
|---|---------|-------|------------|------|
| 1 | Zorunlu alanlar | 350-353 | `projectName`, `assignmentType`, `userOrGroupName` boş mu? | 400 |
| 2 | CSRF | 355-359 | `X-CSRF-Token` header → HMAC doğrulama | 403 |
| 3 | Rate limit | 361-364 | `checkRateLimit(username)` → 5 istek/dk | 429 |
| 4 | userOrGroupName | 366-377 | Seçilen kullanıcı/grup dropdown listesinde var mı? | 400 |
| 5 | Quota | 378-389 | CPU: `/^\d+(\.\d+)?$/`, Memory/Storage: `/^\d+(\.\d+)?[GM]i$/` | 400 |
| 6 | Proje adı | 395-404 | RFC 1123, prefix, max 63, min uzunluk | 400 |
| 7 | Team yetki | 406-419 | Kullanıcı `group-dev/test/prod` üyesi mi? (curl bypass engeli) | 403 |

### `triggerPipelineRun()` Detayı (server.js satır 105-141)

| Adım | Satır | Ne yapıyor |
|------|-------|------------|
| 1 | 106 | `sanitizedProject` = proje adını `[^a-z0-9-]` ile temizler |
| 2 | 108-115 | **PipelineRun isim kısaltma**: prefix(15) + proje adı + suffix(23) > 63 ise proje adı 20 karaktere kısaltılır + 4 hex hash eklenir |
| 3 | 116 | `pipelineRunName` = `create-project-{projeSegment}-{timestamp}-{8hex}` |
| 4 | 118-137 | PipelineRun YAML objesi oluşturur (9 parametre) |
| 5 | 139 | `/tmp/pipelinerun-{timestamp}-{8hex}.yaml` dosyasına yazar |
| 6 | 142 | `oc apply -f {tempFile}` ile PipelineRun'ı oluşturur (timeout: 30sn) |
| 7 | 143-144 | Başarılı → temp dosyayı siler, `{success: true, pipelineRun: name}` döner |
| 8 | 145-146 | Başarısız → temp dosyayı siler, `{success: false, message}` döner |

### CSRF Mekanizması

| Adım | Dosya | Satır | Ne yapıyor |
|------|-------|-------|------------|
| 1 | server.js | 33 | `CSRF_SECRET = crypto.randomBytes(32)` — sunucu başlangıcında üretilir |
| 2 | index.html | 673 | Sayfa yüklenirken `GET /api/csrf-token` çağrılır |
| 3 | server.js | 337-344 | `HMAC-SHA256(username.timestamp, CSRF_SECRET)` → `{token: "user.ts.sig"}` |
| 4 | index.html | 677 | Token `csrfToken` değişkenine kaydedilir |
| 5 | index.html | 968 | POST isteğine `X-CSRF-Token` header'ı eklenir |
| 6 | server.js | 355-359 | `validateCsrfToken(token, username)` → HMAC + TTL (8h) kontrolü |

### Rate Limit Mekanizması

| Adım | Satır | Ne yapıyor |
|------|-------|------------|
| Tanım | 37-39 | `rateLimitMap = {}`, window: 60sn, max: 5 istek |
| Kontrol | 41-52 | `checkRateLimit(username)`: zaman damgalarını temizler, limit aşıldıysa false döner |
| Kullanım | 361 | `/api/create-project` içinde çağrılır |

---

## 6. PipelineRun Durum Takibi (Polling)

### Akış

```
pollPipelineRunStatus() başlar — index.html:1002
        ↓ (her 5 saniyede bir)
fetch GET /api/pipelinerun-status/{name} → server.js:461
        ↓
Regex doğrulama (satır 465) → sanitizeForShell (satır 471) → getPipelineRunStatus()
        ↓
oc get pipelinerun → JSONPath parse → status/reason/namespace
        ↓
isComplete? → Evet: sonuç göster + resetForm() / Hayır: setTimeout(5000)
```

### Detay

| Adım | Dosya | Satır | Ne yapıyor |
|------|-------|-------|------------|
| 1 | index.html | 1002-1083 | `pollPipelineRunStatus(name, formData)` — recursive `setTimeout` loop |
| 2 | index.html | 1004 | `maxRetries = 120` (120 × 5sn = 10 dk max) |
| 3 | index.html | 1005-1008 | Progress steps: Creating project → Creating quota → Setting up network → Assigning role → Finalizing |
| 4 | index.html | 1027-1031 | Timeout: 120 deneme aşılırsa "Timeout" hatası |
| 5 | index.html | 1033 | `fetch('/api/pipelinerun-status/{name}')` |
| 6 | server.js | 461-476 | Handler: regex validasyon → sanitize → `getPipelineRunStatus()` |
| 7 | server.js | 152-192 | `getPipelineRunStatus(name)`: `oc get pipelinerun` ile JSONPath sorgusu |
| 8 | server.js | 163 | Parse: `:` ile 5 parçaya ayırır (types:statuses:reason:namespace:completionTime) |
| 9 | server.js | 169-179 | Durum belirleme: Succeeded+True → Succeeded, Failed/False → Failed |
| 10 | server.js | 472-474 | Console URL ekler (`getConsoleUrl()`) |
| 11 | index.html | 1035-1038 | `isComplete === true` → polling durur |
| 12 | index.html | 1040-1056 | Succeeded → yeşil mesaj, proje detayları, `resetForm()` |
| 13 | index.html | 1057-1069 | Failed → kırmızı mesaj, console linki |
| 14 | index.html | 1072-1075 | Running → "Waiting... (X%)" mesajı, 5sn sonra tekrar |
| 15 | index.html | 1076 | `setTimeout(checkStatus, 5000)` |

### Progress Bar (buton üzerinde)

| CSS | Satır | Ne yapıyor |
|-----|-------|------------|
| `.btn-progress` | 313-324 | Buton üzerinde soldan sağa dolan yeşil bar |
| `shimmer` | 326-329 | Sürekli parıltı efekti |
| `progress-fill` | 331-334 | `width: 0 → 100%`, süre: `--progress-duration` (600s) |
| JS | 957 | `submitBtn.style.setProperty('--progress-duration', '600s')` |

### Form Reset (`resetForm()` — index.html:1085-1123)

Pipeline başarıyla tamamlanınca çağrılır:
- Seçili takım, kullanıcı/grup, rol sıfırlanır
- Proje adı temizlenir, devre dışı bırakılır
- Dropdown metinleri varsayılana döner
- Quota değerleri default'a döner (CPU:2, Memory:4Gi, Storage:10Gi)
- Submit butonu devre dışı

---

## 7. Tüm Güvenlik Önlemleri — Kod Haritası

### Input Validasyonu & Injection Koruması

| Koruma | Dosya | Satır | Ne yapıyor |
|--------|-------|-------|------------|
| `sanitizeForShell()` | server.js | 65-68 | `[^a-z0-9A-Z._@-]` dışındaki tüm karakterleri temizler |
| Proje adı regex | server.js | 311 | `/^[a-z][a-z0-9-]*[a-z0-9]$/` — RFC 1123 |
| PipelineRun adı regex | server.js | 465 | `/^[a-z0-9][a-z0-9.-]*[a-z0-9]$/` |
| username sanitize | server.js | 81 | `sanitizeForShell(username)` — shell injection engeli |
| userOrGroupName | server.js | 366-377 | Dropdown listesinde var mı kontrolü |
| Quota regex | server.js | 378-389 | CPU: sayı, Memory/Storage: sayı+Gi/Mi |

### Yetkilendirme Kontrolleri

| Kontrol | Dosya | Satır | Açıklama |
|---------|-------|-------|----------|
| SAR (OAuth Proxy) | deployment.yaml | 122 | `get services/project-creator-web` — sayfa erişimi |
| Login check | server.js | 208-240 | `checkGroupAccess()` — header varlığı |
| Team check (UI) | server.js | 289-303 | `/api/check-team-access/:team` — grup üyeliği |
| Team check (API) | server.js | 406-419 | `/api/create-project` içinde — curl bypass engeli |
| CSRF | server.js | 54-63, 355 | HMAC token + X-CSRF-Token header |
| Rate limit | server.js | 41-52, 361 | 5 istek/dk/kullanıcı |

### Cache Stratejisi

| Cache | TTL | Dosya:Satır | Kapsam |
|-------|-----|-------------|--------|
| `usersGroupsCache` | 5 dk | server.js:30, 249 | Tüm kullanıcı/grup/rol listesi (dropdown için) |
| `userGroupCache` | 5 dk | server.js:75-76, 78-103 | Per-user grup üyeliği (yetkilendirme için) |
| CSRF token | 8 saat | server.js:34 | Session süresiyle aynı |

**Not:** Yeni yetki eklenen kullanıcı 5 dakika içinde göremez. Bu bilinçli bir trade-off.

### Timeout Koruması (tüm `execSync` çağrıları)

| Fonksiyon | Satır | Timeout |
|-----------|-------|---------|
| `getUserGroups()` | 89 | 10sn |
| `getUsersAndGroups()` — users | 256 | 10sn |
| `getUsersAndGroups()` — groups | 260 | 10sn |
| `getUsersAndGroups()` — roles | 264 | 10sn |
| `triggerPipelineRun()` — oc apply | 142 | 30sn |
| `getPipelineRunStatus()` | 157 | 10sn |
| `getConsoleUrl()` | 197 | 10sn |
| `/api/check-project-name` — oc get | 319 | 10sn |

### Subresource Kontrolü — PipelineRun İsim Uzunluğu

| Koruma | Dosya | Satır | Ne yapıyor |
|--------|-------|-------|------------|
| İsim kısaltma | server.js | 108-115 | PipelineRun adı > 63 karakter ise proje adı kısaltılır + hash eklenir (Kubernetes label limiti) |
| Temp dosya | server.js | 139 | `Date.now()-crypto.randomBytes(4)` — race condition engeli |

### Client-Side Validasyon (API çağrısı yapılmadan önce)

| Kontrol | Dosya | Satır | API engellenir mi? |
|---------|-------|-------|--------------------|
| Proje adı formatı | index.html | 1218-1248 | Evet — `return` |
| Takım seçimi | index.html | 1129-1133 | Evet — `return` |
| Assignment type | index.html | 1134-1137 | Evet — `return` |
| User/Group seçimi | index.html | 1138-1147 | Evet — `return` |
| Role seçimi | index.html | 1148-1153 | Evet — `return` |

---

## 8. Namespace Algılama

| Adım | Dosya | Satır | Ne yapıyor |
|------|-------|-------|------------|
| 1 | server.js | 14 | `/var/run/secrets/kubernetes.io/serviceaccount/namespace` okur |
| 2 | server.js | 15 | Başarılı → `CURRENT_NAMESPACE` |
| 3 | server.js | 17 | Başarısız → `process.env.NAMESPACE` veya `'project-creator'` |
| 4 | server.js | 434, 444 | Console URL'lerinde kullanılır |

---

## 9. Dosya → Fonksiyon Haritası

### server.js (480 satır)

| Satır | İçerik | Tip |
|-------|--------|-----|
| 1-6 | require'lar (express, child_process, js-yaml, fs, path, crypto) | Import |
| 8-9 | `app`, `PORT` | Startup |
| 11-18 | Namespace algılama | Startup |
| 22-27 | `TEAM_CONFIG`, `VALID_PREFIXES` | Startup |
| 30 | `USERS_GROUPS_CACHE_TTL` (5dk) | Sabit |
| 33-34 | `CSRF_SECRET`, `CSRF_TTL` (8h) | Sabit |
| 37-39 | `rateLimitMap`, window, max | Sabit |
| 41-52 | `checkRateLimit(username)` | Güvenlik |
| 54-63 | `validateCsrfToken(token, username)` | Güvenlik |
| 65-68 | `sanitizeForShell(input)` | Yardımcı |
| 71-72 | `/health`, `/ready` | Endpoint (auth bypass) |
| 75-76 | `userGroupCache`, `USER_GROUP_CACHE_TTL` | Cache |
| 78-103 | `getUserGroups(username)` | Yardımcı (cache'li) |
| 105-149 | `triggerPipelineRun(projectName, ...)` | Yardımcı |
| 152-192 | `getPipelineRunStatus(name)` | Yardımcı |
| 194-206 | `getConsoleUrl(namespace, name)` | Yardımcı |
| 208-240 | `checkGroupAccess(req, res, next)` | Middleware |
| 243-246 | `app.use()` zinciri | Middleware |
| 249-276 | `getUsersAndGroups()` | Yardımcı (cache'li) |
| 283-285 | `GET /api/users-groups` | Endpoint |
| 289-303 | `GET /api/check-team-access/:team` | Endpoint |
| 306-324 | `GET /api/check-project-name/:name` | Endpoint |
| 330-336 | `GET /api/me` | Endpoint |
| 337-344 | `GET /api/csrf-token` | Endpoint |
| 346-457 | `POST /api/create-project` | Endpoint (7 katman kontrol) |
| 461-476 | `GET /api/pipelinerun-status/:name` | Endpoint |
| 478 | `GET /` | Endpoint |
| 480 | `app.listen()` | Startup |

### index.html JavaScript (satır 620-1344)

| Satır | İçerik | Tip |
|-------|--------|-----|
| 620-636 | Global değişkenler (`csrfToken` dahil) | Tanım |
| 638-654 | `updateSubmitButtonState()` | UI |
| 656-671 | `fetch /api/users-groups` | API çağrısı |
| 673-677 | `fetch /api/csrf-token` | API çağrısı |
| 679-734 | `initDropdowns()` | UI başlatma |
| 736-760 | Role/Assignment type event handler'ları | Event |
| 778-800 | User dropdown event handler'ları | Event |
| 803-820 | Group dropdown event handler'ları | Event |
| 861-884 | `renderUserList()`, `renderGroupList()` | UI render |
| 887-890 | `updateUserDropdownText()` | UI |
| 892-914 | `assignmentType.change` handler | Event |
| 916-934 | `getFormData()` | Veri |
| 936-948 | `showApprovalModal()`, `hideModal()` | UI modal |
| 951-999 | `createProject(data)` → `fetch POST` (CSRF header'lı) | API çağrısı |
| 1002-1083 | `pollPipelineRunStatus(name, data)` | Polling |
| 1085-1123 | `resetForm()` | UI reset |
| 1125-1158 | Form submit handler (5 client validasyon) | Event |
| 1160-1176 | Confirm/Cancel modal butonları | Event |
| 1183-1190 | `debounce(func, delay)` | Yardımcı |
| 1199-1216 | `checkProjectNameAvailability(name)` | API çağrısı |
| 1218-1248 | `validateProjectName(name)` | Validasyon |
| 1250-1274 | `showNameStatusModal()`, `hideNameStatusModal()` | UI modal |
| 1276-1330 | `projectNameInput` input handler (debounce + validate + check) | Event + iş mantığı |
| 1341 | `submitBtn.disabled = true` | Başlangıç |

---

## 10. API Endpoint Özeti

| Method | Endpoint | Auth | Cache | Açıklama |
|--------|----------|------|-------|----------|
| GET | `/health` | ❌ bypass | — | Liveness probe |
| GET | `/ready` | ❌ bypass | — | Readiness probe |
| GET | `/` | ✅ header | — | index.html serve |
| GET | `/api/me` | ✅ header | — | Kullanıcı bilgisi |
| GET | `/api/users-groups` | ✅ header | 5dk | Kullanıcı/grup/rol listesi |
| GET | `/api/csrf-token` | ✅ header | — | CSRF token üretimi |
| GET | `/api/check-team-access/:team` | ✅ header | 5dk (user group cache) | Takım yetki kontrolü |
| GET | `/api/check-project-name/:name` | ✅ header | — | Proje adı müsaitlik |
| GET | `/api/pipelinerun-status/:name` | ✅ header | — | PipelineRun durumu |
| POST | `/api/create-project` | ✅ header + CSRF + rate limit | — | Proje oluşturma |

---

## 11. Deployment Yapılandırması

### OAuth Proxy (deployment.yaml)

| Parametre | Değer | Açıklama |
|-----------|-------|----------|
| `--openshift-service-account` | `project-creator-web-sa` | SA adı |
| `--openshift-sar` | `{"namespace":"project-creator","resource":"services",...}` | SAR kontrolü |
| `--provider` | `openshift` | Auth sağlayıcı |
| `--cookie-expire` | `8h` | Session süresi |
| `--cookie-refresh` | `15m` | Cookie yenileme |
| `--pass-user-headers` | `true` | `X-Forwarded-User` header'ı iletir |

### RBAC (ClusterRole `project-creator-web-access`)

| API Group | Resource | Verb | Kullanan |
|-----------|----------|------|----------|
| `project.openshift.io` | projects | get, list | check-project-name |
| `user.openshift.io` | users | list | users-groups dropdown |
| `user.openshift.io` | groups | list | users-groups + getUserGroups |
| `rbac.authorization.k8s.io` | clusterroles | list | role dropdown |
| `tekton.dev` | pipelineruns | create, get | triggerPipelineRun + status |
| `operator.openshift.io` | consoles | get | getConsoleUrl |

### Kullanıcıya Verilecek Yetki (SAR için)

```bash
# Sayfayı görebilmesi için kullanıcının bu yetkiye sahip olması gerekir:
oc auth can-i get services/project-creator-web -n project-creator --as=<user>
```

---

## 12. Konfigürasyon Değişkenleri

| Değişken | Varsayılan | Açıklama |
|----------|-----------|----------|
| `PORT` | 8080 | Uygulama portu |
| `NAMESPACE` | auto-detect | Fallback namespace |
| `TEAM_DEV_PREFIX` | `dev-` | Dev takım prefix'i |
| `TEAM_TEST_PREFIX` | `test-` | Test takım prefix'i |
| `TEAM_PROD_PREFIX` | `prod-` | Prod takım prefix'i |
| `TEAM_DEV_GROUP` | `group-dev` | Dev takım grup adı |
| `TEAM_TEST_GROUP` | `group-test` | Test takım grup adı |
| `TEAM_PROD_GROUP` | `group-prod` | Prod takım grup adı |
