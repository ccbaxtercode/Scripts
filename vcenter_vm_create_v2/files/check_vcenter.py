#!/usr/bin/env python3
"""
Check if a single VM exists across all vCenters
Fast parallel check using SearchIndex
"""
import ssl
import json
import sys
import asyncio
import os
import logging
from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim

# Logging configuration
logging.basicConfig(
    level=logging.WARNING,  # Only show warnings/errors
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Parameters from Ansible
VM_NAME = sys.argv[1] if len(sys.argv) > 1 else None
VCENTERS = sys.argv[2].split(",") if len(sys.argv) > 2 else []
DATACENTER_PATHS = sys.argv[3].split(",") if len(sys.argv) > 3 else []

# Credentials from environment variables
VC_USERNAME = os.getenv("VC_USER")
VC_PASSWORD = os.getenv("VC_PASS")

# Validate inputs
if not VM_NAME:
    print(json.dumps({"exists": False, "error": "No VM name provided"}))
    sys.exit(1)

if not VC_USERNAME or not VC_PASSWORD:
    print(json.dumps({"exists": False, "error": "Missing credentials"}))
    sys.exit(1)

if not VCENTERS or not DATACENTER_PATHS:
    print(json.dumps({"exists": False, "error": "Missing vCenter/datacenter parameters"}))
    sys.exit(1)

# SSL context (ignore cert validation)
ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

# Connection pool
VC_CONNECTIONS = {}

def get_vcenter_connection(vc_host):
    """Get or create vCenter connection (connection pooling)"""
    if vc_host not in VC_CONNECTIONS:
        try:
            VC_CONNECTIONS[vc_host] = SmartConnect(
                host=vc_host,
                user=VC_USERNAME,
                pwd=VC_PASSWORD,
                sslContext=ssl_context
            )
        except Exception as e:
            logger.error(f"Failed to connect to {vc_host}: {str(e)}")
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
# VCENTER CHECK
# ============================================

def sync_check_vcenter(vm_name, vc_host, datacenter_path):
    """Check if VM exists in vCenter using SearchIndex"""
    try:
        si = get_vcenter_connection(vc_host)
        if not si:
            return False
        
        # Use SearchIndex for fast lookup
        inventory_path = f"{datacenter_path}/{vm_name}"
        vm = si.content.searchIndex.FindByInventoryPath(inventory_path)
        
        return vm is not None
        
    except Exception as e:
        logger.error(f"Check error ({vc_host}/{datacenter_path}/{vm_name}): {str(e)}")
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
    
    # Run all checks in parallel
    results = await asyncio.gather(*tasks)
    
    # Return True if VM exists in any location
    return any(results)

# ============================================
# MAIN
# ============================================

async def main():
    """Main entry point"""
    try:
        exists = await check_all_vcenters(VM_NAME)
        
        # Return JSON result
        print(json.dumps({
            "exists": exists,
            "vm_name": VM_NAME
        }))
        
    finally:
        cleanup_connections()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        print(json.dumps({
            "exists": False,
            "error": str(e)
        }))
        sys.exit(1)
