---
name: binlog-failure-analysis
description: Use this skill when an MSBuild build fails. Guides you to generate a binary log and use the binlog-mcp tool to analyze build failures, diagnostics, and performance issues.
---

# Analyzing MSBuild Failures with Binary Logs

When an MSBuild build fails, use the binlog-mcp tool to deeply analyze the failure. This skill guides you through generating a binary log and using the MCP tools to diagnose issues.

## Step 1: Generate a Binary Log

Re-run the failed build command with the `/bl` flag to generate a binary log file:

```bash
# For dotnet builds
dotnet build /bl

# For msbuild directly
msbuild /bl

# Custom binlog filename
dotnet build /bl:build.binlog
```

The `/bl` flag tells MSBuild to generate a `msbuild.binlog` file (or the specified filename) in the current directory.

## Step 2: Load the Binary Log

Use the `load_binlog` tool to load the generated binlog file:

```
load_binlog with path: "<absolute-path-to-binlog>"
```

This must be called before using any other binlog analysis tools.

## Step 3: Analyze the Failure

### Get Diagnostics (Errors and Warnings)

Use `get_diagnostics` to extract all errors and warnings:

```
get_diagnostics with:
  - binlog_file: "<path>"
  - includeErrors: true
  - includeWarnings: true
  - includeDetails: true
```

This returns detailed diagnostic information including file paths, line numbers, and context.

### Search for Specific Issues

Use `search_binlog` with the powerful query language to find specific issues:

```
search_binlog with:
  - binlog_file: "<path>"
  - query: "error CS1234"        # Find specific error codes
  - query: "$task Csc"           # Find all C# compilation tasks
  - query: "under($project MyProject)"  # Find nodes under a specific project
```

### Investigate Expensive Operations

If the build is slow or timing out:

```
get_expensive_targets with binlog_file and top_number: 10
get_expensive_tasks with binlog_file and top_number: 10
get_expensive_projects with binlog_file and top_number: 10
```

### Analyze Roslyn Analyzers

If compilation is slow, check analyzer performance:

```
get_expensive_analyzers with binlog_file and top_number: 10
```

## Common Analysis Workflows

### Build Error Investigation
1. `load_binlog` - Load the binlog
2. `get_diagnostics` with `includeErrors: true` - Get all errors
3. `search_binlog` with the error code - Find context around the error
4. `list_projects` - Identify which projects are involved
5. `get_file_from_binlog` - View source files embedded in the binlog

### Performance Investigation
1. `load_binlog` - Load the binlog
2. `get_expensive_targets` - Find slow targets
3. `get_expensive_tasks` - Find slow tasks
4. `search_targets_by_name` - Find all executions of a specific target
5. `get_node_timeline` - Analyze parallelism and node utilization

### Dependency/Evaluation Issues
1. `load_binlog` - Load the binlog
2. `list_projects` - See all projects in the build
3. `list_evaluations` - Check for multiple evaluations (indicates overbuilding)
4. `get_evaluation_global_properties` - Compare properties between evaluations

## Query Language Reference

The `search_binlog` tool supports powerful query syntax:

| Query | Description |
|-------|-------------|
| `"error CS1234"` | Exact text match |
| `$task Copy` | Find all Copy tasks |
| `$target CoreCompile` | Find all CoreCompile target executions |
| `$project MyProject` | Find nodes related to MyProject |
| `under($project X)` | Find nodes under project X |
| `name=Configuration value=Debug` | Find property nodes |
| `skipped=true` | Find skipped targets |

## Tips

- The binlog contains embedded source files - use `list_files_from_binlog` and `get_file_from_binlog` to view them
- Use `maxResults` parameter to limit large result sets
- The binlog captures the complete build state, making it ideal for reproducing and diagnosing issues
