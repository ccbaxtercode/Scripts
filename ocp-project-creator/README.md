# OpenShift Project Creator

OpenShift üzerinde proje oluşturma aracı. Tekton Pipeline kullanarak proje oluşturur, kullanıcı/gruba rol atar, quota ve network policy ekler.

## Özellikler

- Proje oluşturma
- Kullanıcı veya gruba rol atama (edit)
- Resource quota (CPU, Memory, Storage)
- Network Policy (deny-all-ingress, same-project allowed)
- OAuth ile kimlik doğrulama
- Grup bazlı erişim kontrolü

## Gereksinimler

- OpenShift 4.x
- Tekton Pipeline yüklü
- Kullanıcıların OpenShift'e erişimi

## Kurulum Adımları

### 1. Proje Oluştur

```bash
oc new-project project-creator
```

### 2. Kullanıcı Grubunu Oluştur

```bash
# Grup oluştur
oc adm groups new project-creators

# Kullanıcı ekle
oc adm groups add-users project-creators kullanici1 kullanici2
```

### 3. Docker İmajını Build Et ve Push Et

```bash
cd openshift-project-app

# Build et
docker build -t project-creator:latest .

# Nexus'e tagle ve push et
docker tag project-creator:latest <nexus-adresi>/project-creator:latest
docker push <nexus-adresi>/project-creator:latest
```

**Dockerfile'ı kendi Nexus adresinle güncelle:**
```dockerfile
FROM quay.io/openshift/origin-cli:latest
# ...
```

### 4. Tekton Kaynaklarını Yükle

```bash
# Namespace'e geç
oc config set-context --current --namespace=project-creator

# Task ve Pipeline yükle
oc apply -f ../tasks.yaml
oc apply -f ../pipeline.yaml
```

### 5. ServiceAccount ve Secrets Oluştur

```bash
# OAuth proxy secret oluştur
oc create secret generic oauth-proxy-secrets \
  --from-literal=cookie-secret=$(openssl rand -base64 32) \
  -n project-creator
```

### 6. Deployment'ı Uygula

```bash
oc apply -f deployment.yaml
```

### 7. OAuth Yetkilerini Ver

```bash
# OAuth proxy cluster role
oc adm policy add-cluster-role-to-user system:oauth-proxy \
  system:serviceaccount:project-creator:project-creator-sa
```

### 8. Pod'ların Çalıştığını Kontrol Et

```bash
oc get pods -n project-creator
```

Çıktı şöyle olmalı:
```
NAME                               READY   STATUS    RESTARTS   AGE
project-creator-xxxxx-xxxxx       2/2     Running   0          1m
```

### 9. Route'a Eriş

```bash
oc get route project-creator -n project-creator
```

Çıktıdan hostname'i al ve tarayıcıda aç.

## Erişim Kontrolü

### Yeni Kullanıcı Ekleme

```bash
oc adm groups add-users project-creators yeni-kullanici
```

### Yeni Kullanıcı Kaldırma

```bash
oc adm groups remove-users project-creators eski-kullanici
```

### Grubu Değiştirme

```bash
# --allowed-groups değerini deployment.yaml'da değiştir
oc edit deployment project-creator -n project-creator
```

## Sorun Giderme

### Pod Çalışmıyor

```bash
# Pod loglarını incele
oc logs -f deployment/project-creator -c oauth-proxy -n project-creator
oc logs -f deployment/project-creator -c app -n project-creator
```

### OAuth Redirect Hatası

```bash
# ServiceAccount annotation kontrol et
oc get sa project-creator-sa -n project-creator -o yaml
```

### Erişim Reddedildi Hatası

```bash
# Kullanıcının grupta olduğunu kontrol et
oc adm groups view project-creators
```

## Dosya Yapısı

```
openshift-project-app/
├── server.js           # Node.js backend
├── package.json        # Bağımlılıklar
├── Dockerfile          # Container image
├── deployment.yaml     # OpenShift deployment
└── public/
    └── index.html     # Web arayüzü

../pipeline.yaml        # Tekton Pipeline
../tasks.yaml           # Tekton Tasks
```

## API Endpoints

| Endpoint | Metod | Açıklama |
|----------|-------|----------|
| `/` | GET | Web arayüzü |
| `/health` | GET | Sağlık kontrolü |
| `/ready` | GET | Hazırlık kontrolü |
| `/api/users-groups` | GET | Kullanıcı ve grup listesi |
| `/api/create-project` | POST | Proje oluştur |
| `/api/pipelinerun-status/:name` | GET | PipelineRun durumu |
| `/api/me` | GET | Giriş yapmış kullanıcı bilgisi |
