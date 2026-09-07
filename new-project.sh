#!/bin/bash
# Setup script for new Claude Code projects
# Usage: ./new-project.sh /path/to/new-project

set -e

PROJECT_DIR="${1:-.}"
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.claude-template"

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "❌ Error: .claude-template not found at $TEMPLATE_DIR"
  echo "   Run this script from smartbedv3 root directory"
  exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
  echo "❌ Error: Project directory not found: $PROJECT_DIR"
  exit 1
fi

# Copy .claude template to project
echo "📋 Setting up .claude/ in $PROJECT_DIR..."
cp -r "$TEMPLATE_DIR" "$PROJECT_DIR/.claude"

echo "✅ .claude/ template installed"
echo "📝 Next steps:"
echo "   1. cd $PROJECT_DIR"
echo "   2. Customize .claude/.ck.json as needed"
echo "   3. Close & reopen Claude Code"
echo "   4. All tabs will show Rounded Pill statusline 🎉"
