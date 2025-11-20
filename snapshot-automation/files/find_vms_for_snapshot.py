#!/usr/bin/env python3
# Dosya: files/find_vms_for_snapshot.py
# Açıklama: VM Bulma ve Parametre Toplama (Snapshot İşlemleri İçin)

"""
VM Finder for Snapshot Operations
- Accepts list of VM names from Ansible
- Searches across multiple vCenters and datacenters (domain-based)
- Returns JSON with VM details (vcenter, datacenter, folder, uuid, power_state)
- Skips VMs if multiple found in same datacenter (ambiguous)
"""

import ssl
import json
import sys
import os
from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim

# Parameters from Ansible
VM_NAMES_JSON = sys.argv[1] if len(sys.argv) > 1 else "[]"  # JSON list of VM names
VCENTER_SEARCH_TARGETS_JSON = sys.argv[2] if len(sys.argv) > 2 else "[]"  # JSON list of search targets
DOMAIN = sys.argv[3] if len(sys.argv) > 3 else "domain1"

# Credentials from environment variables
VC_USERNAME = os.getenv("VC_USER")
VC_PASSWORD = os.getenv("VC_PASS")

# Parse JSON inputs
try:
    VM_NAMES = json.loads(VM_NAMES_JSON)
except json.JSONDecodeError:
    print(json.dumps({"success": False, "error": "Invalid VM names JSON"}))
    sys.exit(1)

try:
    SEARCH_TARGETS = json.loads(VCENTER_SEARCH_TARGETS_JSON)
except json.JSONDecodeError:
    print(json.dumps({"success": False, "error": "Invalid search targets JSON"}))
    sys.exit(1)

# Validate inputs
if not VM_NAMES or not isinstance(VM_NAMES, list):
    print(json.dumps({"success": False, "error": "No VM names provided or invalid format"}))
    sys.exit(1)

if not VC_USERNAME or not VC_PASSWORD:
    print(json.dumps({"success": False, "error": "Missing vCenter credentials"}))
    sys.exit(1)

if not SEARCH_TARGETS or not isinstance(SEARCH_TARGETS, list):
    print(json.dumps({"success": False, "error": "No search targets provided"}))
    sys.exit(1)

# SSL context
ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

# Connection pool
VC_CONNECTIONS = {}

def get_vcenter_connection(vc_host):
    """Get or create vCenter connection"""
    if vc_host not in VC_CONNECTIONS:
        try:
            VC_CONNECTIONS[vc_host] = SmartConnect(
                host=vc_host,
                user=VC_USERNAME,
                pwd=VC_PASSWORD,
                sslContext=ssl_context
            )
        except Exception as e:
            print(f"[ERROR] Failed to connect to {vc_host}: {str(e)}", file=sys.stderr)
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
# VCENTER VM SEARCH
# ============================================

def get_vm_details(vm_obj):
    """Extract VM details from VM object"""
    try:
        return {
            "uuid": vm_obj.summary.config.uuid,
            "power_state": vm_obj.runtime.powerState,
            "guest_id": vm_obj.summary.config.guestId,
            "num_cpu": vm_obj.summary.config.numCpu,
            "memory_mb": vm_obj.summary.config.memorySizeMB,
            "vm_path": vm_obj.summary.config.vmPathName,
            "instance_uuid": vm_obj.summary.config.instanceUuid
        }
    except Exception as e:
        print(f"[WARN] Failed to get VM details: {str(e)}", file=sys.stderr)
        return {}

def search_vm_in_datacenter(vm_name, vc_host, vc_name, datacenter_name, folder_path=None):
    """Search for VM in specific datacenter"""
    try:
        si = get_vcenter_connection(vc_host)
        if not si:
            return None
        
        content = si.RetrieveContent()
        
        # Find datacenter
        datacenter = None
        for dc in content.rootFolder.childEntity:
            if hasattr(dc, 'name') and dc.name == datacenter_name:
                datacenter = dc
                break
        
        if not datacenter:
            print(f"[WARN] Datacenter {datacenter_name} not found in {vc_name}", file=sys.stderr)
            return None
        
        # Container view for VMs
        container = content.viewManager.CreateContainerView(
            datacenter.vmFolder, [vim.VirtualMachine], True
        )
        
        found_vms = []
        for vm in container.view:
            if vm.name == vm_name:
                # Check folder path if specified
                if folder_path:
                    vm_folder_path = ""
                    parent = vm.parent
                    while parent and parent != datacenter.vmFolder:
                        vm_folder_path = f"/{parent.name}{vm_folder_path}"
                        parent = parent.parent
                    
                    vm_folder_path = f"/{datacenter_name}/vm{vm_folder_path}"
                    
                    if not vm_folder_path.startswith(folder_path):
                        continue
                
                found_vms.append(vm)
        
        container.Destroy()
        
        if len(found_vms) == 0:
            return None
        
        if len(found_vms) > 1:
            return {
                "error": "multiple_vms_found",
                "count": len(found_vms),
                "message": f"Multiple VMs ({len(found_vms)}) with name '{vm_name}' found in {vc_name}/{datacenter_name}"
            }
        
        # Single VM found
        vm = found_vms[0]
        
        # Get folder path
        folder_path_full = ""
        parent = vm.parent
        while parent and parent != datacenter.vmFolder:
            folder_path_full = f"/{parent.name}{folder_path_full}"
            parent = parent.parent
        folder_path_full = f"/{datacenter_name}/vm{folder_path_full}"
        
        vm_details = get_vm_details(vm)
        
        return {
            "name": vm_name,
            "vcenter": vc_name,
            "vcenter_hostname": vc_host,
            "datacenter": datacenter_name,
            "folder": folder_path_full,
            "uuid": vm_details.get("uuid", ""),
            "instance_uuid": vm_details.get("instance_uuid", ""),
            "power_state": vm_details.get("power_state", ""),
            "guest_id": vm_details.get("guest_id", ""),
            "num_cpu": vm_details.get("num_cpu", 0),
            "memory_mb": vm_details.get("memory_mb", 0),
            "vm_path": vm_details.get("vm_path", "")
        }
        
    except Exception as e:
        print(f"[ERROR] Error searching VM {vm_name} in {vc_name}/{datacenter_name}: {str(e)}", file=sys.stderr)
        return None

def find_vm_across_targets(vm_name, search_targets):
    """Search for VM across all search targets"""
    print(f"\n[INFO] Searching for VM: {vm_name}", file=sys.stderr)
    
    found_results = []
    
    for target in search_targets:
        vc_name = target.get("name")
        vc_hostname = target.get("hostname")
        datacenters = target.get("datacenters", [])
        
        for dc in datacenters:
            dc_name = dc.get("name")
            dc_domain = dc.get("domain")
            folder_path = dc.get("folder")
            
            print(f"[DEBUG]   Checking {vc_name}/{dc_name} (domain: {dc_domain}){' [folder: ' + folder_path + ']' if folder_path else ''}", file=sys.stderr)
            
            result = search_vm_in_datacenter(vm_name, vc_hostname, vc_name, dc_name, folder_path)
            
            if result:
                if "error" in result:
                    # Multiple VMs found - skip this VM entirely
                    print(f"[ERROR]   {result['message']}", file=sys.stderr)
                    return {
                        "found": False,
                        "error": result["error"],
                        "message": result["message"]
                    }
                else:
                    # Single VM found
                    print(f"[SUCCESS] Found in {vc_name}/{dc_name}", file=sys.stderr)
                    found_results.append(result)
    
    if len(found_results) == 0:
        print(f"[WARN]   VM not found in any location", file=sys.stderr)
        return {"found": False, "error": "vm_not_found", "message": f"VM '{vm_name}' not found"}
    
    if len(found_results) > 1:
        print(f"[WARN]   VM found in multiple locations ({len(found_results)}), using first one", file=sys.stderr)
    
    # Return first found result
    return {"found": True, "vm_data": found_results[0]}

# ============================================
# MAIN
# ============================================

def main():
    """Main entry point"""
    print("=" * 60, file=sys.stderr)
    print("VM SEARCH FOR SNAPSHOT OPERATIONS", file=sys.stderr)
    print("=" * 60, file=sys.stderr)
    print(f"[INFO] Domain: {DOMAIN}", file=sys.stderr)
    print(f"[INFO] VMs to search: {len(VM_NAMES)}", file=sys.stderr)
    print(f"[INFO] Search targets: {len(SEARCH_TARGETS)} vCenters", file=sys.stderr)
    
    # Count total datacenters
    total_dcs = sum(len(t.get("datacenters", [])) for t in SEARCH_TARGETS)
    print(f"[INFO] Total datacenters to search: {total_dcs}", file=sys.stderr)
    print("=" * 60, file=sys.stderr)
    
    results = {
        "success": True,
        "domain": DOMAIN,
        "total_requested": len(VM_NAMES),
        "vms_found": [],
        "vms_not_found": [],
        "vms_with_errors": []
    }
    
    try:
        # Search each VM
        for vm_name in VM_NAMES:
            search_result = find_vm_across_targets(vm_name, SEARCH_TARGETS)
            
            if search_result.get("found"):
                results["vms_found"].append(search_result["vm_data"])
            else:
                error_info = {
                    "name": vm_name,
                    "error": search_result.get("error", "unknown"),
                    "message": search_result.get("message", "Unknown error")
                }
                
                if search_result.get("error") == "vm_not_found":
                    results["vms_not_found"].append(error_info)
                else:
                    results["vms_with_errors"].append(error_info)
        
        # Summary
        print("\n" + "=" * 60, file=sys.stderr)
        print("SEARCH SUMMARY", file=sys.stderr)
        print("=" * 60, file=sys.stderr)
        print(f"[INFO] Total Requested: {results['total_requested']}", file=sys.stderr)
        print(f"[INFO] Found: {len(results['vms_found'])}", file=sys.stderr)
        print(f"[INFO] Not Found: {len(results['vms_not_found'])}", file=sys.stderr)
        print(f"[INFO] Errors (ambiguous/multiple): {len(results['vms_with_errors'])}", file=sys.stderr)
        print("=" * 60, file=sys.stderr)
        
        if results["vms_found"]:
            print("\n[SUCCESS] Found VMs:", file=sys.stderr)
            for vm in results["vms_found"]:
                print(f"  - {vm['name']} -> {vm['vcenter']}/{vm['datacenter']}", file=sys.stderr)
        
        if results["vms_not_found"]:
            print("\n[WARN] Not Found VMs:", file=sys.stderr)
            for vm in results["vms_not_found"]:
                print(f"  - {vm['name']}", file=sys.stderr)
        
        if results["vms_with_errors"]:
            print("\n[ERROR] VMs with Errors:", file=sys.stderr)
            for vm in results["vms_with_errors"]:
                print(f"  - {vm['name']}: {vm['message']}", file=sys.stderr)
        
        print("", file=sys.stderr)
        
        # Output JSON result (stdout for Ansible parsing)
        print(json.dumps(results, indent=2))
        
    except Exception as e:
        print(f"\n[ERROR] Unexpected error: {str(e)}", file=sys.stderr)
        results["success"] = False
        results["error"] = str(e)
        print(json.dumps(results, indent=2))
        sys.exit(1)
    
    finally:
        cleanup_connections()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[INFO] Interrupted by user", file=sys.stderr)
        cleanup_connections()
        sys.exit(1)
    except Exception as e:
        print(f"\n[ERROR] Fatal error: {str(e)}", file=sys.stderr)
        cleanup_connections()
        print(json.dumps({
            "success": False,
            "error": f"Script error: {str(e)}"
        }))
        sys.exit(1)
