#!/usr/bin/env python3
"""
Fix utm_visualization INSERT statements by:
1. Removing the extra NULL value after user_modified
2. Converting integer id_pattern values to UUIDs
"""

import re
import uuid

# Read the file
with open('/home/hidayat/utmstack/backend/src/main/resources/config/liquibase/scripts/data.sql', 'r') as f:
    content = f.read()

# Create a mapping of integer IDs to UUIDs
id_to_uuid = {
    2: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    4: 'f47ac10b-58cc-4372-a567-0e02b2c3d480', 
    8: 'f47ac10b-58cc-4372-a567-0e02b2c3d481',
    10: 'f47ac10b-58cc-4372-a567-0e02b2c3d482',
    11: 'f47ac10b-58cc-4372-a567-0e02b2c3d483',
    12: 'f47ac10b-58cc-4372-a567-0e02b2c3d484',
    13: 'f47ac10b-58cc-4372-a567-0e02b2c3d485',
    15: 'f47ac10b-58cc-4372-a567-0e02b2c3d486',
    39: 'f47ac10b-58cc-4372-a567-0e02b2c3d487',
    50: 'f47ac10b-58cc-4372-a567-0e02b2c3d488',
    53: 'f47ac10b-58cc-4372-a567-0e02b2c3d489'
}

def fix_visualization_insert(match):
    parts = match.group(1).split(', ')
    if len(parts) == 16:  # Has extra NULL
        # Remove the 8th element (extra NULL after user_modified)
        parts.pop(7)
        
        # Convert id_pattern to UUID if it's an integer
        if len(parts) > 11:
            id_pattern = parts[11].strip()
            if id_pattern.isdigit():
                int_id = int(id_pattern)
                if int_id in id_to_uuid:
                    parts[11] = f"'{id_to_uuid[int_id]}'::uuid"
                else:
                    # Generate a new UUID for unknown IDs
                    parts[11] = f"'{str(uuid.uuid4())}'::uuid"
    
    return f"INSERT INTO public.utm_visualization VALUES ({', '.join(parts)});"

# Fix all utm_visualization INSERT statements
pattern = r'INSERT INTO public\.utm_visualization VALUES \(([^;]+)\);'
content = re.sub(pattern, fix_visualization_insert, content, flags=re.DOTALL)

# Write the fixed content back
with open('/home/hidayat/utmstack/backend/src/main/resources/config/liquibase/scripts/data.sql', 'w') as f:
    f.write(content)

print("Fixed utm_visualization INSERT statements")
