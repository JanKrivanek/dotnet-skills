# .NET Skills for GitHub Copilot CLI

This repository hosts .NET-specific plugins for [GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli). Each plugin provides specialized skills to help Copilot assist with .NET development tasks.

## Available Plugins

| Plugin | Description | Install Command |
|--------|-------------|-----------------|
| [msbuild-skills](./msbuild-skills) | Skills for MSBuild development, including multithreaded task migration | `/plugin install ViktorHofer/skills:msbuild-skills` |

## Installation

1. Launch GitHub Copilot CLI:
   ```bash
   copilot
   ```

2. Install a plugin using the `/plugin install` command:
   ```
   /plugin install ViktorHofer/skills:msbuild-skills
   ```

   For subdirectories, use the `owner/repo:path` format.

3. The plugin's skills will now be available to Copilot in your sessions.

## Adding New Plugins

To add a new plugin to this repository:

1. Create a new subdirectory for your plugin
2. Add a `plugin.json` manifest:
   ```json
   {
     "name": "my-plugin",
     "version": "1.0.0",
     "description": "Description of what the plugin does.",
     "skills": ["skills/my-skill"]
   }
   ```
3. Add skills in a `skills/` subdirectory, each with a `SKILL.md` file
4. Update this README to include your plugin in the table
