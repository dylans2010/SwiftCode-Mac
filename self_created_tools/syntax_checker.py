#!/usr/bin/env python3
import sys
import os

def check_file(filepath):
    print(f"Checking syntax of {filepath}...")
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    # Highly robust Swift braces/brackets parser
    braces = 0
    brackets = 0
    parens = 0

    # Strip comments and literal string contents to perform a pure structural bracket matching check
    # Let's replace strings and comments with empty spaces

    # 1. Block comments
    content = re_replace(r"/\*.*?\*/", "", content)

    # 2. Line comments
    lines = content.splitlines()
    clean_lines = []
    for line in lines:
        if "//" in line:
            # simple split on // if not in string (handled simply)
            parts = line.split("//")
            clean_lines.append(parts[0])
        else:
            clean_lines.append(line)
    content = "\n".join(clean_lines)

    # 3. Multiline strings """
    content = re_replace(r'""".*?"""', '""', content)

    # 4. Standard strings
    content = re_replace(r'"([^"\\]|\\.)*"', '""', content)

    for line_num, line in enumerate(content.splitlines(), 1):
        for char in line:
            if char == '{':
                braces += 1
            elif char == '}':
                braces -= 1
                if braces < 0:
                    print(f"Error: Unmatched closing brace '}}' in {filepath} on line {line_num}")
                    return False
            elif char == '[':
                brackets += 1
            elif char == ']':
                brackets -= 1
                if brackets < 0:
                    print(f"Error: Unmatched closing bracket ']' in {filepath} on line {line_num}")
                    return False
            elif char == '(':
                parens += 1
            elif char == ')':
                parens -= 1
                if parens < 0:
                    print(f"Error: Unmatched closing parenthesis ')' in {filepath} on line {line_num}")
                    return False

    if braces != 0:
        print(f"Error: Unmatched curly braces count ({braces}) in {filepath}")
        return False
    if brackets != 0:
        print(f"Error: Unmatched square brackets count ({brackets}) in {filepath}")
        return False
    if parens != 0:
        print(f"Error: Unmatched parentheses count ({parens}) in {filepath}")
        return False

    print(f"{filepath} syntax check PASSED.")
    return True

def re_replace(pattern, repl, text):
    import re
    return re.sub(pattern, repl, text, flags=re.DOTALL)

if __name__ == "__main__":
    files = [
        "SwiftCode/Core/Preview/PreviewRuntime.swift",
        "SwiftCode/Core/Preview/PreviewManager.swift",
        "SwiftCode/Core/Preview/PreviewDeviceManager.swift",
        "SwiftCode/Core/Preview/PreviewPerformanceMonitor.swift",
        "SwiftCode/Core/Preview/PreviewInteractionManager.swift",
        "SwiftCode/Core/Preview/PreviewRuntimeCompiler.swift",
        "SwiftCode/Core/Preview/PreviewDynamicLoader.swift",
        "SwiftCode/Core/Preview/DynamicSwiftUIPreviewRenderer.swift",
        "SwiftCode/Core/Preview/PreviewHost.swift",
        "SwiftCode/Core/Preview/PreviewContainer.swift",
        "SwiftCode/Views/Utilities/Sims/PreviewDeviceFrameView.swift",
        "SwiftCode/Views/Utilities/VisualUIBuilder/VisualUIPreviewPanel.swift"
    ]

    success = True
    for file in files:
        if os.path.exists(file):
            if not check_file(file):
                success = False
        else:
            print(f"File not found: {file}")
            success = False

    if not success:
        sys.exit(1)
    print("All files passed syntax check successfully!")
