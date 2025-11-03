#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Dosya: roles/vcenter_vm_create/files/ad_query.py
Açıklama: Active Directory Sorgu Aracı
- User ve Computer obje sorgulaması
- LDAPS (636) bağlantısı
- Attribute normalizasyonu
- JSON çıktı formatı
"""

import sys
import os
import json
import ssl
from datetime import datetime, timedelta

# ============================================
# MODÜL KONTROLÜ
# ============================================
try:
    from ldap3 import Server, Connection, SUBTREE, ALL
    LDAP_AVAILABLE = True
except ImportError:
    print(json.dumps({
        "success": False,
        "error": "ldap3 modülü yüklü değil",
        "details": "pip install ldap3 --break-system-packages"
    }))
    sys.exit(1)

# ============================================
# PARAMETRELER
# ============================================
AD_OBJECT = sys.argv[1].lower() if len(sys.argv) > 1 else None
AD_DOMAIN = sys.argv[2] if len(sys.argv) > 2 else None
AD_SEARCH = sys.argv[3] if len(sys.argv) > 3 else None
AD_ATTRIBUTES = sys.argv[4] if len(sys.argv) > 4 else None

# Environment Variables
AD_USER = os.getenv("AD_USER")
AD_PASSWORD = os.getenv("AD_PASSWORD")
DEBUG = os.getenv("AD_QUERY_DEBUG", "false").lower() == "true"

# ============================================
# DEFAULT ATTRIBUTE LİSTELERİ
# ============================================
DEFAULT_USER_ATTRIBUTES = [
    "cn",
    "samaccountname",
    "displayname",
    "mail",
    "userprincipalname",
    "memberof",
    "whencreated",
    "lastlogon",
    "useraccountcontrol"
]

DEFAULT_COMPUTER_ATTRIBUTES = [
    "cn",
    "dnshostname",
    "operatingsystem",
    "operatingsystemversion",
    "whencreated",
    "lastlogon",
    "description"
]

# ============================================
# YARDIMCI FONKSİYONLAR
# ============================================

def debug_log(message):
    """Debug modu aktifse log yaz"""
    if DEBUG:
        print(f"[DEBUG] {message}", file=sys.stderr)

def info_log(message):
    """Info seviyesi log"""
    print(f"[INFO] {message}", file=sys.stderr)

def warn_log(message):
    """Warning seviyesi log"""
    print(f"[WARN] {message}", file=sys.stderr)

def error_log(message):
    """Error seviyesi log"""
    print(f"[ERROR] {message}", file=sys.stderr)

def error_exit(error_message, details=""):
    """Hata ile çık"""
    output = {
        "success": False,
        "error": error_message
    }
    if details:
        output["details"] = details
    print(json.dumps(output, ensure_ascii=False))
    sys.exit(1)

def generate_base_dn(domain):
    """Domain'den Base DN üret
    Örnek: test.local.com → DC=test,DC=local,DC=com
    """
    parts = domain.split(".")
    base_dn = ",".join([f"DC={part}" for part in parts])
    debug_log(f"Base DN oluşturuldu: {base_dn}")
    return base_dn

def windows_timestamp_to_datetime(timestamp):
    """Windows FILETIME timestamp'i datetime'a çevir
    
    Windows FILETIME: 1601-01-01'den itibaren 100-nanosaniye cinsinden
    """
    try:
        timestamp = int(timestamp)
        
        # 0 veya negatif değer (hiç login olmamış)
        if timestamp <= 0:
            return "N/A"
        
        # Windows epoch: 1601-01-01
        epoch = datetime(1601, 1, 1)
        # 100-nanosaniye → saniye
        delta = timedelta(microseconds=timestamp / 10)
        dt = epoch + delta
        
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    except (ValueError, OverflowError) as e:
        debug_log(f"Timestamp dönüştürme hatası: {timestamp} - {e}")
        return str(timestamp)

def normalize_attribute_value(attr_name, value):
    """Attribute değerini normalize et
    
    - Boş değer → "N/A"
    - Timestamp → readable format
    - Binary → hex string
    - Liste → null temizleme
    """
    
    # None veya boş string
    if value is None or value == '':
        return "N/A"
    
    # Boş liste
    if isinstance(value, list) and len(value) == 0:
        return "N/A"
    
    # Liste değeri
    if isinstance(value, list):
        # None/boş değerleri temizle
        cleaned = [v for v in value if v is not None and v != '']
        if len(cleaned) == 0:
            return "N/A"
        # Her elemanı normalize et
        return [normalize_attribute_value(attr_name, v) for v in cleaned]
    
    # Binary değer (objectGUID, objectSid vb.)
    if isinstance(value, bytes):
        return value.hex()
    
    # Timestamp alanları (Windows FILETIME)
    timestamp_fields = ['lastlogon', 'lastlogontimestamp', 'pwdlastset', 'badpasswordtime']
    if attr_name.lower() in timestamp_fields:
        if isinstance(value, (int, str)) and str(value).isdigit():
            return windows_timestamp_to_datetime(value)
    
    # Normal değer
    return str(value) if not isinstance(value, str) else value

# ============================================
# PARAMETRELERİ DOĞRULA
# ============================================

debug_log("=" * 60)
debug_log("AD QUERY SCRIPT BAŞLATILIYOR")
debug_log("=" * 60)

# Zorunlu parametreler
if not AD_OBJECT:
    error_exit("AD_OBJECT parametresi eksik", "Kullanım: ad_query.py <user|computer> <domain> <search> [attributes]")

if AD_OBJECT not in ['user', 'computer']:
    error_exit(f"Geçersiz AD_OBJECT: {AD_OBJECT}", "Geçerli değerler: user, computer")

if not AD_DOMAIN:
    error_exit("AD_DOMAIN parametresi eksik")

if not AD_SEARCH:
    error_exit("AD_SEARCH parametresi eksik")

if not AD_USER or not AD_PASSWORD:
    error_exit("AD credentials eksik", "AD_USER ve AD_PASSWORD environment variable'ları gerekli")

debug_log(f"Object Type: {AD_OBJECT}")
debug_log(f"Domain: {AD_DOMAIN}")
debug_log(f"Search Term: {AD_SEARCH}")
debug_log(f"Custom Attributes: {AD_ATTRIBUTES if AD_ATTRIBUTES else 'None (using defaults)'}")

# ============================================
# ATTRIBUTE LİSTESİNİ BELİRLE
# ============================================

if AD_ATTRIBUTES:
    # Custom attribute listesi - lowercase'e çevir
    requested_attributes = [attr.strip().lower() for attr in AD_ATTRIBUTES.split(",")]
    info_log(f"Custom attribute listesi kullanılıyor: {len(requested_attributes)} attribute")
    debug_log(f"Attributes: {', '.join(requested_attributes)}")
else:
    # Default liste
    if AD_OBJECT == "user":
        requested_attributes = DEFAULT_USER_ATTRIBUTES
        info_log(f"Default user attribute listesi kullanılıyor: {len(requested_attributes)} attribute")
    else:
        requested_attributes = DEFAULT_COMPUTER_ATTRIBUTES
        info_log(f"Default computer attribute listesi kullanılıyor: {len(requested_attributes)} attribute")
    
    debug_log(f"Attributes: {', '.join(requested_attributes)}")

# ============================================
# BASE DN OLUŞTUR
# ============================================

base_dn = generate_base_dn(AD_DOMAIN)
info_log(f"Base DN: {base_dn}")

# ============================================
# LDAP BAĞLANTISI
# ============================================

info_log("=" * 60)
info_log("LDAP BAĞLANTISI KURULUYOR")
info_log("=" * 60)

# SSL Context (self-signed cert desteği)
tls_config = None
try:
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE
    from ldap3 import Tls
    tls_config = Tls(validate=ssl.CERT_NONE, version=ssl.PROTOCOL_TLSv1_2)
    debug_log("SSL context oluşturuldu (certificate validation: disabled)")
except Exception as e:
    warn_log(f"SSL context oluşturulamadı: {e}")

# Server tanımla
ldap_server_url = f"ldaps://{AD_DOMAIN}:636"
debug_log(f"LDAP Server: {ldap_server_url}")

try:
    server = Server(AD_DOMAIN, port=636, use_ssl=True, get_info=ALL, tls=tls_config)
    debug_log("LDAP Server objesi oluşturuldu")
except Exception as e:
    error_exit("LDAP Server objesi oluşturulamadı", str(e))

# Bağlantı testi
info_log(f"Domain'e bağlanılıyor: {AD_DOMAIN}")
debug_log(f"User: {AD_USER}")

try:
    conn = Connection(
        server,
        user=AD_USER,
        password=AD_PASSWORD,
        auto_bind=True,
        raise_exceptions=True
    )
    info_log("✓ LDAP bağlantısı başarılı")
    debug_log(f"Bind successful - Server: {conn.server}")
except Exception as e:
    error_message = str(e)
    if "invalidCredentials" in error_message or "Invalid credentials" in error_message:
        error_exit("LDAP authentication başarısız", "Kullanıcı adı veya şifre hatalı")
    elif "timeout" in error_message.lower():
        error_exit("LDAP bağlantı timeout", f"Domain {AD_DOMAIN} erişilebilir değil")
    elif "refused" in error_message.lower():
        error_exit("LDAP bağlantı reddedildi", f"Port 636 kapalı veya erişilebilir değil")
    else:
        error_exit("LDAP bağlantı hatası", error_message)

# ============================================
# LDAP SORGUSU
# ============================================

info_log("=" * 60)
info_log(f"{AD_OBJECT.upper()} SORGUSU")
info_log("=" * 60)

# Search filter
if AD_OBJECT == "user":
    search_filter = f"(&(objectClass=user)(objectCategory=person)(sAMAccountName={AD_SEARCH}))"
else:
    search_filter = f"(&(objectClass=computer)(cn={AD_SEARCH}))"

debug_log(f"Search Filter: {search_filter}")
debug_log(f"Base DN: {base_dn}")
debug_log(f"Attributes: {', '.join(requested_attributes)}")

info_log(f"Aranıyor: {AD_SEARCH}")

try:
    conn.search(
        search_base=base_dn,
        search_filter=search_filter,
        search_scope=SUBTREE,
        attributes=requested_attributes
    )
    
    debug_log(f"Search tamamlandı - Sonuç sayısı: {len(conn.entries)}")
    
except Exception as e:
    error_exit("LDAP sorgu hatası", str(e))

# ============================================
# SONUÇ İŞLEME
# ============================================

if len(conn.entries) == 0:
    # Object bulunamadı
    info_log(f"✗ {AD_OBJECT.upper()} bulunamadı: {AD_SEARCH}")
    
    output = {
        "success": True,
        "found": False,
        "object_type": AD_OBJECT,
        "domain": AD_DOMAIN,
        "search_term": AD_SEARCH,
        "message": f"{AD_OBJECT.capitalize()} '{AD_SEARCH}' AD'de bulunamadı"
    }
    
    conn.unbind()
    print(json.dumps(output, ensure_ascii=False))
    sys.exit(0)

# Object bulundu
entry = conn.entries[0]
info_log(f"✓ {AD_OBJECT.upper()} bulundu: {AD_SEARCH}")
debug_log(f"DN: {entry.entry_dn}")

# Attributes'leri topla ve normalize et
attributes = {}
missing_attributes = []

for attr in requested_attributes:
    try:
        # LDAP'den değeri al
        if hasattr(entry, attr):
            raw_value = getattr(entry, attr).value
            debug_log(f"Attribute '{attr}': {type(raw_value).__name__} - {repr(raw_value)[:100]}")
            
            # Normalize et
            normalized_value = normalize_attribute_value(attr, raw_value)
            attributes[attr] = normalized_value
        else:
            # Attribute yok
            debug_log(f"Attribute '{attr}': NOT FOUND")
            attributes[attr] = "N/A"
            missing_attributes.append(attr)
    
    except Exception as e:
        warn_log(f"Attribute '{attr}' işlenirken hata: {e}")
        attributes[attr] = "N/A"
        missing_attributes.append(attr)

# Eksik attribute uyarısı
if missing_attributes:
    warn_log(f"Eksik/geçersiz attributes ({len(missing_attributes)}): {', '.join(missing_attributes)}")

# ============================================
# JSON ÇIKTI
# ============================================

output = {
    "success": True,
    "found": True,
    "object_type": AD_OBJECT,
    "domain": AD_DOMAIN,
    "search_term": AD_SEARCH,
    "dn": entry.entry_dn,
    "attributes": attributes
}

# Bağlantıyı kapat
conn.unbind()

info_log("=" * 60)
info_log("SORGU TAMAMLANDI")
info_log("=" * 60)
info_log(f"DN: {entry.entry_dn}")
info_log(f"Attributes: {len(attributes)} adet")
debug_log("JSON Çıktı:")

# JSON çıktı (Ansible için son satır)
print(json.dumps(output, ensure_ascii=False, indent=2 if DEBUG else None))

sys.exit(0)
