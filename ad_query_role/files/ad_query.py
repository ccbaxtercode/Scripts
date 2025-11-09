#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Dosya: roles/ad_query/files/ad_query.py
Açıklama: Active Directory Multi-DC Query Aracı

Özellikler:
- User, Computer, Group obje sorgulaması
- Multi-DC support (DNS SRV discovery)
- Retry logic (her DC için 3 retry, 5s interval)
- Certificate fallback (yoksa CERT_NONE)
- Tek bind (credential test), sonra multi-DC search
- Group member sample (count + ilk N üye)
- Attribute normalizasyonu (timestamp, binary, null)
"""

import sys
import os
import json
import ssl
import time
from datetime import datetime, timedelta

# ============================================
# MODÜL KONTROLÜ
# ============================================
try:
    from ldap3 import Server, Connection, SUBTREE, ALL, Tls
    LDAP_AVAILABLE = True
except ImportError:
    print(json.dumps({
        "success": False,
        "error": "ldap3 modülü yüklü değil",
        "details": "pip install ldap3 --break-system-packages"
    }))
    sys.exit(1)

try:
    import dns.resolver
    DNS_AVAILABLE = True
except ImportError:
    DNS_AVAILABLE = False

# ============================================
# PARAMETRELER
# ============================================
AD_OBJECT = sys.argv[1].lower() if len(sys.argv) > 1 else None
AD_DOMAIN = sys.argv[2] if len(sys.argv) > 2 else None
AD_SEARCH = sys.argv[3] if len(sys.argv) > 3 else None
AD_ATTRIBUTES = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4].strip() else None

# Environment Variables
AD_USER = os.getenv("AD_USER")
AD_PASSWORD = os.getenv("AD_PASSWORD")
AD_CERT_PATH = os.getenv("AD_CERT_PATH", "/etc/ssl/certs/ad_chain.crt")
LDAP_TIMEOUT = int(os.getenv("LDAP_TIMEOUT", "10"))
MAX_RETRIES = int(os.getenv("AD_QUERY_MAX_RETRIES", "3"))
RETRY_DELAY = int(os.getenv("AD_QUERY_RETRY_DELAY", "5"))
MEMBER_SAMPLE_SIZE = int(os.getenv("MEMBER_SAMPLE_SIZE", "10"))
DEBUG = os.getenv("AD_QUERY_DEBUG", "false").lower() == "true"

# ============================================
# DEFAULT ATTRIBUTE LİSTELERİ
# ============================================
DEFAULT_USER_ATTRIBUTES = [
    "cn", "samaccountname", "displayname", "mail", "userprincipalname",
    "memberof", "whencreated", "lastlogon", "useraccountcontrol"
]

DEFAULT_COMPUTER_ATTRIBUTES = [
    "cn", "dnshostname", "operatingsystem", "operatingsystemversion",
    "whencreated", "lastlogon", "description"
]

DEFAULT_GROUP_ATTRIBUTES = [
    "cn", "distinguishedname", "samaccountname", "description",
    "member", "memberof", "whencreated", "whenchanged", "grouptype", "mail"
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

def error_exit(error_message, details=""):
    """Hata ile çık"""
    output = {"success": False, "error": error_message}
    if details:
        output["details"] = details
    print(json.dumps(output, ensure_ascii=False))
    sys.exit(1)

def generate_base_dn(domain):
    """Domain'den Base DN üret"""
    parts = domain.split(".")
    base_dn = ",".join([f"DC={part}" for part in parts])
    debug_log(f"Base DN: {base_dn}")
    return base_dn

def discover_all_domain_controllers(domain):
    """DNS SRV query ile tüm DC'leri bul ve sırala"""
    srv_record = f"_ldap._tcp.dc._msdcs.{domain}"
    
    if not DNS_AVAILABLE:
        warn_log("dnspython modülü yok, domain direkt kullanılacak")
        return [domain]
    
    try:
        debug_log(f"DNS SRV query: {srv_record}")
        answers = dns.resolver.resolve(srv_record, 'SRV')
        
        # Priority/weight sıralaması
        dc_list_sorted = sorted(answers, key=lambda x: (x.priority, -x.weight))
        dc_hostnames = [str(dc.target).rstrip('.') for dc in dc_list_sorted]
        
        info_log(f"✓ {len(dc_hostnames)} DC bulundu")
        for idx, (dc, srv) in enumerate(zip(dc_hostnames, dc_list_sorted)):
            debug_log(f"  DC #{idx+1}: {dc} (priority={srv.priority}, weight={srv.weight})")
        
        return dc_hostnames
        
    except dns.resolver.NXDOMAIN:
        warn_log(f"DNS SRV kaydı bulunamadı: {srv_record}")
        return [domain]
    except Exception as e:
        warn_log(f"DC discovery başarısız: {e}")
        return [domain]

def windows_timestamp_to_datetime(timestamp):
    """Windows FILETIME timestamp'i datetime'a çevir"""
    try:
        timestamp = int(timestamp)
        if timestamp <= 0:
            return "N/A"
        epoch = datetime(1601, 1, 1)
        delta = timedelta(microseconds=timestamp / 10)
        dt = epoch + delta
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    except (ValueError, OverflowError) as e:
        debug_log(f"Timestamp dönüştürme hatası: {timestamp} - {e}")
        return str(timestamp)

def normalize_attribute_value(attr_name, value):
    """Attribute değerini normalize et"""
    
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
        
        # Group member özel işlemi
        if attr_name.lower() == "member":
            return {
                "count": len(cleaned),
                "sample": cleaned[:MEMBER_SAMPLE_SIZE]
            }
        
        # Diğer listeler
        return [normalize_attribute_value(attr_name, v) for v in cleaned]
    
    # Binary değer
    if isinstance(value, bytes):
        return value.hex()
    
    # Timestamp alanları
    timestamp_fields = ['lastlogon', 'lastlogontimestamp', 'pwdlastset', 'badpasswordtime', 'whenchanged', 'whencreated']
    if attr_name.lower() in timestamp_fields:
        if isinstance(value, (int, str)) and str(value).isdigit():
            return windows_timestamp_to_datetime(value)
    
    # Normal değer
    return str(value) if not isinstance(value, str) else value

def create_tls_config():
    """TLS konfigürasyonu oluştur (sertifika varsa doğrulama, yoksa fallback)"""
    
    if os.path.exists(AD_CERT_PATH):
        # Sertifika var → CERT_REQUIRED
        try:
            ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            ssl_context.verify_mode = ssl.CERT_REQUIRED
            ssl_context.check_hostname = True
            ssl_context.load_verify_locations(cafile=AD_CERT_PATH)
            
            tls_config = Tls(
                ca_certs_file=AD_CERT_PATH,
                validate=ssl.CERT_REQUIRED,
                version=ssl.PROTOCOL_TLSv1_2
            )
            
            info_log("✓ SSL context oluşturuldu (certificate validation: ENABLED)")
            debug_log(f"  Verify Mode: CERT_REQUIRED")
            debug_log(f"  Hostname Check: ENABLED")
            debug_log(f"  CA File: {AD_CERT_PATH}")
            
            return tls_config
            
        except Exception as e:
            error_exit(f"SSL sertifika yüklenemedi: {AD_CERT_PATH}", str(e))
    else:
        # Sertifika yok → CERT_NONE (fallback)
        warn_log(f"Sertifika bulunamadı: {AD_CERT_PATH}")
        warn_log("SSL doğrulama devre dışı (CERT_NONE)")
        
        tls_config = Tls(
            validate=ssl.CERT_NONE,
            version=ssl.PROTOCOL_TLSv1_2
        )
        
        info_log("✓ SSL context oluşturuldu (certificate validation: DISABLED)")
        return tls_config

def test_credentials_on_first_dc(dc_list, tls_config):
    """İlk erişilebilir DC'de credential test yap"""
    
    info_log("=" * 60)
    info_log("CREDENTİAL TEST (İlk erişilebilir DC)")
    info_log("=" * 60)
    
    for dc in dc_list:
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                debug_log(f"Credential test: {dc} (attempt {attempt}/{MAX_RETRIES})")
                
                server = Server(
                    dc,
                    port=636,
                    use_ssl=True,
                    get_info=ALL,
                    tls=tls_config,
                    connect_timeout=LDAP_TIMEOUT
                )
                
                conn = Connection(
                    server,
                    user=AD_USER,
                    password=AD_PASSWORD,
                    auto_bind=False,
                    raise_exceptions=True
                )
                
                # Bind işlemi (credential test)
                if conn.bind():
                    info_log(f"✓ Credential test başarılı: {dc}")
                    conn.unbind()
                    return dc  # Başarılı DC döndür
                else:
                    # Bind başarısız - credential hatası
                    error_exit(
                        "LDAP authentication başarısız",
                        f"Kullanıcı adı veya şifre hatalı (test DC: {dc})"
                    )
                
            except Exception as e:
                error_message = str(e)
                
                # Credential hatası → tüm DC'leri durdur
                if "invalidCredentials" in error_message or "Invalid credentials" in error_message:
                    error_exit("LDAP authentication başarısız", "Kullanıcı adı veya şifre hatalı")
                
                # Bağlantı hatası → retry
                debug_log(f"Bağlantı hatası ({dc}): {error_message}")
                
                if attempt < MAX_RETRIES:
                    debug_log(f"Retry {attempt}/{MAX_RETRIES} sonrası bekleniyor ({RETRY_DELAY}s)...")
                    time.sleep(RETRY_DELAY)
                else:
                    warn_log(f"DC erişilemedi ({MAX_RETRIES} retry sonrası): {dc}")
                    # Sonraki DC'ye geç
                    break
    
    # Hiçbir DC'ye erişilemedi
    error_exit(
        "Hiçbir DC'ye bağlanılamadı",
        f"Tüm DC'ler ({len(dc_list)} adet) erişilemez durumda"
    )

def search_object_on_dc(dc, base_dn, search_filter, attributes, tls_config):
    """Bir DC'de object ara (retry ile)"""
    
    tried_info = {"hostname": dc, "status": "unknown", "attempts": 0}
    
    for attempt in range(1, MAX_RETRIES + 1):
        tried_info["attempts"] = attempt
        
        try:
            debug_log(f"Search: {dc} (attempt {attempt}/{MAX_RETRIES})")
            
            server = Server(
                dc,
                port=636,
                use_ssl=True,
                get_info=ALL,
                tls=tls_config,
                connect_timeout=LDAP_TIMEOUT
            )
            
            conn = Connection(
                server,
                user=AD_USER,
                password=AD_PASSWORD,
                auto_bind=True,
                raise_exceptions=True,
                receive_timeout=LDAP_TIMEOUT
            )
            
            # Search
            conn.search(
                search_base=base_dn,
                search_filter=search_filter,
                search_scope=SUBTREE,
                attributes=attributes
            )
            
            if len(conn.entries) > 0:
                # Object bulundu
                tried_info["status"] = "success"
                debug_log(f"✓ Object bulundu: {dc}")
                return {"found": True, "entries": conn.entries, "tried_info": tried_info}
            else:
                # Object yok
                tried_info["status"] = "not_found"
                debug_log(f"Object bulunamadı: {dc}")
                conn.unbind()
                return {"found": False, "tried_info": tried_info}
        
        except Exception as e:
            error_message = str(e)
            debug_log(f"Search hatası ({dc}): {error_message}")
            
            # Certificate error özel loglama
            if "certificate" in error_message.lower() or "ssl" in error_message.lower():
                warn_log(f"SSL/Certificate hatası: {dc}")
            
            if attempt < MAX_RETRIES:
                debug_log(f"Retry {attempt}/{MAX_RETRIES} sonrası bekleniyor ({RETRY_DELAY}s)...")
                time.sleep(RETRY_DELAY)
            else:
                tried_info["status"] = "connection_failed"
                warn_log(f"Bağlantı başarısız ({MAX_RETRIES} retry sonrası): {dc}")
                return {"found": False, "tried_info": tried_info}
    
    return {"found": False, "tried_info": tried_info}

def search_across_all_dcs(dc_list, base_dn, search_filter, attributes, tls_config):
    """Tüm DC'leri sırayla tara"""
    
    info_log("=" * 60)
    info_log("MULTI-DC SEARCH")
    info_log("=" * 60)
    
    tried_servers = []
    
    for dc in dc_list:
        info_log(f"DC sorgulanıyor: {dc}")
        
        result = search_object_on_dc(dc, base_dn, search_filter, attributes, tls_config)
        tried_servers.append(result["tried_info"])
        
        if result["found"]:
            info_log(f"✓ Object bulundu: {dc}")
            return {
                "success": True,
                "found": True,
                "server": dc,
                "entries": result["entries"],
                "tried_servers": tried_servers
            }
    
    # Hiçbir DC'de bulunamadı
    info_log("✗ Object hiçbir DC'de bulunamadı")
    return {
        "success": True,
        "found": False,
        "tried_servers": tried_servers
    }

# ============================================
# PARAMETRELERİ DOĞRULA
# ============================================

debug_log("=" * 60)
debug_log("AD QUERY SCRIPT BAŞLATILIYOR")
debug_log("=" * 60)

if not AD_OBJECT:
    error_exit("AD_OBJECT parametresi eksik", "Kullanım: ad_query.py <user|computer|group> <domain> <search> [attributes]")

if AD_OBJECT not in ['user', 'computer', 'group']:
    error_exit(f"Geçersiz AD_OBJECT: {AD_OBJECT}", "Geçerli değerler: user, computer, group")

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
debug_log(f"Timeout: {LDAP_TIMEOUT}s")
debug_log(f"Max Retries: {MAX_RETRIES}")
debug_log(f"Retry Delay: {RETRY_DELAY}s")

# ============================================
# ATTRIBUTE LİSTESİNİ BELİRLE
# ============================================

if AD_ATTRIBUTES:
    requested_attributes = [attr.strip().lower() for attr in AD_ATTRIBUTES.split(",")]
    info_log(f"Custom attribute listesi: {len(requested_attributes)} attribute")
    debug_log(f"Attributes: {', '.join(requested_attributes)}")
else:
    if AD_OBJECT == "user":
        requested_attributes = DEFAULT_USER_ATTRIBUTES
    elif AD_OBJECT == "computer":
        requested_attributes = DEFAULT_COMPUTER_ATTRIBUTES
    else:  # group
        requested_attributes = DEFAULT_GROUP_ATTRIBUTES
    
    info_log(f"Default {AD_OBJECT} attribute listesi: {len(requested_attributes)} attribute")
    debug_log(f"Attributes: {', '.join(requested_attributes)}")

# ============================================
# SEARCH FILTER BELİRLE
# ============================================

if AD_OBJECT == "user":
    search_filter = f"(&(objectClass=user)(objectCategory=person)(sAMAccountName={AD_SEARCH}))"
elif AD_OBJECT == "computer":
    search_filter = f"(&(objectClass=computer)(cn={AD_SEARCH}))"
else:  # group
    search_filter = f"(&(objectClass=group)(cn={AD_SEARCH}))"

debug_log(f"Search Filter: {search_filter}")

# ============================================
# BASE DN OLUŞTUR
# ============================================

base_dn = generate_base_dn(AD_DOMAIN)
info_log(f"Base DN: {base_dn}")

# ============================================
# DC DISCOVERY
# ============================================

info_log("=" * 60)
info_log("DC DISCOVERY")
info_log("=" * 60)

dc_list = discover_all_domain_controllers(AD_DOMAIN)
info_log(f"DC listesi hazır: {len(dc_list)} DC")

# ============================================
# TLS KONFİGÜRASYONU
# ============================================

info_log("=" * 60)
info_log("SSL/TLS KONFİGÜRASYONU")
info_log("=" * 60)

tls_config = create_tls_config()

# ============================================
# CREDENTİAL TEST (İlk DC'de)
# ============================================

credential_test_dc = test_credentials_on_first_dc(dc_list, tls_config)
info_log(f"✓ Credential test tamamlandı: {credential_test_dc}")

# ============================================
# MULTI-DC SEARCH
# ============================================

search_result = search_across_all_dcs(dc_list, base_dn, search_filter, requested_attributes, tls_config)

# ============================================
# SONUÇ İŞLEME
# ============================================

if not search_result["found"]:
    # Object bulunamadı
    output = {
        "success": True,
        "found": False,
        "object_type": AD_OBJECT,
        "domain": AD_DOMAIN,
        "search_term": AD_SEARCH,
        "credential_test_dc": credential_test_dc,
        "tried_servers": search_result["tried_servers"],
        "message": f"{AD_OBJECT.capitalize()} '{AD_SEARCH}' hiçbir DC'de bulunamadı"
    }
    
    info_log("=" * 60)
    info_log("SORGU TAMAMLANDI - OBJECT BULUNAMADI")
    info_log("=" * 60)
    
    print(json.dumps(output, ensure_ascii=False, indent=2 if DEBUG else None))
    sys.exit(0)

# Object bulundu - attribute'leri işle
entry = search_result["entries"][0]
info_log(f"✓ Object bulundu: {AD_SEARCH}")
debug_log(f"DN: {entry.entry_dn}")

attributes = {}
missing_attributes = []

for attr in requested_attributes:
    try:
        if hasattr(entry, attr):
            raw_value = getattr(entry, attr).value
            debug_log(f"Attribute '{attr}': {type(raw_value).__name__}")
            normalized_value = normalize_attribute_value(attr, raw_value)
            attributes[attr] = normalized_value
        else:
            debug_log(f"Attribute '{attr}': NOT FOUND")
            attributes[attr] = "N/A"
            missing_attributes.append(attr)
    except Exception as e:
        warn_log(f"Attribute '{attr}' işlenirken hata: {e}")
        attributes[attr] = "N/A"
        missing_attributes.append(attr)

if missing_attributes:
    warn_log(f"Eksik attributes ({len(missing_attributes)}): {', '.join(missing_attributes)}")

# ============================================
# JSON ÇIKTI
# ============================================

output = {
    "success": True,
    "found": True,
    "object_type": AD_OBJECT,
    "domain": AD_DOMAIN,
    "server": search_result["server"],
    "credential_test_dc": credential_test_dc,
    "search_term": AD_SEARCH,
    "dn": entry.entry_dn,
    "tried_servers": search_result["tried_servers"],
    "attributes": attributes
}

info_log("=" * 60)
info_log("SORGU TAMAMLANDI")
info_log("=" * 60)
info_log(f"DN: {entry.entry_dn}")
info_log(f"Server: {search_result['server']}")
info_log(f"Attributes: {len(attributes)} adet")

print(json.dumps(output, ensure_ascii=False, indent=2 if DEBUG else None))
sys.exit(0)
