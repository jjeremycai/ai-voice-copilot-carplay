#!/bin/bash
# Simplified startup - Node.js server only
# Python agent can be added later as separate service

set -e

echo "🚀 Starting Node.js server..."
exec npm start
