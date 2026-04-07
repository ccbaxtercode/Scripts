# OpenShift Project Creator

OpenShift üzerinde proje oluşturma aracı. Tekton Pipeline kullanarak proje oluşturur, kullanıcı/gruba rol atar, quota ve network policy ekler.

## Özellikler

- Proje oluşturma
- Kullanıcı veya gruba rol atama (edit)
- Resource quota (CPU, Memory, Storage)
- Network Policy (deny-all-ingress, same-project allowed)
- OAuth ile kimlik doğrulama
- Grup bazlı erişim kontrolü

## Dosya Yapısı

```
openshift-project-app/     # Web uygulaması
├── server.js              # Node.js backend
├── package.json           # Bağımlılıklar
├── Dockerfile             # Container image
├── deployment.yaml        # OpenShift deployment
├── README.md             # Detaylı kurulum rehberi
└── public/
    └── index.html        # Web arayüzü

pipeline.yaml              # Tekton Pipeline
tasks.yaml                 # Tekton Tasks
preview.html               # Web arayüzü önizleme
```

## Web Arayüzü Önizleme

`preview.html` dosyasını tarayıcıda açarak arayüzü test edebilirsiniz.

## Detaylı Kurulum

Detaylı kurulum ve deployment adımları için `openshift-project-app/README.md` dosyasına bakın.
