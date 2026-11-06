import sys
import json
import os

def main():
    print(json.dumps({"status": "ready", "python_version": sys.version}))

if __name__ == "__main__":
    main()
