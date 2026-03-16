const postcss = require('postcss');
const autoprefixer = require('autoprefixer');
const tailwind = require('@tailwindcss/postcss');
const fs = require('fs');
const path = require('path');

const inputPath = path.join(__dirname, 'public/assets/css/tailwind-source.css');
const outputPath = path.join(__dirname, 'public/assets/css/tailwind.css');

const css = fs.readFileSync(inputPath, 'utf8');

postcss([tailwind(), autoprefixer()])
  .process(css, { from: inputPath, to: outputPath })
  .then(result => {
    fs.writeFileSync(outputPath, result.css);
    console.log('✓ Tailwind CSS built successfully!');
    console.log(`  Output: ${outputPath}`);
    console.log(`  Size: ${(result.css.length / 1024).toFixed(2)} KB`);
  })
  .catch(error => {
    console.error('Error building Tailwind CSS:', error.message);
    process.exit(1);
  });
