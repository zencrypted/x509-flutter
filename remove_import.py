import os
import glob

directory = 'macos/Runner/ASN1'
for filepath in glob.iglob(os.path.join(directory, '*.swift')):
    with open(filepath, 'r') as file:
        data = file.read()
    data = data.replace('import SwiftASN1\n', '')
    with open(filepath, 'w') as file:
        file.write(data)

directory2 = 'macos/Runner/SwiftASN1'
for root, dirs, files in os.walk(directory2):
    for filename in files:
        if filename.endswith('.swift'):
            filepath = os.path.join(root, filename)
            with open(filepath, 'r') as file:
                data = file.read()
            # Also might need to fix any imports inside SwiftASN1 if any
            with open(filepath, 'w') as file:
                file.write(data)
