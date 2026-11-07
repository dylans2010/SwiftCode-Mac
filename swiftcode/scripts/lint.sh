#!/bin/sh
cd "$(dirname "$0")/../.." && exec swiftlint lint --strict "$@"
