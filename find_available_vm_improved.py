#!/usr/bin/env python3
# Dosya: roles/vcenter_vm_create/files/find_available_vm.py
# Açıklama: VM İsim Kontrolü (Sertifika Zorunlu + DC Discovery + Async vCenter)

"""
VM Name Finder - Improved Version
- AD: Sertifika zorunlu, LDAPS (636), DC discovery
- Preflight: Test AD and vCenter connectivity
- Personal mode: Loop 01-99, find first available name
- Standard mode: Check single VM name availability
- Windows: AD check (all DCs), then vCenter (parallel async)
- Linux: vCenter only (parallel async)

Parameters:
  1. VM_NAME: "personal" or VM name
  2. PREFIX: Personal VM prefix (e.g., "VDI-MEHMET")
  3. VCENTERS: Comma-separated vCenter hostnames
  4. DATACENTER_PATHS: Comma-separated datacenter paths
  5. OS_FAMILY: "windows" or "linux"
  6. DOMAIN_NAME: Domain name (e.g., "test.local.com")
  7. AD_CERT_PATH: Certificate path (e.g., "/etc/ssl/certs/ad_chain.crt")
"""

import ssl
import json
import sys
import asyncio
import os
import traceback
from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim

try:
    from ldap3 import Server, Connection, Tls, SUBTREE, ALL
    LDAP_AVAILABLE = True
except ImportError:
    LDAP_AVAILABLE = False
    print("[ERROR] ldap3 not available")
    sys.exit(1)

try:
    import dns.resolver
    DNS_AVAILABLE = True
except ImportError:
    DNS_AVAILABLE = False
    print("[ERROR] dnspython not available")
    sys.exit(1)

# Parameters from Ansible
VM_NAME = sys.argv[1] if len(sys.argv) > 1 else None
PREFIX = sys.argv[2] if len(sys.argv) > 2 else ""
VCENTERS = sys.argv[3].split(",") if len(sys.argv) > 3 else []
DATACENTER_PATHS = sys.argv[4].split(",") if len(sys.argv) > 4 else []
OS_FAMILY = sys.argv[5] if len(sys.argv) > 5 else "linux"
DOMAIN_NAME = sys.argv[6] if len(sys.argv) > 6 else None  # test.local.com
AD_CERT_PATH = sys.argv[7] if len(sys.argv) > 7 else None

# Generate AD_BASE_DN from DOMAIN_NAME
AD_BASE_DN = None
if DOMAIN_NAME:
    domain_parts = DOMAIN_NAME.split('.')
    AD_BASE_DN = ",".join([f"DC={part}" for part in domain_parts])
    print(f"[INFO] Generated AD_BASE_DN: {AD_BASE_DN}")

# Credentials from environment variables
VC_USERNAME = os.getenv("VC_USER")
VC_PASSWORD = os.getenv("VC_PASS")
AD_USERNAME = os.getenv("AD_USER")
AD_PASSWORD = os.getenv("AD_PASS")

# Validate inputs
if not VM_NAME:
    print(json.dumps({"available": False, "reason": "No VM name provided"}))
    sys.exit(1)

if not VC_USERNAME or not VC_PASSWORD:
    print(json.dumps({"available": False, "reason": "Missing vCenter credentials"}))
    sys.exit(1)

if OS_FAMILY == "windows":
    if not AD_USERNAME or not AD_PASSWORD or not DOMAIN_NAME:
        print(json.dumps({"available": False, "reason": "Missing AD credentials or domain name for Windows VM"}))
        sys.exit(1)
    
    if not AD_CERT_PATH or not os.path.exists(AD_CERT_PATH):
        print(json.dumps({"available": False, "reason": f"AD certificate not found: {AD_CERT_PATH}"}))
        sys.exit(1)

# SSL context for vCenter
vc_ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
vc_ssl_context.check_hostname = False
vc_ssl_context.verify_mode = ssl.CERT_NONE

# Connection pool
VC_CONNECTIONS = {}

def get_vcenter_connection(vc_host):
    """Get or create vCenter connection from pool"""
    if vc_host not in VC_CONNECTIONS:
        try:
            VC_CONNECTIONS[vc_host] = SmartConnect(
                host=vc_host,
                user=VC_USERNAME,
                pwd=VC_PASSWORD,
                sslContext=vc_ssl_context
            )
        except Exception as e:
            print(f"[ERROR] Failed to connect to {vc_host}: {str(e)}")
            return None
    
    return VC_CONNECTIONS[vc_host]

def cleanup_connections():
    """Cleanup all vCenter connections"""
    for vc_host, connection in VC_CONNECTIONS.items():
        try:
            Disconnect(connection)
        except:
            pass

# ============================================
# DC DISCOVERY
# ============================================

def discover_domain_controllers(domain):
    """DNS SRV query to discover all DCs
    
    Returns:
        list: DC hostnames sorted by priority/weight
    """
    if not DNS_AVAILABLE:
        print(f"[ERROR] dnspython required for DC discovery")
        return []
    
    srv_record = f"_ldap._tcp.dc._msdcs.{domain}"
    
    try:
        print(f"[INFO] DNS SRV query: {srv_record}")
        answers = dns.resolver.resolve(srv_record, 'SRV')
        
        # Sort by priority (lower first), then by weight (higher first)
        dc_list = sorted(answers, key=lambda x: (x.priority, -x.weight))
        dc_hostnames = [str(dc.target).rstrip('.') for dc in dc_list]
        
        print(f"[INFO] Found {len(dc_hostnames)} DCs: {', '.join(dc_hostnames)}")
        return dc_hostnames
        
    except Exception as e:
        print(f"[ERROR] DC discovery failed: {e}")
        return []

# ============================================
# AD TLS CONFIGURATION
# ============================================

def get_ad_tls_config():
    """Get TLS configuration for AD (certificate required)"""
    try:
        tls_config = Tls(
            ca_certs_file=AD_CERT_PATH,
            validate=ssl.CERT_REQUIRED,
            version=ssl.PROTOCOL_TLSv1_2
        )
        return tls_config
    except Exception as e:
        print(f"[ERROR] Failed to configure TLS: {e}")
        return None

# ============================================
# PREFLIGHT CHECKS
# ============================================

def test_ad_bind(dc_hostname):
    """Test AD bind on first DC (credential test)"""
    try:
        print(f"[INFO] Testing AD bind: {dc_hostname}")
        
        tls_config = get_ad_tls_config()
        if not tls_config:
            return False, "TLS configuration failed"
        
        server = Server(
            dc_hostname,
            port=636,
            use_ssl=True,
            get_info=ALL,
            tls=tls_config,
            connect_timeout=10
        )
        
        conn = Connection(
            server,
            user=AD_USERNAME,
            password=AD_PASSWORD,
            auto_bind=True,
            receive_timeout=10
        )
        
        if not conn.bind():
            return False, f"Bind failed: {conn.result}"
        
        conn.unbind()
        print(f"[INFO]   ✓ AD bind OK")
        return True, "Bind successful"
        
    except Exception as e:
        return False, f"Bind error: {str(e)}"

def test_vcenter_connection(vc_host):
    """Test vCenter connectivity"""
    try:
        print(f"[INFO] Testing vCenter: {vc_host}")
        si = SmartConnect(
            host=vc_host,
            user=VC_USERNAME,
            pwd=VC_PASSWORD,
            sslContext=vc_ssl_context
        )
        
        content = si.RetrieveContent()
        if not content:
            Disconnect(si)
            return False, "Failed to retrieve content"
        
        Disconnect(si)
        print(f"[INFO]   ✓ vCenter connection OK")
        return True, "vCenter connection OK"
        
    except vim.fault.InvalidLogin:
        return False, "Invalid credentials"
    except Exception as e:
        error_msg = str(e)
        if "timeout" in error_msg.lower():
            return False, "Connection timeout"
        elif "refused" in error_msg.lower():
            return False, "Connection refused"
        else:
            return False, f"Connection error: {error_msg}"

async def test_connection_async(service_name, test_func):
    """Async wrapper for connection tests"""
    loop = asyncio.get_event_loop()
    success, message = await loop.run_in_executor(None, test_func)
    return {"service": service_name, "success": success, "message": message}

async def preflight_check(dc_list):
    """Run preflight checks (parallel)"""
    print("=" * 60)
    print("PREFLIGHT CHECK")
    print("=" * 60)
    
    tasks = []
    
    # Test AD (Windows only - test first DC)
    if OS_FAMILY == "windows" and dc_list:
        tasks.append(test_connection_async("AD", lambda: test_ad_bind(dc_list[0])))
    
    # Test all vCenters
    for vc in VCENTERS:
        tasks.append(test_connection_async(f"vCenter-{vc}", lambda v=vc: test_vcenter_connection(v)))
    
    results = await asyncio.gather(*tasks)
    
    failures = [r for r in results if not r['success']]
    
    if failures:
        print("[ERROR] PREFLIGHT CHECK FAILED")
        for fail in failures:
            print(f"[ERROR]   ✗ {fail['service']}: {fail['message']}")
        print("=" * 60)
        print(json.dumps({
            "available": False,
            "reason": "Preflight check failed - service connectivity issues",
            "errors": failures
        }))
        sys.exit(1)
    
    print("[SUCCESS] Preflight checks passed")
    print("=" * 60)
    print()
    return True

# ============================================
# AD CHECK (IMPROVED)
# ============================================

def check_ad_on_dc(vm_name, dc_hostname):
    """Check if computer exists in specific DC"""
    try:
        tls_config = get_ad_tls_config()
        if not tls_config:
            return False
        
        server = Server(
            dc_hostname,
            port=636,
            use_ssl=True,
            get_info=ALL,
            tls=tls_config,
            connect_timeout=5
        )
        
        conn = Connection(
            server,
            user=AD_USERNAME,
            password=AD_PASSWORD,
            auto_bind=True,
            receive_timeout=5
        )
        
        if not conn.bind():
            return False
        
        search_filter = f"(&(objectClass=computer)(cn={vm_name}))"
        conn.search(
            search_base=AD_BASE_DN,
            search_filter=search_filter,
            search_scope=SUBTREE,
            attributes=['cn']
        )
        
        exists = len(conn.entries) > 0
        conn.unbind()
        return exists
        
    except Exception:
        # Fail silently for individual DC failures
        return False

def check_ad_all_dcs(vm_name, dc_list):
    """Check AD across all DCs (sequential for consistency)
    
    Returns:
        bool: True if found on any DC
    """
    if not dc_list:
        return False
    
    # Log sade ve öz
    ad_results = []
    for dc in dc_list:
        result = check_ad_on_dc(vm_name, dc)
        ad_results.append((dc, result))
        if result:
            # Bulundu, diğer DC'leri kontrol etmeye gerek yok
            print(f"[AD] {vm_name}: EXISTS (found on {dc})")
            return True
    
    # Hiçbirinde bulunamadı
    print(f"[AD] {vm_name}: NOT_FOUND (checked {len(dc_list)} DCs)")
    return False

# ============================================
# VCENTER CHECK (ASYNC IMPROVED)
# ============================================

def sync_check_vcenter_simple(vm_name, vc_host, datacenter_path):
    """Check if VM exists in vCenter (simplified)"""
    try:
        si = get_vcenter_connection(vc_host)
        if not si:
            return False
        
        # Tek arama yap - inventory path ile
        inventory_path = f"{datacenter_path}/{vm_name}"
        vm = si.content.searchIndex.FindByInventoryPath(inventory_path)
        
        # Alternatif arama kaldırıldı - performans için
        return vm is not None
        
    except Exception:
        return False

async def check_vcenter_async(vm_name, vc_host, datacenter_path):
    """Async wrapper for vCenter check"""
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(
        None, 
        sync_check_vcenter_simple, 
        vm_name, 
        vc_host, 
        datacenter_path
    )
    return {"vc": vc_host, "dc": datacenter_path, "exists": result}

async def check_all_vcenters(vm_name):
    """Check VM across all vCenters (parallel async)
    
    Returns:
        tuple: (exists: bool, details: list)
    """
    tasks = []
    
    # Tüm vCenter/DC kombinasyonları için async task oluştur
    for vc_host in VCENTERS:
        for dc_path in DATACENTER_PATHS:
            tasks.append(check_vcenter_async(vm_name, vc_host, dc_path))
    
    # Paralel çalıştır
    results = await asyncio.gather(*tasks)
    
    # Sonuçları değerlendir
    exists = any(r["exists"] for r in results)
    
    # Sade log
    if exists:
        found_in = [f"{r['vc']}/{r['dc'].split('/')[-2]}" for r in results if r["exists"]]
        print(f"[vCenter] {vm_name}: EXISTS (found in: {', '.join(found_in)})")
    else:
        total_checked = len(VCENTERS) * len(DATACENTER_PATHS)
        print(f"[vCenter] {vm_name}: NOT_FOUND (checked {total_checked} locations)")
    
    return exists, results

# ============================================
# MAIN SEARCH LOGIC (IMPROVED)
# ============================================

async def find_available_vm(dc_list):
    """Find available VM name (Personal or Standard mode)"""
    
    # Detect mode
    if VM_NAME.lower() == "personal":
        mode = "personal"
        print(f"[INFO] Mode: Personal VM search")
        print(f"[INFO] Prefix: {PREFIX}, OS: {OS_FAMILY}")
    else:
        mode = "standard"
        print(f"[INFO] Mode: Standard VM check")
        print(f"[INFO] VM Name: {VM_NAME}, OS: {OS_FAMILY}")
    
    print("=" * 60)
    
    # PERSONAL MODE: Loop 01-99
    if mode == "personal":
        checked_count = 0
        
        for i in range(1, 100):
            test_name = f"{PREFIX}{i:02d}"
            checked_count += 1
            
            # Sade progress log
            if i % 10 == 0:
                print(f"[Progress] Checked {i} names...")
            
            # Windows: Check AD first (all DCs)
            if OS_FAMILY == "windows":
                ad_exists = check_ad_all_dcs(test_name, dc_list)
                if ad_exists:
                    continue  # Skip to next index
            
            # vCenter check (parallel async)
            vc_exists, _ = await check_all_vcenters(test_name)
            if vc_exists:
                continue  # Skip to next index
            
            # Found available name!
            print("=" * 60)
            print(f"[SUCCESS] Available VM found: {test_name}")
            print(f"[SUMMARY] Checked {checked_count} names, Index: {i:02d}")
            print("=" * 60)
            return {"available": True, "vm_name": test_name, "index": i, "mode": mode}
        
        # All indices full
        print("=" * 60)
        print(f"[ERROR] No available index (01-99 all used)")
        print(f"[SUMMARY] Checked all 99 possible names")
        print("=" * 60)
        return {"available": False, "vm_name": None, "reason": "All indices (01-99) are in use", "mode": mode}
    
    # STANDARD MODE: Single check
    else:
        test_name = VM_NAME
        
        # Windows: Check AD first (all DCs)
        if OS_FAMILY == "windows":
            ad_exists = check_ad_all_dcs(test_name, dc_list)
            if ad_exists:
                print("=" * 60)
                print(f"[ERROR] VM unavailable: {test_name}")
                print(f"[REASON] Exists in Active Directory")
                print("=" * 60)
                return {"available": False, "vm_name": test_name, "reason": "VM exists in AD", "mode": mode}
        
        # vCenter check (parallel async)
        vc_exists, details = await check_all_vcenters(test_name)
        
        if vc_exists:
            print("=" * 60)
            print(f"[ERROR] VM unavailable: {test_name}")
            print(f"[REASON] Exists in vCenter")
            print("=" * 60)
            return {"available": False, "vm_name": test_name, "reason": "VM exists in vCenter", "mode": mode}
        
        # Available!
        print("=" * 60)
        print(f"[SUCCESS] VM available: {test_name}")
        total_checks = len(dc_list) if OS_FAMILY == "windows" else 0
        total_checks += len(VCENTERS) * len(DATACENTER_PATHS)
        print(f"[SUMMARY] Verified across {total_checks} systems")
        print("=" * 60)
        return {"available": True, "vm_name": test_name, "index": None, "mode": mode}

# ============================================
# MAIN
# ============================================

async def main():
    """Main entry point"""
    try:
        # DC Discovery (Windows only)
        dc_list = []
        if OS_FAMILY == "windows":
            print(f"[INFO] Domain: {DOMAIN_NAME}")
            dc_list = discover_domain_controllers(DOMAIN_NAME)
            
            if not dc_list:
                print(json.dumps({
                    "available": False,
                    "reason": "No domain controllers found via DNS SRV"
                }))
                sys.exit(1)
        
        # Preflight checks
        await preflight_check(dc_list)
        
        # Find/check VM name
        result = await find_available_vm(dc_list)
        
        # Output JSON result (last line for Ansible parsing)
        print(json.dumps(result))
        
    finally:
        cleanup_connections()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("[INFO] Interrupted by user")
        cleanup_connections()
        sys.exit(1)
    except Exception as e:
        print(f"[ERROR] Unexpected error: {str(e)}")
        cleanup_connections()
        print(json.dumps({
            "available": False,
            "reason": f"Script error: {str(e)}"
        }))
        sys.exit(1)
