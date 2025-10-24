#!/usr/bin/env python3
"""
phpIPAM Excel to NetBox Import Script
======================================
Imports IP addresses from phpIPAM Excel export into NetBox

Usage:
    1. Install requirements: pip install pynetbox pandas xlrd --break-system-packages
    2. Edit NETBOX_URL and NETBOX_TOKEN below
    3. Run: python3 import_phpipam_to_netbox.py
"""

import pandas as pd
import pynetbox
import sys
from ipaddress import ip_network, ip_address

# ============================================================================
# CONFIGURATION - EDIT THESE
# ============================================================================

NETBOX_URL = "http://localhost"           # Your NetBox URL
NETBOX_TOKEN = "your_api_token_here"      # Your NetBox API token
EXCEL_FILE = "phpipam_IP_adress_export_2025-01-09.xls"

DRY_RUN = True    # Set to False to actually import data
VERBOSE = True    # Print detailed progress

# ============================================================================

class PhpIpamImporter:
    def __init__(self):
        self.nb = None
        self.stats = {
            'prefixes_created': 0,
            'prefixes_skipped': 0,
            'ips_created': 0,
            'ips_skipped': 0,
            'errors': 0
        }
        
    def connect_netbox(self):
        """Connect to NetBox API"""
        try:
            self.nb = pynetbox.api(NETBOX_URL, token=NETBOX_TOKEN)
            # Test connection
            self.nb.status()
            print(f"✓ Connected to NetBox at {NETBOX_URL}")
            return True
        except Exception as e:
            print(f"✗ Error connecting to NetBox: {e}")
            print("\nPlease check:")
            print("1. NETBOX_URL is correct")
            print("2. NETBOX_TOKEN is valid")
            print("3. NetBox is running")
            return False
    
    def read_phpipam_export(self):
        """Read phpIPAM Excel export"""
        try:
            print(f"\n📁 Reading {EXCEL_FILE}...")
            df = pd.read_excel(EXCEL_FILE, engine='xlrd')
            print(f"✓ Found {len(df)} rows")
            return df
        except FileNotFoundError:
            print(f"✗ File not found: {EXCEL_FILE}")
            print("Please place the file in the same directory as this script")
            return None
        except Exception as e:
            print(f"✗ Error reading file: {e}")
            return None
    
    def parse_subnet_header(self, header):
        """Extract subnet from header like '10.1.8.0/24 - CTRL-W27-04-LANtime (vlan: 108 - CTRL-W27-04-LANtime)'"""
        if not isinstance(header, str) or '/' not in header:
            return None, None
        
        parts = header.split(' - ')
        if len(parts) < 2:
            return None, None
            
        subnet = parts[0].strip()
        description = ' - '.join(parts[1:])
        
        try:
            # Validate subnet
            ip_network(subnet)
            return subnet, description
        except:
            return None, None
    
    def create_prefix(self, subnet, description):
        """Create prefix in NetBox"""
        try:
            if VERBOSE:
                print(f"  Processing prefix: {subnet}")
            
            if not DRY_RUN:
                # Check if prefix already exists
                existing = self.nb.ipam.prefixes.get(prefix=subnet)
                if existing:
                    if VERBOSE:
                        print(f"    → Prefix already exists")
                    self.stats['prefixes_skipped'] += 1
                    return existing
                
                # Create new prefix
                prefix = self.nb.ipam.prefixes.create(
                    prefix=subnet,
                    description=description[:200] if description else "",
                    status='active'
                )
                self.stats['prefixes_created'] += 1
                print(f"    ✓ Created prefix: {subnet}")
                return prefix
            else:
                self.stats['prefixes_created'] += 1
                print(f"    [DRY RUN] Would create prefix: {subnet}")
                return True
                
        except Exception as e:
            print(f"    ✗ Error creating prefix {subnet}: {e}")
            self.stats['errors'] += 1
            return None
    
    def create_ip_address(self, ip, hostname, description, mac, owner, device, port, note):
        """Create IP address in NetBox"""
        try:
            # Validate IP address
            ip_obj = ip_address(ip)
            ip_with_mask = f"{ip}/32" if ip_obj.version == 4 else f"{ip}/128"
            
            if VERBOSE:
                print(f"    Processing IP: {ip}")
            
            if not DRY_RUN:
                # Check if IP already exists
                existing = self.nb.ipam.ip_addresses.get(address=ip_with_mask)
                if existing:
                    if VERBOSE:
                        print(f"      → IP already exists")
                    self.stats['ips_skipped'] += 1
                    return
                
                # Build description
                desc_parts = []
                if pd.notna(description) and description:
                    desc_parts.append(str(description))
                if pd.notna(note) and note:
                    desc_parts.append(f"Note: {note}")
                full_description = " | ".join(desc_parts) if desc_parts else ""
                
                # Create IP address
                self.nb.ipam.ip_addresses.create(
                    address=ip_with_mask,
                    dns_name=hostname if pd.notna(hostname) else "",
                    description=full_description[:200] if full_description else "",
                    status='active'
                )
                self.stats['ips_created'] += 1
                if VERBOSE:
                    print(f"      ✓ Created IP: {ip}")
            else:
                self.stats['ips_created'] += 1
                if VERBOSE:
                    print(f"      [DRY RUN] Would create IP: {ip}")
                    
        except ValueError:
            # Invalid IP address, skip
            pass
        except Exception as e:
            if VERBOSE:
                print(f"      ✗ Error creating IP {ip}: {e}")
            self.stats['errors'] += 1
    
    def process_data(self, df):
        """Process phpIPAM data and import to NetBox"""
        print("\n📊 Processing data...")
        
        current_subnet = None
        current_description = None
        
        for idx, row in df.iterrows():
            # Check if this row is a subnet header
            first_col = row.iloc[0]
            
            if isinstance(first_col, str):
                # Check if it's a subnet header
                subnet, description = self.parse_subnet_header(first_col)
                if subnet:
                    print(f"\n[Subnet] {subnet}")
                    current_subnet = subnet
                    current_description = description
                    self.create_prefix(subnet, description)
                    continue
                
                # Check if it's a column header row
                if first_col.lower() == 'ip address':
                    continue
            
            # Check if this is an IP address row
            second_col = row.iloc[1] if len(row) > 1 else None
            
            # Try to parse as IP address
            if pd.notna(first_col):
                try:
                    ip_obj = ip_address(str(first_col).strip())
                    # Valid IP address found
                    ip = str(first_col).strip()
                    ip_state = row.iloc[1] if len(row) > 1 else None
                    description = row.iloc[2] if len(row) > 2 else None
                    hostname = row.iloc[3] if len(row) > 3 else None
                    mac = row.iloc[4] if len(row) > 4 else None
                    owner = row.iloc[5] if len(row) > 5 else None
                    device = row.iloc[6] if len(row) > 6 else None
                    port = row.iloc[7] if len(row) > 7 else None
                    note = row.iloc[8] if len(row) > 8 else None
                    
                    self.create_ip_address(ip, hostname, description, mac, owner, device, port, note)
                    
                except (ValueError, AttributeError):
                    # Not a valid IP address
                    pass
        
        print("\n" + "="*60)
        print("📈 Import Statistics")
        print("="*60)
        print(f"Prefixes created: {self.stats['prefixes_created']}")
        print(f"Prefixes skipped (already exist): {self.stats['prefixes_skipped']}")
        print(f"IP addresses created: {self.stats['ips_created']}")
        print(f"IP addresses skipped (already exist): {self.stats['ips_skipped']}")
        print(f"Errors: {self.stats['errors']}")
        print("="*60)
        
        if DRY_RUN:
            print("\n⚠️  This was a DRY RUN - no data was actually imported")
            print("Set DRY_RUN = False to perform actual import")

def main():
    print("="*60)
    print("phpIPAM to NetBox Import Script")
    print("="*60)
    
    importer = PhpIpamImporter()
    
    # Connect to NetBox
    if not importer.connect_netbox():
        sys.exit(1)
    
    # Read phpIPAM export
    df = importer.read_phpipam_export()
    if df is None:
        sys.exit(1)
    
    # Confirm before proceeding
    if not DRY_RUN:
        print("\n⚠️  WARNING: This will import data into NetBox!")
        response = input("Continue? (yes/no): ")
        if response.lower() != 'yes':
            print("Import cancelled")
            sys.exit(0)
    else:
        print("\n🔍 Running in DRY RUN mode (no data will be imported)")
    
    # Process and import data
    importer.process_data(df)
    
    print("\n✅ Import complete!")

if __name__ == "__main__":
    main()
