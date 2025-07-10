const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

// Get folder path from command line argument
const folderPath = process.argv[2];
if (!folderPath) {
    console.error('Usage: node process-yaml.js <folder-path>');
    console.error('Example: node process-yaml.js ./android');
    process.exit(1);
}

// Check if folder exists
if (!fs.existsSync(folderPath)) {
    console.error(`Error: Folder "${folderPath}" does not exist`);
    process.exit(1);
}

// Read processed.txt to get already processed files
const processedFile = 'processed.txt';
let processedFiles = new Set();

if (fs.existsSync(processedFile)) {
    const content = fs.readFileSync(processedFile, 'utf8');
    processedFiles = new Set(content.split('\n').filter(line => line.trim()));
}

// Get all YAML files in the folder
const allFiles = fs.readdirSync(folderPath)
    .filter(file => file.endsWith('.yaml') || file.endsWith('.yml'));

const unprocessedFiles = allFiles.filter(file => !processedFiles.has(file));

console.log(`Found ${allFiles.length} total YAML files`);
console.log(`Found ${processedFiles.size} already processed files`);
console.log(`Found ${unprocessedFiles.length} unprocessed YAML files`);

if (unprocessedFiles.length === 0) {
    console.log('No files to process. All done!');
    process.exit(0);
}

// Process each file
async function processFile(filename) {
    const filePath = path.join(folderPath, filename);
    const command = `zapstore2 --no-auto-update publish -c "${filePath}" -d`;
    
    console.log(`\nProcessing: ${filename}`);
    console.log(`Command: ${command}`);
    
    return new Promise((resolve, reject) => {
        exec(command, (error, stdout, stderr) => {
            if (error) {
                console.error(`❌ Error processing ${filename}:`);
                console.error(`Exit code: ${error.code}`);
                console.error(`Error message: ${error.message}`);
                if (stderr) console.error(`stderr: ${stderr}`);
                reject(error);
                return;
            }
            
            if (stdout) console.log(`stdout: ${stdout}`);
            if (stderr) console.log(`stderr: ${stderr}`);
            
            // Add to processed.txt
            fs.appendFileSync(processedFile, filename + '\n');
            console.log(`✅ Successfully processed: ${filename}`);
            resolve();
        });
    });
}

// Process files sequentially
async function processAllFiles() {
    for (let i = 0; i < unprocessedFiles.length; i++) {
        const filename = unprocessedFiles[i];
        console.log(`\n[${i + 1}/${unprocessedFiles.length}] Processing ${filename}...`);
        
        try {
            await processFile(filename);
        } catch (error) {
            console.error(`\n🛑 ABORTING: Failed to process ${filename}`);
            console.error('Fix the YAML file and re-run the program.');
            process.exit(1);
        }
    }
    
    console.log('\n🎉 All files processed successfully!');
}

// Start processing
processAllFiles().catch(error => {
    console.error('Unexpected error:', error);
    process.exit(1);
}); 