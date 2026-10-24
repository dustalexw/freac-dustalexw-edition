#!/bin/bash
# Compiles the UI-free core (help parsing, command building, progress parsing) with the fixtures and runs the checks.
# Works on macOS and Linux:  ./Tests/core/run.sh
set -e
cd "$(dirname "$0")/../.."
mkdir -p .lt
swiftc -swift-version 5 -o .lt/coretests Sources/Frickoss/Core/*.swift Tests/core/main.swift
.lt/coretests Tests/core
