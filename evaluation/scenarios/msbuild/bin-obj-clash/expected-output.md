# Expected Findings: bin-obj-clash Scenario

## Problem Summary
This solution demonstrates MSBuild output path and intermediate output path clashes that cause build failures.

## Expected Findings

### 1. MultiTargetLib - Multi-targeting Clash
- **Issue**: Project multi-targets net8.0 and net9.0 but has `AppendTargetFrameworkToOutputPath=false`
- **Impact**: Both target frameworks write to the same output directory
- **Solution**: Remove `AppendTargetFrameworkToOutputPath=false` or ensure output paths are unique per target framework

### 2. LibraryA & LibraryB - Shared Output Path Clash
- **Issue**: Both projects share `../SharedOutput/` as their output path
- **Impact**: Build artifacts overwrite each other during parallel builds
- **Solution**: Give each project a unique output path

### 3. LibraryA & LibraryB - Shared Intermediate Path Clash
- **Issue**: Both projects share `../SharedObj/` as their intermediate output path
- **Impact**: `project.assets.json` and generated files conflict
- **Error**: "Cannot create a file when that file already exists" during NuGet restore
- **Solution**: Give each project a unique intermediate output path

## Key Concepts That Should Be Mentioned
- IntermediateOutputPath
- OutputPath
- AppendTargetFrameworkToOutputPath
- BaseIntermediateOutputPath
- Multi-targeting
- project.assets.json
- Parallel build conflicts
