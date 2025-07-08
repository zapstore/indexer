# Android YAML Transformer

This Node.js script transforms the `github-android.yaml` file into individual YAML files for each app in the `android/` directory.

## Installation

1. Make sure you have Node.js installed (version 12 or higher)
2. Install dependencies:
   ```bash
   npm install
   ```

## Usage

Run the transformation script:
```bash
node transform-android-yaml.js
```

Or use the npm script:
```bash
npm run transform
```

## What it does

The script reads `github-android.yaml` and for each app entry:

1. **Removes** unused fields: `name`, `developer`
2. **Preserves** `description` if present
3. **Copies** `repository` and/or `release_repository` fields
4. **Transforms** `artifacts` → `assets` with `%v` → `.*`
5. **Skips** commented artifacts (lines starting with `#`)
6. **Adds** `remote_metadata: [github, playstore]` to all files
7. **Preserves** existing regex patterns (only replaces `%v`)

## Example Transformation

**Input** (`github-android.yaml`):
```yaml
primal:
  android:
    name: Primal
    repository: https://github.com/PrimalHQ/primal-android-app
    developer: npub12vkcxr0luzwp8e673v29eqjhrr7p9vqq8asav85swaepclllj09sylpugg
    artifacts:
      - primal-%v.apk
```

**Output** (`android/primal.yaml`):
```yaml
repository: https://github.com/PrimalHQ/primal-android-app
assets:
  - primal-.*.apk
remote_metadata:
  - github
  - playstore
```

## Special Cases

- **release_repository**: If present, copied as `release_repository` (not `repository`)
- **Both repositories**: If both `repository` and `release_repository` exist, both are copied
- **Complex regex**: Existing regex patterns like `\d+` are preserved, only `%v` is replaced
- **Descriptions**: Preserved if present in the original file

## Output

The script creates individual `.yaml` files in the `android/` directory, one for each app entry from the original file. 