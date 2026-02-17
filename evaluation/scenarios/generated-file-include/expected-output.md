# Expected Findings: generated-file-include Scenario

## Problem Summary
This project generates a C# source file during the build (via an MSBuild inline task), but fails to include it in compilation. The build fails because `Program.cs` references `TestProject.Generated.BuildInfo` which exists in the generated file.

## Root Cause
The `GenerateSampleCode` target writes a `.cs` file to `$(IntermediateOutputPath)Generated\GeneratedInfo.cs` using the `WriteCodeFile` inline task, but the target does **not** add the generated file to the `Compile` item group. Since the file is generated during the build (execution phase), it wasn't present during MSBuild's evaluation phase when default globs are expanded, so it is never compiled.

## Expected Fix
The fix should add an `<ItemGroup>` inside the `GenerateSampleCode` target (after the file is written) that includes the generated file in compilation and registers it for cleanup:

```xml
<ItemGroup>
  <Compile Include="$(_GeneratedFilePath)" />
  <FileWrites Include="$(_GeneratedFilePath)" />
</ItemGroup>
```

## Key Concepts That Should Be Mentioned
- MSBuild evaluation phase vs execution phase
- Files generated during build are not captured by default glob patterns
- `Compile` item group for source files that need to be compiled
- `FileWrites` item group for proper cleanup during `dotnet clean`
- `$(IntermediateOutputPath)` as the correct base directory for generated files
- `BeforeTargets="CoreCompile;BeforeCompile"` as the correct target timing for generated source files
- The generated file must be added to `Compile` **inside the target** (not at the project level) because it doesn't exist at evaluation time
