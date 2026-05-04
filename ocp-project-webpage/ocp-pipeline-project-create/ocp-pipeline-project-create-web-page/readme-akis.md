Kullanıcı Akışı
1. Login & Yetki Kontrolü
- Kullanıcı web sayfasını açar
- OAuth proxy kullanıcı bilgisini alır (x-remote-user header)
- getUserGroups() ile kullanıcının grupları cache'den alınır
- Eğer kullanıcı ALLOWED_GROUPS ('project-creators') içinde yoksa → "Access Denied" sayfası gösterilir, işlem biter
2. Sayfa Yüklenir
- /api/users-groups çağrılır → users, groups, roles cache'den dönderilir
- Dropdown'lar doldurulur
- "Team Name" seçimi yapılabilir hale gelir
- Proje adı input'u disabled durumdadır ("Select a team first..." placeholder)
3. Team Seçimi
- Kullanıcı dropdown'dan "dev", "test" veya "prod" seçer
- /api/check-team-access/:team çağrılır
- groupsCache kontrol edilir (60sn içinde yenilenmediyse refresh yapılır)
- Kullanıcının seçili team'in grubunda üyeliği kontrol edilir
  - Üye değilse: "❌ Access denied — you are not a member of group-dev" hatası, proje adı hala disabled
  - Üye ise: ✅ "Access granted — prefix: dev-" mesajı, proje adı input'u aktif olur, otomatik prefix eklenir
4. Proje Adı Girişi
- Kullanıcı proje adı yazmaya başlar (örn: "myapp")
- Her 500ms debounce sonrası:
  - Format validation yapılır (63 char, RFC 1123, prefix kontrolü)
  - Format hatalıysa modal ile hata gösterilir
  - Format doğruysa /api/check-project-name/:name ile OpenShift'te müsait mi kontrol edilir
  - Sonuç: ✔ "Project name available!" veya ✖ "Project name already exists"
- Input'ta yeşil/kırmızı ikon ve feedback mesajı gösterilir
5. Role Assignment
- Assignment Type seçilir: "User" veya "Group"
- User seçilirse: Multi-select dropdown ile kullanıcılar seçilir
- Group seçilirse: Single-select dropdown ile grup seçilir
- Role dropdown'undan cluster role seçilir (örn: "ocp-dev", "ocp-admin")
6. Resource Quotas
- CPU Request, Memory, Storage değerleri girilir (varsayılan: 2, 4Gi, 10Gi)
7. Form Submit
- "Create Project" butonuna tıklanır
- Validation kontrolleri yapılır (team seçili mi, atama tipi seçili mi, kullanıcı/grup seçildi mi, role seçildi mi)
- Hata varsa mesaj gösterilir, işlem biter
8. Onay Modalı
- Tüm bilgiler özet olarak gösterilir:
  - Team, Project Name, Assignment Type, User/Group, Role, Quota
- "Cancel" → işlem iptal
- "Confirm & Create" → devam
9. Proje Oluşturma İsteği
- /api/create-project POST edilir
- Server-side validation yapılır
- triggerPipelineRun() çalışır:
  - PipelineRun YAML oluşturulur
  - oc apply -f ile OpenShift'e gönderilir
- "⏳ PipelineRun triggered: create-project-dev-myapp-1234567890" mesajı
10. Status Polling
- Her 5 saniyede /api/pipelinerun-status/:name çağrılır
- Max 120retry (10 dakika) yapılır
- Pipeline tamamlanana kadar "⏳ Waiting for pipeline to complete..." mesajı
11. Sonuç
- Başarılı: ✅ "Project created successfully!" + proje bilgileri
- Başarısız: ❌ "Pipeline failed!" + hata açıklaması + Console linki
- Timeout: "Pipeline did not complete within 10 minutes"