

How to Test
1. Local Development (without OpenShift)
# Test server.js syntax
cd /Users/kadir/kadir/project/ocp-pipeline-project-create/ocp-pipeline-project-create-web-page
node --check server.js
# Start server locally (will use mock namespace)
PORT=8080 node server.js
2. Build and Deploy to OpenShift
# Build image
docker build -t project-creator-web:latest .
# Push to registry (if using internal registry)
# docker tag project-creator-web:latest registry.example.com/project-creator/project-creator-web:latest
# docker push registry.example.com/project-creator/project-creator-web:latest
# Deploy
oc apply -f deployment.yaml
# Check pods
oc get pods -n project-creator
# Follow logs
oc logs -l app=project-creator-web -c app -n project-creator -f
3. Test Endpoints (after deployment)
# Get route URL
oc get route project-creator-web -n project-creator -o jsonpath='{.status.ingress[0].host}'
# Test health endpoints
curl -k https://<route>/health
curl -k https://<route>/ready
# Test API (with auth headers)
curl -k -H "x-remote-user: testuser" https://<route>/api/me
curl -k -H "x-remote-user: testuser" https://<route>/api/users-groups
4. Key Test Scenarios
Test	Expected
Access without login	OAuth redirect to login
User not in allowed group	403 Access Denied (no group info)
User in allowed group	Main page loads
Select team without access	"Access denied" feedback
Select team with access	Prefix auto-fills, project input enabled
Invalid project name format	Modal shows validation errors
Project name already exists	Modal shows "already exists"
Project name available	"Available!" feedback
Create project success	Form resets, success message
Create project failure	Error message with console link



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