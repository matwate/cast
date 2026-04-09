#!/bin/bash
set -e

# Cast Application - Setup Script
# Downloads and prepares all static assets

echo "🚀 Setting up Cast application..."

# Create directory structure
mkdir -p public/assets/{css,js,fonts,vendor}

# Download fonts
echo "📦 Downloading fonts..."
curl -sL "https://fonts.googleapis.com/css2?family=Public+Sans:wght@300;400;500;600;700&display=swap" -o public/assets/css/public-sans.css
curl -sL "https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&display=swap" -o public/assets/css/material-symbols.css

echo "✓ Fonts downloaded"

# Build Tailwind CSS
echo "🎨 Building Tailwind CSS..."

       # Create tailwind-source.css if it doesn't exist
if [ ! -f "public/assets/css/tailwind-source.css" ]; then
  echo "📝 Creating tailwind-source.css..."
  cat > public/assets/css/tailwind-source.css << 'EOF'
@import "tailwindcss";
@theme {
  --color-brand: #136dec;
  --color-nord-0: #2e3440;
  --color-nord-1: #3b4252;
  --color-nord-2: #434c5e;
  --color-nord-3: #4c566a;
  --color-nord-4: #d8dee9;
  --color-nord-5: #e5e9f0;
  --color-nord-6: #eceff4;
  --color-nord-7: #8fbcbb;
  --color-nord-8: #88c0d0;
  --color-nord-9: #81a1c1;
  --color-nord-10: #5e81ac;
  --radius-theme: 8px;
  --radius-button: 24px;
}
@variant dark (&:where(.dark, .dark *));
EOF
  echo "✓ tailwind-source.css created"
fi


npm run build:css
echo "✓ Tailwind CSS built"

# Copy vendor libraries
echo "📚 Copying vendor libraries..."
mkdir -p public/assets/vendor

if [ -d "node_modules/reveal.js" ]; then
  cp -r node_modules/reveal.js/dist/* public/assets/vendor/
  echo "✓ Reveal.js copied"
fi

if [ -d "node_modules/hyperscript.org" ]; then
  cp node_modules/hyperscript.org/dist/_hyperscript.min.js public/assets/vendor/
  echo "✓ Hyperscript copied"
fi

# Copy root HTML files to public
echo "📄 Copying HTML files to public..."
cp index.html public/
cp controls.html public/
cp view.html public/

echo "✓ Setup complete!"
echo ""
echo "To start the application:"
echo "  nix run ."
echo ""
echo "Or with custom WebSocket URL:"
echo "  WEBSOCKET_URL='ws://your-domain/ws/' nix run ."
