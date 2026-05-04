# OpenShift Project Creator Web UI

OpenShift üzerinde Tekton Pipeline aracılığıyla proje oluşturmayı sağlayan web tabanlı self-servis portalı.

## Genel Bakış

Bu uygulama, yetkili kullanıcıların bir web arayüzü üzerinden OpenShift projeleri oluşturmasını sağlar. Proje oluşturma işlemi doğrudan yapılmaz — bir **Tekton PipelineRun** tetiklenir ve pipeline proje oluşturma, rol atama ve kota belirleme işlemlerini gerçekleştirir.

### Mimari

```
Kullanıcı → Route (HTTPS) → OAuth Proxy (Kimlik Doğrulama) → Node.js App (Yetkilendirme + İş Mantığı)
                                                                       ↓
                                                               Tekton PipelineRun
                                                                       ↓
                                                              OpenShift Proje Oluşturma
```

### İki Katmanlı Güvenlik

| Katman | Bileşen | Görev |
|--------|---------|-------|
| **Authentication** | OAuth Proxy | OpenShift login ile kimlik doğrulama, session cookie yönetimi, `X-Remote-User` header'ı set etme |
| **Authorization** | server.js middleware | `X-Remote-User` header'ını okuyarak grup üyeliğini kontrol etme, sadece izinli gruplara erişim verme |

## Proje Yapısı

```
ocp-pipeline-project-create-web-page/
├── server.js            # Node.js backend (Express)
├── public/
│   └── index.html       # Web arayüzü (SPA)
├── deployment.yaml      # OpenShift deployment manifesti
├── Dockerfile           # Container image tanımı
├── package.json         # Node.js bağımlılıkları
└── README.md
```

## Özellikler

- **Proje Adı Validasyonu**: RFC 1123 uyumlu, `dev-` prefix zorunlu, max 63 karakter, hem client hem server tarafında kontrol
- **Proje Adı Müsaitlik Kontrolü**: Debounce ile gerçek zamanlı OpenShift API sorgusu
- **Rol Atama**: Kullanıcı veya gruba `ocp-` prefixli ClusterRole atama
- **Kaynak Kotaları**: CPU, memory ve storage kotaları belirleme
- **Onay Modalı**: Submit öncesi tüm bilgilerin gözden geçirilmesi
- **Pipeline Durumu İzleme**: PipelineRun tamamlanana kadar polling ile durum takibi
- **Console URL Yönlendirmesi**: PipelineRun detayları için OpenShift Console linki

## API Endpoints

| Method | Endpoint | Açıklama |
|--------|----------|----------|
| `GET` | `/health` | Liveness probe (auth bypass) |
| `GET` | `/ready` | Readiness probe (auth bypass) |
| `GET` | `/api/users-groups` | Kullanıcı, grup ve rol listesi |
| `GET` | `/api/check-project-name/:name` | Proje adı müsaitlik kontrolü |
| `GET` | `/api/me` | Oturum açmış kullanıcı bilgisi |
| `POST` | `/api/create-project` | PipelineRun tetikleyerek proje oluşturma |
| `GET` | `/api/pipelinerun-status/:name` | PipelineRun durum sorgulama |

## Kurulum

### Ön Gereksinimler

- OpenShift 4.x cluster
- Tekton Pipelines Operator kurulu
- `create-project-and-assign-role` adında bir Tekton Pipeline tanımlı
- `ocp-` prefixli ClusterRole'ler oluşturulmuş

### 1. Container Image Oluşturma

```bash
# Proje dizininde
podman build -t project-creator-web:latest .

# Registry'ye push
podman tag project-creator-web:latest <registry>/project-creator-web:latest
podman push <registry>/project-creator-web:latest
```

### 2. Cookie Secret Oluşturma

OAuth Proxy session cookie'lerini şifrelemek için bir secret gereklidir:

```bash
# Rastgele bir secret üret
openssl rand -base64 32
```

Çıktıyı `deployment.yaml` dosyasındaki `REPLACE_WITH_GENERATED_SECRET` yerine yapıştırın.

### 3. Deploy Etme

```bash
# deployment.yaml içindeki image adresini güncelleyin
# deployment.yaml içindeki cookie-secret değerini güncelleyin

oc apply -f deployment.yaml
```

### 4. Doğrulama

```bash
# Pod durumunu kontrol et
oc get pods -n project-creator

# Route URL'ini al
oc get route project-creator-web -n project-creator -o jsonpath='{.spec.host}'
```

## Yapılandırma

### Environment Variables

| Değişken | Varsayılan | Açıklama |
|----------|-----------|----------|
| `PORT` | `8080` | Uygulama portu |
| `ALLOWED_GROUPS` | `project-creators` | Virgülle ayrılmış izinli grup listesi |
| `NAMESPACE` | *(otomatik algılama)* | Fallback namespace (normalde Kubernetes SA mount'tan otomatik algılanır) |

### Namespace Algılama

Uygulama namespace'ini şu sırayla belirler:

1. `/var/run/secrets/kubernetes.io/serviceaccount/namespace` dosyası (Kubernetes otomatik mount)
2. `NAMESPACE` environment variable
3. Fallback: `project-creator`

## Kubernetes Kaynakları

`deployment.yaml` aşağıdaki kaynakları oluşturur:

| Kaynak | İsim | Açıklama |
|--------|------|----------|
| Namespace | `project-creator` | Paylaşılan namespace |
| ServiceAccount | `project-creator-web-sa` | Uygulama service account'u (OAuth redirect annotation'lı) |
| ClusterRole | `project-creator-web-access` | Gerekli API izinleri |
| ClusterRoleBinding | `project-creator-web-sa-binding` | SA → ClusterRole bağlantısı |
| Deployment | `project-creator-web` | App + OAuth Proxy sidecar |
| Service | `project-creator-web` | TLS serving cert annotation'lı |
| Route | `project-creator-web` | Reencrypt TLS termination |
| Secret | `project-creator-web-secrets` | OAuth Proxy cookie secret |

### RBAC İzinleri

ClusterRole `project-creator-web-access` şu izinleri içerir:

| API Group | Resource | Verbs | Kullanım Yeri |
|-----------|----------|-------|---------------|
| `project.openshift.io` | projects | get, list | Proje adı müsaitlik kontrolü |
| `user.openshift.io` | users | list | Kullanıcı dropdown listesi |
| `user.openshift.io` | groups | list | Grup dropdown listesi + yetki kontrolü |
| `rbac.authorization.k8s.io` | clusterroles | list | Rol dropdown listesi (`ocp-` prefixli) |
| `tekton.dev` | pipelineruns | create, get | PipelineRun oluşturma ve durum sorgulama |
| `operator.openshift.io` | consoles | get | OpenShift Console URL'i alma |

## Güvenlik

### Input Validasyonu

- **Proje adı**: Client + server tarafında RFC 1123, `dev-` prefix, max 63 karakter kontrolü
- **Shell injection koruması**: Tüm kullanıcı girdileri `sanitizeForShell()` ile temizlenir veya regex ile doğrulanır
- **PipelineRun adı**: Regex ile format kontrolü yapılır (`/api/pipelinerun-status/:name`)

### Container Güvenliği

- Dockerfile'da `USER 1001` ile non-root çalıştırma
- Deployment'ta `securityContext.runAsNonRoot: true` ile Kubernetes seviyesinde koruma
- OpenShift `restricted` SCC uyumlu

### Timeout Koruması

Tüm `oc` komutları timeout ile korunmaktadır:

| İşlem | Timeout |
|-------|---------|
| Genel sorgular (`oc get ...`) | 10 saniye |
| PipelineRun oluşturma (`oc apply`) | 30 saniye |

Timeout aşılırsa komut iptal edilir ve hata catch bloğunda yakalanır. Sunucu donmaz.

### Cookie Secret Yönetimi

- OAuth Proxy, session cookie'leri şifrelemek için cookie-secret kullanır
- Secret bir kere oluşturulur ve değiştirilmediği sürece aynı kalır
- Değiştirilirse tüm aktif oturumlar sonlanır (kullanıcılar tekrar login olur)

**Secret rotasyonu (gerektiğinde):**

```bash
# Yeni secret üret ve güncelle
oc create secret generic project-creator-web-secrets \
  --from-literal=cookie-secret=$(openssl rand -base64 32) \
  -n project-creator --dry-run=client -o yaml | oc apply -f -

# Pod'ları restart et
oc rollout restart deployment/project-creator-web -n project-creator
```

## Proje Adı Kuralları

| Kural | Açıklama |
|-------|----------|
| `dev-` prefix | Zorunlu — tüm proje adları `dev-` ile başlamalı |
| RFC 1123 | Küçük harf ile başlamalı, `[a-z0-9-]` içermeli, harf/rakam ile bitmeli |
| Max uzunluk | 63 karakter |
| Min uzunluk | `dev-` + en az 3 karakter = 7 karakter minimum |

**Geçerli örnekler:** `dev-my-app`, `dev-team-frontend-v2`, `dev-test123`
**Geçersiz örnekler:** `my-project` (prefix yok), `Dev-App` (büyük harf), `dev-a` (çok kısa)

## Teknik Detaylar

### Bağımlılıklar

| Paket | Versiyon | Kullanım |
|-------|---------|----------|
| `express` | ^4.18.2 | HTTP server |
| `js-yaml` | ^4.1.0 | PipelineRun YAML oluşturma |

### Dockerfile

```dockerfile
FROM quay.io/openshift/origin-cli:latest    # oc CLI dahil
RUN dnf install -y nodejs:20 npm && dnf clean all
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY server.js ./
COPY public/ ./public/
EXPOSE 8080
USER 1001
CMD ["node", "server.js"]
```

Base image olarak `origin-cli` kullanılır çünkü uygulama `oc` CLI aracını kullanarak OpenShift API ile iletişim kurar.

### PipelineRun Parametreleri

Oluşturulan PipelineRun `create-project-and-assign-role` pipeline'ına şu parametreleri gönderir:

| Parametre | Açıklama |
|-----------|----------|
| `project-name` | Oluşturulacak proje adı |
| `assignment-type` | `user` veya `group` |
| `user-or-group-name` | Seçilen kullanıcı/grup adı (virgülle ayrılmış) |
| `user-or-group-names-json` | Seçilen kullanıcı/gruplar (JSON dizisi) |
| `set-quota` | Her zaman `true` |
| `cpu-request` | CPU kotası (örn. `2`) |
| `memory-request` | Memory kotası (örn. `4Gi`) |
| `storage-request` | Storage kotası (örn. `10Gi`) |
| `role-name` | Atanacak ClusterRole adı |

## Sorun Giderme

### Pod başlamıyor

```bash
# Pod loglarını kontrol et
oc logs -n project-creator deployment/project-creator-web -c app
oc logs -n project-creator deployment/project-creator-web -c oauth-proxy

# Event'leri kontrol et
oc get events -n project-creator --sort-by='.lastTimestamp'
```

### "Access Denied" hatası

- Kullanıcının `ALLOWED_GROUPS` env variable'da tanımlı gruplardan birine üye olduğunu doğrulayın:
  ```bash
  oc get groups -o json | jq '.items[] | select(.users[] == "USERNAME") | .metadata.name'
  ```

### Roller yüklenmiyor

- `ocp-` prefixli ClusterRole'lerin varlığını kontrol edin:
  ```bash
  oc get clusterrole | grep ^ocp-
  ```

### PipelineRun başarısız oluyor

- OpenShift Console'dan PipelineRun detaylarına bakın
- Pipeline ve TaskRun loglarını kontrol edin:
  ```bash
  oc get pipelinerun -n project-creator
  oc logs -n project-creator <taskrun-pod-name>
  ```
