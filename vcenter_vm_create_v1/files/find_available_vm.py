#!/usr/bin/env python3
"""
Optimized VM Name Finder
Async/parallel checking across multiple vCenters and AD
"""
import ssl
import json
import sys
import asyncio
import os
import logging
from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim

try:
    from ldap3 import Server, Connection, SUBTREE, ALL
    LDAP_AVAILABLE = True
except ImportError:
    LDAP_AVAILABLE = False
    logging.warning("ldap3 not available, AD checks will be skipped")

# Logging configuration
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Parameters from Ansible
PREFIX = sys.argv[1]
VCENTERS = sys.argv[2].split(",")
DATACENTER_PATHS = sys.argv[3].split(",")
OS_FAMILY = sys.argv[4]  # "windows" or "linux"
AD_SERVER = sys.argv[5] if len(sys.argv) > 5 else None
AD_BASE_DN = sys.argv[6] if len(sys.argv) > 6 else None
MAX_SUFFIX = 99

# Credentials from environment variables (secure)
VC_USERNAME = os.getenv("VC_USER")
VC_PASSWORD = os.getenv("VC_PASS")
AD_USERNAME = os.getenv("AD_USER")
AD_PASSWORD = os.getenv("AD_PASS")

# Validate credentials
if not VC_USERNAME or not VC_PASSWORD:
    logger.error("Missing vCenter credentials")
    print(json.dumps({"available": False, "vm_name": None, "reason": "Missing vCenter credentials"}))
    sys.exit(1)

if OS_FAMILY == "windows" and (not AD_USERNAME or not AD_PASSWORD or not AD_SERVER):
    logger.warning("Missing AD credentials for Windows VM - AD checks will be skipped")

# SSL context (ignore cert validation)
ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

# Connection pool for vCenter
VC_CONNECTIONS = {}

def get_vcenter_connection(vc_host):
    """Get or create vCenter connection (connection pooling)"""
    if vc_host not in VC_CONNECTIONS:
        try:
            logger.info(f"Connecting to vCenter: {vc_host}")
            VC_CONNECTIONS[vc_host] = SmartConnect(
                host=vc_host,
                user=VC_USERNAME,
                pwd=VC_PASSWORD,
                sslContext=ssl_context
            )
        except Exception as e:
            logger.error(f"Failed to connect to vCenter {vc_host}: {str(e)}")
            return None
    return VC_CONNECTIONS[vc_host]

def cleanup_connections():
    """Cleanup all vCenter connections"""
    for vc_host, connection in VC_CONNECTIONS.items():
        try:
            Disconnect(connection)
            logger.info(f"Disconnected from vCenter: {vc_host}")
        except:
            pass

# -----------------------------
# AD Check (LDAP3)
# -----------------------------
def check_ad_ldap(vm_name):
    """Check if computer object exists in AD using LDAP"""
    if not LDAP_AVAILABLE or not AD_SERVER or not AD_USERNAME or not AD_PASSWORD:
        return False
    
    try:
        server = Server(AD_SERVER, get_info=ALL)
        conn = Connection(
            server,
            user=AD_USERNAME,
            password=AD_PASSWORD,
            auto_bind=True
        )
        
        # Search for computer object
        search_filter = f"(&(objectClass=computer)(cn={vm_name}))"
        conn.search(
            search_base=AD_BASE_DN,
            search_filter=search_filter,
            search_scope=SUBTREE,
            attributes=['cn']
        )
        
        exists = len(conn.entries) > 0
        conn.unbind()
        
        if exists:
            logger.info(f"AD: {vm_name} exists (skipping)")
        
        return exists
        
    except Exception as e:
        logger.error(f"AD check error for {vm_name}: {str(e)}")
        return False

async def check_ad_async(vm_name):
    """Async wrapper for AD check"""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, check_ad_ldap, vm_name)

# -----------------------------
# VCenter Check
# -----------------------------
def sync_check_vcenter(vm_name, vc_host, datacenter_path):
    """Check if VM exists in vCenter using SearchIndex"""
    try:
        si = get_vcenter_connection(vc_host)
        if not si:
            return False
        
        # Use SearchIndex for fast lookup
        inventory_path = f"{datacenter_path}/{vm_name}"
        vm = si.content.searchIndex.FindByInventoryPath(inventory_path)
        
        exists = vm is not None
        
        if exists:
            logger.debug(f"vCenter {vc_host}: {vm_name} exists in {datacenter_path}")
        
        return exists
        
    except Exception as e:
        logger.error(f"vCenter check error ({vc_host}/{datacenter_path}/{vm_name}): {str(e)}")
        return False

async def check_vcenter_async(vm_name, vc_host, datacenter_path):
    """Async wrapper for vCenter check"""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, sync_check_vcenter, vm_name, vc_host, datacenter_path)

async def check_all_vcenters(vm_name):
    """Check VM existence across all vCenters and datacenters (parallel)"""
    tasks = []
    for vc_host in VCENTERS:
        for dc_path in DATACENTER_PATHS:
            tasks.append(check_vcenter_async(vm_name, vc_host, dc_path))
    
    results = await asyncio.gather(*tasks)
    return any(results)

# -----------------------------
# Main Logic
# -----------------------------
async def find_available_vm():
    """Find first available VM name (01-99)"""
    logger.info(f"Starting search for {PREFIX}XX (OS: {OS_FAMILY})")
    
    for i in range(1, MAX_SUFFIX + 1):
        suffix = f"{i:02d}"
        vm_candidate = f"{PREFIX}{suffix}"
        
        logger.debug(f"Checking: {vm_candidate}")
        
        # Parallel check: AD (if Windows) + all vCenters
        tasks = []
        
        # Add AD check for Windows
        if OS_FAMILY == "windows":
            tasks.append(check_ad_async(vm_candidate))
        else:
            # For Linux, create a dummy task that returns False
            async def dummy_ad_check():
                return False
            tasks.append(dummy_ad_check())
        
        # Add vCenter checks
        tasks.append(check_all_vcenters(vm_candidate))
        
        # Execute all checks in parallel
        ad_exists, vc_exists = await asyncio.gather(*tasks)
        
        # If exists in AD or vCenter, continue to next index
        if ad_exists:
            logger.info(f"{vm_candidate} - exists in AD (skipped)")
            continue
        
        if vc_exists:
            logger.info(f"{vm_candidate} - exists in vCenter (skipped)")
            continue
        
        # Found available name!
        logger.info(f"✓ Available VM name found: {vm_candidate}")
        print(json.dumps({
            "available": True,
            "vm_name": vm_candidate,
            "index": i,
            "reason": None
        }))
        return
    
    # No available suffix found
    logger.error(f"No available suffix found for {PREFIX} (01-99 all used)")
    print(json.dumps({
        "available": False,
        "vm_name": None,
        "index": None,
        "reason": f"All suffixes (01-{MAX_SUFFIX}) are in use"
    }))

# -----------------------------
# Entry Point
# -----------------------------
async def main():
    try:
        await find_available_vm()
    finally:
        cleanup_connections()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        cleanup_connections()
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        cleanup_connections()
        print(json.dumps({
            "available": False,
            "vm_name": None,
            "reason": f"Script error: {str(e)}"
        }))
        sys.exit(1)