#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const yaml = require('yaml');

// Check if yaml package is available, if not, provide installation instructions
try {
  require('yaml');
} catch (error) {
  console.error('Error: yaml package not found. Please install it with:');
  console.error('npm install yaml');
  process.exit(1);
}

function transformEntry(key, entry) {
  const androidData = entry.android;
  const result = {};
  
  // Handle repository and release_repository
  if (androidData.repository) {
    result.repository = androidData.repository;
  }
  
  if (androidData.release_repository) {
    result.release_repository = androidData.release_repository;
  }
  
  // Handle description if present
  if (androidData.description) {
    result.description = androidData.description;
  }
  
  // Transform artifacts to assets
  if (androidData.artifacts) {
    result.assets = androidData.artifacts
      .filter(artifact => !artifact.trim().startsWith('#')) // Skip commented artifacts
      .map(artifact => artifact.replace(/%v/g, '.*')); // Replace %v with .*
  }
  
  // Add remote_metadata
  result.remote_metadata = ['github', 'playstore'];
  
  return result;
}

function main() {
  const inputFile = 'github-android.yaml';
  const outputDir = 'android';
  
  // Check if input file exists
  if (!fs.existsSync(inputFile)) {
    console.error(`Error: Input file '${inputFile}' not found.`);
    process.exit(1);
  }
  
  // Create output directory if it doesn't exist
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }
  
  // Read and parse the input YAML
  const inputContent = fs.readFileSync(inputFile, 'utf8');
  const data = yaml.parse(inputContent);
  
  let processedCount = 0;
  let skippedCount = 0;
  
  // Process each entry
  for (const [key, entry] of Object.entries(data)) {
    try {
      // Skip if no android section
      if (!entry.android) {
        console.log(`Skipping ${key}: No android section found`);
        skippedCount++;
        continue;
      }
      
      // Transform the entry
      const transformed = transformEntry(key, entry);
      
      // Write to individual file
      const outputFile = path.join(outputDir, `${key}.yaml`);
      const outputContent = yaml.stringify(transformed, {
        indent: 2,
        lineWidth: 0, // Prevent line wrapping
      });
      
      fs.writeFileSync(outputFile, outputContent);
      console.log(`✓ Created ${outputFile}`);
      processedCount++;
      
    } catch (error) {
      console.error(`Error processing ${key}:`, error.message);
      skippedCount++;
    }
  }
  
  console.log(`\nTransformation complete!`);
  console.log(`Processed: ${processedCount} entries`);
  console.log(`Skipped: ${skippedCount} entries`);
}

// Run the transformation
main(); 