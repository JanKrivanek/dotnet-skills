---
name: check-bin-obj-clash
description: "Detects MSBuild projects with conflicting OutputPath or IntermediateOutputPath. Use when builds fail with file access errors, missing outputs, or intermittent failures. Identifies when multiple projects or multi-targeting builds write to the same bin/obj directories."
---

# Detecting OutputPath and IntermediateOutputPath Clashes

## Overview

This skill helps identify when multiple MSBuild project evaluations share the same `OutputPath` or `IntermediateOutputPath`. This is a common source of build failures including:

- File access conflicts during parallel builds
- Missing or overwritten output files
- Intermittent build failures
- "File in use" errors
- **NuGet restore errors like `Cannot create a file when that file already exists`** - this strongly indicates multiple projects share the same `IntermediateOutputPath` where `project.assets.json` is written

Clashes can occur between:
- **Different projects** sharing the same output directory
- **Multi-targeting builds** (e.g., `TargetFrameworks=net8.0;net9.0`) where the path doesn't include the target framework

## When to Use This Skill

**Invoke this skill immediately when you see:**
- `Cannot create a file when that file already exists` during NuGet restore
- `The process cannot access the file because it is being used by another process`
- Intermittent build failures that succeed on retry
- Missing output files or unexpected overwriting

## Step 1: Generate a Binary Log

Follow the instructions in the [binlog-generation skill](../binlog-generation/SKILL.md) to generate a binary log with the correct naming convention.

## Step 2: Load the Binary Log

```
load_binlog with path: "<absolute-path-to-build.binlog>"
```

## Step 3: List All Projects

```
list_projects with binlog_file: "<path>"
```

This returns all projects with their IDs and file paths.

## Step 4: Get Evaluations for Each Project

For each unique project file path, list its evaluations:

```
list_evaluations with:
  - binlog_file: "<path>"
  - projectFilePath: "<project-file-path>"
```

Multiple evaluations for the same project indicate multi-targeting or multiple build configurations.

## Step 5: Check Global Properties for Each Evaluation

For each evaluation, get the global properties to understand the build configuration:

```
get_evaluation_global_properties with:
  - binlog_file: "<path>"
  - evaluationId: <evaluation-id>
```

Look for properties like `TargetFramework`, `Configuration`, `Platform`, and `RuntimeIdentifier` that should differentiate output paths.

## Step 6: Get Output Paths for Each Evaluation

For each evaluation, retrieve the `OutputPath` and `IntermediateOutputPath`:

```
get_evaluation_properties_by_name with:
  - binlog_file: "<path>"
  - evaluationId: <evaluation-id>
  - propertyNames: ["OutputPath", "IntermediateOutputPath", "BaseOutputPath", "BaseIntermediateOutputPath", "TargetFramework", "Configuration", "Platform"]
```

## Step 7: Identify Clashes

Compare the `OutputPath` and `IntermediateOutputPath` values across all evaluations:

1. **Normalize paths** - Convert to absolute paths and normalize separators
2. **Group by path** - Find evaluations that share the same OutputPath or IntermediateOutputPath
3. **Report clashes** - Any group with more than one evaluation indicates a clash

### Expected Output Structure

For each evaluation, collect:
- Project file path
- Evaluation ID
- TargetFramework (if multi-targeting)
- Configuration
- OutputPath
- IntermediateOutputPath

### Clash Detection Logic

```
For each unique OutputPath:
  - If multiple evaluations share it → CLASH
  
For each unique IntermediateOutputPath:
  - If multiple evaluations share it → CLASH
```

## Common Causes and Fixes

### Multi-targeting without TargetFramework in path

**Problem:** Project uses `TargetFrameworks` but OutputPath doesn't vary by framework.

```xml
<!-- BAD: Same path for all frameworks -->
<OutputPath>bin\$(Configuration)\</OutputPath>
```

**Fix:** Include TargetFramework in the path:

```xml
<!-- GOOD: Path varies by framework -->
<OutputPath>bin\$(Configuration)\$(TargetFramework)\</OutputPath>
```

Or rely on SDK defaults which handle this automatically:

```xml
<AppendTargetFrameworkToOutputPath>true</AppendTargetFrameworkToOutputPath>
<AppendTargetFrameworkToIntermediateOutputPath>true</AppendTargetFrameworkToIntermediateOutputPath>
```

### Shared output directory across projects (CANNOT be fixed with AppendTargetFramework)

**Problem:** Multiple projects explicitly set the same `BaseOutputPath` or `BaseIntermediateOutputPath`.

```xml
<!-- Project A - Directory.Build.props -->
<BaseOutputPath>..\SharedOutput\</BaseOutputPath>
<BaseIntermediateOutputPath>..\SharedObj\</BaseIntermediateOutputPath>

<!-- Project B - Directory.Build.props -->
<BaseOutputPath>..\SharedOutput\</BaseOutputPath>
<BaseIntermediateOutputPath>..\SharedObj\</BaseIntermediateOutputPath>
```

**IMPORTANT:** Even with `AppendTargetFrameworkToOutputPath=true`, this will still clash! .NET writes certain files directly to the `IntermediateOutputPath` without the TargetFramework suffix, including:

- `project.assets.json` (NuGet restore output)
- Other NuGet-related files

This causes errors like `Cannot create a file when that file already exists` during parallel restore.

**Fix:** Each project MUST have a unique `BaseIntermediateOutputPath`. Do not share intermediate output directories across projects:

```xml
<!-- Project A -->
<BaseIntermediateOutputPath>..\obj\ProjectA\</BaseIntermediateOutputPath>

<!-- Project B -->
<BaseIntermediateOutputPath>..\obj\ProjectB\</BaseIntermediateOutputPath>
```

Or simply use the SDK defaults which place `obj` inside each project's directory.

### RuntimeIdentifier builds clashing

**Problem:** Building for multiple RIDs without RID in path.

**Fix:** Ensure RuntimeIdentifier is in the path:

```xml
<AppendRuntimeIdentifierToOutputPath>true</AppendRuntimeIdentifierToOutputPath>
```

## Example Workflow

```
1. load_binlog with path: "C:\repo\build.binlog"

2. list_projects → Returns projects with IDs

3. For project "MyLib.csproj":
   list_evaluations → Returns evaluation IDs 1, 2 (net8.0, net9.0)

4. get_evaluation_properties_by_name for evaluation 1:
   - TargetFramework: "net8.0"
   - OutputPath: "bin\Debug\net8.0\"
   - IntermediateOutputPath: "obj\Debug\net8.0\"

5. get_evaluation_properties_by_name for evaluation 2:
   - TargetFramework: "net9.0"
   - OutputPath: "bin\Debug\net9.0\"
   - IntermediateOutputPath: "obj\Debug\net9.0\"

6. Compare paths → No clash (paths differ by TargetFramework)
```

## Tips

- Use `search_binlog` with query `"OutputPath"` to quickly find all OutputPath property assignments
- Check `BaseOutputPath` and `BaseIntermediateOutputPath` as they form the root of output paths
- The SDK default paths include `$(TargetFramework)` - clashes often occur when projects override these defaults
- Remember that paths may be relative - normalize to absolute paths before comparing
- **Cross-project IntermediateOutputPath clashes cannot be fixed with `AppendTargetFrameworkToOutputPath`** - files like `project.assets.json` are written directly to the intermediate path
- For multi-targeting clashes within the same project, `AppendTargetFrameworkToOutputPath=true` is the correct fix
- Common error messages indicating path clashes:
  - `Cannot create a file when that file already exists` (NuGet restore)
  - `The process cannot access the file because it is being used by another process`
  - Intermittent build failures that succeed on retry
