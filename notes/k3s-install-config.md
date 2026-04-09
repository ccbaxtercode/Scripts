Aynen, dışarıdan erişimi **Service (NodePort / LB)** üzerinden yapacaksan, o endpoint’i **TLS SAN** içine eklemen gerekiyor. Yoksa kubectl tarafında **x509 hatası** kaçınılmaz.

Bir de `--write-kubeconfig-mode 644` ekleyelim 👍

Aşağıya **tam ve doğru production’a yakın kurulum** bırakıyorum:

---

# 🧠 MASTER0 (ilk control-plane)

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="
server \
--cluster-init \
--node-ip=192.168.100.10 \
--advertise-address=192.168.100.10 \
--flannel-iface=eth1 \
--tls-san=192.168.100.10 \
--tls-san=<SERVICE_IP_OR_DNS> \
--write-kubeconfig-mode=644
" sh -
```

---

# 🧠 MASTER1 / MASTER2

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="
server \
--server https://192.168.100.10:6443 \
--token <TOKEN> \
--node-ip=192.168.100.11 \
--advertise-address=192.168.100.11 \
--flannel-iface=eth1 \
--tls-san=<SERVICE_IP_OR_DNS> \
--write-kubeconfig-mode=644
" sh -
```

(master2 için IP değiştir)

---

# ⚙️ WORKER

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="
agent \
--server https://<SERVICE_IP_OR_DNS>:6443 \
--token <TOKEN> \
--node-ip=192.168.100.20 \
--flannel-iface=eth1
" sh -
```

---

# 🔴 Service ile erişim (senin senaryo)

Sen diyorsun ki:

👉 API’ye dışarıdan Service ile erişiyorum

O zaman 3 kritik nokta var:

---

## ✅ 1. TLS SAN içine eklemen ŞART

Eğer Service:

* ClusterIP ise → işe yaramaz (dışarıdan erişemezsin)
* NodePort / LoadBalancer ise → onun IP/DNS’ini ekle

Örnek:

```bash
--tls-san=10.96.0.1        # service cluster ip (genelde gerekmez)
--tls-san=172.30.x.x      # openshift service ip
--tls-san=k3s-api.my.lab  # dns
```

👉 En doğrusu:

* DNS varsa → onu koy
* yoksa → external IP

---

## ⚠️ 2. Worker join ederken de aynı endpoint’i kullan

```bash
--server https://<SERVICE_IP_OR_DNS>:6443
```

Yoksa:

* worker başka IP’ye gider
* cert mismatch olur

---

## ⚠️ 3. Service NAT yapıyorsa dikkat

OpenShift Virtualization’da bazen:

* source IP değişir
* reverse path sorun çıkar

Bunu görürsen:
👉 direkt NAD IP ile test et

---

# 💥 En sık yapılan hata

Şu kombinasyon patlatır:

* Service IP ile bağlan
* ama TLS SAN’da yok

Sonuç:

```
x509: certificate is not valid for any names
```

---

# 🔧 Kubeconfig düzeltme (çok önemli)

Master’da oluşan kubeconfig:

```bash
cat /etc/rancher/k3s/k3s.yaml
```

İçinde:

```yaml
server: https://127.0.0.1:6443
```

bunu değiştir:

```yaml
server: https://<SERVICE_IP_OR_DNS>:6443
```

---

# 🎯 Özet

Evet doğru düşünüyorsun:

👉 Service kullanıyorsan
✔ TLS SAN’a ekleyeceksin
✔ join ederken aynı endpoint’i kullanacaksın
✔ kubeconfig’i ona göre değiştireceksin
✔ `--write-kubeconfig-mode=644` ekleyeceksin

---

İstersen bana Service YAML’ını at
👉 yanlış kuruluysa direkt düzelteyim (özellikle OpenShift tarafı kritik burada).
