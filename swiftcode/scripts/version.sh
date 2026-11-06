#!/bin/sh
# Prints the release's version: swiftcode/VERSION, the one source of truth.
exec cat "$(dirname "$0")/../VERSION"
