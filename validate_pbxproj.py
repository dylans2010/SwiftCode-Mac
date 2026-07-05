import sys

def check_integrity(file_path):
    with open(file_path, 'r') as f:
        content = f.read()

    # Check for balanced braces
    stack = []
    for char in content:
        if char == '{':
            stack.append('{')
        elif char == '}':
            if not stack:
                print("Error: Unbalanced braces (extra closing brace)")
                return False
            stack.pop()

    if stack:
        print("Error: Unbalanced braces (missing closing brace)")
        return False

    print("PBXProj integrity check passed (balanced braces).")
    return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 validate_pbxproj.py <path_to_pbxproj>")
        sys.exit(1)

    if check_integrity(sys.argv[1]):
        sys.exit(0)
    else:
        sys.exit(1)
