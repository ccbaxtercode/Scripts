# Changelog

Tüm önemli değişiklikler bu dosyada belgelenecektir.

Format [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) standardına dayanır,
ve bu proje [Semantic Versioning](https://semver.org/spec/v2.0.0.html) kullanır.

## [2.0.0] - 2025-11-02

### Added
- 🎉 Ansible Role yapısına dönüştürüldü
- ✨ Retry mekanizması (3 deneme, configurable)
- ✨ Ayrı connection ve read timeout
- ✨ SSL warning susturma özelliği
- ✨ Response encoding otomatik düzeltme
- ✨ DEBUG seviyesi logging
- ✨ Elapsed time tracking
- 📝 Comprehensive README.md
- 📝 Örnek playbook'lar (examples/)
- 🧪 Test suite (tests/test.yml)
- 📋 Python requirements.txt

### Changed
- ⚡ Performance iyileştirmeleri
- 📊 Daha detaylı hata mesajları
- 🔧 Timeout parametreleri configurable

### Fixed
- 🐛 Character encoding sorunları
- 🐛 SSL certificate uyarıları
- 🐛 NTLM auth username formatı

### Security
- 🔒 `no_log: true` varsayılan olarak aktif
- 🔒 Ansible Vault zorunlu kılındı
- 🔒 SSL doğrulama varsayılan olarak açık

## [1.0.0] - 2025-10-01

### Added
- ✨ İlk sürüm
- ✨ NTLM Authentication desteği
- ✨ Basic Authentication desteği
- ✨ GET, POST, PUT, DELETE metodları
- ✨ JSON request/response desteği
- ✨ Custom headers desteği
- ✨ SSL/TLS kontrolü
- ✨ Temel hata yönetimi
- ✨ Ansible integration

[2.0.0]: https://github.com/username/ansible-role-api-request/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/username/ansible-role-api-request/releases/tag/v1.0.0
