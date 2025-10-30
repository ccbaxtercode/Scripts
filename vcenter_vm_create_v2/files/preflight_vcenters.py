#!/usr/bin/env python3
"""
vCenter Preflight Check
Tests connectivity and authentication to all vCenters before starting VM search
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
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Parameters from Ansible
VCENTERS = sys.argv[1].split(",") if len(sys.argv) > 1 else []

# Credentials from environment variables
VC_USERNAME = os.getenv("VC_USER")
VC_PASSWORD = os.getenv("VC_PASS")

# Validate credentials
if not VC_USERNAME or not VC_PASSWORD:
    logger.error("Missing vCenter credentials (VC_USER/VC_PASS)")
    print(json.dumps({
        "success": False,
        "errors": [{"service": "credentials", "message": "Missing vCenter credentials"}]
    }))
    sys.exit(1)

if not VCENTERS:
    logger.error("No vCenter hosts provided")
    print(json.dumps({
        "success": False,
        "errors": [{"service": "parameters", "message": "No vCenter hosts provided"}]
    }))
    sys.exit(1)

# SSL context (ignore cert validation)
ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

# ============================================
# VCENTER CONNECTIVITY TEST
# ============================================

def test_vcenter_connection(vc_host):
    """Test vCenter connectivity and authentication"""
    try:
        logger.debug(f"Testing vCenter: {vc_host}")
        
        # Connect to vCenter
        si = SmartConnect(
            host=vc_host,
            user=VC_USERNAME,
            pwd=VC_PASSWORD,
            sslContext=ssl_context
        )
        
        # Simple API call to verify connection works
        content = si.RetrieveContent()
        if not content:
            Disconnect(si)
            return False, f"Failed to retrieve content"
        
        Disconnect(si)
        return True, "Connection OK"
        
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

async def test_connection_async(vc_host):
    """Async wrapper for vCenter connection test"""
    loop = asyncio.get_event_loop()
    success, message = await loop.run_in_executor(None, test_vcenter_connection, vc_host)
    return {
        "service": f"vCenter-{vc_host}",
        "success": success,
        "message": message
    }

async def preflight_check():
    """Run preflight checks on all vCenters in parallel"""
    logger.info("=" * 60)
    logger.info("PREFLIGHT CHECK - vCenter Connectivity")
    logger.info("=" * 60)
    
    # Test all vCenter connections in parallel
    tasks = []
    for vc in VCENTERS:
        logger.info(f"Testing vCenter: {vc}")
        tasks.append(test_connection_async(vc))
    
    # Run all tests in parallel
    results = await asyncio.gather(*tasks)
    
    # Check for failures
    failures = [r for r in results if not r['success']]
    successes = [r for r in results if r['success']]
    
    # Log results
    logger.info("-" * 60)
    for result in successes:
        logger.info(f"  ✓ {result['service']}: {result['message']}")
    
    for result in failures:
        logger.error(f"  ✗ {result['service']}: {result['message']}")
    
    logger.info("-" * 60)
    
    if failures:
        logger.error("PREFLIGHT CHECK FAILED")
        logger.error(f"Failed vCenters: {len(failures)}/{len(results)}")
        logger.info("=" * 60)
        
        # Return error JSON
        print(json.dumps({
            "success": False,
            "errors": failures
        }))
        sys.exit(1)
    
    logger.info("PREFLIGHT CHECK PASSED - All vCenters reachable")
    logger.info("=" * 60)
    
    # Return success JSON
    print(json.dumps({
        "success": True,
        "errors": []
    }))
    sys.exit(0)

# ============================================
# MAIN
# ============================================

if __name__ == "__main__":
    try:
        asyncio.run(preflight_check())
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        print(json.dumps({
            "success": False,
            "errors": [{"service": "script", "message": str(e)}]
        }))
        sys.exit(1)
